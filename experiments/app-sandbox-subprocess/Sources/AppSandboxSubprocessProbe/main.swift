import CoreFoundation
import Foundation
import Security

struct ProbeResult: Codable {
    let expectedSandbox: Bool
    let entitlementSandbox: Bool?
    let pythonStarted: Bool
    let pythonExitCode: Int32?
    let pythonStdoutJSONValid: Bool
    let pythonReportedFFmpegStarted: Bool
    let pythonReportedFFmpegExitCode: Int?
    let pythonStderrSeparated: Bool
    let classification: String
    let detail: String
}

struct ChildResult: Decodable {
    let ffmpegStarted: Bool
    let ffmpegExitCode: Int?
    let classification: String
}

func mark(_ message: String) {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
}

func sandboxEntitlement() -> Bool? {
    guard let task = SecTaskCreateFromSelf(nil),
          let value = SecTaskCopyValueForEntitlement(task, "com.apple.security.app-sandbox" as CFString, nil)
    else { return nil }
    return (value as? NSNumber)?.boolValue
}

func emit(_ result: ProbeResult, exitCode: Int32) -> Never {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    if let data = try? encoder.encode(result) {
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0A]))
    }
    exit(exitCode)
}

let arguments = CommandLine.arguments
mark("process_started")
guard arguments.count == 4,
      ["true", "false"].contains(arguments[1])
else {
    emit(ProbeResult(expectedSandbox: false, entitlementSandbox: sandboxEntitlement(), pythonStarted: false, pythonExitCode: nil, pythonStdoutJSONValid: false, pythonReportedFFmpegStarted: false, pythonReportedFFmpegExitCode: nil, pythonStderrSeparated: false, classification: "invalid_arguments", detail: "expected: <true|false> <python> <ffmpeg>"), exitCode: 2)
}

let expectedSandbox = arguments[1] == "true"
mark("entitlement_check_started")
let entitlement = sandboxEntitlement()
let effectiveSandbox = entitlement ?? false
mark("entitlement_check_finished")
guard effectiveSandbox == expectedSandbox else {
    emit(ProbeResult(expectedSandbox: expectedSandbox, entitlementSandbox: entitlement, pythonStarted: false, pythonExitCode: nil, pythonStdoutJSONValid: false, pythonReportedFFmpegStarted: false, pythonReportedFFmpegExitCode: nil, pythonStderrSeparated: false, classification: "entitlement_mismatch", detail: "runtime entitlement did not match expected condition"), exitCode: 3)
}

guard let fixture = Bundle.main.url(forResource: "ffmpeg_child_fixture", withExtension: "py") else {
    emit(ProbeResult(expectedSandbox: expectedSandbox, entitlementSandbox: entitlement, pythonStarted: false, pythonExitCode: nil, pythonStdoutJSONValid: false, pythonReportedFFmpegStarted: false, pythonReportedFFmpegExitCode: nil, pythonStderrSeparated: false, classification: "fixture_missing", detail: "bundle resource was not found"), exitCode: 4)
}
mark("fixture_resolved")

let process = Process()
process.executableURL = URL(fileURLWithPath: arguments[2])
process.arguments = [fixture.path, arguments[3]]
let stdoutPipe = Pipe()
let stderrPipe = Pipe()
process.standardOutput = stdoutPipe
process.standardError = stderrPipe

do {
    mark("python_launch_started")
    try process.run()
    mark("python_launch_returned")
} catch {
    emit(ProbeResult(expectedSandbox: expectedSandbox, entitlementSandbox: entitlement, pythonStarted: false, pythonExitCode: nil, pythonStdoutJSONValid: false, pythonReportedFFmpegStarted: false, pythonReportedFFmpegExitCode: nil, pythonStderrSeparated: false, classification: "swift_to_python_launch_failed", detail: String(describing: error)), exitCode: 10)
}

let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
process.waitUntilExit()
mark("python_exit_observed")

let child = try? JSONDecoder().decode(ChildResult.self, from: stdoutData)
let stderrText = String(data: stderrData, encoding: .utf8) ?? ""
let passed = process.terminationReason == .exit && process.terminationStatus == 0 && child?.ffmpegStarted == true && child?.ffmpegExitCode == 0 && child?.classification == "ffmpeg_completed" && stderrText.contains("python fixture log")
emit(ProbeResult(expectedSandbox: expectedSandbox, entitlementSandbox: entitlement, pythonStarted: true, pythonExitCode: process.terminationStatus, pythonStdoutJSONValid: child != nil, pythonReportedFFmpegStarted: child?.ffmpegStarted ?? false, pythonReportedFFmpegExitCode: child?.ffmpegExitCode, pythonStderrSeparated: stderrText.contains("python fixture log"), classification: passed ? "chain_completed" : "python_or_ffmpeg_failed", detail: passed ? "all required checks passed" : stderrText), exitCode: passed ? 0 : 20)
