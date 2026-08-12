import Foundation

enum QualityDecisionErrorCode: String, CaseIterable, Sendable {
    case busy = "quality_decisions_busy"
    case jobInvalid = "quality_decisions_job_invalid"
    case inputUnavailable = "quality_decisions_input_unavailable"
    case inputInvalid = "quality_decisions_input_invalid"
    case finalizationFailed = "quality_decisions_finalization_failed"
    case reuseInvalid = "quality_decisions_reuse_invalid"
    case protocolError = "quality_decisions_protocol_error"
}

struct QualityDecisionResult: Equatable, Sendable {
    let reused: Bool
    let candidateCount: Int
}

enum QualityDecisionOutcome: Equatable, Sendable {
    case success(QualityDecisionResult)
    case failure(QualityDecisionErrorCode)
}

struct QualityDecisionConfiguration: Sendable {
    let processConfiguration: PythonProcessConfiguration
    let workspaceRootURL: URL

    static func bundled(bundle: Bundle = .main, fileManager: FileManager = .default) -> Self? {
        guard let script = bundle.url(forResource: "quality_decisions", withExtension: "py"),
              let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        let python = bundle.bundleURL.appendingPathComponent(
            "Contents/Frameworks/Python.framework/Versions/3.13/bin/python3.13"
        )
        return Self(
            processConfiguration: PythonProcessConfiguration(
                executableURL: python,
                scriptURL: script,
                argumentsPrefix: ["-I", "-S"],
                environment: ["LANG": "C.UTF-8", "PATH": "/nonexistent", "PYTHONNOUSERSITE": "1"]
            ),
            workspaceRootURL: applicationSupport
                .appendingPathComponent("local.YoiSceneKirinuKu", isDirectory: true)
                .appendingPathComponent("workspace", isDirectory: true)
        )
    }
}

protocol QualityDecisionServicing: Sendable {
    func generate(jobID: UUID) async -> QualityDecisionOutcome
}

final class QualityDecisionService: QualityDecisionServicing, @unchecked Sendable {
    private let configuration: QualityDecisionConfiguration?

    init(configuration: QualityDecisionConfiguration? = .bundled()) {
        self.configuration = configuration
    }

    func generate(jobID: UUID) async -> QualityDecisionOutcome {
        guard let configuration,
              let job = try? AnalysisJobService.loadJob(from: configuration.workspaceRootURL),
              job.jobID == jobID else { return .failure(.jobInvalid) }
        let outcome = await PythonProcessService(configuration: configuration.processConfiguration).run(payload: [
            "workspace_root": .string(configuration.workspaceRootURL.path),
            "job_id": .string(jobID.uuidString.lowercased()),
        ])
        return QualityDecisionProtocolParser.parse(outcome)
    }
}

enum QualityDecisionProtocolParser {
    static func parse(_ outcome: PythonProcessServiceOutcome) -> QualityDecisionOutcome {
        guard case .success(let execution) = outcome else { return .failure(.protocolError) }
        var started = false
        var completed = false
        var recordedError: QualityDecisionErrorCode?
        for event in execution.events {
            switch event.type {
            case .progress:
                guard recordedError == nil,
                      case .string("quality_decisions") = event.payload["stage"],
                      case .string(let status) = event.payload["status"],
                      Set(event.payload.keys) == Set(["stage", "status"])
                else { return .failure(.protocolError) }
                if status == "running", !started { started = true }
                else if status == "completed", started, !completed { completed = true }
                else { return .failure(.protocolError) }
            case .error:
                guard recordedError == nil, Set(event.payload.keys) == ["code"],
                      case .string(let raw) = event.payload["code"],
                      let code = QualityDecisionErrorCode(rawValue: raw)
                else { return .failure(.protocolError) }
                recordedError = code
            case .finished:
                guard case .string(let terminal) = event.payload["outcome"] else { return .failure(.protocolError) }
                if terminal == "failed", Set(event.payload.keys) == Set(["outcome", "code"]),
                   case .string(let raw) = event.payload["code"],
                   let error = recordedError, error.rawValue == raw { return .failure(error) }
                if terminal == "succeeded", recordedError == nil,
                   Set(event.payload.keys) == Set(["outcome", "result"]),
                   case .object(let result) = event.payload["result"],
                   Set(result.keys) == Set(["reused", "candidate_count"]),
                   case .boolean(let reused) = result["reused"],
                   let count = integer(result["candidate_count"]),
                   completed || reused {
                    return .success(QualityDecisionResult(reused: reused, candidateCount: count))
                }
                return .failure(.protocolError)
            }
        }
        return .failure(.protocolError)
    }

    private static func integer(_ value: PythonIPCValue?) -> Int? {
        guard case .integer(let raw) = value, raw >= 0, raw <= Int64(Int.max) else { return nil }
        return Int(raw)
    }
}
