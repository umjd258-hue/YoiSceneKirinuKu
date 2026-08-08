import Combine

@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var route: AppRoute = .home

    @discardableResult
    func navigateToAnalysis() -> Bool {
        transition(from: .home, to: .analysis)
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
