import Foundation
import CoreFoundation

enum PreflightErrorCode: String, Codable, CaseIterable, Sendable {
    case invalidRequest = "invalid_request"
    case unsupportedFileType = "unsupported_file_type"
    case inputNotFound = "input_not_found"
    case inputNotReadable = "input_not_readable"
    case probeNotStarted = "probe_not_started"
    case probeTimedOut = "probe_timed_out"
    case probeFailed = "probe_failed"
    case invalidProbeOutput = "invalid_probe_output"
    case videoStreamMissing = "video_stream_missing"
    case audioStreamMissing = "audio_stream_missing"
    case invalidDuration = "invalid_duration"
    case protocolError = "protocol_error"
    case internalError = "internal_error"

    var userMessage: String {
        switch self {
        case .invalidRequest, .probeNotStarted, .internalError:
            "動画を確認できませんでした"
        case .unsupportedFileType:
            "MP4ファイルを選んでください"
        case .inputNotFound:
            "選択した動画が見つかりません"
        case .inputNotReadable:
            "この動画を読み込めません"
        case .probeTimedOut:
            "動画の確認に時間がかかりすぎました"
        case .probeFailed:
            "この動画は解析できません"
        case .invalidProbeOutput:
            "動画情報を確認できませんでした"
        case .videoStreamMissing:
            "映像トラックが見つかりません"
        case .audioStreamMissing:
            "音声トラックが見つかりません"
        case .invalidDuration:
            "動画の長さを確認できません"
        case .protocolError:
            "動画の確認処理で問題が発生しました"
        }
    }
}

struct PreflightResult: Equatable, Sendable {
    let fileName: String
    let durationMilliseconds: Int64
    let containerFormat: String
    let videoStreamCount: Int
    let audioStreamCount: Int
}

enum PreflightOutcome: Equatable, Sendable {
    case success(PreflightResult)
    case failure(PreflightErrorCode)
}

protocol PreflightServicing: Sendable {
    func run(sourceURL: URL, requestID: UUID) async -> PreflightOutcome
}

struct PreflightConfiguration: Sendable {
    let pythonExecutableURL: URL
    let ffprobeExecutableURL: URL
    let scriptURL: URL

    static func bundled(bundle: Bundle = .main) -> PreflightConfiguration? {
        guard
            let pythonPath = bundle.object(forInfoDictionaryKey: "PreflightPythonExecutable") as? String,
            let ffprobePath = bundle.object(forInfoDictionaryKey: "PreflightFFprobeExecutable") as? String,
            let scriptURL = bundle.url(forResource: "preflight", withExtension: "py")
        else {
            return nil
        }

        return PreflightConfiguration(
            pythonExecutableURL: URL(fileURLWithPath: pythonPath),
            ffprobeExecutableURL: URL(fileURLWithPath: ffprobePath),
            scriptURL: scriptURL
        )
    }
}

final class PreflightService: PreflightServicing, @unchecked Sendable {
    private let configuration: PreflightConfiguration?

    init(configuration: PreflightConfiguration? = .bundled()) {
        self.configuration = configuration
    }

    func run(sourceURL: URL, requestID: UUID) async -> PreflightOutcome {
        guard let configuration else {
            return .failure(.probeNotStarted)
        }

        let controller = PreflightProcessController()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(returning: Self.execute(
                        sourceURL: sourceURL,
                        requestID: requestID,
                        configuration: configuration,
                        controller: controller
                    ))
                }
            }
        } onCancel: {
            controller.terminate()
        }
    }

    private static func execute(
        sourceURL: URL,
        requestID: UUID,
        configuration: PreflightConfiguration,
        controller: PreflightProcessController
    ) -> PreflightOutcome {
        guard validateExecutable(configuration.pythonExecutableURL),
              validateExecutable(configuration.ffprobeExecutableURL),
              FileManager.default.fileExists(atPath: configuration.scriptURL.path) else {
            return .failure(.probeNotStarted)
        }

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = configuration.pythonExecutableURL
        process.arguments = [configuration.scriptURL.path, configuration.ffprobeExecutableURL.path]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        guard controller.register(process) else {
            return .failure(.internalError)
        }

        let request: [String: Any] = [
            "protocol_version": 1,
            "request_id": requestID.uuidString.lowercased(),
            "operation": "preflight",
            "source_path": sourceURL.path,
        ]

        guard let requestData = try? JSONSerialization.data(withJSONObject: request) else {
            return .failure(.internalError)
        }

        do {
            try process.run()
        } catch {
            controller.clear(process)
            return .failure(.probeNotStarted)
        }
        if controller.isCancellationRequested {
            controller.terminate()
        }

        let streamGroup = DispatchGroup()
        let dataStore = PreflightStreamData()
        streamGroup.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            dataStore.setStdout(outputPipe.fileHandleForReading.readDataToEndOfFile())
            streamGroup.leave()
        }
        streamGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            dataStore.setStderr(errorPipe.fileHandleForReading.readDataToEndOfFile())
            streamGroup.leave()
        }

        do {
            try inputPipe.fileHandleForWriting.write(contentsOf: requestData)
            try inputPipe.fileHandleForWriting.write(contentsOf: Data([0x0A]))
            try inputPipe.fileHandleForWriting.close()
        } catch {
            controller.terminate()
        }

        let deadline = DispatchTime.now() + .seconds(30)
        while process.isRunning && DispatchTime.now() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if process.isRunning {
            controller.terminate()
        }
        process.waitUntilExit()
        streamGroup.wait()
        controller.clear(process)

        guard !Task.isCancelled else {
            return .failure(.internalError)
        }

        return PreflightProtocolParser.parse(
            stdout: dataStore.stdout,
            requestID: requestID,
            terminationStatus: process.terminationStatus,
            terminationReason: process.terminationReason
        )
    }

    private static func validateExecutable(_ url: URL) -> Bool {
        url.path.hasPrefix("/")
            && FileManager.default.fileExists(atPath: url.path)
            && FileManager.default.isExecutableFile(atPath: url.path)
    }
}

