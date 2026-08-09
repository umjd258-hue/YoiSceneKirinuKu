import XCTest
@testable import YoiSceneKirinuKu

@MainActor
final class AppViewModelTests: XCTestCase {
    private let analysisReadyHome = HomeState(
        video: .ready(fileName: "episode01.mp4", duration: "24分12秒"),
        characters: .selected(names: ["コナン"]),
        isAIModelAvailable: true,
        isWorkspaceAvailable: true,
        isAnalysisSlotAvailable: true
    )

    func testInitialRouteIsHome() {
        let subject = AppViewModel()

        XCTAssertEqual(subject.route, .home)
    }

    func testHomeCanNavigateToAnalysis() {
        let subject = AppViewModel(homeState: analysisReadyHome)

        XCTAssertTrue(subject.navigateToAnalysis())
        XCTAssertEqual(subject.route, .analysis)
    }

    func testHomeCanNavigateToCharacters() {
        let subject = AppViewModel()

        XCTAssertTrue(subject.navigateToCharacters())
        XCTAssertEqual(subject.route, .characters)
    }

    func testAnalysisCanNavigateToResults() {
        let subject = AppViewModel(homeState: analysisReadyHome)
        XCTAssertTrue(subject.navigateToAnalysis())

        XCTAssertTrue(subject.navigateToResults())
        XCTAssertEqual(subject.route, .results)
    }

    func testEveryNonHomeRouteCanReturnHome() {
        let analysis = AppViewModel(homeState: analysisReadyHome)
        XCTAssertTrue(analysis.navigateToAnalysis())
        XCTAssertTrue(analysis.returnHome())
        XCTAssertEqual(analysis.route, .home)

        let results = AppViewModel(homeState: analysisReadyHome)
        XCTAssertTrue(results.navigateToAnalysis())
        XCTAssertTrue(results.navigateToResults())
        XCTAssertTrue(results.returnHome())
        XCTAssertEqual(results.route, .home)

        let characters = AppViewModel()
        XCTAssertTrue(characters.navigateToCharacters())
        XCTAssertTrue(characters.returnHome())
        XCTAssertEqual(characters.route, .home)
    }

    func testInvalidTransitionIsRejectedWithoutChangingRoute() {
        let subject = AppViewModel()

        XCTAssertFalse(subject.navigateToResults())
        XCTAssertEqual(subject.route, .home)

        XCTAssertTrue(subject.navigateToCharacters())
        XCTAssertFalse(subject.navigateToAnalysis())
        XCTAssertEqual(subject.route, .characters)
    }

    func testReturningHomeWhileAlreadyHomeIsRejected() {
        let subject = AppViewModel()

        XCTAssertFalse(subject.returnHome())
        XCTAssertEqual(subject.route, .home)
    }

    func testAnalysisStartRequiresEveryMockPrerequisite() {
        var states = [HomeState]()
        states.append(HomeState(
            video: .unselected,
            characters: analysisReadyHome.characters,
            isAIModelAvailable: true,
            isWorkspaceAvailable: true,
            isAnalysisSlotAvailable: true
        ))
        states.append(HomeState(
            video: .checking,
            characters: analysisReadyHome.characters,
            isAIModelAvailable: true,
            isWorkspaceAvailable: true,
            isAnalysisSlotAvailable: true
        ))
        states.append(HomeState(
            video: .failed(message: "音声トラックが見つかりません"),
            characters: analysisReadyHome.characters,
            isAIModelAvailable: true,
            isWorkspaceAvailable: true,
            isAnalysisSlotAvailable: true
        ))
        states.append(HomeState(
            video: analysisReadyHome.video,
            characters: .unregistered,
            isAIModelAvailable: true,
            isWorkspaceAvailable: true,
            isAnalysisSlotAvailable: true
        ))
        states.append(HomeState(
            video: analysisReadyHome.video,
            characters: .unselected,
            isAIModelAvailable: true,
            isWorkspaceAvailable: true,
            isAnalysisSlotAvailable: true
        ))
        states.append(HomeState(
            video: analysisReadyHome.video,
            characters: .selected(names: []),
            isAIModelAvailable: true,
            isWorkspaceAvailable: true,
            isAnalysisSlotAvailable: true
        ))
        states.append(HomeState(
            video: analysisReadyHome.video,
            characters: analysisReadyHome.characters,
            isAIModelAvailable: false,
            isWorkspaceAvailable: true,
            isAnalysisSlotAvailable: true
        ))
        states.append(HomeState(
            video: analysisReadyHome.video,
            characters: analysisReadyHome.characters,
            isAIModelAvailable: true,
            isWorkspaceAvailable: false,
            isAnalysisSlotAvailable: true
        ))
        states.append(HomeState(
            video: analysisReadyHome.video,
            characters: analysisReadyHome.characters,
            isAIModelAvailable: true,
            isWorkspaceAvailable: true,
            isAnalysisSlotAvailable: false
        ))

        for state in states {
            XCTAssertFalse(state.canStartAnalysis)
            let subject = AppViewModel(homeState: state)
            XCTAssertFalse(subject.navigateToAnalysis())
            XCTAssertEqual(subject.route, .home)
        }
    }

