import XCTest
@testable import YoiSceneKirinuKu

final class AnalysisStoppingTests: XCTestCase {
    func testRequestSeparatesRunningFromStopRequestedAndWritesStrictMarker() throws {
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("YoiSceneKirinuKu-AnalysisStoppingTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("current_job"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".partial"), withIntermediateDirectories: false)
        let jobID = UUID()
        let job = AnalysisJobDocument(
            schemaVersion: 1, jobID: jobID, startRequestID: UUID(), stateRevision: 4,
            state: .running,
            source: AnalysisJobSource(path: "/private/tmp/artificial.mp4", fingerprint: SourceFingerprint(
                version: 1, algorithm: "sha256", byteCount: 1, digest: String(repeating: "0", count: 64)
            )),
            selectedCharacterIDs: ["char_\(UUID().uuidString.lowercased())"], failureCode: nil
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try (try encoder.encode(job) + Data([0x0A])).write(to: root.appendingPathComponent("current_job/job.json"))
        let requestID = UUID()

        XCTAssertEqual(
            AnalysisStopRequestService(workspaceRootURL: root).requestStop(jobID: jobID, requestID: requestID),
            .requested(jobID: jobID, requestID: requestID)
        )
        let stored = try AnalysisJobService.loadJob(from: root)
        XCTAssertEqual(stored.state, .stopRequested)
        XCTAssertEqual(stored.stateRevision, 5)
        let markerData = try Data(contentsOf: root.appendingPathComponent("current_job/stop.requested"))
        let marker = try XCTUnwrap(JSONSerialization.jsonObject(with: markerData) as? [String: Any])
        XCTAssertEqual(Set(marker.keys), ["schema_version", "job_id", "request_id"])
        XCTAssertEqual(marker["job_id"] as? String, jobID.uuidString.lowercased())
        XCTAssertEqual(marker["request_id"] as? String, requestID.uuidString.lowercased())
    }
}
