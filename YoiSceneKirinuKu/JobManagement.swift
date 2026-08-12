import CoreFoundation
import CryptoKit
import Foundation

enum AnalysisJobState: String, Codable, CaseIterable, Sendable {
    case startRequested = "start_requested"
    case preparing
    case running
    case stopRequested = "stop_requested"
    case stopped
    case completed
    case failed
    case recoveryRequired = "recovery_required"
}

struct SourceFingerprint: Codable, Equatable, Sendable {
    let version: Int
    let algorithm: String
    let byteCount: Int64
    let digest: String

    enum CodingKeys: String, CodingKey {
        case version, algorithm, digest
        case byteCount = "byte_count"
    }
}

struct AnalysisJobSource: Codable, Equatable, Sendable {
    let path: String
    let fingerprint: SourceFingerprint
}

struct AnalysisJobDocument: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let jobID: UUID
    let startRequestID: UUID
    let stateRevision: Int
    let state: AnalysisJobState
    let source: AnalysisJobSource
    let selectedCharacterIDs: [String]
    let failureCode: String?

    enum CodingKeys: String, CodingKey {
        case state, source
        case schemaVersion = "schema_version"
        case jobID = "job_id"
        case startRequestID = "start_request_id"
        case stateRevision = "state_revision"
        case selectedCharacterIDs = "selected_character_ids"
        case failureCode = "failure_code"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(jobID.uuidString.lowercased(), forKey: .jobID)
        try container.encode(startRequestID.uuidString.lowercased(), forKey: .startRequestID)
        try container.encode(stateRevision, forKey: .stateRevision)
        try container.encode(state, forKey: .state)
        try container.encode(source, forKey: .source)
        try container.encode(selectedCharacterIDs, forKey: .selectedCharacterIDs)
        if let failureCode {
            try container.encode(failureCode, forKey: .failureCode)
        } else {
            try container.encodeNil(forKey: .failureCode)
        }
    }
}

enum AnalysisJobErrorCode: String, CaseIterable, Sendable {
    case analysisBusy = "analysis_busy"
    case jobAlreadyExists = "job_already_exists"
    case jobNotFound = "job_not_found"
    case jobInvalid = "job_invalid"
    case jobWorkspaceInvalid = "job_workspace_invalid"
    case jobWriteFailed = "job_write_failed"
    case sourceUnavailable = "source_unavailable"
    case sourceChanged = "source_changed"
    case processNotStarted = "process_not_started"
    case protocolError = "protocol_error"
}

enum AnalysisJobOutcome: Equatable, Sendable {
    case success(jobID: UUID, state: AnalysisJobState)
    case failure(AnalysisJobErrorCode)
}

struct AnalysisJobConfiguration: Sendable {
    let pythonExecutableURL: URL
    let scriptURL: URL
    let workspaceRootURL: URL

    static func bundled(bundle: Bundle = .main, fileManager: FileManager = .default) -> AnalysisJobConfiguration? {
        guard let python = bundle.object(forInfoDictionaryKey: "AnalysisJobPythonExecutable") as? String,
              !python.isEmpty,
              let script = bundle.url(forResource: "analysis_job_runner", withExtension: "py"),
              let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return AnalysisJobConfiguration(
            pythonExecutableURL: URL(fileURLWithPath: python),
            scriptURL: script,
            workspaceRootURL: applicationSupport
                .appendingPathComponent("local.YoiSceneKirinuKu", isDirectory: true)
                .appendingPathComponent("workspace", isDirectory: true)
        )
    }
}

protocol AnalysisJobServicing: Sendable {
    func createJob(sourceURL: URL, characterIDs: [UUID], requestID: UUID) async -> AnalysisJobOutcome
    func recoverJob(requestID: UUID) async -> AnalysisJobOutcome
    func resumeJob(requestID: UUID) async -> AnalysisJobOutcome
    func resumeRecoveryJob(requestID: UUID) async -> AnalysisJobOutcome
    func prepareJob(jobID: UUID, requestID: UUID) async -> AnalysisJobOutcome
    func failJob(jobID: UUID, failureCode: String, requestID: UUID) async -> AnalysisJobOutcome
}