    func testAnalysisStartIsEnabledWhenEveryMockPrerequisiteIsReady() {
        XCTAssertTrue(analysisReadyHome.canStartAnalysis)
    }

    func testSuccessfulPreflightUpdatesOnlyVideoState() async {
        let result = PreflightResult(
            fileName: "episode01.mp4",
            durationMilliseconds: 1_452_001,
            containerFormat: "mov,mp4,m4a,3gp,3g2,mj2",
            videoStreamCount: 1,
            audioStreamCount: 1
        )
        let subject = AppViewModel(preflightService: ImmediatePreflightService(outcome: .success(result)))

        subject.selectVideo(URL(fileURLWithPath: "/tmp/episode01.mp4"))
        await Task.yield()

        XCTAssertEqual(subject.homeState.video, .ready(fileName: "episode01.mp4", duration: "24分12秒"))
        XCTAssertEqual(subject.homeState.characters, .unregistered)
    }

    func testPreflightFailureUsesStableUserMessage() async {
        let subject = AppViewModel(preflightService: ImmediatePreflightService(outcome: .failure(.audioStreamMissing)))

        subject.selectVideo(URL(fileURLWithPath: "/tmp/no-audio.mp4"))
        await Task.yield()

        XCTAssertEqual(subject.homeState.video, .failed(message: "音声トラックが見つかりません"))
        XCTAssertFalse(subject.homeState.canStartAnalysis)
    }

    func testOlderPreflightResultDoesNotReplaceNewSelection() async {
        let service = ControlledPreflightService()
        let subject = AppViewModel(preflightService: service)
        subject.selectVideo(URL(fileURLWithPath: "/tmp/old.mp4"))
        await Task.yield()
        subject.selectVideo(URL(fileURLWithPath: "/tmp/new.mp4"))
        await Task.yield()

        await service.resume(fileName: "old.mp4", with: .success(PreflightResult(
            fileName: "old.mp4",
            durationMilliseconds: 1_000,
            containerFormat: "mp4",
            videoStreamCount: 1,
            audioStreamCount: 1
        )))
        await Task.yield()

        XCTAssertEqual(subject.homeState.video, .checking)

        await service.resume(fileName: "new.mp4", with: .success(PreflightResult(
            fileName: "new.mp4",
            durationMilliseconds: 2_000,
            containerFormat: "mp4",
            videoStreamCount: 1,
            audioStreamCount: 1
        )))
        await Task.yield()

        XCTAssertEqual(subject.homeState.video, .ready(fileName: "new.mp4", duration: "2秒"))
    }

    func testProtocolParserAcceptsCompleteSuccessfulContract() throws {
        let requestID = UUID()
        let lines = [
            event(type: "progress", requestID: requestID, sequence: 1, payload: ["stage": "preflight", "status": "running"]),
            event(type: "finished", requestID: requestID, sequence: 2, payload: [
                "outcome": "succeeded",
                "result": [
                    "file_name": "sample.mp4",
                    "duration_ms": 1_001,
                    "container_format": "mp4",
                    "video_stream_count": 1,
                    "audio_stream_count": 1,
                ],
            ]),
        ]
        let stdout = try lines.map {
            try JSONSerialization.data(withJSONObject: $0)
        }.reduce(into: Data()) {
            $0.append($1)
            $0.append(0x0A)
        }

        XCTAssertEqual(
            PreflightProtocolParser.parse(stdout: stdout, requestID: requestID, terminationStatus: 0, terminationReason: .exit),
            .success(PreflightResult(
                fileName: "sample.mp4",
                durationMilliseconds: 1_001,
                containerFormat: "mp4",
                videoStreamCount: 1,
                audioStreamCount: 1
            ))
        )
    }

