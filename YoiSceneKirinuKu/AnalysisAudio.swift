import CoreFoundation
import Foundation

enum AnalysisAudioErrorCode: String, CaseIterable, Sendable {
    case busy = "analysis_audio_busy"
    case jobInvalid = "analysis_audio_job_invalid"
    case sourceUnavailable = "analysis_audio_source_unavailable"
    case sourceChanged = "analysis_audio_source_changed"
    case probeFailed = "analysis_audio_probe_failed"
    case durationInvalid = "analysis_audio_duration_invalid"
    case insufficientSpace = "analysis_audio_insufficient_space"
    case ffmpegFailed = "analysis_audio_ffmpeg_failed"
    case invalid = "analysis_audio_invalid"
    case finalizationFailed = "analysis_audio_finalization_failed"
    case reuseInvalid = "analysis_audio_reuse_invalid"
    case protocolError = "analysis_audio_protocol_error"
}

struct AnalysisAudioResult: Equatable, Sendable {
    let reused: Bool
    let frameCount: Int64
    let durationMilliseconds: Int64
    let selectedStreamIndex: Int
}

enum AnalysisAudioOutcome: Equatable, Sendable {
    case success(AnalysisAudioResult)
    case stopped(jobID: UUID)
    case failure(AnalysisAudioErrorCode)
}

struct AnalysisAudioConfiguration: Sendable {
    let pythonExecutableURL: URL
    let scriptURL: URL
    let ffmpegExecutableURL: URL
    let ffprobeExecutableURL: URL
    let bundleRootURL: URL
    let workspaceRootURL: URL

    static func bundled(bundle: Bundle = .main, fileManager: FileManager = .default) -> AnalysisAudioConfiguration? {
        guard
            let script = bundle.url(forResource: "analysis_audio", withExtension: "py"),
            let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        let bundleRoot = bundle.bundleURL
        return AnalysisAudioConfiguration(
            pythonExecutableURL: bundleRoot.appendingPathComponent(
                "Contents/Frameworks/Python.framework/Versions/3.13/bin/python3.13"
            ),
            scriptURL: script,
            ffmpegExecutableURL: bundleRoot.appendingPathComponent("Contents/MacOS/ffmpeg"),
            ffprobeExecutableURL: bundleRoot.appendingPathComponent("Contents/MacOS/ffprobe"),
            bundleRootURL: bundleRoot,
            workspaceRootURL: applicationSupport
                .appendingPathComponent("local.YoiSceneKirinuKu", isDirectory: true)
                .appendingPathComponent("workspace", isDirectory: true)
        )
    }
}

protocol AnalysisAudioServicing: Sendable {
    func prepare(jobID: UUID, requestID: UUID) async -> AnalysisAudioOutcome
}

final class AnalysisAudioService: AnalysisAudioServicing, @unchecked Sendable {
    private let configuration: AnalysisAudioConfiguration?

    init(configuration: AnalysisAudioConfiguration? = .bundled()) {
        self.configuration = configuration
    }

