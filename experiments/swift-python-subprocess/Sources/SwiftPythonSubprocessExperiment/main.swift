import Foundation

struct Configuration {
    let pythonPath: String
    let scriptPath: String
    let mode: String
    let message: String
    let expectedExitCode: Int32?
    let expectSpawnFailure: Bool
    let profile: String?
    let records: Int?
    let payloadBytes: Int?
    let delayMicroseconds: Int?
    let deadlineSeconds: TimeInterval?

    static func parse(_ arguments: [String]) throws -> Configuration {
        var values: [String: String] = [:]
        var flags = Set<String>()
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--expect-spawn-failure" {
                flags.insert(argument)
                index += 1
                continue
            }

            guard argument.hasPrefix("--"), index + 1 < arguments.count else {
                throw ExperimentError.invalidArguments("Unexpected argument: \(argument)")
            }
            values[argument] = arguments[index + 1]
            index += 2
        }

        guard let pythonPath = values["--python"],
              let scriptPath = values["--script"],
              let mode = values["--mode"] else {
            throw ExperimentError.invalidArguments("--python, --script, and --mode are required")
        }

        func integer(_ name: String) throws -> Int? {
            guard let rawValue = values[name] else { return nil }
            guard let value = Int(rawValue), value >= 0 else {
                throw ExperimentError.invalidArguments("\(name) must be a non-negative integer")
            }
            return value
        }

        let expectedExitCode: Int32?
        if let rawValue = values["--expected-exit"] {
            guard let parsed = Int32(rawValue) else {
                throw ExperimentError.invalidArguments("--expected-exit must be an Int32")
            }
            expectedExitCode = parsed
        } else {
            expectedExitCode = nil
        }

        let deadlineSeconds: TimeInterval?
        if let rawValue = values["--deadline-seconds"] {
            guard let value = TimeInterval(rawValue), value > 0 else {
                throw ExperimentError.invalidArguments("--deadline-seconds must be positive")
            }
            deadlineSeconds = value
        } else {
            deadlineSeconds = nil
        }

        let configuration = Configuration(
            pythonPath: pythonPath,
            scriptPath: scriptPath,
            mode: mode,
            message: values["--message"] ?? "",
            expectedExitCode: expectedExitCode,
            expectSpawnFailure: flags.contains("--expect-spawn-failure"),
            profile: values["--profile"],
            records: try integer("--records"),
            payloadBytes: try integer("--payload-bytes"),
            delayMicroseconds: try integer("--delay-microseconds"),
            deadlineSeconds: deadlineSeconds
        )

        if mode == "streaming" {
            guard configuration.profile != nil,
                  configuration.records != nil,
                  configuration.payloadBytes != nil,
                  configuration.delayMicroseconds != nil,
                  configuration.deadlineSeconds != nil else {
                throw ExperimentError.invalidArguments(
                    "streaming mode requires --profile, --records, --payload-bytes, --delay-microseconds, and --deadline-seconds"
                )
            }
        }
        return configuration
    }
}

enum ExperimentError: Error, CustomStringConvertible {
    case invalidArguments(String)
    case unexpectedSpawnFailure(String)
    case expectedSpawnFailureDidNotOccur
    case unexpectedExitCode(expected: Int32, actual: Int32)
    case timeout(String)
    case streamValidation(String)

    var description: String {
        switch self {
        case .invalidArguments(let message):
            return "invalid_arguments: \(message)"
        case .unexpectedSpawnFailure(let message):
            return "unexpected_spawn_failure: \(message)"
        case .expectedSpawnFailureDidNotOccur:
            return "expected_spawn_failure_did_not_occur"
        case .unexpectedExitCode(let expected, let actual):
            return "unexpected_exit_code: expected=\(expected) actual=\(actual)"
        case .timeout(let message):
            return "timeout: \(message)"
        case .streamValidation(let message):
            return "stream_validation_failed: \(message)"
        }
    }
}

final class StreamCollector: @unchecked Sendable {
    let name: String
    private let lock = NSLock()
    private var storage = Data()
    private var didReachEOF = false
    private var readFailure: String?

    init(name: String) {
        self.name = name
    }

    func readToEOF(from handle: FileHandle) {
        do {
            while let data = try handle.read(upToCount: 64 * 1024), !data.isEmpty {
                lock.lock()
                storage.append(data)
                lock.unlock()
            }
            lock.lock()
            didReachEOF = true
            lock.unlock()
        } catch {
            lock.lock()
            readFailure = String(describing: error)
            lock.unlock()
        }
    }

