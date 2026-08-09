import Combine
import Foundation

enum HomeVideoState: Equatable {
    case unselected
    case checking
    case ready(fileName: String, duration: String)
    case failed(message: String)
}

enum HomeCharactersMockState: Equatable {
    case unregistered
    case unselected
    case selected(names: [String])
}

struct HomeState: Equatable {
    var video: HomeVideoState
    var characters: HomeCharactersMockState
    var isAIModelAvailable: Bool
    var isWorkspaceAvailable: Bool
    var isAnalysisSlotAvailable: Bool

    static let initial = HomeState(
        video: .unselected,
        characters: .unregistered,
        isAIModelAvailable: false,
        isWorkspaceAvailable: false,
        isAnalysisSlotAvailable: false
    )

    var canStartAnalysis: Bool {
        guard case .ready = video, case .selected(let names) = characters else {
            return false
        }

        return !names.isEmpty
            && isAIModelAvailable
            && isWorkspaceAvailable
            && isAnalysisSlotAvailable
    }
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var route: AppRoute = .home
    @Published private(set) var homeState: HomeState
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
