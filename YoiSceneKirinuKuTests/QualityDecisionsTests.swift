import XCTest
@testable import YoiSceneKirinuKu

final class QualityDecisionsTests: XCTestCase {
    func testParsesCompletedDecisionGeneration() {
        let requestID = UUID()
        let events = [
            event(.progress, requestID, 1, ["stage": .string("quality_decisions"), "status": .string("running")]),
            event(.progress, requestID, 2, ["stage": .string("quality_decisions"), "status": .string("completed")]),
            event(.finished, requestID, 3, ["outcome": .string("succeeded"), "result": .object(["reused": .boolean(false), "candidate_count": .integer(36)])]),
        ]
        let outcome = QualityDecisionProtocolParser.parse(.success(PythonProcessExecution(requestID: requestID, events: events, stderr: Data())))
        XCTAssertEqual(outcome, .success(QualityDecisionResult(reused: false, candidateCount: 36)))
    }

    func testMapsStablePythonFailure() {
        let requestID = UUID()
        let events = [
            event(.error, requestID, 1, ["code": .string("quality_decisions_input_invalid")]),
            event(.finished, requestID, 2, ["outcome": .string("failed"), "code": .string("quality_decisions_input_invalid")]),
        ]
        let outcome = QualityDecisionProtocolParser.parse(.success(PythonProcessExecution(requestID: requestID, events: events, stderr: Data())))
        XCTAssertEqual(outcome, .failure(.inputInvalid))
    }

    func testRejectsSuccessWithoutCompletion() {
        let requestID = UUID()
        let events = [event(.finished, requestID, 1, ["outcome": .string("succeeded"), "result": .object(["reused": .boolean(false), "candidate_count": .integer(1)])])]
        let outcome = QualityDecisionProtocolParser.parse(.success(PythonProcessExecution(requestID: requestID, events: events, stderr: Data())))
        XCTAssertEqual(outcome, .failure(.protocolError))
    }

    private func event(_ type: PythonIPCEventType, _ requestID: UUID, _ sequence: Int, _ payload: [String: PythonIPCValue]) -> PythonIPCEvent {
        PythonIPCEvent(type: type, requestID: requestID, sequence: sequence, payload: payload)
    }
}