    func snapshot() -> (data: Data, eof: Bool, error: String?) {
        lock.lock()
        defer { lock.unlock() }
        return (storage, didReachEOF, readFailure)
    }
}

struct WireRecord: Decodable {
    let stream: String
    let sequence: Int?
    let payload: String?
    let sentinel: Bool
}

struct ValidationSummary {
    let stream: String
    let expected: Int
    let received: Int
    let missing: Int
    let duplicates: Int
    let orderViolations: Int
    let payloadErrors: Int
    let sentinelCount: Int
    let eof: Bool
}

func validate(
    collector: StreamCollector,
    expectedRecords: Int,
    payloadBytes: Int
) throws -> ValidationSummary {
    let newlineByte: UInt8 = 0x0A
    let snapshot = collector.snapshot()
    if let error = snapshot.error {
        throw ExperimentError.streamValidation("\(collector.name) read error: \(error)")
    }
    guard snapshot.eof else {
        throw ExperimentError.streamValidation("\(collector.name) EOF not observed")
    }
    guard snapshot.data.last == newlineByte else {
        throw ExperimentError.streamValidation("\(collector.name) ended with an incomplete line")
    }

    let lines = snapshot.data.split(separator: newlineByte)
    var sequences: [Int] = []
    var payloadErrors = 0
    var sentinelCount = 0
    let expectedCharacter = collector.name == "stdout" ? Character("O") : Character("E")

    for line in lines {
        let record: WireRecord
        do {
            record = try JSONDecoder().decode(WireRecord.self, from: Data(line))
        } catch {
            throw ExperimentError.streamValidation("\(collector.name) malformed record: \(error)")
        }
        guard record.stream == collector.name else {
            throw ExperimentError.streamValidation(
                "\(collector.name) received record for \(record.stream)"
            )
        }
        if record.sentinel {
            sentinelCount += 1
            continue
        }
        guard let sequence = record.sequence, let payload = record.payload else {
            throw ExperimentError.streamValidation("\(collector.name) missing sequence or payload")
        }
        sequences.append(sequence)
        if payload.utf8.count != payloadBytes || !payload.allSatisfy({ $0 == expectedCharacter }) {
            payloadErrors += 1
        }
    }

    var seen = Set<Int>()
    var duplicates = 0
    var orderViolations = 0
    for (index, sequence) in sequences.enumerated() {
        if !seen.insert(sequence).inserted { duplicates += 1 }
        if sequence != index { orderViolations += 1 }
    }
    let expectedSet = Set(0..<expectedRecords)
    let missing = expectedSet.subtracting(seen).count

    let summary = ValidationSummary(
        stream: collector.name,
        expected: expectedRecords,
        received: sequences.count,
        missing: missing,
        duplicates: duplicates,
        orderViolations: orderViolations,
        payloadErrors: payloadErrors,
        sentinelCount: sentinelCount,
        eof: snapshot.eof
    )
    guard summary.received == expectedRecords,
          missing == 0,
          duplicates == 0,
          orderViolations == 0,
          payloadErrors == 0,
          sentinelCount == 1 else {
        throw ExperimentError.streamValidation(String(describing: summary))
    }
    return summary
}

func waitForExit(_ process: Process, deadlineSeconds: TimeInterval) throws -> TimeInterval {
    let start = Date()
    while process.isRunning {
        if Date().timeIntervalSince(start) > deadlineSeconds {
            // timeout時の後始末専用。本番の停止方式を示すものではない。
            process.terminate()
            let cleanupDeadline = Date().addingTimeInterval(2)
            while process.isRunning, Date() < cleanupDeadline {
                Thread.sleep(forTimeInterval: 0.01)
            }
            throw ExperimentError.timeout("child process did not finish within \(deadlineSeconds) seconds")
        }
        Thread.sleep(forTimeInterval: 0.01)
    }
    return Date().timeIntervalSince(start)
}

