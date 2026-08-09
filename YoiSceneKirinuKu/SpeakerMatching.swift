import CoreFoundation
import Foundation

enum SpeakerMatchingErrorCode: String, CaseIterable, Sendable {
    case busy = "speaker_matching_busy"
    case jobInvalid = "speaker_matching_job_invalid"
    case inputUnavailable = "speaker_matching_input_unavailable"
    case candidatesInvalid = "speaker_matching_candidates_invalid"
    case characterInvalid = "speaker_matching_character_invalid"
    case modelUnavailable = "speaker_matching_model_unavailable"
    case embeddingFailed = "speaker_matching_embedding_failed"
    case embeddingInvalid = "speaker_matching_embedding_invalid"
    case finalizationFailed = "speaker_matching_finalization_failed"
    case reuseInvalid = "speaker_matching_reuse_invalid"
    case protocolError = "speaker_matching_protocol_error"
}

struct SpeakerMatchingResult: Equatable, Sendable {
    let reused: Bool
    let candidateCount: Int
    let selectedCharacterCount: Int
}

enum SpeakerMatchingOutcome: Equatable, Sendable {
    case success(SpeakerMatchingResult)
    case failure(SpeakerMatchingErrorCode)
}

struct SpeakerMatchingConfiguration: Sendable {
    let pythonExecutableURL: URL
    let scriptURL: URL
    let modelDirectoryURL: URL
    let workspaceRootURL: URL
    let charactersRootURL: URL

    static func bundled(bundle: Bundle = .main, fileManager: FileManager = .default) -> SpeakerMatchingConfiguration? {
        guard
            let python = bundle.object(forInfoDictionaryKey: "SpeakerMatchingPythonExecutable") as? String,
            let model = bundle.object(forInfoDictionaryKey: "SpeakerMatchingModelDirectory") as? String,
            !python.isEmpty, !model.isEmpty,
            let script = bundle.url(forResource: "speaker_matching", withExtension: "py"),
            let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        let root = applicationSupport.appendingPathComponent("local.YoiSceneKirinuKu", isDirectory: true)
        return SpeakerMatchingConfiguration(
            pythonExecutableURL: URL(fileURLWithPath: python), scriptURL: script,
            modelDirectoryURL: URL(fileURLWithPath: model, isDirectory: true),
            workspaceRootURL: root.appendingPathComponent("workspace", isDirectory: true),
            charactersRootURL: root.appendingPathComponent("characters", isDirectory: true)
        )
    }
}

protocol SpeakerMatchingServicing: Sendable {
    func match(jobID: UUID, requestID: UUID) async -> SpeakerMatchingOutcome
}

final class SpeakerMatchingService: SpeakerMatchingServicing, @unchecked Sendable {
    private let configuration: SpeakerMatchingConfiguration?

    init(configuration: SpeakerMatchingConfiguration? = .bundled()) {
        self.configuration = configuration
    }

    func match(jobID: UUID, requestID: UUID) async -> SpeakerMatchingOutcome {
        guard let configuration else { return .failure(.modelUnavailable) }
        guard Self.validateExecutable(configuration.pythonExecutableURL),
              Self.validateRegularFile(configuration.scriptURL)
        else { return .failure(.protocolError) }
        guard Self.validateDirectory(configuration.modelDirectoryURL) else {
            return .failure(.modelUnavailable)
        }
        guard
              let job = try? AnalysisJobService.loadJob(from: configuration.workspaceRootURL),
              job.jobID == jobID
        else { return .failure(.jobInvalid) }
        let request: [String: Any] = [
            "protocol_version": 1,
            "request_id": requestID.uuidString.lowercased(),
            "workspace_root": configuration.workspaceRootURL.path,
            "characters_root": configuration.charactersRootURL.path,
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
        return SpeakerMatchingProtocolParser.parse(processResult, requestID: requestID)
    }

    private static func run(input: Data, configuration: SpeakerMatchingConfiguration) -> SpeakerMatchingProcessResult {
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = configuration.pythonExecutableURL
        process.arguments = [configuration.scriptURL.path, configuration.modelDirectoryURL.path]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        let streams = SpeakerMatchingStreamData()
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
        return SpeakerMatchingProcessResult(
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
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return false }
        return values.isRegularFile == true && values.isSymbolicLink != true
    }

    private static func validateDirectory(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return false }
        return values.isDirectory == true && values.isSymbolicLink != true
    }
}