final class AnalysisJobService: AnalysisJobServicing, @unchecked Sendable {
    private let configuration: AnalysisJobConfiguration?

    init(configuration: AnalysisJobConfiguration? = .bundled()) {
        self.configuration = configuration
    }

    func createJob(sourceURL: URL, characterIDs: [UUID], requestID: UUID) async -> AnalysisJobOutcome {
        guard let configuration, !characterIDs.isEmpty, Set(characterIDs).count == characterIDs.count else {
            return .failure(.jobInvalid)
        }
        let fingerprint: SourceFingerprint
        do {
            fingerprint = try Self.fingerprint(sourceURL)
        } catch let code as AnalysisJobErrorCodeError {
            return .failure(code.code)
        } catch {
            return .failure(.sourceUnavailable)
        }
        let job = AnalysisJobDocument(
            schemaVersion: 1,
            jobID: UUID(),
            startRequestID: requestID,
            stateRevision: 0,
            state: .startRequested,
            source: AnalysisJobSource(path: sourceURL.path, fingerprint: fingerprint),
            selectedCharacterIDs: characterIDs.map { "char_\($0.uuidString.lowercased())" },
            failureCode: nil
        )
        return await execute(operation: "create_job", job: job, requestID: requestID, configuration: configuration)
    }

    func recoverJob(requestID: UUID) async -> AnalysisJobOutcome {
        guard let configuration else {
            return .failure(.jobNotFound)
        }
        let job: AnalysisJobDocument
        do {
            job = try Self.loadJob(from: configuration.workspaceRootURL)
        } catch let error as AnalysisJobErrorCodeError {
            return .failure(error.code)
        } catch {
            return .failure(.jobInvalid)
        }
        return await execute(operation: "recover_job", job: job, requestID: requestID, configuration: configuration)
    }

    func resumeJob(requestID: UUID) async -> AnalysisJobOutcome {
        guard let configuration,
              let job = try? Self.loadJob(from: configuration.workspaceRootURL),
              job.state == .stopped else { return .failure(.jobInvalid) }
        return await execute(operation: "resume_job", job: job, requestID: requestID, configuration: configuration)
    }

    func resumeRecoveryJob(requestID: UUID) async -> AnalysisJobOutcome {
        guard let configuration,
              let job = try? Self.loadJob(from: configuration.workspaceRootURL),
              job.state == .recoveryRequired else { return .failure(.jobInvalid) }
        return await execute(
            operation: "resume_recovery_job", job: job, requestID: requestID, configuration: configuration
        )
    }

    func failJob(jobID: UUID, failureCode: String, requestID: UUID) async -> AnalysisJobOutcome {
        guard let configuration,
              !failureCode.isEmpty, failureCode.count <= 100,
              let job = try? Self.loadJob(from: configuration.workspaceRootURL),
              job.jobID == jobID,
              ![.completed, .failed, .stopped].contains(job.state) else {
            return .failure(.jobInvalid)
        }
        let failed = AnalysisJobDocument(
            schemaVersion: job.schemaVersion,
            jobID: job.jobID,
            startRequestID: job.startRequestID,
            stateRevision: job.stateRevision + 1,
            state: .failed,
            source: job.source,
            selectedCharacterIDs: job.selectedCharacterIDs,
            failureCode: failureCode
        )
        return await execute(operation: "fail_job", job: failed, requestID: requestID, configuration: configuration)
    }

    func prepareJob(jobID: UUID, requestID: UUID) async -> AnalysisJobOutcome {
        guard let configuration,
              let job = try? Self.loadJob(from: configuration.workspaceRootURL),
              job.jobID == jobID, job.state == .startRequested else {
            return .failure(.jobInvalid)
        }
        let preparing = AnalysisJobDocument(
            schemaVersion: job.schemaVersion,
            jobID: job.jobID,
            startRequestID: job.startRequestID,
            stateRevision: job.stateRevision + 1,
            state: .preparing,
            source: job.source,
            selectedCharacterIDs: job.selectedCharacterIDs,
            failureCode: nil
        )
        return await execute(operation: "prepare_job", job: preparing, requestID: requestID, configuration: configuration)
    }