    func testProtocolParserRejectsMalformedUnknownAndAbnormalExit() throws {
        let requestID = UUID()
        XCTAssertEqual(
            PreflightProtocolParser.parse(stdout: Data("not-json\n".utf8), requestID: requestID, terminationStatus: 0, terminationReason: .exit),
            .failure(.protocolError)
        )

        let unknown = try JSONSerialization.data(withJSONObject: event(
            type: "unknown",
            requestID: requestID,
            sequence: 1,
            payload: [:]
        )) + Data([0x0A])
        XCTAssertEqual(
            PreflightProtocolParser.parse(stdout: unknown, requestID: requestID, terminationStatus: 0, terminationReason: .exit),
            .failure(.protocolError)
        )

        XCTAssertEqual(
            PreflightProtocolParser.parse(stdout: Data(), requestID: requestID, terminationStatus: 1, terminationReason: .exit),
            .failure(.protocolError)
        )
    }

    func testProtocolParserMapsUnknownErrorCodeToInternalError() throws {
        let requestID = UUID()
        let events = [
            event(type: "error", requestID: requestID, sequence: 1, payload: ["code": "future_error"]),
            event(type: "finished", requestID: requestID, sequence: 2, payload: ["outcome": "failed", "code": "future_error"]),
        ]
        let stdout = try events.map {
            try JSONSerialization.data(withJSONObject: $0)
        }.reduce(into: Data()) {
            $0.append($1)
            $0.append(0x0A)
        }

        XCTAssertEqual(
            PreflightProtocolParser.parse(stdout: stdout, requestID: requestID, terminationStatus: 0, terminationReason: .exit),
            .failure(.internalError)
        )
    }

    func testProtocolParserRejectsNonIntegerDuration() throws {
        let requestID = UUID()
        let finished = event(type: "finished", requestID: requestID, sequence: 1, payload: [
            "outcome": "succeeded",
            "result": [
                "file_name": "sample.mp4",
                "duration_ms": 1.5,
                "container_format": "mp4",
                "video_stream_count": 1,
                "audio_stream_count": 1,
            ],
        ])
        let stdout = try JSONSerialization.data(withJSONObject: finished) + Data([0x0A])

        XCTAssertEqual(
            PreflightProtocolParser.parse(stdout: stdout, requestID: requestID, terminationStatus: 0, terminationReason: .exit),
            .failure(.protocolError)
        )
    }

    func testProtocolParserRejectsBooleanDuration() throws {
        let requestID = UUID()
        let finished = event(type: "finished", requestID: requestID, sequence: 1, payload: [
            "outcome": "succeeded",
            "result": [
                "file_name": "sample.mp4",
                "duration_ms": true,
                "container_format": "mp4",
                "video_stream_count": 1,
                "audio_stream_count": 1,
            ],
        ])
        let stdout = try JSONSerialization.data(withJSONObject: finished) + Data([0x0A])

        XCTAssertEqual(
            PreflightProtocolParser.parse(stdout: stdout, requestID: requestID, terminationStatus: 0, terminationReason: .exit),
            .failure(.protocolError)
        )
    }

    private func event(type: String, requestID: UUID, sequence: Int, payload: [String: Any]) -> [String: Any] {
        [
            "protocol_version": 1,
            "type": type,
            "request_id": requestID.uuidString.lowercased(),
            "sequence": sequence,
            "payload": payload,
        ]
    }
}

private struct ImmediatePreflightService: PreflightServicing {
    let outcome: PreflightOutcome

    func run(sourceURL: URL, requestID: UUID) async -> PreflightOutcome { outcome }
}

private actor ControlledPreflightService: PreflightServicing {
    private var continuations = [String: CheckedContinuation<PreflightOutcome, Never>]()

    func run(sourceURL: URL, requestID: UUID) async -> PreflightOutcome {
        await withCheckedContinuation { continuations[sourceURL.lastPathComponent] = $0 }
    }

    func resume(fileName: String, with outcome: PreflightOutcome) {
        continuations.removeValue(forKey: fileName)?.resume(returning: outcome)
    }
}
