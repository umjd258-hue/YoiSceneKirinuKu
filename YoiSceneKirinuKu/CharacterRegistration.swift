import CoreFoundation
import Foundation

enum CharacterRegistrationErrorCode: String, Codable, CaseIterable, Sendable {
    case invalidRequest = "registration_invalid_request"
    case sourceUnavailable = "registration_source_unavailable"
    case invalidInterval = "registration_invalid_interval"
    case ffmpegLaunchFailed = "registration_ffmpeg_launch_failed"
    case ffmpegFailed = "registration_ffmpeg_failed"
    case wavMissing = "registration_wav_missing"
    case wavInvalidFormat = "registration_wav_invalid_format"
    case audioTooShort = "registration_audio_too_short"
    case audioTooLong = "registration_audio_too_long"
    case audioSilent = "registration_audio_silent"
    case audioTooQuiet = "registration_audio_too_quiet"
    case modelUnavailable = "registration_model_unavailable"
    case embeddingFailed = "registration_embedding_failed"
    case embeddingInvalid = "registration_embedding_invalid"
    case metadataWriteFailed = "registration_metadata_write_failed"
    case finalizationFailed = "registration_finalization_failed"
    case characterNotFound = "registration_character_not_found"
    case characterBusy = "registration_character_busy"
    case protocolError = "registration_protocol_error"

    var userMessage: String {
        switch self {
        case .invalidRequest, .protocolError:
            "人物登録処理で問題が発生しました。"
        case .sourceUnavailable:
            "登録元の動画を読み込めません。"
        case .invalidInterval:
            "3秒以上30秒以下の範囲を選んでください。"
        case .ffmpegLaunchFailed, .ffmpegFailed, .wavMissing, .wavInvalidFormat:
            "登録音声を作成できませんでした。"
        case .audioTooShort:
            "登録音声は3秒以上必要です。"
        case .audioTooLong:
            "登録音声は30秒以内にしてください。"
        case .audioSilent:
            "選択範囲に音声がありません。"
        case .audioTooQuiet:
            "選択範囲の声が小さすぎます。"
        case .modelUnavailable, .embeddingFailed, .embeddingInvalid:
            "人物の声を登録できませんでした。"
        case .metadataWriteFailed, .finalizationFailed:
            "人物データを安全に保存できませんでした。"
        case .characterNotFound:
            "追加先の人物が見つかりません。"
        case .characterBusy:
            "この人物は別の処理で更新中です。"
        }
    }
}

struct CharacterRegistrationRequest: Equatable, Sendable {
    let displayName: String
    let sourceURL: URL
    let startMilliseconds: Int64
    let endMilliseconds: Int64
}

struct CharacterSampleAdditionRequest: Equatable, Sendable {
    let characterID: UUID
    let sourceURL: URL
    let startMilliseconds: Int64
    let endMilliseconds: Int64
}

struct RegisteredCharacter: Equatable, Sendable {
    let characterID: UUID
    let displayName: String
    let samples: [RegisteredAudioSampleSummary]
}

enum CharacterRegistrationOutcome: Equatable, Sendable {
    case success(RegisteredCharacter)
    case failure(CharacterRegistrationErrorCode)
}

enum CharacterLoadOutcome: Equatable, Sendable {
    case success([RegisteredCharacter])
    case failure(CharacterRegistrationErrorCode)
}

protocol CharacterRegistrationServicing: Sendable {
    func register(_ request: CharacterRegistrationRequest, requestID: UUID) async -> CharacterRegistrationOutcome
    func addSample(_ request: CharacterSampleAdditionRequest, requestID: UUID) async -> CharacterRegistrationOutcome
    func loadCharacters(requestID: UUID) async -> CharacterLoadOutcome
}

struct CharacterRegistrationConfiguration: Sendable {
    let pythonExecutableURL: URL
    let ffmpegExecutableURL: URL
    let modelDirectoryURL: URL
    let scriptURL: URL
    let charactersRootURL: URL

    static func bundled(bundle: Bundle = .main, fileManager: FileManager = .default) -> CharacterRegistrationConfiguration? {
        guard
            let pythonPath = bundle.object(forInfoDictionaryKey: "CharacterRegistrationPythonExecutable") as? String,
            let ffmpegPath = bundle.object(forInfoDictionaryKey: "CharacterRegistrationFFmpegExecutable") as? String,
            let modelPath = bundle.object(forInfoDictionaryKey: "CharacterRegistrationModelDirectory") as? String,
            !pythonPath.isEmpty, !ffmpegPath.isEmpty, !modelPath.isEmpty,
            let scriptURL = bundle.url(forResource: "character_registration", withExtension: "py"),
            let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else {
            return nil
        }
        return CharacterRegistrationConfiguration(
            pythonExecutableURL: URL(fileURLWithPath: pythonPath),
            ffmpegExecutableURL: URL(fileURLWithPath: ffmpegPath),
            modelDirectoryURL: URL(fileURLWithPath: modelPath, isDirectory: true),
            scriptURL: scriptURL,
            charactersRootURL: applicationSupport
                .appendingPathComponent("local.YoiSceneKirinuKu", isDirectory: true)
                .appendingPathComponent("characters", isDirectory: true)
        )
    }
}

