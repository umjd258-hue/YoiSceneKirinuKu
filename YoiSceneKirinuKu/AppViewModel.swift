import Combine
import Foundation

enum HomeVideoState: Equatable {
    case unselected
    case checking
    case ready(fileName: String, duration: String)
    case failed(message: String)
}

struct CharacterSummary: Identifiable, Equatable {
    let id: UUID
    let name: String
}

enum HomeCharactersState: Equatable {
    case unregistered
    case unselected
    case selected(characters: [CharacterSummary])
}

struct HomeState: Equatable {
    var video: HomeVideoState
    var registeredCharacters: [CharacterSummary]
    var selectedCharacterIDs: Set<UUID>
    var isAIModelAvailable: Bool
    var isWorkspaceAvailable: Bool
    var isAnalysisSlotAvailable: Bool

    static let initial = HomeState(
        video: .unselected,
        registeredCharacters: [
            CharacterSummary(id: UUID(uuidString: "1c87d576-6f98-4e10-bf44-427cadb4e634")!, name: "コナン"),
            CharacterSummary(id: UUID(uuidString: "ceae23e4-f6fb-4aa8-860a-2c4a22fe1d07")!, name: "蘭"),
            CharacterSummary(id: UUID(uuidString: "a0386bc8-7d73-47de-ae6f-7a729255c194")!, name: "灰原"),
        ],
        selectedCharacterIDs: [],
        isAIModelAvailable: false,
        isWorkspaceAvailable: false,
        isAnalysisSlotAvailable: false
    )

    var selectedCharacters: [CharacterSummary] {
        registeredCharacters.filter { selectedCharacterIDs.contains($0.id) }
    }

    var characters: HomeCharactersState {
        if registeredCharacters.isEmpty { return .unregistered }
        let selected = selectedCharacters
        return selected.isEmpty ? .unselected : .selected(characters: selected)
    }

    var canStartAnalysis: Bool {
        guard case .ready = video, !selectedCharacters.isEmpty else {
            return false
        }

        return isAIModelAvailable
            && isWorkspaceAvailable
            && isAnalysisSlotAvailable
    }
}

enum AnalysisStep: Int, CaseIterable, Identifiable, Equatable {
    case prepareVideo
    case findSpeech
    case identifyCharacters
    case evaluateAudioQuality
    case organizeResults

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .prepareVideo: "動画を準備"
        case .findSpeech: "発話を探す"
        case .identifyCharacters: "人物を確認"
        case .evaluateAudioQuality: "音声品質を確認"
        case .organizeResults: "結果を整理"
        }
    }
}

enum AnalysisProgressValue: Equatable {
    case count(completed: Int, total: Int)
    case time(completedMilliseconds: Int64, totalMilliseconds: Int64)

    var displayText: String {
        switch self {
        case .count(let completed, let total):
            "\(completed) / \(total)"
        case .time(let completedMilliseconds, let totalMilliseconds):
            "\(Self.format(milliseconds: completedMilliseconds)) / \(Self.format(milliseconds: totalMilliseconds))"
        }
    }

    private static func format(milliseconds: Int64) -> String {
        let seconds = max(0, milliseconds) / 1_000
        return "\(seconds / 60)分\(seconds % 60)秒"
    }
}

struct AnalysisProgress: Equatable {
    let step: AnalysisStep
    let value: AnalysisProgressValue
}

enum AnalysisState: Equatable {
    case running(progress: AnalysisProgress)
    case stopRequested
    case stopped(resumeProgress: AnalysisProgress?)

    static let initial = AnalysisState.running(progress: AnalysisProgress(
        step: .identifyCharacters,
        value: .count(completed: 42, total: 128)
    ))
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var route: AppRoute = .home
    @Published private(set) var homeState: HomeState
    @Published private(set) var draftCharacterIDs: Set<UUID>?
    @Published private(set) var analysisState: AnalysisState
    private let preflightService: any PreflightServicing
    private var preflightTask: Task<Void, Never>?
    private var currentPreflightRequestID: UUID?

    init(
        homeState: HomeState = .initial,
        analysisState: AnalysisState = .initial,
        preflightService: any PreflightServicing = PreflightService()
    ) {
        self.homeState = homeState
        self.analysisState = analysisState
        self.preflightService = preflightService
    }