    private static func jobURL(in workspace: URL) -> URL {
        workspace.appendingPathComponent("current_job/job.json")
    }

    static func loadJob(from workspace: URL) throws -> AnalysisJobDocument {
        let url = jobURL(in: workspace)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AnalysisJobErrorCodeError(.jobNotFound)
        }
        do {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw AnalysisJobErrorCodeError(.jobInvalid)
            }
            let data = try Data(contentsOf: url)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  Set(root.keys) == Set(["schema_version", "job_id", "start_request_id", "state_revision", "state", "source", "selected_character_ids", "failure_code"]),
                  let source = root["source"] as? [String: Any],
                  Set(source.keys) == Set(["path", "fingerprint"]),
                  let fingerprint = source["fingerprint"] as? [String: Any],
                  Set(fingerprint.keys) == Set(["version", "algorithm", "byte_count", "digest"]) else {
                throw AnalysisJobErrorCodeError(.jobInvalid)
            }
            return try JSONDecoder().decode(AnalysisJobDocument.self, from: data)
        } catch let error as AnalysisJobErrorCodeError {
            throw error
        } catch {
            throw AnalysisJobErrorCodeError(.jobInvalid)
        }
    }

    private func execute(
        operation: String,
        job: AnalysisJobDocument,
        requestID: UUID,
        configuration: AnalysisJobConfiguration
    ) async -> AnalysisJobOutcome {
        guard Self.validateExecutable(configuration.pythonExecutableURL),
              Self.validateRegularFile(configuration.scriptURL),
              let jobObject = Self.jsonObject(job) else {
            return .failure(.processNotStarted)
        }
        let body: [String: Any] = [
            "protocol_version": 1,
            "request_id": requestID.uuidString.lowercased(),
            "operation": operation,
            "workspace_root": configuration.workspaceRootURL.path,
            "job": jobObject,
        ]
        guard let input = try? JSONSerialization.data(withJSONObject: body) else {
            return .failure(.protocolError)
        }
        let result = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: Self.run(input: input, configuration: configuration))
            }
        }
        return AnalysisJobProtocolParser.parse(result, requestID: requestID)
    }

    private static func run(input: Data, configuration: AnalysisJobConfiguration) -> JobProcessResult {
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = configuration.pythonExecutableURL
        process.arguments = [configuration.scriptURL.path]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        let group = DispatchGroup()
        let streams = JobStreamData()
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
        return JobProcessResult(
            stdout: streams.stdout,
            terminationStatus: process.terminationStatus,
            terminationReason: process.terminationReason
        )
    }

    static func fingerprint(_ url: URL) throws -> SourceFingerprint {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey, .fileResourceIdentifierKey]
        let before = try url.resourceValues(forKeys: keys)
        guard before.isRegularFile == true, before.isSymbolicLink != true else {
            throw AnalysisJobErrorCodeError(.sourceUnavailable)
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        var byteCount: Int64 = 0
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
            hasher.update(data: data)
            byteCount += Int64(data.count)
        }
        let after = try url.resourceValues(forKeys: keys)
        guard before.fileSize == after.fileSize,
              before.contentModificationDate == after.contentModificationDate,
              String(describing: before.fileResourceIdentifier) == String(describing: after.fileResourceIdentifier),
              byteCount == Int64(after.fileSize ?? -1) else {
            throw AnalysisJobErrorCodeError(.sourceChanged)
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return SourceFingerprint(version: 1, algorithm: "sha256", byteCount: byteCount, digest: digest)
    }

    private static func jsonObject(_ job: AnalysisJobDocument) -> [String: Any]? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(job) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func validateExecutable(_ url: URL) -> Bool {
        let resolved = url.resolvingSymlinksInPath()
        return validateRegularFile(resolved) && FileManager.default.isExecutableFile(atPath: resolved.path)
    }

    private static func validateRegularFile(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return false }
        return values.isRegularFile == true && values.isSymbolicLink != true
    }
}

