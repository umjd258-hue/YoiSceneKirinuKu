import SwiftUI

struct RootView: View {
    @StateObject private var appViewModel = AppViewModel()

    var body: some View {
        switch appViewModel.route {
        case .home:
            HomeView(
                state: appViewModel.homeState,
                onSelectVideo: appViewModel.selectVideo,
                onVideoSelectionFailed: appViewModel.videoSelectionFailed,
                onOpenAnalysis: appViewModel.navigateToAnalysis,
                onOpenCharacters: appViewModel.navigateToCharacters,
                draftCharacterIDs: appViewModel.draftCharacterIDs,
                onBeginCharacterSelection: appViewModel.beginCharacterSelection,
                onToggleDraftCharacter: appViewModel.toggleDraftCharacter,
                onConfirmCharacterSelection: appViewModel.confirmCharacterSelection,
                onCancelCharacterSelection: appViewModel.cancelCharacterSelection
            )
        case .analysis:
            AnalysisView(
                state: appViewModel.analysisState,
                onRequestStop: appViewModel.requestAnalysisStop,
                onResume: appViewModel.resumeAnalysis,
                onReturnHome: appViewModel.returnHome
            )
        case .results:
            ResultsView(onReturnHome: appViewModel.returnHome)
        case .characters:
            CharactersView(onReturnHome: appViewModel.returnHome)
        }
    }
}