struct SpeakerMatchingProcessResult: Sendable {
    let stdout: Data
    let terminationStatus: Int32
    let terminationReason: Process.TerminationReason

    static let notStarted = SpeakerMatchingProcessResult(
        stdout: Data(), terminationStatus: -1, terminationReason: .uncaughtSignal
    )
}

enum SpeakerMatchingProtocolParser {
    static func parse(_ process: SpeakerMatchingProcessResult, requestID: UUID) -> SpeakerMatchingOutcome {
        guard process.terminationReason == .exit, process.terminationStatus == 0,
              let text = String(data: process.stdout, encoding: .utf8) else { return .failure(.protocolError) }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.last == "" else { return .failure(.protocolError) }
        var sequence = 1
        var started = false
        var completed = false
        var processed = 0
        var total: Int?
        var recordedError: SpeakerMatchingErrorCode?
        var terminal: SpeakerMatchingOutcome?
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
                guard recordedError == nil, payload["stage"] as? String == "speaker_matching",
                      let status = payload["status"] as? String else { return .failure(.protocolError) }
                if status == "running", !started, Set(payload.keys) == Set(["stage", "status"]) {
                    started = true
                } else if status == "processing", started, !completed,
                          Set(payload.keys) == Set(["stage", "status", "completed_count", "total_count"]),
                          let count = integer(payload["completed_count"]), let newTotal = integer(payload["total_count"]),
                          count == processed + 1, newTotal >= count, total == nil || total == newTotal {
                    processed = count
                    total = newTotal
                } else if status == "completed", started, !completed,
                          Set(payload.keys) == Set(["stage", "status"]), total == nil || processed == total {
                    completed = true
                } else { return .failure(.protocolError) }
            case "error":
                guard started, !completed, recordedError == nil, Set(payload.keys) == ["code"],
                      let raw = payload["code"] as? String,
                      let code = SpeakerMatchingErrorCode(rawValue: raw) else { return .failure(.protocolError) }
                recordedError = code
            case "finished":
                guard let outcome = payload["outcome"] as? String else { return .failure(.protocolError) }
                if outcome == "failed", Set(payload.keys) == Set(["outcome", "code"]),
                   let raw = payload["code"] as? String, let code = recordedError, code.rawValue == raw {
                    terminal = .failure(code)
                } else if outcome == "succeeded", recordedError == nil, completed,
                          Set(payload.keys) == Set(["outcome", "result"]), let result = parseResult(payload["result"]) {
                    terminal = .success(result)
                } else { return .failure(.protocolError) }
            default:
                return .failure(.protocolError)
            }
        }
        return terminal ?? .failure(.protocolError)
    }

    private static func parseResult(_ value: Any?) -> SpeakerMatchingResult? {
        guard let result = value as? [String: Any],
              Set(result.keys) == Set(["reused", "candidate_count", "selected_character_count"]),
              let reused = result["reused"] as? Bool,
              let candidates = integer(result["candidate_count"]),
              let characters = integer(result["selected_character_count"])
        else { return nil }
        return SpeakerMatchingResult(reused: reused, candidateCount: candidates, selectedCharacterCount: characters)
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        guard double.isFinite, double.rounded() == double, double >= 0, double <= Double(Int.max) else { return nil }
        return number.intValue
    }
}

private final class SpeakerMatchingStreamData: @unchecked Sendable {
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
