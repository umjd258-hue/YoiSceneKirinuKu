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

@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var route: AppRoute = .home
    @Published private(set) var homeState: HomeState
    @Published private(set) var draftCharacterIDs: Set<UUID>?
    private let preflightService: any PreflightServicing
    private var preflightTask: Task<Void, Never>?
    private var currentPreflightRequestID: UUID?

    init(homeState: HomeState = .initial, preflightService: any PreflightServicing = PreflightService()) {
        self.homeState = homeState
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
