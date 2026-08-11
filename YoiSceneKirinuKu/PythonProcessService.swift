import Foundation

struct PythonProcessConfiguration: Sendable {
    let executableURL: URL
    let scriptURL: URL
    let argumentsPrefix: [String]
    let environment: [String: String]

    static func bundled(scriptRelativePath: String, bundle: Bundle = .main) -> Self {
        Self(
            executableURL: bundle.bundleURL.appendingPathComponent(
                "Contents/Frameworks/Python.framework/Versions/3.13/bin/python3.13"
            ),
            scriptURL: bundle.bundleURL.appendingPathComponent(
                "Contents/Resources/Stage6/\(scriptRelativePath)"
            ),
            argumentsPrefix: ["-I", "-S"],
            environment: ["LANG": "C.UTF-8", "PATH": "/nonexistent", "PYTHONNOUSERSITE": "1"]
        )
    }
}

struct PythonProcessExecution: Equatable, Sendable {
    let requestID: UUID
    let events: [PythonIPCEvent]
    let stderr: Data
}

enum PythonProcessServiceError: Error, Equatable, Sendable {
    case invalidConfiguration
    case requestEncodingFailed
    case processNotStarted
    case stdinWriteFailed
    case protocolFailure(PythonIPCError)
    case nonzeroExit(Int32)
    case stopped
}

enum PythonProcessServiceOutcome: Equatable, Sendable {
    case success(PythonProcessExecution)
    case failure(PythonProcessServiceError, stderr: Data)
}

final class PythonProcessService: @unchecked Sendable {
    private let configuration: PythonProcessConfiguration

    init(configuration: PythonProcessConfiguration) {
        self.configuration = configuration
    }

    func run(payload: [String: PythonIPCValue]) async -> PythonProcessServiceOutcome {
        let requestID = UUID()
        guard let input = try? PythonIPCRequestEncoder.encode(requestID: requestID, payload: payload) else {
            return .failure(.requestEncodingFailed, stderr: Data())
        }
        let controller = PythonProcessController()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(returning: Self.execute(
                        input: input,
                        requestID: requestID,
                        configuration: self.configuration,
                        controller: controller
                    ))
                }
            }
        } onCancel: {
            controller.stop()
        }
    }

    private static func execute(
        input: Data,
        requestID: UUID,
        configuration: PythonProcessConfiguration,
        controller: PythonProcessController
    ) -> PythonProcessServiceOutcome {
        guard FileManager.default.isExecutableFile(atPath: configuration.executableURL.path),
              FileManager.default.fileExists(atPath: configuration.scriptURL.path) else {
            return .failure(.invalidConfiguration, stderr: Data())
        }

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = configuration.executableURL
        process.arguments = configuration.argumentsPrefix + [configuration.scriptURL.path]
        process.environment = configuration.environment
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        guard controller.register(process) else { return .failure(.stopped, stderr: Data()) }

        do {
            try process.run()
        } catch {
            controller.clear(process)
            return .failure(.processNotStarted, stderr: Data())
        }

        let group = DispatchGroup()
        let stdout = PythonProcessStdoutState(requestID: requestID)
        let stderr = PythonProcessStderrState()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            stdout.read(from: outputPipe.fileHandleForReading)
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            stderr.read(from: errorPipe.fileHandleForReading)
            group.leave()
        }

        do {
            try inputPipe.fileHandleForWriting.write(contentsOf: input)
            try inputPipe.fileHandleForWriting.close()
        } catch {
            controller.stop()
            process.waitUntilExit()
            group.wait()
            controller.clear(process)
            return .failure(.stdinWriteFailed, stderr: stderr.data)
        }

        process.waitUntilExit()
        group.wait()
        let wasStopped = controller.wasStopRequested
        controller.clear(process)
        if wasStopped { return .failure(.stopped, stderr: stderr.data) }
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            return .failure(.nonzeroExit(process.terminationStatus), stderr: stderr.data)
        }
        switch stdout.result {
        case .success(let events):
            return .success(PythonProcessExecution(
                requestID: requestID,
                events: events,
                stderr: stderr.data
            ))
        case .failure(let error):
            return .failure(.protocolFailure(error), stderr: stderr.data)
        }
    }
}

private final class PythonProcessController: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var stopRequested = false

    var wasStopRequested: Bool { lock.withLock { stopRequested } }

    func register(_ process: Process) -> Bool {
        lock.withLock {
            guard !stopRequested else { return false }
            self.process = process
            return true
        }
    }

    func stop() {
        lock.withLock {
            stopRequested = true
            if process?.isRunning == true { process?.terminate() }
        }
    }

    func clear(_ process: Process) {
        lock.withLock {
            if self.process === process { self.process = nil }
        }
    }
}

private final class PythonProcessStdoutState: @unchecked Sendable {
    private var parser: PythonIPCLineParser
    private var events: [PythonIPCEvent] = []
    private var buffer = Data()
    private var firstError: PythonIPCError?

    init(requestID: UUID) { parser = PythonIPCLineParser(requestID: requestID) }

    func read(from handle: FileHandle) {
        do {
            while let chunk = try handle.read(upToCount: 4096), !chunk.isEmpty {
                buffer.append(chunk)
                consumeLines()
            }
        } catch {
            firstError = firstError ?? .malformed
        }
        guard buffer.isEmpty else {
            firstError = firstError ?? .malformed
            return
        }
        do {
            try parser.finish()
        } catch let error as PythonIPCError {
            firstError = firstError ?? error
        } catch {
            firstError = firstError ?? .malformed
        }
    }

    var result: Result<[PythonIPCEvent], PythonIPCError> {
        if let firstError { return .failure(firstError) }
        return .success(events)
    }

    private func consumeLines() {
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[..<newline]
            buffer.removeSubrange(...newline)
            guard firstError == nil else { continue }
            do {
                events.append(try parser.parseLine(Data(line)))
            } catch let error as PythonIPCError {
                firstError = error
            } catch {
                firstError = .malformed
            }
        }
    }
}

private final class PythonProcessStderrState: @unchecked Sendable {
    private(set) var data = Data()

    func read(from handle: FileHandle) {
        do {
            while let chunk = try handle.read(upToCount: 4096), !chunk.isEmpty {
                data.append(chunk)
            }
        } catch {
            // stderrはprotocol判定に使用せず、取得できた診断だけを保持する。
        }
    }
}
