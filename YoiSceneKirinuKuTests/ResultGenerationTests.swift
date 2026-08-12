import XCTest
@testable import YoiSceneKirinuKu

final class ResultGenerationTests: XCTestCase {
    func testParsesSuccessAndStableFailure() {
        let requestID = UUID()
        let success = [
            event(.progress, requestID, 1, ["stage": .string("result_generation"), "status": .string("running")]),
            event(.progress, requestID, 2, ["stage": .string("result_generation"), "status": .string("completed")]),
            event(.finished, requestID, 3, ["outcome": .string("succeeded"), "result": .object(["reused": .boolean(false), "candidate_count": .integer(2)])]),
        ]
        XCTAssertEqual(ResultGenerationProtocolParser.parse(.success(.init(requestID: requestID, events: success, stderr: Data()))), .success(.init(reused: false, candidateCount: 2)))
        let failure = [
            event(.error, requestID, 1, ["code": .string("result_input_invalid")]),
            event(.finished, requestID, 2, ["outcome": .string("failed"), "code": .string("result_input_invalid")]),
        ]
        XCTAssertEqual(ResultGenerationProtocolParser.parse(.success(.init(requestID: requestID, events: failure, stderr: Data()))), .failure(.inputInvalid))
    }

    private func event(_ type: PythonIPCEventType, _ requestID: UUID, _ sequence: Int, _ payload: [String: PythonIPCValue]) -> PythonIPCEvent {
        PythonIPCEvent(type: type, requestID: requestID, sequence: sequence, payload: payload)
    }
}
