import CryptoKit
import XCTest
@testable import YoiSceneKirinuKu

final class ResultListTests: XCTestCase {
    func testStrictResultBecomesDeterministicSingleSelectionState() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sources = try writeSources(directory)
        let jobID = UUID()
        let characterID = UUID()
        let firstID = UUID()
        let secondID = UUID()
        let root: [String: Any] = [
            "schema_version": 1,
            "job_id": jobID.uuidString.lowercased(),
            "contract_version": "stage18-result-v1",
            "sources": sources,
            "candidates": [
                candidate(id: firstID, start: 1_000, end: 4_000, match: "matched", characterID: "char_\(characterID.uuidString.lowercased())", quality: "excellent"),
                candidate(id: secondID, start: 5_000, end: 9_000, match: "unknown", characterID: NSNull(), quality: "needs_review"),
            ],
        ]
        let service = ResultListService(configuration: nil)
        let state = try service.parse(root, jobID: jobID, currentJobURL: directory, characters: [.init(id: characterID, name: "人物A")])

        XCTAssertEqual(state.groups.flatMap(\.candidates).map(\.candidateID), [
            "candidate_\(firstID.uuidString.lowercased())",
            "candidate_\(secondID.uuidString.lowercased())",
        ])
        XCTAssertEqual(state.groups.map(\.title), ["人物A", "人物不明"])
        XCTAssertTrue(state.selectedCandidateIDs.isEmpty)
    }

    func testRejectsStaleAndMalformedResults() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var sources = try writeSources(directory)
        var fingerprint = try XCTUnwrap(sources["speaker_candidates"] as? [String: Any])
        fingerprint["digest"] = String(repeating: "0", count: 64)
        sources["speaker_candidates"] = fingerprint
        let jobID = UUID()
        let root: [String: Any] = [
            "schema_version": 1,
            "job_id": jobID.uuidString.lowercased(),
            "contract_version": "stage18-result-v1",
            "sources": sources,
            "candidates": [],
        ]
        let service = ResultListService(configuration: nil)
        XCTAssertThrowsError(try service.parse(root, jobID: jobID, currentJobURL: directory, characters: [])) {
            XCTAssertEqual($0 as? ResultListErrorCode, .stale)
        }

        var malformed = root
        malformed["extra"] = true
        XCTAssertThrowsError(try service.parse(malformed, jobID: jobID, currentJobURL: directory, characters: [])) {
            XCTAssertEqual($0 as? ResultListErrorCode, .schemaInvalid)
        }
    }

    private func makeDirectory() throws -> URL {
        let url = URL(fileURLWithPath: "/private/tmp/YoiSceneKirinuKu-ResultListTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    private func writeSources(_ directory: URL) throws -> [String: Any] {
        var result: [String: Any] = [:]
        for name in ["speaker_candidates", "speaker_decisions", "quality_decisions"] {
            let data = Data("\(name)\n".utf8)
            try data.write(to: directory.appendingPathComponent("\(name).json"))
            result[name] = [
                "algorithm": "sha256",
                "byte_count": data.count,
                "digest": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            ]
        }
        return result
    }

    private func candidate(id: UUID, start: Int, end: Int, match: String, characterID: Any, quality: String) -> [String: Any] {
        [
            "candidate_id": "candidate_\(id.uuidString.lowercased())",
            "start_ms": start,
            "end_ms": end,
            "match": match,
            "character_id": characterID,
            "match_reason": match == "matched" ? "unique_match" : "below_threshold",
            "top_similarity": match == "matched" ? 0.9 : 0.4,
            "quality": quality,
            "quality_reasons": [],
        ]
    }
}
