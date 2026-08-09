import CoreFoundation
import Foundation

enum CandidateGenerationErrorCode: String, CaseIterable, Sendable {
    case busy = "candidate_busy"
    case jobInvalid = "candidate_job_invalid"
    case inputUnavailable = "candidate_input_unavailable"
    case vadFailed = "candidate_vad_failed"
    case vadInvalid = "candidate_vad_invalid"
    case generationFailed = "candidate_generation_failed"
    case finalizationFailed = "candidate_finalization_failed"
    case reuseInvalid = "candidate_reuse_invalid"
    case protocolError = "candidate_protocol_error"
}

struct CandidateGenerationResult: Equatable, Sendable {
    let reused: Bool
    let vadSegmentCount: Int
    let candidateCount: Int
}

enum CandidateGenerationOutcome: Equatable, Sendable {
    case success(CandidateGenerationResult)
    case failure(CandidateGenerationErrorCode)
}

struct CandidateGenerationConfiguration: Sendable {
    let pythonExecutableURL: URL
    let scriptURL: URL
    let workspaceRootURL: URL

    static func bundled(bundle: Bundle = .main, fileManager: FileManager = .default) -> CandidateGenerationConfiguration? {
        guard
            let python = bundle.object(forInfoDictionaryKey: "CandidateGenerationPythonExecutable") as? String,
            !python.isEmpty,
            let script = bundle.url(forResource: "candidate_generation", withExtension: "py"),
            let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        return CandidateGenerationConfiguration(
            pythonExecutableURL: URL(fileURLWithPath: python),
            scriptURL: script,
            workspaceRootURL: applicationSupport
                .appendingPathComponent("local.YoiSceneKirinuKu", isDirectory: true)
                .appendingPathComponent("workspace", isDirectory: true)
        )
    }
}

protocol CandidateGenerationServicing: Sendable {
    func generate(jobID: UUID, requestID: UUID) async -> CandidateGenerationOutcome
}

final class CandidateGenerationService: CandidateGenerationServicing, @unchecked Sendable {
    private let configuration: CandidateGenerationConfiguration?

    init(configuration: CandidateGenerationConfiguration? = .bundled()) {
        self.configuration = configuration
    }

    func generate(jobID: UUID, requestID: UUID) async -> CandidateGenerationOutcome {
        guard let configuration,
              Self.validateExecutable(configuration.pythonExecutableURL),
              Self.validateRegularFile(configuration.scriptURL),
              let job = try? AnalysisJobService.loadJob(from: configuration.workspaceRootURL),
              job.jobID == jobID
        else { return .failure(.jobInvalid) }
        let request: [String: Any] = [
            "protocol_version": 1,
            "request_id": requestID.uuidString.lowercased(),
            "workspace_root": configuration.workspaceRootURL.path,
            "job_id": jobID.uuidString.lowercased(),
        ]
        guard let input = try? JSONSerialization.data(withJSONObject: request) else {
            return .failure(.protocolError)
        }
        let processResult = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: Self.run(input: input, configuration: configuration))
            }
        }
        return CandidateGenerationProtocolParser.parse(processResult, requestID: requestID)
    }

    private static func run(input: Data, configuration: CandidateGenerationConfiguration) -> CandidateGenerationProcessResult {
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = configuration.pythonExecutableURL
        process.arguments = [configuration.scriptURL.path]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        let streams = CandidateGenerationStreamData()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            streams.setStdout(outputPipe.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            streams.setStderr(errorPipe.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }
        do {
            try process.run()
            try inputPipe.fileHandleForWriting.write(contentsOf: input)
            try inputPipe.fileHandleForWriting.write(contentsOf: Data([0x0A]))
            try inputPipe.fileHandleForWriting.close()
        } catch {
            if process.isRunning { process.terminate() }
            return .notStarted
        }
        process.waitUntilExit()
        group.wait()
        return CandidateGenerationProcessResult(
            stdout: streams.stdout,
            terminationStatus: process.terminationStatus,
            terminationReason: process.terminationReason
        )
    }

    private static func validateExecutable(_ url: URL) -> Bool {
        let resolved = url.resolvingSymlinksInPath()
        return validateRegularFile(resolved) && FileManager.default.isExecutableFile(atPath: resolved.path)
    }

    private static func validateRegularFile(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else {
            return false
        }
        return values.isRegularFile == true && values.isSymbolicLink != true
    }
}

