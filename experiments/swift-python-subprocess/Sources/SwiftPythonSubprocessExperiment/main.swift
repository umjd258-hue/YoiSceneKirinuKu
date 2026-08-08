import Foundation

struct Configuration {
    let pythonPath: String
    let scriptPath: String
    let mode: String
    let message: String
    let expectedExitCode: Int32?
    let expectSpawnFailure: Bool

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

        let expectedExitCode: Int32?
        if let rawValue = values["--expected-exit"] {
            guard let parsed = Int32(rawValue) else {
                throw ExperimentError.invalidArguments("--expected-exit must be an Int32")
            }
            expectedExitCode = parsed
        } else {
            expectedExitCode = nil
        }

        return Configuration(
            pythonPath: pythonPath,
            scriptPath: scriptPath,
            mode: mode,
            message: values["--message"] ?? "",
            expectedExitCode: expectedExitCode,
            expectSpawnFailure: flags.contains("--expect-spawn-failure")
        )
    }
}

enum ExperimentError: Error, CustomStringConvertible {
    case invalidArguments(String)
    case unexpectedSpawnFailure(String)
    case expectedSpawnFailureDidNotOccur
    case unexpectedExitCode(expected: Int32, actual: Int32)

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
        }
    }
}

func decoded(_ data: Data) -> String {
    String(data: data, encoding: .utf8) ?? "<non-utf8-data>"
}

func run(configuration: Configuration) throws {
    let process = Process()
    let standardOutput = Pipe()
    let standardError = Pipe()

    process.executableURL = URL(fileURLWithPath: configuration.pythonPath)
    process.arguments = [
        configuration.scriptPath,
        "--mode", configuration.mode,
        "--message", configuration.message
    ]
    process.standardOutput = standardOutput
    process.standardError = standardError

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

    // fixtureの出力量を小さく固定した検証。大量出力時の方式は本番通信契約で別途検証する。
    process.waitUntilExit()
    let outputData = standardOutput.fileHandleForReading.readDataToEndOfFile()
    let errorData = standardError.fileHandleForReading.readDataToEndOfFile()

    let outputText = decoded(outputData).trimmingCharacters(in: .newlines)
    let errorText = decoded(errorData).trimmingCharacters(in: .newlines)

    print("classification=launched")
    print("termination_reason=\(process.terminationReason.rawValue)")
    print("termination_status=\(process.terminationStatus)")
    print("child_stdout=\(outputText)")
    print("child_stderr=\(errorText)")

    let expected = configuration.expectedExitCode ?? 0
    guard process.terminationStatus == expected else {
        throw ExperimentError.unexpectedExitCode(
            expected: expected,
            actual: process.terminationStatus
        )
    }
}

do {
    let configuration = try Configuration.parse(Array(CommandLine.arguments.dropFirst()))
    try run(configuration: configuration)
    print("experiment_result=passed")
    exit(EXIT_SUCCESS)
} catch {
    FileHandle.standardError.write(Data("experiment_result=failed \(error)\n".utf8))
    exit(EXIT_FAILURE)
}

