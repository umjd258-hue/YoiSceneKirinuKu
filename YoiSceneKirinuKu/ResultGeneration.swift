import Foundation

enum ResultGenerationErrorCode: String, CaseIterable, Sendable {
    case busy = "result_busy"
    case jobInvalid = "result_job_invalid"
    case inputInvalid = "result_input_invalid"
    case finalizationFailed = "result_finalization_failed"
    case reuseInvalid = "result_reuse_invalid"
    case protocolError = "result_protocol_error"
}

struct ResultGenerationResult: Equatable, Sendable { let reused: Bool; let candidateCount: Int }
enum ResultGenerationOutcome: Equatable, Sendable { case success(ResultGenerationResult); case failure(ResultGenerationErrorCode) }

struct ResultGenerationConfiguration: Sendable {
    let processConfiguration: PythonProcessConfiguration
    let workspaceRootURL: URL
    static func bundled(bundle: Bundle = .main, fileManager: FileManager = .default) -> Self? {
        guard let script = bundle.url(forResource: "result_generation", withExtension: "py"),
              let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let python = bundle.bundleURL.appendingPathComponent("Contents/Frameworks/Python.framework/Versions/3.13/bin/python3.13")
        return Self(processConfiguration: .init(executableURL: python, scriptURL: script, argumentsPrefix: ["-I", "-S"], environment: ["LANG": "C.UTF-8", "PATH": "/nonexistent", "PYTHONNOUSERSITE": "1"]), workspaceRootURL: support.appendingPathComponent("local.YoiSceneKirinuKu/workspace", isDirectory: true))
    }
}

final class ResultGenerationService: @unchecked Sendable {
    private let configuration: ResultGenerationConfiguration?
    init(configuration: ResultGenerationConfiguration? = .bundled()) { self.configuration = configuration }
    func generate(jobID: UUID) async -> ResultGenerationOutcome {
        guard let configuration, let job = try? AnalysisJobService.loadJob(from: configuration.workspaceRootURL), job.jobID == jobID else { return .failure(.jobInvalid) }
        return ResultGenerationProtocolParser.parse(await PythonProcessService(configuration: configuration.processConfiguration).run(payload: ["workspace_root": .string(configuration.workspaceRootURL.path), "job_id": .string(jobID.uuidString.lowercased())]))
    }
}

enum ResultGenerationProtocolParser {
    static func parse(_ outcome: PythonProcessServiceOutcome) -> ResultGenerationOutcome {
        guard case .success(let execution) = outcome else { return .failure(.protocolError) }
        var started = false, completed = false
        var recorded: ResultGenerationErrorCode?
        for event in execution.events {
            switch event.type {
            case .progress:
                guard recorded == nil, case .string("result_generation") = event.payload["stage"], case .string(let status) = event.payload["status"], Set(event.payload.keys) == Set(["stage", "status"]) else { return .failure(.protocolError) }
                if status == "running", !started { started = true } else if status == "completed", started, !completed { completed = true } else { return .failure(.protocolError) }
            case .error:
                guard recorded == nil, Set(event.payload.keys) == ["code"], case .string(let raw) = event.payload["code"], let code = ResultGenerationErrorCode(rawValue: raw) else { return .failure(.protocolError) }
                recorded = code
            case .finished:
                guard case .string(let terminal) = event.payload["outcome"] else { return .failure(.protocolError) }
                if terminal == "failed", Set(event.payload.keys) == Set(["outcome", "code"]), case .string(let raw) = event.payload["code"], let error = recorded, error.rawValue == raw { return .failure(error) }
                if terminal == "succeeded", recorded == nil, Set(event.payload.keys) == Set(["outcome", "result"]), case .object(let result) = event.payload["result"], Set(result.keys) == Set(["reused", "candidate_count"]), case .boolean(let reused) = result["reused"], case .integer(let count) = result["candidate_count"], count >= 0, completed || reused { return .success(.init(reused: reused, candidateCount: Int(count))) }
                return .failure(.protocolError)
            }
        }
        return .failure(.protocolError)
    }
}
