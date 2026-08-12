import XCTest
@testable import YoiSceneKirinuKu

final class QualityFeaturesTests: XCTestCase {
    func testParsesCompletedFeatureGeneration() {
        let requestID = UUID()
        let events = [
            event(.progress, requestID, 1, ["stage": .string("quality_features"), "status": .string("running")]),
            event(.progress, requestID, 2, ["stage": .string("quality_features"), "status": .string("processing"), "completed_count": .integer(1), "total_count": .integer(1)]),
            event(.progress, requestID, 3, ["stage": .string("quality_features"), "status": .string("completed")]),
            event(.finished, requestID, 4, ["outcome": .string("succeeded"), "result": .object(["reused": .boolean(false), "candidate_count": .integer(1)])]),
        ]
        let outcome = QualityFeatureProtocolParser.parse(.success(PythonProcessExecution(requestID: requestID, events: events, stderr: Data())))
        XCTAssertEqual(outcome, .success(QualityFeatureResult(reused: false, candidateCount: 1)))
    }

    func testMapsStablePythonFailure() {
        let requestID = UUID()
        let events = [
            event(.error, requestID, 1, ["code": .string("quality_features_input_invalid")]),
            event(.finished, requestID, 2, ["outcome": .string("failed"), "code": .string("quality_features_input_invalid")]),
        ]
        let outcome = QualityFeatureProtocolParser.parse(.success(PythonProcessExecution(requestID: requestID, events: events, stderr: Data())))
        XCTAssertEqual(outcome, .failure(.inputInvalid))
    }

    func testRejectsIncompleteProgress() {
        let requestID = UUID()
        let events = [event(.finished, requestID, 1, ["outcome": .string("succeeded"), "result": .object(["reused": .boolean(false), "candidate_count": .integer(1)])])]
        let outcome = QualityFeatureProtocolParser.parse(.success(PythonProcessExecution(requestID: requestID, events: events, stderr: Data())))
        XCTAssertEqual(outcome, .failure(.protocolError))
    }

    private func event(_ type: PythonIPCEventType, _ requestID: UUID, _ sequence: Int, _ payload: [String: PythonIPCValue]) -> PythonIPCEvent {
        PythonIPCEvent(type: type, requestID: requestID, sequence: sequence, payload: payload)
    }
}
