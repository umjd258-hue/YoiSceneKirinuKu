import CryptoKit
import Foundation

enum ResultListErrorCode: String, Error, Equatable, Sendable {
    case jobInvalid = "result_list_job_invalid"
    case schemaInvalid = "result_list_schema_invalid"
    case stale = "result_list_stale"

    var userMessage: String {
        switch self {
        case .jobInvalid: "解析ジョブを確認できません。"
        case .schemaInvalid: "解析結果を読み込めません。"
        case .stale: "解析結果が古いため使用できません。"
        }
    }

    var nextAction: String { "解析をもう一度実行してください。" }
}

enum ResultListOutcome: Equatable {
    case success(ResultsState)
    case failure(ResultListErrorCode)
}

protocol ResultListLoading {
    func load(jobID: UUID, characters: [CharacterSummary]) -> ResultListOutcome
}

struct ResultListConfiguration: Sendable {
    let workspaceRootURL: URL

    static func bundled(fileManager: FileManager = .default) -> Self? {
        guard let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return Self(workspaceRootURL: support.appendingPathComponent("local.YoiSceneKirinuKu/workspace", isDirectory: true))
    }
}

struct ResultListService: ResultListLoading {
    private let configuration: ResultListConfiguration?
    private let fileManager: FileManager

    init(configuration: ResultListConfiguration? = .bundled(), fileManager: FileManager = .default) {
        self.configuration = configuration
        self.fileManager = fileManager
    }

    func load(jobID: UUID, characters: [CharacterSummary]) -> ResultListOutcome {
        guard let configuration,
              let job = try? AnalysisJobService.loadJob(from: configuration.workspaceRootURL),
              job.jobID == jobID else {
            return .failure(.jobInvalid)
        }
        let current = configuration.workspaceRootURL.appendingPathComponent("current_job", isDirectory: true)
        let resultURL = current.appendingPathComponent("result.json")
        guard isRegularFile(resultURL), let data = try? Data(contentsOf: resultURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(.schemaInvalid)
        }
        do {
            return .success(try parse(root, jobID: jobID, currentJobURL: current, characters: characters))
        } catch let code as ResultListErrorCode {
            return .failure(code)
        } catch {
            return .failure(.schemaInvalid)
        }
    }

    func parse(
        _ root: [String: Any],
        jobID: UUID,
        currentJobURL: URL,
        characters: [CharacterSummary]
    ) throws -> ResultsState {
        try exact(root, ["schema_version", "job_id", "contract_version", "sources", "candidates"])
        guard integer(root["schema_version"]) == 1,
              root["job_id"] as? String == jobID.uuidString.lowercased(),
              root["contract_version"] as? String == "stage18-result-v1",
              let sources = root["sources"] as? [String: Any],
              Set(sources.keys) == ["speaker_candidates", "speaker_decisions", "quality_decisions"],
              let items = root["candidates"] as? [[String: Any]] else {
            throw ResultListErrorCode.schemaInvalid
        }
        for (name, value) in sources {
            guard let fingerprint = value as? [String: Any] else { throw ResultListErrorCode.schemaInvalid }
            try validateFingerprint(fingerprint, fileURL: currentJobURL.appendingPathComponent("\(name).json"))
        }

        let names = Dictionary(uniqueKeysWithValues: characters.map { ($0.id, $0.name) })
        var candidates: [(ResultGroupID, String, ResultCandidate)] = []
        var seen = Set<String>()
        var previous: (Int64, Int64, String)?
        for item in items {
            try exact(item, ["candidate_id", "start_ms", "end_ms", "match", "character_id", "match_reason", "top_similarity", "quality", "quality_reasons"])
            guard let candidateID = item["candidate_id"] as? String,
                  candidateID.hasPrefix("candidate_"),
                  let id = UUID(uuidString: String(candidateID.dropFirst("candidate_".count))),
                  seen.insert(candidateID).inserted,
                  let start = integer(item["start_ms"]), let end = integer(item["end_ms"]),
                  start >= 0, end > start,
                  let match = item["match"] as? String,
                  let matchReason = item["match_reason"] as? String,
                  !matchReason.isEmpty,
                  let qualityRaw = item["quality"] as? String,
                  let quality = ResultQuality(rawValue: qualityRaw),
                  let reasons = item["quality_reasons"] as? [String],
                  reasons.allSatisfy({ !$0.isEmpty }) else {
                throw ResultListErrorCode.schemaInvalid
            }
            if let score = item["top_similarity"], !(score is NSNull) {
                guard let value = number(score), value.isFinite, (-1.0...1.0).contains(value) else {
                    throw ResultListErrorCode.schemaInvalid
                }
            }
            let key = (start, end, candidateID)
            if let previous, !(previous < key) { throw ResultListErrorCode.schemaInvalid }
            previous = key

            let groupID: ResultGroupID
            let title: String
            let display: CharacterMatchDisplay
            if match == "matched", let rawID = item["character_id"] as? String,
               rawID.hasPrefix("char_"),
               let characterID = UUID(uuidString: String(rawID.dropFirst("char_".count))),
               let name = names[characterID] {
                groupID = .character(characterID)
                title = name
                display = .matched
            } else if match == "unknown", item["character_id"] is NSNull {
                groupID = .unknown
                title = "人物不明"
                display = .unknown
            } else {
                throw ResultListErrorCode.schemaInvalid
            }
            candidates.append((groupID, title, ResultCandidate(
                id: id,
                candidateID: candidateID,
                startMilliseconds: start,
                durationMilliseconds: end - start,
                quality: quality,
                characterMatch: display,
                qualityReasons: reasons
            )))
        }

        var order: [ResultGroupID] = []
        var titles: [ResultGroupID: String] = [:]
        var grouped: [ResultGroupID: [ResultCandidate]] = [:]
        for (groupID, title, candidate) in candidates {
            if grouped[groupID] == nil { order.append(groupID) }
            titles[groupID] = title
            grouped[groupID, default: []].append(candidate)
        }
        let groups = order.map { ResultGroup(id: $0, title: titles[$0]!, candidates: grouped[$0]!) }
        return ResultsState(
            groups: groups,
            selection: ResultSelectionState(selectedCandidateIDs: []),
            focusedCandidateID: groups.first?.candidates.first?.id,
            expandedGroupIDs: Set(order),
            loadError: nil
        )
    }

    private func validateFingerprint(_ value: [String: Any], fileURL: URL) throws {
        try exact(value, ["algorithm", "byte_count", "digest"])
        guard value["algorithm"] as? String == "sha256",
              let expectedHash = value["digest"] as? String, expectedHash.count == 64,
              let expectedSize = integer(value["byte_count"]), expectedSize >= 0,
              isRegularFile(fileURL), let data = try? Data(contentsOf: fileURL),
              Int64(data.count) == expectedSize else {
            throw ResultListErrorCode.stale
        }
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual == expectedHash else { throw ResultListErrorCode.stale }
    }

    private func exact(_ value: [String: Any], _ keys: Set<String>) throws {
        guard Set(value.keys) == keys else { throw ResultListErrorCode.schemaInvalid }
    }

    private func isRegularFile(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return false }
        return values.isRegularFile == true && values.isSymbolicLink != true
    }

    private func integer(_ value: Any?) -> Int64? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let integer = number.int64Value
        return number.doubleValue == Double(integer) ? integer : nil
    }

    private func number(_ value: Any) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return number.doubleValue
    }
}
