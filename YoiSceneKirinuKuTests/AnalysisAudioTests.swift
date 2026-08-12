import XCTest
@testable import YoiSceneKirinuKu

final class AnalysisAudioTests: XCTestCase {
    func testBundledConfigurationUsesFixedApplicationPaths() throws {
        let configuration = try XCTUnwrap(AnalysisAudioConfiguration.bundled())
        XCTAssertEqual(
            configuration.ffmpegExecutableURL.path,
            configuration.bundleRootURL.appendingPathComponent("Contents/MacOS/ffmpeg").path
        )
        XCTAssertEqual(
            configuration.ffprobeExecutableURL.path,
            configuration.bundleRootURL.appendingPathComponent("Contents/MacOS/ffprobe").path
        )
        XCTAssertEqual(
            configuration.pythonExecutableURL.path,
            configuration.bundleRootURL.appendingPathComponent(
                "Contents/Frameworks/Python.framework/Versions/3.13/bin/python3.13"
            ).path
        )
    }

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

    func testProtocolParserAcceptsStoppedOnlyAfterOrderedVerification() {
        let requestID = UUID()
        let jobID = UUID()
        let output = """
        {"protocol_version":1,"type":"progress","request_id":"\(requestID.uuidString.lowercased())","sequence":1,"payload":{"stage":"analysis_audio","status":"running"}}
        {"protocol_version":1,"type":"progress","request_id":"\(requestID.uuidString.lowercased())","sequence":2,"payload":{"stage":"analysis_stop","status":"stop_requested_detected"}}
        {"protocol_version":1,"type":"progress","request_id":"\(requestID.uuidString.lowercased())","sequence":3,"payload":{"stage":"analysis_stop","status":"child_exit_observed"}}
        {"protocol_version":1,"type":"progress","request_id":"\(requestID.uuidString.lowercased())","sequence":4,"payload":{"stage":"analysis_stop","status":"post_stop_state_verified"}}
        {"protocol_version":1,"type":"finished","request_id":"\(requestID.uuidString.lowercased())","sequence":5,"payload":{"outcome":"stopped","result":{"job_id":"\(jobID.uuidString.lowercased())","state":"stopped","reason":"user_requested"}}}

        """
        XCTAssertEqual(parse(output, requestID: requestID), .stopped(jobID: jobID))
        XCTAssertEqual(
            parse(output.replacingOccurrences(of: "child_exit_observed", with: "post_stop_state_verified"), requestID: requestID),
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