private struct AnalysisJobErrorCodeError: Error {
    let code: AnalysisJobErrorCode
    init(_ code: AnalysisJobErrorCode) { self.code = code }
}

struct JobProcessResult: Sendable {
    let stdout: Data
    let terminationStatus: Int32
    let terminationReason: Process.TerminationReason
    static let notStarted = JobProcessResult(stdout: Data(), terminationStatus: -1, terminationReason: .uncaughtSignal)
}

enum AnalysisJobProtocolParser {
    static func parse(_ process: JobProcessResult, requestID: UUID) -> AnalysisJobOutcome {
        guard process.terminationReason == .exit, process.terminationStatus == 0,
              let text = String(data: process.stdout, encoding: .utf8) else { return .failure(.protocolError) }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.last == "" else { return .failure(.protocolError) }
        var sequence = 1
        let expectedProgressStages = ["job_lock", "job_ready"]
        var progressIndex = 0
        var recordedError: AnalysisJobErrorCode?
        var terminal: AnalysisJobOutcome?
        for line in lines.dropLast() {
            guard terminal == nil, !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  Set(event.keys) == Set(["protocol_version", "type", "request_id", "sequence", "payload"]),
                  event["protocol_version"] as? Int == 1,
                  event["request_id"] as? String == requestID.uuidString.lowercased(),
                  event["sequence"] as? Int == sequence,
                  let type = event["type"] as? String,
                  let payload = event["payload"] as? [String: Any] else { return .failure(.protocolError) }
            sequence += 1
            switch type {
            case "progress":
                guard Set(payload.keys) == Set(["stage", "status"]),
                      progressIndex < expectedProgressStages.count,
                      payload["stage"] as? String == expectedProgressStages[progressIndex],
                      payload["status"] as? String == "completed" else { return .failure(.protocolError) }
                progressIndex += 1
            case "error":
                guard recordedError == nil, Set(payload.keys) == ["code"],
                      let raw = payload["code"] as? String,
                      let code = AnalysisJobErrorCode(rawValue: raw) else { return .failure(.protocolError) }
                recordedError = code
            case "finished":
                guard let outcome = payload["outcome"] as? String else { return .failure(.protocolError) }
                if outcome == "succeeded", recordedError == nil,
                   progressIndex == expectedProgressStages.count,
                   Set(payload.keys) == Set(["outcome", "result"]),
                   let result = payload["result"] as? [String: Any],
                   Set(result.keys) == Set(["job_id", "state"]),
                   let rawID = result["job_id"] as? String,
                   let jobID = UUID(uuidString: rawID),
                   jobID.uuidString.lowercased() == rawID,
                   let rawState = result["state"] as? String,
                   let state = AnalysisJobState(rawValue: rawState) {
                    terminal = .success(jobID: jobID, state: state)
                } else if outcome == "failed", Set(payload.keys) == Set(["outcome", "code"]),
                          let raw = payload["code"] as? String,
                          let code = recordedError, code.rawValue == raw {
                    terminal = .failure(code)
                } else {
                    return .failure(.protocolError)
                }
            default:
                return .failure(.protocolError)
            }
        }
        return terminal ?? .failure(.protocolError)
    }
}

private final class JobStreamData: @unchecked Sendable {
    private let lock = NSLock()
    private var storedStdout = Data()
    private var storedStderr = Data()
    var stdout: Data { lock.withLock { storedStdout } }
    func setStdout(_ data: Data) { lock.withLock { storedStdout = data } }
    func setStderr(_ data: Data) { lock.withLock { storedStderr = data } }
}

enum AnalysisPipelineError: Equatable, Sendable {
    case invalidInput
    case cancelled
    case preflight(PreflightErrorCode)
    case character(CharacterRegistrationErrorCode)
    case job(AnalysisJobErrorCode)
    case audio(AnalysisAudioErrorCode)
}

