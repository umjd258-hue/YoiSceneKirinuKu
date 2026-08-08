import XCTest
@testable import YoiSceneKirinuKu

@MainActor
final class AppViewModelTests: XCTestCase {
    private let analysisReadyHome = HomeMockState(
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
        let subject = AppViewModel(homeMockState: analysisReadyHome)

        XCTAssertTrue(subject.navigateToAnalysis())
        XCTAssertEqual(subject.route, .analysis)
    }

    func testHomeCanNavigateToCharacters() {
        let subject = AppViewModel()

        XCTAssertTrue(subject.navigateToCharacters())
        XCTAssertEqual(subject.route, .characters)
    }

    func testAnalysisCanNavigateToResults() {
        let subject = AppViewModel(homeMockState: analysisReadyHome)
        XCTAssertTrue(subject.navigateToAnalysis())

        XCTAssertTrue(subject.navigateToResults())
        XCTAssertEqual(subject.route, .results)
    }

    func testEveryNonHomeRouteCanReturnHome() {
        let analysis = AppViewModel(homeMockState: analysisReadyHome)
        XCTAssertTrue(analysis.navigateToAnalysis())
        XCTAssertTrue(analysis.returnHome())
        XCTAssertEqual(analysis.route, .home)

        let results = AppViewModel(homeMockState: analysisReadyHome)
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
        var states = [HomeMockState]()
        states.append(HomeMockState(
            video: .unselected,
            characters: analysisReadyHome.characters,
            isAIModelAvailable: true,
            isWorkspaceAvailable: true,
            isAnalysisSlotAvailable: true
        ))
        states.append(HomeMockState(
            video: .checking,
            characters: analysisReadyHome.characters,
            isAIModelAvailable: true,
            isWorkspaceAvailable: true,
            isAnalysisSlotAvailable: true
        ))
        states.append(HomeMockState(
            video: .failed(message: "音声トラックが見つかりません"),
            characters: analysisReadyHome.characters,
            isAIModelAvailable: true,
            isWorkspaceAvailable: true,
            isAnalysisSlotAvailable: true
        ))
        states.append(HomeMockState(
            video: analysisReadyHome.video,
            characters: .unregistered,
            isAIModelAvailable: true,
            isWorkspaceAvailable: true,
            isAnalysisSlotAvailable: true
        ))
        states.append(HomeMockState(
            video: analysisReadyHome.video,
            characters: .unselected,
            isAIModelAvailable: true,
            isWorkspaceAvailable: true,
            isAnalysisSlotAvailable: true
        ))
        states.append(HomeMockState(
            video: analysisReadyHome.video,
            characters: .selected(names: []),
            isAIModelAvailable: true,
            isWorkspaceAvailable: true,
            isAnalysisSlotAvailable: true
        ))
        states.append(HomeMockState(
            video: analysisReadyHome.video,
            characters: analysisReadyHome.characters,
            isAIModelAvailable: false,
            isWorkspaceAvailable: true,
            isAnalysisSlotAvailable: true
        ))
        states.append(HomeMockState(
            video: analysisReadyHome.video,
            characters: analysisReadyHome.characters,
            isAIModelAvailable: true,
            isWorkspaceAvailable: false,
            isAnalysisSlotAvailable: true
        ))
        states.append(HomeMockState(
            video: analysisReadyHome.video,
            characters: analysisReadyHome.characters,
            isAIModelAvailable: true,
            isWorkspaceAvailable: true,
            isAnalysisSlotAvailable: false
        ))

        for state in states {
            XCTAssertFalse(state.canStartAnalysis)
            let subject = AppViewModel(homeMockState: state)
            XCTAssertFalse(subject.navigateToAnalysis())
            XCTAssertEqual(subject.route, .home)
        }
    }

    func testAnalysisStartIsEnabledWhenEveryMockPrerequisiteIsReady() {
        XCTAssertTrue(analysisReadyHome.canStartAnalysis)
    }
}
