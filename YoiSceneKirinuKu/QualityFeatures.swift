import Foundation

enum QualityFeatureErrorCode: String, CaseIterable, Sendable {
    case busy = "quality_features_busy"
    case jobInvalid = "quality_features_job_invalid"
    case inputUnavailable = "quality_features_input_unavailable"
    case inputInvalid = "quality_features_input_invalid"
    case processingFailed = "quality_features_processing_failed"
    case finalizationFailed = "quality_features_finalization_failed"
    case reuseInvalid = "quality_features_reuse_invalid"
    case protocolError = "quality_features_protocol_error"
}

struct QualityFeatureResult: Equatable, Sendable {
    let reused: Bool
    let candidateCount: Int
}

enum QualityFeatureOutcome: Equatable, Sendable {
    case success(QualityFeatureResult)
    case failure(QualityFeatureErrorCode)
}

struct QualityFeatureConfiguration: Sendable {
    let processConfiguration: PythonProcessConfiguration
    let workspaceRootURL: URL

    static func bundled(bundle: Bundle = .main, fileManager: FileManager = .default) -> Self? {
        guard let script = bundle.url(forResource: "quality_features", withExtension: "py"),
              let applicationSupport = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
              ).first else { return nil }
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

protocol QualityFeatureServicing: Sendable {
    func generate(jobID: UUID) async -> QualityFeatureOutcome
}

final class QualityFeatureService: QualityFeatureServicing, @unchecked Sendable {
    private let configuration: QualityFeatureConfiguration?

    init(configuration: QualityFeatureConfiguration? = .bundled()) {
        self.configuration = configuration
    }

    func generate(jobID: UUID) async -> QualityFeatureOutcome {
        guard let configuration,
              let job = try? AnalysisJobService.loadJob(from: configuration.workspaceRootURL),
              job.jobID == jobID else { return .failure(.jobInvalid) }
        let service = PythonProcessService(configuration: configuration.processConfiguration)
        let outcome = await service.run(payload: [
            "workspace_root": .string(configuration.workspaceRootURL.path),
            "job_id": .string(jobID.uuidString.lowercased()),
        ])
        return QualityFeatureProtocolParser.parse(outcome)
    }
}

enum QualityFeatureProtocolParser {
    static func parse(_ outcome: PythonProcessServiceOutcome) -> QualityFeatureOutcome {
        guard case .success(let execution) = outcome else { return .failure(.protocolError) }
        var started = false
        var completed = false
        var processed = 0
        var total: Int?
        var recordedError: QualityFeatureErrorCode?
        for event in execution.events {
            switch event.type {
            case .progress:
                guard recordedError == nil,
                      case .string("quality_features") = event.payload["stage"],
                      case .string(let status) = event.payload["status"] else {
                    return .failure(.protocolError)
                }
                if status == "running", !started,
                   Set(event.payload.keys) == Set(["stage", "status"]) {
                    started = true
                } else if status == "processing", started, !completed,
                          Set(event.payload.keys) == Set(["stage", "status", "completed_count", "total_count"]),
                          let count = integer(event.payload["completed_count"]),
                          let newTotal = integer(event.payload["total_count"]),
                          count == processed + 1, newTotal >= count,
                          total == nil || total == newTotal {
                    processed = count
                    total = newTotal
                } else if status == "completed", started, !completed,
                          Set(event.payload.keys) == Set(["stage", "status"]),
                          total == nil || processed == total {
                    completed = true
                } else { return .failure(.protocolError) }
            case .error:
                guard recordedError == nil, Set(event.payload.keys) == ["code"],
                      case .string(let raw) = event.payload["code"],
                      let code = QualityFeatureErrorCode(rawValue: raw) else {
                    return .failure(.protocolError)
                }
                recordedError = code
            case .finished:
                guard case .string(let terminal) = event.payload["outcome"] else {
                    return .failure(.protocolError)
                }
                if terminal == "failed", Set(event.payload.keys) == Set(["outcome", "code"]),
                   case .string(let raw) = event.payload["code"],
                   let error = recordedError, error.rawValue == raw {
                    return .failure(error)
                }
                if terminal == "succeeded", recordedError == nil,
                   Set(event.payload.keys) == Set(["outcome", "result"]),
                   case .object(let result) = event.payload["result"],
                   Set(result.keys) == Set(["reused", "candidate_count"]),
                   case .boolean(let reused) = result["reused"],
                   let count = integer(result["candidate_count"]),
                   (completed || reused) {
                    return .success(QualityFeatureResult(reused: reused, candidateCount: count))
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
