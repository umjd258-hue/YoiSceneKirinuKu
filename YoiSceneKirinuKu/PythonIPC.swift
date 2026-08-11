import Foundation

indirect enum PythonIPCValue: Codable, Equatable, Sendable {
    case string(String)
    case integer(Int64)
    case number(Double)
    case boolean(Bool)
    case array([PythonIPCValue])
    case object([String: PythonIPCValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([PythonIPCValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: PythonIPCValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .integer(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .boolean(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

enum PythonIPCEventType: String, Equatable, Sendable {
    case progress
    case error
    case finished
}

struct PythonIPCEvent: Equatable, Sendable {
    let type: PythonIPCEventType
    let requestID: UUID
    let sequence: Int
    let payload: [String: PythonIPCValue]
}

enum PythonIPCError: Error, Equatable {
    case encodingFailed
    case malformed
    case protocolViolation
    case unknownType
    case requestIDMismatch
    case sequenceViolation
    case terminalViolation
}

private struct PythonIPCRawEnvelope: Codable {
    let protocolVersion: Int
    let type: String
    let requestID: String
    let sequence: Int
    let payload: [String: PythonIPCValue]

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case type
        case requestID = "request_id"
        case sequence
        case payload
    }
}

enum PythonIPCRequestEncoder {
    static func encode(
        requestID: UUID,
        payload: [String: PythonIPCValue]
    ) throws -> Data {
        let envelope = PythonIPCRawEnvelope(
            protocolVersion: 1,
            type: "request",
            requestID: requestID.uuidString.lowercased(),
            sequence: 0,
            payload: payload
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard var data = try? encoder.encode(envelope) else {
            throw PythonIPCError.encodingFailed
        }
        data.append(0x0A)
        return data
    }
}

enum PythonIPCEventParser {
    fileprivate static let envelopeKeys = Set([
        "protocol_version",
        "type",
        "request_id",
        "sequence",
        "payload",
    ])

    static func parse(_ data: Data, requestID: UUID) throws -> [PythonIPCEvent] {
        guard let text = String(data: data, encoding: .utf8), text.hasSuffix("\n") else {
            throw PythonIPCError.malformed
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > 1, lines.last?.isEmpty == true else {
            throw PythonIPCError.malformed
        }

        var parser = PythonIPCLineParser(requestID: requestID)
        let events = try lines.dropLast().map { try parser.parseLine(Data($0.utf8)) }
        try parser.finish()
        return events
    }
}

struct PythonIPCLineParser {
    private let requestID: UUID
    private var expectedSequence = 1
    private var recordedError = false
    private var reachedTerminal = false

    init(requestID: UUID) {
        self.requestID = requestID
    }

    mutating func parseLine(_ lineData: Data) throws -> PythonIPCEvent {
        guard !lineData.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
              Set(object.keys) == PythonIPCEventParser.envelopeKeys,
              let envelope = try? JSONDecoder().decode(PythonIPCRawEnvelope.self, from: lineData)
        else {
            throw PythonIPCError.malformed
        }
        guard envelope.protocolVersion == 1 else { throw PythonIPCError.protocolViolation }
        guard envelope.requestID == requestID.uuidString.lowercased() else {
            throw PythonIPCError.requestIDMismatch
        }
        guard envelope.sequence == expectedSequence else { throw PythonIPCError.sequenceViolation }
        guard !reachedTerminal else { throw PythonIPCError.terminalViolation }
        guard let type = PythonIPCEventType(rawValue: envelope.type) else {
            throw PythonIPCError.unknownType
        }

        switch type {
        case .progress:
            guard !recordedError else { throw PythonIPCError.terminalViolation }
        case .error:
            guard !recordedError else { throw PythonIPCError.terminalViolation }
            recordedError = true
        case .finished:
            guard case .string(let outcome) = envelope.payload["outcome"],
                  ["succeeded", "failed", "stopped"].contains(outcome),
                  (outcome == "failed") == recordedError else {
                throw PythonIPCError.terminalViolation
            }
            reachedTerminal = true
        }

        expectedSequence += 1
        return PythonIPCEvent(
            type: type,
            requestID: requestID,
            sequence: envelope.sequence,
            payload: envelope.payload
        )
    }

    func finish() throws {
        guard reachedTerminal else { throw PythonIPCError.terminalViolation }
    }
}
