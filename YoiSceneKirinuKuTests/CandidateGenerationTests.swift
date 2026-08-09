import XCTest
@testable import YoiSceneKirinuKu

final class CandidateGenerationTests: XCTestCase {
    func testParserAcceptsStrictSuccessfulResult() {
        let requestID = UUID()
        let output = outputForSuccess(requestID: requestID)
        XCTAssertEqual(
            CandidateGenerationProtocolParser.parse(
                CandidateGenerationProcessResult(
                    stdout: Data(output.utf8), terminationStatus: 0, terminationReason: .exit
                ),
                requestID: requestID
            ),
            .success(CandidateGenerationResult(reused: false, vadSegmentCount: 2, candidateCount: 1))
        )
    }

    func testParserRejectsWrongProgressOrderAndUnknownEvent() {
        let requestID = UUID()
        let wrongOrder = outputForSuccess(requestID: requestID)
            .replacingOccurrences(of: #""status":"vad_completed""#, with: #""status":"completed""#, options: [], range: nil)
        XCTAssertEqual(parse(wrongOrder, requestID: requestID), .failure(.protocolError))

        let unknown = outputForSuccess(requestID: requestID)
            .replacingOccurrences(of: #""type":"progress""#, with: #""type":"unknown""#, options: [], range: nil)
        XCTAssertEqual(parse(unknown, requestID: requestID), .failure(.protocolError))
    }

    func testParserRequiresVerifiedCompletionAndNormalExit() {
        let requestID = UUID()
        XCTAssertEqual(
            parse(outputForSuccess(requestID: requestID).dropLast().description, requestID: requestID),
            .failure(.protocolError)
        )
        XCTAssertEqual(
            CandidateGenerationProtocolParser.parse(
                CandidateGenerationProcessResult(
                    stdout: Data(outputForSuccess(requestID: requestID).utf8),
                    terminationStatus: 1,
                    terminationReason: .exit
                ),
                requestID: requestID
            ),
            .failure(.protocolError)
        )
    }

    private func outputForSuccess(requestID: UUID) -> String {
        """
        {"protocol_version":1,"type":"progress","request_id":"\(requestID.uuidString.lowercased())","sequence":1,"payload":{"stage":"candidate_generation","status":"running"}}
        {"protocol_version":1,"type":"progress","request_id":"\(requestID.uuidString.lowercased())","sequence":2,"payload":{"stage":"candidate_generation","status":"vad_completed"}}
        {"protocol_version":1,"type":"progress","request_id":"\(requestID.uuidString.lowercased())","sequence":3,"payload":{"stage":"candidate_generation","status":"completed"}}
        {"protocol_version":1,"type":"finished","request_id":"\(requestID.uuidString.lowercased())","sequence":4,"payload":{"outcome":"succeeded","result":{"reused":false,"vad_segment_count":2,"candidate_count":1}}}

        """
    }

    private func parse(_ text: String, requestID: UUID) -> CandidateGenerationOutcome {
        CandidateGenerationProtocolParser.parse(
            CandidateGenerationProcessResult(
                stdout: Data(text.utf8), terminationStatus: 0, terminationReason: .exit
            ),
            requestID: requestID
        )
    }
}
