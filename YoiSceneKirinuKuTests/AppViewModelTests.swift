import XCTest
@testable import YoiSceneKirinuKu

@MainActor
final class AppViewModelTests: XCTestCase {
    func testInitialRouteIsHome() {
        let subject = AppViewModel()

        XCTAssertEqual(subject.route, .home)
    }

    func testHomeCanNavigateToAnalysis() {
        let subject = AppViewModel()

        XCTAssertTrue(subject.navigateToAnalysis())
        XCTAssertEqual(subject.route, .analysis)
    }

    func testHomeCanNavigateToCharacters() {
        let subject = AppViewModel()

        XCTAssertTrue(subject.navigateToCharacters())
        XCTAssertEqual(subject.route, .characters)
    }

    func testAnalysisCanNavigateToResults() {
        let subject = AppViewModel()
        XCTAssertTrue(subject.navigateToAnalysis())

        XCTAssertTrue(subject.navigateToResults())
        XCTAssertEqual(subject.route, .results)
    }

    func testEveryNonHomeRouteCanReturnHome() {
        let analysis = AppViewModel()
        XCTAssertTrue(analysis.navigateToAnalysis())
        XCTAssertTrue(analysis.returnHome())
        XCTAssertEqual(analysis.route, .home)

        let results = AppViewModel()
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
}