final class CharacterRegistrationService: CharacterRegistrationServicing, @unchecked Sendable {
    private let configuration: CharacterRegistrationConfiguration?

    init(configuration: CharacterRegistrationConfiguration? = .bundled()) {
        self.configuration = configuration
    }

    func register(_ request: CharacterRegistrationRequest, requestID: UUID) async -> CharacterRegistrationOutcome {
        guard let configuration else { return .failure(.modelUnavailable) }
        let body: [String: Any] = [
            "protocol_version": 1,
            "request_id": requestID.uuidString.lowercased(),
            "operation": "register_character",
            "display_name": request.displayName,
            "source_path": request.sourceURL.path,
            "start_ms": request.startMilliseconds,
            "end_ms": request.endMilliseconds,
            "characters_root": configuration.charactersRootURL.path,
        ]
        let result = await execute(body: body, requestID: requestID, configuration: configuration)
        return CharacterRegistrationProtocolParser.parseRegistration(result, requestID: requestID)
    }

    func loadCharacters(requestID: UUID) async -> CharacterLoadOutcome {
        guard let configuration else { return .failure(.modelUnavailable) }
        let body: [String: Any] = [
            "protocol_version": 1,
            "request_id": requestID.uuidString.lowercased(),
            "operation": "list_characters",
            "characters_root": configuration.charactersRootURL.path,
        ]
        let result = await execute(body: body, requestID: requestID, configuration: configuration)
        return CharacterRegistrationProtocolParser.parseLoad(result, requestID: requestID)
    }

    func addSample(_ request: CharacterSampleAdditionRequest, requestID: UUID) async -> CharacterRegistrationOutcome {
        guard let configuration else { return .failure(.modelUnavailable) }
        let body: [String: Any] = [
            "protocol_version": 1,
            "request_id": requestID.uuidString.lowercased(),
            "operation": "add_sample",
            "character_id": "char_\(request.characterID.uuidString.lowercased())",
            "source_path": request.sourceURL.path,
            "start_ms": request.startMilliseconds,
            "end_ms": request.endMilliseconds,
            "characters_root": configuration.charactersRootURL.path,
        ]
        let result = await execute(body: body, requestID: requestID, configuration: configuration)
        return CharacterRegistrationProtocolParser.parseRegistration(result, requestID: requestID)
    }

    private func execute(
        body: [String: Any],
        requestID: UUID,
        configuration: CharacterRegistrationConfiguration
    ) async -> CharacterProcessResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: Self.executeSynchronously(
                    body: body,
                    configuration: configuration
                ))
            }
        }
    }

    private static func executeSynchronously(
        body: [String: Any],
        configuration: CharacterRegistrationConfiguration
    ) -> CharacterProcessResult {
        guard validateExecutable(configuration.pythonExecutableURL),
              validateExecutable(configuration.ffmpegExecutableURL),
              validateRegularFile(configuration.scriptURL),
              validateDirectory(configuration.modelDirectoryURL) else {
            return .notStarted
        }
        guard let requestData = try? JSONSerialization.data(withJSONObject: body) else {
            return .notStarted
        }

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = configuration.pythonExecutableURL
        process.arguments = [
            configuration.scriptURL.path,
            configuration.ffmpegExecutableURL.path,
            configuration.modelDirectoryURL.path,
        ]
        process.environment = (ProcessInfo.processInfo.environment).merging([
            "HF_HUB_OFFLINE": "1",
            "TRANSFORMERS_OFFLINE": "1",
        ]) { _, injected in injected }
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            return .notStarted
        }

        let streamGroup = DispatchGroup()
        let dataStore = CharacterStreamData()
        streamGroup.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            dataStore.setStdout(outputPipe.fileHandleForReading.readDataToEndOfFile())
            streamGroup.leave()
        }
        streamGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            dataStore.setStderr(errorPipe.fileHandleForReading.readDataToEndOfFile())
            streamGroup.leave()
        }

        do {
            try inputPipe.fileHandleForWriting.write(contentsOf: requestData)
            try inputPipe.fileHandleForWriting.write(contentsOf: Data([0x0A]))
            try inputPipe.fileHandleForWriting.close()
        } catch {
            process.terminate()
        }
        process.waitUntilExit()
        streamGroup.wait()
        return CharacterProcessResult(
            stdout: dataStore.stdout,
            terminationStatus: process.terminationStatus,
            terminationReason: process.terminationReason
        )
    }

    private static func validateExecutable(_ url: URL) -> Bool {
        guard url.path.hasPrefix("/") else { return false }
        let resolvedURL = url.resolvingSymlinksInPath()
        return validateRegularFile(resolvedURL)
            && FileManager.default.isExecutableFile(atPath: resolvedURL.path)
    }

    private static func validateRegularFile(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return false }
        return values.isRegularFile == true && values.isSymbolicLink != true
    }

    private static func validateDirectory(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return false }
        return values.isDirectory == true && values.isSymbolicLink != true
    }
}

