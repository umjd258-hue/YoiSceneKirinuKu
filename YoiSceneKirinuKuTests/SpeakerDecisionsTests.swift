import XCTest
@testable import YoiSceneKirinuKu

final class SpeakerDecisionsTests: XCTestCase {
    func testParsesCompletedDecisionGeneration() {
        let requestID = UUID()
        let events = [
            event(.progress, requestID, 1, ["stage": .string("speaker_decisions"), "status": .string("running")]),
            event(.progress, requestID, 2, ["stage": .string("speaker_decisions"), "status": .string("completed")]),
            event(.finished, requestID, 3, ["outcome": .string("succeeded"), "result": .object(["reused": .boolean(false), "candidate_count": .integer(4)])]),
        ]
        let outcome = SpeakerDecisionProtocolParser.parse(.success(PythonProcessExecution(requestID: requestID, events: events, stderr: Data())))
        XCTAssertEqual(outcome, .success(SpeakerDecisionResult(reused: false, candidateCount: 4)))
    }

    func testMapsStableFailureAndRejectsIncompleteSuccess() {
        let requestID = UUID()
        let failure = [
            event(.error, requestID, 1, ["code": .string("speaker_decisions_input_invalid")]),
            event(.finished, requestID, 2, ["outcome": .string("failed"), "code": .string("speaker_decisions_input_invalid")]),
        ]
        XCTAssertEqual(
            SpeakerDecisionProtocolParser.parse(.success(PythonProcessExecution(requestID: requestID, events: failure, stderr: Data()))),
            .failure(.inputInvalid)
        )
        let incomplete = [event(.finished, requestID, 1, ["outcome": .string("succeeded"), "result": .object(["reused": .boolean(false), "candidate_count": .integer(1)])])]
        XCTAssertEqual(
            SpeakerDecisionProtocolParser.parse(.success(PythonProcessExecution(requestID: requestID, events: incomplete, stderr: Data()))),
            .failure(.protocolError)
        )
    }

    private func event(_ type: PythonIPCEventType, _ requestID: UUID, _ sequence: Int, _ payload: [String: PythonIPCValue]) -> PythonIPCEvent {
        PythonIPCEvent(type: type, requestID: requestID, sequence: sequence, payload: payload)
    }
}
