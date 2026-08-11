import Foundation
import Darwin

enum GateError: Error, CustomStringConvertible {
    case invalidLayout
    case launchFailed(String)
    case nonzeroExit(Int32)
    case invalidStderr
    case invalidProtocol(String)
    case stdinWriteFailed(status: Int32, reason: String, stderr: String, detail: String)

    var description: String {
        switch self {
        case .invalidLayout: return "invalid_bundle_layout"
        case .launchFailed(let detail): return "launch_failed: \(detail)"
        case .nonzeroExit(let status): return "nonzero_exit: \(status)"
        case .invalidStderr: return "invalid_stderr"
        case .invalidProtocol(let detail): return "invalid_protocol: \(detail)"
        case .stdinWriteFailed(let status, let reason, let stderr, let detail):
            return "stdin_write_failed: child_status=\(status) child_reason=\(reason) child_stderr=\(stderr.debugDescription) detail=\(detail)"
        }
    }
}

struct Envelope: Decodable {
    let protocolVersion: Int
    let type: String
    let requestID: String
    let sequence: Int
    let payload: [String: JSONValue]

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case type
        case requestID = "request_id"
        case sequence
        case payload
    }
}

enum JSONValue: Decodable, Equatable {
    case string(String)
    case integer(Int)
    case boolean(Bool)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "unsupported JSON value")
        }
    }
}

func fixedBundleURLs() throws -> (python: URL, script: URL) {
    let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    let contents = executable.deletingLastPathComponent().deletingLastPathComponent()
    guard contents.lastPathComponent == "Contents" else { throw GateError.invalidLayout }
    return (
        contents.appendingPathComponent("Frameworks/Python.framework/Versions/3.13/bin/python3.13"),
        contents.appendingPathComponent("Resources/Stage6/stage6_gate_fixture.py")
    )
}

func validate(stdout: Data, stderr: Data, requestID: String) throws {
    guard String(data: stderr, encoding: .utf8) == "stage6_gate_diagnostic\n" else {
        throw GateError.invalidStderr
    }
    guard let text = String(data: stdout, encoding: .utf8), text.hasSuffix("\n") else {
        throw GateError.invalidProtocol("stdout is not newline terminated UTF-8")
    }
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    guard lines.count == 3, lines.last?.isEmpty == true else {
        throw GateError.invalidProtocol("unexpected line count")
    }

    let decoder = JSONDecoder()
    let expectedTypes = ["progress", "finished"]
    for (index, line) in lines.dropLast().enumerated() {
        let data = Data(line.utf8)
        guard let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(raw.keys) == Set(["protocol_version", "type", "request_id", "sequence", "payload"]) else {
            throw GateError.invalidProtocol("envelope keys")
        }
        let envelope = try decoder.decode(Envelope.self, from: data)
        guard envelope.protocolVersion == 1,
              envelope.type == expectedTypes[index],
              envelope.requestID == requestID,
              envelope.sequence == index + 1 else {
            throw GateError.invalidProtocol("envelope values")
        }
        if index == 0 {
            guard envelope.payload["stage"] == .string("stage6_gate"),
                  envelope.payload["status"] == .string("running") else {
                throw GateError.invalidProtocol("progress payload")
            }
        } else {
            guard envelope.payload["outcome"] == .string("succeeded"),
                  envelope.payload["python_version"] == .string("3.13.14"),
                  envelope.payload["isolated"] == .boolean(true),
                  envelope.payload["ignore_environment"] == .boolean(true),
                  envelope.payload["no_user_site"] == .boolean(true),
                  envelope.payload["site_loaded"] == .boolean(false),
                  envelope.payload["site_packages_paths"] == .integer(0),
                  envelope.payload["network_audit_events"] == .integer(0),
                  envelope.payload["path"] == .string("/nonexistent") else {
                throw GateError.invalidProtocol("finished payload")
            }
        }
    }
}

do {
    signal(SIGPIPE, SIG_IGN)
    let urls = try fixedBundleURLs()
    let fileManager = FileManager.default
    guard fileManager.isExecutableFile(atPath: urls.python.path),
          fileManager.fileExists(atPath: urls.script.path) else { throw GateError.invalidLayout }

    let requestID = UUID().uuidString.lowercased()
    let request: [String: Any] = [
        "protocol_version": 1,
        "type": "request",
        "request_id": requestID,
        "sequence": 0,
        "payload": ["operation": "stage6_gate"]
    ]
    let requestData = try JSONSerialization.data(withJSONObject: request)

    let process = Process()
    process.executableURL = urls.python
    process.arguments = ["-I", "-S", urls.script.path]
    process.environment = ["LANG": "C.UTF-8", "PATH": "/nonexistent", "PYTHONNOUSERSITE": "1"]
    let stdinPipe = Pipe()
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardInput = stdinPipe
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    do { try process.run() } catch { throw GateError.launchFailed(String(describing: error)) }
    guard let pidFile = ProcessInfo.processInfo.environment["STAGE6_PYTHON_PID_FILE"] else {
        throw GateError.invalidLayout
    }
    try Data("\(process.processIdentifier)\n".utf8).write(
        to: URL(fileURLWithPath: pidFile),
        options: .atomic
    )
    do {
        try stdinPipe.fileHandleForWriting.write(contentsOf: requestData)
        try stdinPipe.fileHandleForWriting.write(contentsOf: Data("\n".utf8))
    } catch {
        try? stdinPipe.fileHandleForWriting.close()
        let childStderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let reason = process.terminationReason == .exit ? "exit" : "uncaught_signal"
        throw GateError.stdinWriteFailed(
            status: process.terminationStatus,
            reason: reason,
            stderr: String(decoding: childStderr, as: UTF8.self),
            detail: String(describing: error)
        )
    }
    try stdinPipe.fileHandleForWriting.close()
    let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let stderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationReason == .exit, process.terminationStatus == 0 else {
        let childStderr = String(decoding: stderr, as: UTF8.self)
        FileHandle.standardError.write(Data("python_nonzero_stderr: \(childStderr.debugDescription)\n".utf8))
        throw GateError.nonzeroExit(process.terminationStatus)
    }
    try validate(stdout: stdout, stderr: stderr, requestID: requestID)

    let result: [String: Any] = [
        "classification": "stage6_gate_passed",
        "fixed_bundle_relative_launch": true,
        "foundation_process_shell_free": true,
        "strict_json_lines": true,
        "stdout_protocol_only": true,
        "stderr_diagnostic_only": true,
        "python_version": "3.13.14",
        "third_party_packages": 0,
        "path_search": false,
        "runtime_download": false,
        "user_site_packages": false,
        "external_communication": false
    ]
    let output = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    print(String(decoding: output, as: UTF8.self))
} catch {
    FileHandle.standardError.write(Data("stage6_gate_failed: \(error)\n".utf8))
    exit(1)
}