private struct CharacterProcessResult: Sendable {
    let stdout: Data
    let terminationStatus: Int32
    let terminationReason: Process.TerminationReason

    static let notStarted = CharacterProcessResult(
        stdout: Data(),
        terminationStatus: -1,
        terminationReason: .uncaughtSignal
    )
}

private enum CharacterRegistrationProtocolParser {
    private struct ParsedTerminal {
        let result: [String: Any]?
        let error: CharacterRegistrationErrorCode?
    }

    static func parseRegistration(_ process: CharacterProcessResult, requestID: UUID) -> CharacterRegistrationOutcome {
        guard let terminal = parse(process, requestID: requestID) else { return .failure(.protocolError) }
        if let error = terminal.error { return .failure(error) }
        guard let value = terminal.result?["character"], let character = parseCharacter(value) else {
            return .failure(.protocolError)
        }
        return .success(character)
    }

    static func parseLoad(_ process: CharacterProcessResult, requestID: UUID) -> CharacterLoadOutcome {
        guard let terminal = parse(process, requestID: requestID) else { return .failure(.protocolError) }
        if let error = terminal.error { return .failure(error) }
        guard let values = terminal.result?["characters"] as? [Any] else { return .failure(.protocolError) }
        var characters = [RegisteredCharacter]()
        for value in values {
            guard let character = parseCharacter(value) else { return .failure(.protocolError) }
            characters.append(character)
        }
        return .success(characters)
    }

    private static func parse(_ process: CharacterProcessResult, requestID: UUID) -> ParsedTerminal? {
        guard process.terminationReason == .exit, process.terminationStatus == 0,
              let text = String(data: process.stdout, encoding: .utf8) else { return nil }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.last == "" else { return nil }
        var expectedSequence = 1
        var recordedError: CharacterRegistrationErrorCode?
        var terminal: ParsedTerminal?
        for line in lines.dropLast() {
            guard terminal == nil, !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["protocol_version"] as? Int == 1,
                  object["request_id"] as? String == requestID.uuidString.lowercased(),
                  object["sequence"] as? Int == expectedSequence,
                  let type = object["type"] as? String,
                  let payload = object["payload"] as? [String: Any] else { return nil }
            expectedSequence += 1
            switch type {
            case "progress":
                guard payload["stage"] is String, payload["status"] is String else { return nil }
            case "error":
                guard recordedError == nil,
                      let raw = payload["code"] as? String,
                      let code = CharacterRegistrationErrorCode(rawValue: raw) else { return nil }
                recordedError = code
            case "finished":
                guard let outcome = payload["outcome"] as? String else { return nil }
                if outcome == "succeeded", recordedError == nil,
                   let result = payload["result"] as? [String: Any] {
                    terminal = ParsedTerminal(result: result, error: nil)
                } else if outcome == "failed",
                          let raw = payload["code"] as? String,
                          let code = recordedError,
                          code.rawValue == raw {
                    terminal = ParsedTerminal(result: nil, error: code)
                } else {
                    return nil
                }
            default:
                return nil
            }
        }
        return terminal
    }

    private static func parseCharacter(_ value: Any) -> RegisteredCharacter? {
        guard let value = value as? [String: Any],
              let rawCharacterID = value["character_id"] as? String,
              let characterID = parseID(rawCharacterID, prefix: "char_"),
              let displayName = value["display_name"] as? String,
              !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let sampleValues = value["samples"] as? [[String: Any]],
              !sampleValues.isEmpty else { return nil }
        var samples = [RegisteredAudioSampleSummary]()
        for sample in sampleValues {
            guard let rawSampleID = sample["sample_id"] as? String,
                  let sampleID = parseID(rawSampleID, prefix: "sample_"),
                  let duration = exactPositiveInteger(sample["duration_ms"]) else { return nil }
            samples.append(RegisteredAudioSampleSummary(
                id: sampleID,
                sourceFileName: "source.wav",
                durationMilliseconds: duration
            ))
        }
        return RegisteredCharacter(characterID: characterID, displayName: displayName, samples: samples)
    }

    private static func parseID(_ value: String, prefix: String) -> UUID? {
        guard value.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(value.dropFirst(prefix.count)))
    }

    private static func exactPositiveInteger(_ value: Any?) -> Int64? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite,
              number.doubleValue == Double(number.int64Value),
              number.int64Value > 0 else { return nil }
        return number.int64Value
    }
}

private final class CharacterStreamData: @unchecked Sendable {
    private let lock = NSLock()
    private var storedStdout = Data()
    private var storedStderr = Data()

    var stdout: Data { lock.withLock { storedStdout } }
    func setStdout(_ data: Data) { lock.withLock { storedStdout = data } }
    func setStderr(_ data: Data) { lock.withLock { storedStderr = data } }
}
