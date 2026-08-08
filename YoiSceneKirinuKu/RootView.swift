import SwiftUI

struct RootView: View {
    @StateObject private var appViewModel = AppViewModel()

    var body: some View {
        switch appViewModel.route {
        case .home:
            HomeView(
                state: appViewModel.homeMockState,
                onOpenAnalysis: appViewModel.navigateToAnalysis,
                onOpenCharacters: appViewModel.navigateToCharacters
            )
        case .analysis:
            AnalysisView(
                onOpenResults: appViewModel.navigateToResults,
                onReturnHome: appViewModel.returnHome
            )
        case .results:
            ResultsView(onReturnHome: appViewModel.returnHome)
        case .characters:
            CharactersView(onReturnHome: appViewModel.returnHome)
        }
    }
}