    func selectVideo(_ url: URL) {
        preflightTask?.cancel()
        let requestID = UUID()
        currentPreflightRequestID = requestID
        homeState.video = .checking
        preflightTask = Task { [weak self, preflightService] in
            let outcome = await preflightService.run(sourceURL: url, requestID: requestID)
            guard !Task.isCancelled else { return }
            self?.apply(outcome, requestID: requestID)
        }
    }

    func videoSelectionFailed() {
        preflightTask?.cancel()
        currentPreflightRequestID = nil
        homeState.video = .failed(message: PreflightErrorCode.internalError.userMessage)
    }

    @discardableResult
    func beginCharacterSelection() -> Bool {
        guard route == .home, !homeState.registeredCharacters.isEmpty else { return false }
        let availableIDs = Set(homeState.registeredCharacters.map(\.id))
        draftCharacterIDs = homeState.selectedCharacterIDs.intersection(availableIDs)
        return true
    }

    func toggleDraftCharacter(_ id: UUID) {
        guard var draftCharacterIDs,
              homeState.registeredCharacters.contains(where: { $0.id == id }) else { return }
        if draftCharacterIDs.contains(id) {
            draftCharacterIDs.remove(id)
        } else {
            draftCharacterIDs.insert(id)
        }
        self.draftCharacterIDs = draftCharacterIDs
    }

    func confirmCharacterSelection() {
        guard let draftCharacterIDs else { return }
        let availableIDs = Set(homeState.registeredCharacters.map(\.id))
        homeState.selectedCharacterIDs = draftCharacterIDs.intersection(availableIDs)
        self.draftCharacterIDs = nil
    }

    func cancelCharacterSelection() {
        draftCharacterIDs = nil
    }

    func updateAnalysisProgress(_ progress: AnalysisProgress) {
        guard route == .analysis, case .running = analysisState else { return }
        analysisState = .running(progress: progress)
    }

    @discardableResult
    func requestAnalysisStop() -> Bool {
        guard route == .analysis, case .running = analysisState else { return false }
        analysisState = .stopRequested
        return true
    }

    @discardableResult
    func confirmAnalysisStopped(resumeProgress: AnalysisProgress?) -> Bool {
        guard route == .analysis, case .stopRequested = analysisState else { return false }
        analysisState = .stopped(resumeProgress: resumeProgress)
        return true
    }

    @discardableResult
    func resumeAnalysis() -> Bool {
        guard route == .analysis,
              case .stopped(let resumeProgress) = analysisState,
              let resumeProgress else { return false }
        analysisState = .running(progress: resumeProgress)
        return true
    }

    private func apply(_ outcome: PreflightOutcome, requestID: UUID) {
        guard currentPreflightRequestID == requestID else { return }
        switch outcome {
        case .success(let result):
            homeState.video = .ready(
                fileName: result.fileName,
                duration: Self.formatDuration(milliseconds: result.durationMilliseconds)
            )
        case .failure(let code):
            homeState.video = .failed(message: code.userMessage)
        }
    }

    private static func formatDuration(milliseconds: Int64) -> String {
        let totalSeconds = milliseconds / 1_000
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 { return "\(hours)時間\(minutes)分\(seconds)秒" }
        if minutes > 0 { return "\(minutes)分\(seconds)秒" }
        return "\(seconds)秒"
    }

    @discardableResult
    func navigateToAnalysis() -> Bool {
        guard homeState.canStartAnalysis else {
            return false
        }
        return transition(from: .home, to: .analysis)
    }

    @discardableResult
    func navigateToResults() -> Bool {
        transition(from: .analysis, to: .results)
    }

    @discardableResult
    func navigateToCharacters() -> Bool {
        transition(from: .home, to: .characters)
    }

    @discardableResult
    func returnHome() -> Bool {
        guard route != .home else {
            return false
        }
        route = .home
        return true
    }

    private func transition(from expectedRoute: AppRoute, to nextRoute: AppRoute) -> Bool {
        guard route == expectedRoute else {
            return false
        }
        route = nextRoute
        return true
    }
}
