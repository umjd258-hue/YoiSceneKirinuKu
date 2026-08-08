import Combine

enum HomeVideoMockState: Equatable {
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

struct HomeMockState: Equatable {
    var video: HomeVideoMockState
    var characters: HomeCharactersMockState
    var isAIModelAvailable: Bool
    var isWorkspaceAvailable: Bool
    var isAnalysisSlotAvailable: Bool

    static let initial = HomeMockState(
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
    let homeMockState: HomeMockState

    init(homeMockState: HomeMockState = .initial) {
        self.homeMockState = homeMockState
    }

    @discardableResult
    func navigateToAnalysis() -> Bool {
        guard homeMockState.canStartAnalysis else {
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
