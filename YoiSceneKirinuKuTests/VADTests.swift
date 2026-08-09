import XCTest
@testable import YoiSceneKirinuKu

final class VADTests: XCTestCase {
    func testProtocolParserAcceptsVerifiedSegmentsAndEmptyResult() {
        let requestID = UUID()
        let output = successfulOutput(requestID: requestID, result: """
        {"frame_ms":30,"segment_count":2,"segments":[{"start_ms":300,"end_ms":810},{"start_ms":1020,"end_ms":1620}]}
        """)
        XCTAssertEqual(
            parse(output, requestID: requestID),
            .success(VADResult(frameMilliseconds: 30, segments: [
                VADSegment(startMilliseconds: 300, endMilliseconds: 810),
                VADSegment(startMilliseconds: 1_020, endMilliseconds: 1_620),
            ]))
        )

        let empty = successfulOutput(
            requestID: requestID,
            result: #"{"frame_ms":30,"segment_count":0,"segments":[]}"#
        )
        XCTAssertEqual(parse(empty, requestID: requestID), .success(VADResult(frameMilliseconds: 30, segments: [])))
    }

    func testProtocolParserRejectsInvalidIntervalsAndMissingCompletion() {
        let requestID = UUID()
        let overlap = successfulOutput(requestID: requestID, result: """
        {"frame_ms":30,"segment_count":2,"segments":[{"start_ms":300,"end_ms":810},{"start_ms":800,"end_ms":1000}]}
        """)
        XCTAssertEqual(parse(overlap, requestID: requestID), .failure(.protocolError))

        let short = successfulOutput(requestID: requestID, result: """
        {"frame_ms":30,"segment_count":1,"segments":[{"start_ms":300,"end_ms":330}]}
        """)
        XCTAssertEqual(parse(short, requestID: requestID), .failure(.protocolError))

        let missingCompleted = """
        {"protocol_version":1,"type":"progress","request_id":"\(requestID.uuidString.lowercased())","sequence":1,"payload":{"stage":"vad","status":"running"}}
        {"protocol_version":1,"type":"finished","request_id":"\(requestID.uuidString.lowercased())","sequence":2,"payload":{"outcome":"succeeded","result":{"frame_ms":30,"segment_count":0,"segments":[]}}}

        """
        XCTAssertEqual(parse(missingCompleted, requestID: requestID), .failure(.protocolError))
    }

    func testProtocolParserRequiresKnownMatchingErrorAndNormalExit() {
        let requestID = UUID()
        let failed = """
        {"protocol_version":1,"type":"progress","request_id":"\(requestID.uuidString.lowercased())","sequence":1,"payload":{"stage":"vad","status":"running"}}
        {"protocol_version":1,"type":"error","request_id":"\(requestID.uuidString.lowercased())","sequence":2,"payload":{"code":"vad_input_invalid"}}
        {"protocol_version":1,"type":"finished","request_id":"\(requestID.uuidString.lowercased())","sequence":3,"payload":{"outcome":"failed","code":"vad_input_invalid"}}

        """
        XCTAssertEqual(parse(failed, requestID: requestID), .failure(.inputInvalid))
        XCTAssertEqual(
            VADProtocolParser.parse(
                VADProcessResult(stdout: Data(failed.utf8), terminationStatus: 1, terminationReason: .exit),
                requestID: requestID
            ),
            .failure(.protocolError)
        )
    }

    private func successfulOutput(requestID: UUID, result: String) -> String {
        """
        {"protocol_version":1,"type":"progress","request_id":"\(requestID.uuidString.lowercased())","sequence":1,"payload":{"stage":"vad","status":"running"}}
        {"protocol_version":1,"type":"progress","request_id":"\(requestID.uuidString.lowercased())","sequence":2,"payload":{"stage":"vad","status":"completed"}}
        {"protocol_version":1,"type":"finished","request_id":"\(requestID.uuidString.lowercased())","sequence":3,"payload":{"outcome":"succeeded","result":\(result)}}

        """
    }

    private func parse(_ text: String, requestID: UUID) -> VADOutcome {
        VADProtocolParser.parse(
            VADProcessResult(stdout: Data(text.utf8), terminationStatus: 0, terminationReason: .exit),
            requestID: requestID
        )
    }
}
