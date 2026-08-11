import XCTest
@testable import YoiSceneKirinuKu

final class PythonProcessServiceTests: XCTestCase {
    func testSuccessfulStrictJSONLinesAndStderrSeparation() async {
        let outcome = await service().run(payload: ["operation": .string("success")])
        guard case .success(let execution) = outcome else {
            return XCTFail("Expected success: \(outcome)")
        }
        XCTAssertEqual(execution.events.map(\.type), [.progress, .finished])
        XCTAssertEqual(execution.events.map(\.sequence), [1, 2])
        XCTAssertEqual(execution.events.map(\.requestID), [execution.requestID, execution.requestID])
        XCTAssertEqual(String(decoding: execution.stderr, as: UTF8.self), "stage6 fixture diagnostic\n")
    }

    func testMalformedLineFailsClosed() async {
        await assertFailure(operation: "malformed", expected: .protocolFailure(.malformed))
    }

    func testUnknownTypeFailsClosed() async {
        await assertFailure(operation: "unknown_type", expected: .protocolFailure(.unknownType))
    }

    func testRequestIDMismatchFailsClosed() async {
        await assertFailure(operation: "request_id_mismatch", expected: .protocolFailure(.requestIDMismatch))
    }

    func testSequenceViolationFailsClosed() async {
        await assertFailure(operation: "sequence_violation", expected: .protocolFailure(.sequenceViolation))
    }

    func testTerminalViolationFailsClosed() async {
        await assertFailure(operation: "terminal_violation", expected: .protocolFailure(.terminalViolation))
    }

    func testNonzeroExitFailsClosedAndKeepsStderr() async {
        let outcome = await service().run(payload: ["operation": .string("nonzero")])
        guard case .failure(let error, let stderr) = outcome else {
            return XCTFail("Expected failure: \(outcome)")
        }
        XCTAssertEqual(error, .nonzeroExit(7))
        XCTAssertEqual(String(decoding: stderr, as: UTF8.self), "stage6 fixture nonzero\n")
    }

    func testCancellationStopsDirectPythonProcess() async throws {
        let service = service()
        let task = Task { await service.run(payload: ["operation": .string("wait")]) }
        try await Task.sleep(for: .milliseconds(200))
        task.cancel()
        let outcome = await task.value
        guard case .failure(let error, _) = outcome else {
            return XCTFail("Expected failure: \(outcome)")
        }
        XCTAssertEqual(error, .stopped)
    }

    private func assertFailure(operation: String, expected: PythonProcessServiceError) async {
        let outcome = await service().run(payload: ["operation": .string(operation)])
        guard case .failure(let error, _) = outcome else {
            return XCTFail("Expected failure: \(outcome)")
        }
        XCTAssertEqual(error, expected)
    }

    private func service() -> PythonProcessService {
        let fixture = Bundle(for: PythonProcessServiceTests.self)
            .url(forResource: "stage6_process_fixture", withExtension: "py")!
        return PythonProcessService(configuration: PythonProcessConfiguration(
            executableURL: URL(fileURLWithPath: "/Library/Frameworks/Python.framework/Versions/3.13/bin/python3"),
            scriptURL: fixture,
            argumentsPrefix: ["-I", "-S"],
            environment: ["LANG": "C.UTF-8", "PATH": "/nonexistent", "PYTHONNOUSERSITE": "1"]
        ))
    }
}