    func prepare(jobID: UUID, requestID: UUID) async -> AnalysisAudioOutcome {
        guard let configuration,
              Self.validateExecutable(configuration.pythonExecutableURL),
              Self.validateExecutable(configuration.ffmpegExecutableURL),
              Self.validateExecutable(configuration.ffprobeExecutableURL),
              Self.validateRegularFile(configuration.scriptURL),
              let job = try? AnalysisJobService.loadJob(from: configuration.workspaceRootURL),
              job.jobID == jobID
        else { return .failure(.jobInvalid) }
        let body: [String: Any] = [
            "protocol_version": 1,
            "request_id": requestID.uuidString.lowercased(),
            "workspace_root": configuration.workspaceRootURL.path,
            "job_id": jobID.uuidString.lowercased(),
            "bundle_root": configuration.bundleRootURL.path,
            "ffmpeg_path": configuration.ffmpegExecutableURL.path,
            "ffprobe_path": configuration.ffprobeExecutableURL.path,
        ]
        guard let input = try? JSONSerialization.data(withJSONObject: body) else {
            return .failure(.protocolError)
        }
        let processResult = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: Self.run(input: input, configuration: configuration))
            }
        }
        return AnalysisAudioProtocolParser.parse(processResult, requestID: requestID)
    }

    private static func run(input: Data, configuration: AnalysisAudioConfiguration) -> AnalysisAudioProcessResult {
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = configuration.pythonExecutableURL
        process.arguments = [configuration.scriptURL.path]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        let streams = AnalysisAudioStreamData()
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
        return AnalysisAudioProcessResult(
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

struct AnalysisAudioProcessResult: Sendable {
    let stdout: Data
    let terminationStatus: Int32
    let terminationReason: Process.TerminationReason
    static let notStarted = AnalysisAudioProcessResult(
        stdout: Data(), terminationStatus: -1, terminationReason: .uncaughtSignal
    )
}

enum AnalysisAudioProtocolParser {
    static func parse(_ process: AnalysisAudioProcessResult, requestID: UUID) -> AnalysisAudioOutcome {
        guard process.terminationReason == .exit, process.terminationStatus == 0,
              let text = String(data: process.stdout, encoding: .utf8) else {
            return .failure(.protocolError)
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.last == "" else { return .failure(.protocolError) }
        var sequence = 1
        var progressIndex = 0
        let statuses = ["running", "completed"]
        let stopStatuses = ["stop_requested_detected", "child_exit_observed", "post_stop_state_verified"]
        var stopIndex = 0
        var recordedError: AnalysisAudioErrorCode?
        var terminal: AnalysisAudioOutcome?
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
                guard recordedError == nil,
                      Set(payload.keys) == Set(["stage", "status"]),
                      let stage = payload["stage"] as? String,
                      let status = payload["status"] as? String else { return .failure(.protocolError) }
                if stage == "analysis_audio", stopIndex == 0, progressIndex < statuses.count,
                   status == statuses[progressIndex] {
                    progressIndex += 1
                } else if stage == "analysis_stop", progressIndex == 1,
                          stopIndex < stopStatuses.count, status == stopStatuses[stopIndex] {
                    stopIndex += 1
                } else {
                    return .failure(.protocolError)
                }
            case "error":
                guard recordedError == nil, progressIndex == 1,
                      Set(payload.keys) == ["code"],
                      let raw = payload["code"] as? String,
                      let code = AnalysisAudioErrorCode(rawValue: raw)
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
                } else if outcome == "succeeded", recordedError == nil, progressIndex == 2,
                          Set(payload.keys) == Set(["outcome", "result"]),
                          let result = payload["result"] as? [String: Any],
                          Set(result.keys) == Set(["reused", "frame_count", "duration_ms", "selected_stream_index"]),
                          let reused = result["reused"] as? Bool,
                          let frames = integer(result["frame_count"]), frames > 0,
                          let duration = integer(result["duration_ms"]), duration > 0,
                          let stream = integer(result["selected_stream_index"]), stream >= 0,
                          stream <= Int64(Int.max) {
                    terminal = .success(AnalysisAudioResult(
                        reused: reused,
                        frameCount: frames,
                        durationMilliseconds: duration,
                        selectedStreamIndex: Int(stream)
                    ))
                } else if outcome == "stopped", recordedError == nil,
                          progressIndex == 1, stopIndex == stopStatuses.count,
                          Set(payload.keys) == Set(["outcome", "result"]),
                          let result = payload["result"] as? [String: Any],
                          Set(result.keys) == Set(["job_id", "state", "reason"]),
                          let rawID = result["job_id"] as? String,
                          let jobID = UUID(uuidString: rawID),
                          jobID.uuidString.lowercased() == rawID,
                          result["state"] as? String == "stopped",
                          result["reason"] as? String == "user_requested" {
                    terminal = .stopped(jobID: jobID)
                } else {
                    return .failure(.protocolError)
                }
            default:
                return .failure(.protocolError)
            }
        }
        return terminal ?? .failure(.protocolError)
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

private final class AnalysisAudioStreamData: @unchecked Sendable {
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