enum PreflightProtocolParser {
    static func parse(
        stdout: Data,
        requestID: UUID,
        terminationStatus: Int32,
        terminationReason: Process.TerminationReason
    ) -> PreflightOutcome {
        guard terminationReason == .exit, terminationStatus == 0,
              let text = String(data: stdout, encoding: .utf8) else {
            return .failure(.protocolError)
        }

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.last == "" else {
            return .failure(.protocolError)
        }

        var expectedSequence = 1
        var errorCode: PreflightErrorCode?
        var errorRawCode: String?
        var terminalOutcome: PreflightOutcome?
        var didFinish = false

        for line in lines.dropLast() {
            guard !line.isEmpty,
                  !didFinish,
                  let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["protocol_version"] as? Int == 1,
                  object["request_id"] as? String == requestID.uuidString.lowercased(),
                  object["sequence"] as? Int == expectedSequence,
                  let type = object["type"] as? String,
                  let payload = object["payload"] as? [String: Any]
            else {
                return .failure(.protocolError)
            }
            expectedSequence += 1

            switch type {
            case "progress":
                guard payload["stage"] as? String == "preflight",
                      ["running", "completed"].contains(payload["status"] as? String) else {
                    return .failure(.protocolError)
                }
            case "error":
                guard errorCode == nil,
                      let rawCode = payload["code"] as? String else {
                    return .failure(.protocolError)
                }
                errorRawCode = rawCode
                errorCode = PreflightErrorCode(rawValue: rawCode) ?? .internalError
            case "finished":
                didFinish = true
                guard let outcome = payload["outcome"] as? String else {
                    return .failure(.protocolError)
                }
                if outcome == "failed" {
                    guard let rawCode = payload["code"] as? String,
                          rawCode == errorRawCode,
                          let code = errorCode else {
                        return .failure(.protocolError)
                    }
                    terminalOutcome = .failure(code)
                } else if outcome == "succeeded" {
                    guard errorCode == nil,
                          let result = parseResult(payload["result"]) else {
                        return .failure(.protocolError)
                    }
                    terminalOutcome = .success(result)
                } else {
                    return .failure(.protocolError)
                }
            default:
                return .failure(.protocolError)
            }
        }

        return terminalOutcome ?? .failure(.protocolError)
    }

    private static func parseResult(_ value: Any?) -> PreflightResult? {
        guard let value = value as? [String: Any],
              let fileName = value["file_name"] as? String, !fileName.isEmpty,
              let duration = exactPositiveInteger(value["duration_ms"]),
              let format = value["container_format"] as? String, !format.isEmpty,
              let videoCountValue = exactPositiveInteger(value["video_stream_count"]),
              let audioCountValue = exactPositiveInteger(value["audio_stream_count"]),
              videoCountValue <= Int64(Int.max),
              audioCountValue <= Int64(Int.max) else {
            return nil
        }
        return PreflightResult(
            fileName: fileName,
            durationMilliseconds: duration,
            containerFormat: format,
            videoStreamCount: Int(videoCountValue),
            audioStreamCount: Int(audioCountValue)
        )
    }

    private static func exactPositiveInteger(_ value: Any?) -> Int64? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite,
              number.doubleValue == Double(number.int64Value),
              number.int64Value > 0 else {
            return nil
        }
        return number.int64Value
    }
}

private final class PreflightProcessController: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancellationRequested = false

    var isCancellationRequested: Bool {
        lock.withLock { cancellationRequested }
    }

    func register(_ process: Process) -> Bool {
        lock.withLock {
            guard !cancellationRequested else { return false }
            self.process = process
            return true
        }
    }

    func clear(_ process: Process) {
        lock.withLock {
            if self.process === process { self.process = nil }
        }
    }

    func terminate() {
        let registeredProcess = lock.withLock {
            cancellationRequested = true
            return process
        }
        if registeredProcess?.isRunning == true { registeredProcess?.terminate() }
    }
}

private final class PreflightStreamData: @unchecked Sendable {
    private let lock = NSLock()
    private var storedStdout = Data()
    private var storedStderr = Data()

    var stdout: Data { lock.withLock { storedStdout } }
    var stderr: Data { lock.withLock { storedStderr } }

    func setStdout(_ data: Data) { lock.withLock { storedStdout = data } }
    func setStderr(_ data: Data) { lock.withLock { storedStderr = data } }
}
