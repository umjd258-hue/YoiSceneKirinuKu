import XCTest
@testable import YoiSceneKirinuKu

final class SpeakerMatchingTests: XCTestCase {
    func testParserAcceptsStrictSuccessWithProcessing() {
        let requestID = UUID()
        let id = requestID.uuidString.lowercased()
        let output = """
        {"protocol_version":1,"type":"progress","request_id":"\(id)","sequence":1,"payload":{"stage":"speaker_matching","status":"running"}}
        {"protocol_version":1,"type":"progress","request_id":"\(id)","sequence":2,"payload":{"stage":"speaker_matching","status":"processing","completed_count":1,"total_count":2}}
        {"protocol_version":1,"type":"progress","request_id":"\(id)","sequence":3,"payload":{"stage":"speaker_matching","status":"processing","completed_count":2,"total_count":2}}
        {"protocol_version":1,"type":"progress","request_id":"\(id)","sequence":4,"payload":{"stage":"speaker_matching","status":"completed"}}
        {"protocol_version":1,"type":"finished","request_id":"\(id)","sequence":5,"payload":{"outcome":"succeeded","result":{"reused":false,"candidate_count":2,"selected_character_count":1}}}

        """
        XCTAssertEqual(parse(output, requestID), .success(.init(reused: false, candidateCount: 2, selectedCharacterCount: 1)))
    }

    func testParserAcceptsZeroCandidatesWithoutProcessing() {
        let requestID = UUID()
        let id = requestID.uuidString.lowercased()
        let output = """
        {"protocol_version":1,"type":"progress","request_id":"\(id)","sequence":1,"payload":{"stage":"speaker_matching","status":"running"}}
        {"protocol_version":1,"type":"progress","request_id":"\(id)","sequence":2,"payload":{"stage":"speaker_matching","status":"completed"}}
        {"protocol_version":1,"type":"finished","request_id":"\(id)","sequence":3,"payload":{"outcome":"succeeded","result":{"reused":true,"candidate_count":0,"selected_character_count":1}}}

        """
        XCTAssertEqual(parse(output, requestID), .success(.init(reused: true, candidateCount: 0, selectedCharacterCount: 1)))
    }

    func testParserRejectsSkippedProgressAndRawScorePayload() {
        let requestID = UUID()
        let id = requestID.uuidString.lowercased()
        let skipped = """
        {"protocol_version":1,"type":"progress","request_id":"\(id)","sequence":1,"payload":{"stage":"speaker_matching","status":"running"}}
        {"protocol_version":1,"type":"progress","request_id":"\(id)","sequence":2,"payload":{"stage":"speaker_matching","status":"processing","completed_count":2,"total_count":2}}
        """ + "\n"
        XCTAssertEqual(parse(skipped, requestID), .failure(.protocolError))

        let score = """
        {"protocol_version":1,"type":"progress","request_id":"\(id)","sequence":1,"payload":{"stage":"speaker_matching","status":"running","cosine_similarity":0.9}}
        """ + "\n"
        XCTAssertEqual(parse(score, requestID), .failure(.protocolError))
    }

    private func parse(_ output: String, _ requestID: UUID) -> SpeakerMatchingOutcome {
        SpeakerMatchingProtocolParser.parse(
            .init(stdout: Data(output.utf8), terminationStatus: 0, terminationReason: .exit),
            requestID: requestID
        )
    }
}