func runStreaming(configuration: Configuration, process: Process, stdout: Pipe, stderr: Pipe) throws {
    let records = configuration.records!
    let payloadBytes = configuration.payloadBytes!
    let profile = configuration.profile!
    let deadlineSeconds = configuration.deadlineSeconds!
    process.arguments = [
        configuration.scriptPath,
        "--mode", "streaming",
        "--profile", profile,
        "--records", String(records),
        "--payload-bytes", String(payloadBytes),
        "--delay-microseconds", String(configuration.delayMicroseconds!)
    ]

    let stdoutCollector = StreamCollector(name: "stdout")
    let stderrCollector = StreamCollector(name: "stderr")
    let readers = DispatchGroup()
    readers.enter()
    DispatchQueue.global().async {
        stdoutCollector.readToEOF(from: stdout.fileHandleForReading)
        readers.leave()
    }
    readers.enter()
    DispatchQueue.global().async {
        stderrCollector.readToEOF(from: stderr.fileHandleForReading)
        readers.leave()
    }

    try process.run()
    let elapsed = try waitForExit(process, deadlineSeconds: deadlineSeconds)
    guard readers.wait(timeout: .now() + 2) == .success else {
        throw ExperimentError.timeout("stdout/stderr EOF was not observed after process exit")
    }
    guard process.terminationStatus == 0 else {
        throw ExperimentError.unexpectedExitCode(expected: 0, actual: process.terminationStatus)
    }

    let stdoutSummary = try validate(
        collector: stdoutCollector,
        expectedRecords: records,
        payloadBytes: payloadBytes
    )
    let stderrSummary = try validate(
        collector: stderrCollector,
        expectedRecords: records,
        payloadBytes: payloadBytes
    )

    print("profile=\(profile)")
    print("elapsed_seconds=\(String(format: "%.3f", elapsed))")
    for summary in [stdoutSummary, stderrSummary] {
        print(
            "stream=\(summary.stream) expected=\(summary.expected) received=\(summary.received) "
                + "missing=\(summary.missing) duplicates=\(summary.duplicates) "
                + "order_violations=\(summary.orderViolations) payload_errors=\(summary.payloadErrors) "
                + "sentinel_count=\(summary.sentinelCount) eof=\(summary.eof)"
        )
    }
    print("timeout=false")
    print("experiment_result=passed")
}

func decoded(_ data: Data) -> String {
    String(data: data, encoding: .utf8) ?? "<non-utf8-data>"
}

func run(configuration: Configuration) throws {
    let process = Process()
    let standardOutput = Pipe()
    let standardError = Pipe()
    process.executableURL = URL(fileURLWithPath: configuration.pythonPath)
    process.standardOutput = standardOutput
    process.standardError = standardError

    if configuration.mode == "streaming" {
        do {
            try runStreaming(
                configuration: configuration,
                process: process,
                stdout: standardOutput,
                stderr: standardError
            )
        } catch CocoaError.fileNoSuchFile {
            throw ExperimentError.unexpectedSpawnFailure("Python executable was not found")
        }
        return
    }

    process.arguments = [
        configuration.scriptPath,
        "--mode", configuration.mode,
        "--message", configuration.message
    ]
    do {
        try process.run()
    } catch {
        if configuration.expectSpawnFailure {
            print("classification=spawn_failure")
            print("spawn_error=\(error)")
            return
        }
        throw ExperimentError.unexpectedSpawnFailure(String(describing: error))
    }
    if configuration.expectSpawnFailure {
        process.terminate()
        process.waitUntilExit()
        throw ExperimentError.expectedSpawnFailureDidNotOccur
    }

    process.waitUntilExit()
    let outputText = decoded(standardOutput.fileHandleForReading.readDataToEndOfFile())
        .trimmingCharacters(in: .newlines)
    let errorText = decoded(standardError.fileHandleForReading.readDataToEndOfFile())
        .trimmingCharacters(in: .newlines)
    print("classification=launched")
    print("termination_reason=\(process.terminationReason.rawValue)")
    print("termination_status=\(process.terminationStatus)")
    print("child_stdout=\(outputText)")
    print("child_stderr=\(errorText)")
    let expected = configuration.expectedExitCode ?? 0
    guard process.terminationStatus == expected else {
        throw ExperimentError.unexpectedExitCode(expected: expected, actual: process.terminationStatus)
    }
}

do {
    let configuration = try Configuration.parse(Array(CommandLine.arguments.dropFirst()))
    try run(configuration: configuration)
    if configuration.mode != "streaming" {
        print("experiment_result=passed")
    }
    exit(EXIT_SUCCESS)
} catch {
    FileHandle.standardError.write(Data("experiment_result=failed \(error)\n".utf8))
    exit(EXIT_FAILURE)
}
