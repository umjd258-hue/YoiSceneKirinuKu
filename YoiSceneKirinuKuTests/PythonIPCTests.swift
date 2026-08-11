import XCTest
@testable import YoiSceneKirinuKu

final class PythonIPCTests: XCTestCase {
    func testRequestEncoderProducesCanonicalEnvelope() throws {
        let requestID = UUID()
        let data = try PythonIPCRequestEncoder.encode(
            requestID: requestID,
            payload: ["operation": .string("stage6_test")]
        )

        XCTAssertEqual(data.last, 0x0A)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data.dropLast()) as? [String: Any]
        )
        XCTAssertEqual(
            Set(object.keys),
            Set(["protocol_version", "type", "request_id", "sequence", "payload"])
        )
        XCTAssertEqual(object["protocol_version"] as? Int, 1)
        XCTAssertEqual(object["type"] as? String, "request")
        XCTAssertEqual(object["request_id"] as? String, requestID.uuidString.lowercased())
        XCTAssertEqual(object["sequence"] as? Int, 0)
        XCTAssertEqual((object["payload"] as? [String: Any])?["operation"] as? String, "stage6_test")
    }

    func testEventParserAcceptsOrderedSuccessfulTerminal() throws {
        let requestID = UUID()
        let data = events(
            requestID: requestID,
            values: [
                ("progress", 1, ["stage": "stage6", "completed": 0]),
                ("progress", 2, ["stage": "stage6", "completed": 1]),
                ("finished", 3, ["outcome": "succeeded"]),
            ]
        )

        let parsed = try PythonIPCEventParser.parse(data, requestID: requestID)

        XCTAssertEqual(parsed.map(\.type), [.progress, .progress, .finished])
        XCTAssertEqual(parsed.map(\.sequence), [1, 2, 3])
    }

    func testEventParserRejectsMalformedLine() {
        assertError(.malformed, data: Data("not-json\n".utf8), requestID: UUID())
    }

    func testEventParserRejectsUnknownType() {
        let requestID = UUID()
        assertError(
            .unknownType,
            data: events(
                requestID: requestID,
                values: [("future", 1, ["outcome": "succeeded"])]
            ),
            requestID: requestID
        )
    }

    func testEventParserRejectsRequestIDMismatch() {
        let requestID = UUID()
        assertError(
            .requestIDMismatch,
            data: events(
                requestID: UUID(),
                values: [("finished", 1, ["outcome": "succeeded"])]
            ),
            requestID: requestID
        )
    }

    func testEventParserRejectsSequenceViolation() {
        let requestID = UUID()
        assertError(
            .sequenceViolation,
            data: events(
                requestID: requestID,
                values: [("finished", 2, ["outcome": "succeeded"])]
            ),
            requestID: requestID
        )
    }

    func testEventParserRejectsTerminalViolations() {
        let requestID = UUID()
        assertError(
            .terminalViolation,
            data: events(
                requestID: requestID,
                values: [("progress", 1, ["stage": "stage6"])]
            ),
            requestID: requestID
        )
        assertError(
            .terminalViolation,
            data: events(
                requestID: requestID,
                values: [
                    ("error", 1, ["error_code": "failed"]),
                    ("finished", 2, ["outcome": "succeeded"]),
                ]
            ),
            requestID: requestID
        )
    }

    private func assertError(
        _ expected: PythonIPCError,
        data: Data,
        requestID: UUID,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try PythonIPCEventParser.parse(data, requestID: requestID),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? PythonIPCError, expected, file: file, line: line)
        }
    }

    private func events(
        requestID: UUID,
        values: [(type: String, sequence: Int, payload: [String: Any])]
    ) -> Data {
        values.reduce(into: Data()) { result, value in
            let envelope: [String: Any] = [
                "protocol_version": 1,
                "type": value.type,
                "request_id": requestID.uuidString.lowercased(),
                "sequence": value.sequence,
                "payload": value.payload,
            ]
            result.append(try! JSONSerialization.data(withJSONObject: envelope))
            result.append(0x0A)
        }
    }
}
