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
            ResultsView(
                state: appViewModel.resultsState,
                onToggleSelection: appViewModel.toggleResultSelection,
                onFocusCandidate: appViewModel.focusResultCandidate,
                onToggleGroup: appViewModel.toggleResultGroup,
                onReturnHome: appViewModel.returnHome
            )
        case .characters:
            CharactersView(
                registeredCharacters: appViewModel.homeState.registeredCharacters,
                registration: appViewModel.newCharacterRegistration,
                onBeginRegistration: appViewModel.beginNewCharacterRegistration,
                onUpdateName: appViewModel.updateNewCharacterName,
                onSelectVideo: appViewModel.selectNewCharacterVideo,
                onVideoSelectionFailed: appViewModel.newCharacterVideoSelectionFailed,
                onUpdateCurrentPosition: appViewModel.updateNewCharacterCurrentPosition,
                onSetRangeStart: appViewModel.setNewCharacterRangeStart,
                onSetRangeEnd: appViewModel.setNewCharacterRangeEnd,
                onRequestRegistration: appViewModel.requestNewCharacterRegistration,
                onCancelRegistration: appViewModel.cancelNewCharacterRegistration,
                onReturnHome: appViewModel.returnHome
            )
        }
    }
}