struct CandidateGenerationProcessResult: Sendable {
    let stdout: Data
    let terminationStatus: Int32
    let terminationReason: Process.TerminationReason

    static let notStarted = CandidateGenerationProcessResult(
        stdout: Data(), terminationStatus: -1, terminationReason: .uncaughtSignal
    )
}

enum CandidateGenerationProtocolParser {
    static func parse(_ process: CandidateGenerationProcessResult, requestID: UUID) -> CandidateGenerationOutcome {
        guard process.terminationReason == .exit, process.terminationStatus == 0,
              let text = String(data: process.stdout, encoding: .utf8) else {
            return .failure(.protocolError)
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.last == "" else { return .failure(.protocolError) }
        var sequence = 1
        var progressIndex = 0
        let statuses = ["running", "vad_completed", "completed"]
        var recordedError: CandidateGenerationErrorCode?
        var terminal: CandidateGenerationOutcome?
        for line in lines.dropLast() {
            guard terminal == nil, !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  Set(event.keys) == Set(["protocol_version", "type", "request_id", "sequence", "payload"]),
                  event["protocol_version"] as? Int == 1,
                  event["request_id"] as? String == requestID.uuidString.lowercased(),
                  event["sequence"] as? Int == sequence,
                  let type = event["type"] as? String,
                  let payload = event["payload"] as? [String: Any]
            else { return .failure(.protocolError) }
            sequence += 1
            switch type {
            case "progress":
                guard recordedError == nil, progressIndex < statuses.count,
                      Set(payload.keys) == Set(["stage", "status"]),
                      payload["stage"] as? String == "candidate_generation",
                      payload["status"] as? String == statuses[progressIndex]
                else { return .failure(.protocolError) }
                progressIndex += 1
            case "error":
                guard recordedError == nil, progressIndex >= 1, progressIndex < 3,
                      Set(payload.keys) == ["code"],
                      let raw = payload["code"] as? String,
                      let code = CandidateGenerationErrorCode(rawValue: raw)
                else { return .failure(.protocolError) }
                recordedError = code
            case "finished":
                guard let outcome = payload["outcome"] as? String else {
                    return .failure(.protocolError)
                }
                if outcome == "failed", Set(payload.keys) == Set(["outcome", "code"]),
                   let raw = payload["code"] as? String,
                   let code = recordedError, code.rawValue == raw {
                    terminal = .failure(code)
                } else if outcome == "succeeded", recordedError == nil, progressIndex == 3,
                          Set(payload.keys) == Set(["outcome", "result"]),
                          let result = parseResult(payload["result"]) {
                    terminal = .success(result)
                } else {
                    return .failure(.protocolError)
                }
            default:
                return .failure(.protocolError)
            }
        }
        return terminal ?? .failure(.protocolError)
    }

    private static func parseResult(_ value: Any?) -> CandidateGenerationResult? {
        guard let result = value as? [String: Any],
              Set(result.keys) == Set(["reused", "vad_segment_count", "candidate_count"]),
              let reused = result["reused"] as? Bool,
              let vadCount = integer(result["vad_segment_count"]), vadCount >= 0,
              let candidateCount = integer(result["candidate_count"]), candidateCount >= 0,
              vadCount <= Int64(Int.max), candidateCount <= Int64(Int.max)
        else { return nil }
        return CandidateGenerationResult(
            reused: reused,
            vadSegmentCount: Int(vadCount),
            candidateCount: Int(candidateCount)
        )
    }

    private static func integer(_ value: Any?) -> Int64? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        guard double.isFinite, double.rounded() == double,
              double >= Double(Int64.min), double <= Double(Int64.max) else { return nil }
        return number.int64Value
    }
}

private final class CandidateGenerationStreamData: @unchecked Sendable {
    private let lock = NSLock()
    private var storedStdout = Data()
    private var storedStderr = Data()

    var stdout: Data {
        lock.lock()
        defer { lock.unlock() }
        return storedStdout
    }

    func setStdout(_ data: Data) {
        lock.lock()
        storedStdout = data
        lock.unlock()
    }

    func setStderr(_ data: Data) {
        lock.lock()
        storedStderr = data
        lock.unlock()
    }
}
