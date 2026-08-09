import XCTest
@testable import YoiSceneKirinuKu

final class AnalysisAudioTests: XCTestCase {
    func testProtocolParserAcceptsVerifiedSuccessfulResult() {
        let requestID = UUID()
        let output = """
        {"protocol_version":1,"type":"progress","request_id":"\(requestID.uuidString.lowercased())","sequence":1,"payload":{"stage":"analysis_audio","status":"running"}}
        {"protocol_version":1,"type":"progress","request_id":"\(requestID.uuidString.lowercased())","sequence":2,"payload":{"stage":"analysis_audio","status":"completed"}}
        {"protocol_version":1,"type":"finished","request_id":"\(requestID.uuidString.lowercased())","sequence":3,"payload":{"outcome":"succeeded","result":{"reused":false,"frame_count":16000,"duration_ms":1000,"selected_stream_index":1}}}

        """
        XCTAssertEqual(
            AnalysisAudioProtocolParser.parse(
                AnalysisAudioProcessResult(
                    stdout: Data(output.utf8), terminationStatus: 0, terminationReason: .exit
                ),
                requestID: requestID
            ),
            .success(AnalysisAudioResult(
                reused: false, frameCount: 16_000, durationMilliseconds: 1_000,
                selectedStreamIndex: 1
            ))
        )
    }

    func testProtocolParserRejectsMissingValidationAndUnknownEvent() {
        let requestID = UUID()
        let missingCompleted = """
        {"protocol_version":1,"type":"progress","request_id":"\(requestID.uuidString.lowercased())","sequence":1,"payload":{"stage":"analysis_audio","status":"running"}}
        {"protocol_version":1,"type":"finished","request_id":"\(requestID.uuidString.lowercased())","sequence":2,"payload":{"outcome":"succeeded","result":{"reused":false,"frame_count":16000,"duration_ms":1000,"selected_stream_index":0}}}

        """
        XCTAssertEqual(parse(missingCompleted, requestID: requestID), .failure(.protocolError))

        let unknown = """
        {"protocol_version":1,"type":"unknown","request_id":"\(requestID.uuidString.lowercased())","sequence":1,"payload":{}}

        """
        XCTAssertEqual(parse(unknown, requestID: requestID), .failure(.protocolError))
    }

    func testProtocolParserRequiresMatchingErrorAndNormalExit() {
        let requestID = UUID()
        let failed = """
        {"protocol_version":1,"type":"progress","request_id":"\(requestID.uuidString.lowercased())","sequence":1,"payload":{"stage":"analysis_audio","status":"running"}}
        {"protocol_version":1,"type":"error","request_id":"\(requestID.uuidString.lowercased())","sequence":2,"payload":{"code":"analysis_audio_ffmpeg_failed"}}
        {"protocol_version":1,"type":"finished","request_id":"\(requestID.uuidString.lowercased())","sequence":3,"payload":{"outcome":"failed","code":"analysis_audio_ffmpeg_failed"}}

        """
        XCTAssertEqual(parse(failed, requestID: requestID), .failure(.ffmpegFailed))
        XCTAssertEqual(
            AnalysisAudioProtocolParser.parse(
                AnalysisAudioProcessResult(
                    stdout: Data(failed.utf8), terminationStatus: 1, terminationReason: .exit
                ),
                requestID: requestID
            ),
            .failure(.protocolError)
        )
    }

    private func parse(_ text: String, requestID: UUID) -> AnalysisAudioOutcome {
        AnalysisAudioProtocolParser.parse(
            AnalysisAudioProcessResult(
                stdout: Data(text.utf8), terminationStatus: 0, terminationReason: .exit
            ),
            requestID: requestID
        )
    }
}