enum AnalysisPipelineOutcome: Equatable, Sendable {
    case ready(jobID: UUID, state: AnalysisJobState, audio: AnalysisAudioResult)
    case stopped(jobID: UUID)
    case failure(AnalysisPipelineError)
}

struct AnalysisPipelineOrchestrator: Sendable {
    let preflightService: any PreflightServicing
    let characterService: any CharacterRegistrationServicing
    let jobService: any AnalysisJobServicing
    let audioService: any AnalysisAudioServicing

    func start(sourceURL: URL, characterIDs: [UUID], requestID: UUID) async -> AnalysisPipelineOutcome {
        guard !characterIDs.isEmpty, Set(characterIDs).count == characterIDs.count else {
            return .failure(.invalidInput)
        }
        guard !Task.isCancelled else { return .failure(.cancelled) }
        switch await preflightService.run(sourceURL: sourceURL, requestID: requestID) {
        case .success:
            break
        case .failure(let code):
            return .failure(.preflight(code))
        }
        guard !Task.isCancelled else { return .failure(.cancelled) }

        for characterID in characterIDs {
            switch await characterService.regenerateEmbeddings(for: characterID, requestID: UUID()) {
            case .success:
                break
            case .failure(let code):
                return .failure(.character(code))
            }
        }
        let characters: [RegisteredCharacter]
        switch await characterService.loadCharacters(requestID: UUID()) {
        case .success(let loaded):
            characters = loaded
        case .failure(let code):
            return .failure(.character(code))
        }
        guard Set(characterIDs).isSubset(of: Set(characters.map(\.characterID))) else {
            return .failure(.character(.characterNotFound))
        }
        guard !Task.isCancelled else { return .failure(.cancelled) }

        switch await jobService.createJob(sourceURL: sourceURL, characterIDs: characterIDs, requestID: requestID) {
        case .failure(let code):
            return .failure(.job(code))
        case .success(let jobID, .startRequested):
            return await prepare(jobID: jobID, requestID: UUID())
        case .success:
            return .failure(.job(.jobInvalid))
        }
    }

    func resumeStopped(requestID: UUID) async -> AnalysisPipelineOutcome {
        switch await jobService.resumeJob(requestID: requestID) {
        case .success(let jobID, .preparing):
            return await prepareAudio(jobID: jobID, requestID: UUID())
        case .failure(let code):
            return .failure(.job(code))
        case .success:
            return .failure(.job(.jobInvalid))
        }
    }

    func resumeRecovery(requestID: UUID) async -> AnalysisPipelineOutcome {
        switch await jobService.resumeRecoveryJob(requestID: requestID) {
        case .success(let jobID, .preparing):
            return await prepareAudio(jobID: jobID, requestID: UUID())
        case .failure(let code):
            return .failure(.job(code))
        case .success:
            return .failure(.job(.jobInvalid))
        }
    }

    private func prepare(jobID: UUID, requestID: UUID) async -> AnalysisPipelineOutcome {
        switch await jobService.prepareJob(jobID: jobID, requestID: requestID) {
        case .success(_, .preparing):
            return await prepareAudio(jobID: jobID, requestID: UUID())
        case .failure(let code):
            return .failure(.job(code))
        case .success:
            return .failure(.job(.jobInvalid))
        }
    }

    private func prepareAudio(jobID: UUID, requestID: UUID) async -> AnalysisPipelineOutcome {
        guard !Task.isCancelled else { return .failure(.cancelled) }
        switch await audioService.prepare(jobID: jobID, requestID: requestID) {
        case .success(let result):
            return .ready(jobID: jobID, state: .preparing, audio: result)
        case .stopped(let stoppedJobID):
            return .stopped(jobID: stoppedJobID)
        case .failure(let code):
            _ = await jobService.failJob(
                jobID: jobID,
                failureCode: code.rawValue,
                requestID: UUID()
            )
            return .failure(.audio(code))
        }
    }
}
