import Foundation

enum AnalysisStopErrorCode: String, Equatable, Sendable {
    case jobInvalid = "stop_job_invalid"
    case notRunning = "stop_not_running"
    case alreadyRequested = "stop_already_requested"
    case writeFailed = "stop_write_failed"
}

enum AnalysisStopRequestOutcome: Equatable, Sendable {
    case requested(jobID: UUID, requestID: UUID)
    case failure(AnalysisStopErrorCode)
}

struct AnalysisStopRequestService: Sendable {
    let workspaceRootURL: URL

    func requestStop(jobID: UUID, requestID: UUID) -> AnalysisStopRequestOutcome {
        let current = workspaceRootURL.appendingPathComponent("current_job", isDirectory: true)
        let marker = current.appendingPathComponent("stop.requested")
        guard let values = try? current.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              values.isDirectory == true, values.isSymbolicLink != true,
              let job = try? AnalysisJobService.loadJob(from: workspaceRootURL),
              job.jobID == jobID else { return .failure(.jobInvalid) }
        guard job.state == .running else {
            return .failure(job.state == .stopRequested ? .alreadyRequested : .notRunning)
        }
        guard !FileManager.default.fileExists(atPath: marker.path) else {
            return .failure(.alreadyRequested)
        }
        do {
            try writeMarker(jobID: jobID, requestID: requestID, destination: marker)
            let updated = AnalysisJobDocument(
                schemaVersion: job.schemaVersion, jobID: job.jobID,
                startRequestID: job.startRequestID, stateRevision: job.stateRevision + 1,
                state: .stopRequested, source: job.source,
                selectedCharacterIDs: job.selectedCharacterIDs, failureCode: nil
            )
            try replaceJob(updated, requestID: requestID)
            let stored = try AnalysisJobService.loadJob(from: workspaceRootURL)
            guard stored.state == .stopRequested, stored.stateRevision == job.stateRevision + 1 else {
                return .failure(.writeFailed)
            }
            return .requested(jobID: jobID, requestID: requestID)
        } catch {
            return .failure(.writeFailed)
        }
    }

    private func writeMarker(jobID: UUID, requestID: UUID, destination: URL) throws {
        let partial = workspaceRootURL.appendingPathComponent(".partial/stop_\(requestID.uuidString.lowercased()).json.partial")
        let value: [String: Any] = [
            "schema_version": 1,
            "job_id": jobID.uuidString.lowercased(),
            "request_id": requestID.uuidString.lowercased(),
        ]
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) + Data([0x0A])
        try data.write(to: partial, options: .withoutOverwriting)
        let handle = try FileHandle(forWritingTo: partial)
        try handle.synchronize()
        try handle.close()
        try FileManager.default.moveItem(at: partial, to: destination)
    }

    private func replaceJob(_ job: AnalysisJobDocument, requestID: UUID) throws {
        let partial = workspaceRootURL.appendingPathComponent(".partial/job_\(requestID.uuidString.lowercased()).json.partial")
        let destination = workspaceRootURL.appendingPathComponent("current_job/job.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(job) + Data([0x0A])
        try data.write(to: partial, options: .withoutOverwriting)
        let handle = try FileHandle(forWritingTo: partial)
        try handle.synchronize()
        try handle.close()
        _ = try FileManager.default.replaceItemAt(destination, withItemAt: partial)
    }
}
