import SwiftUI

struct RootView: View {
    @StateObject private var appViewModel = AppViewModel(homeState: .runtimeInitial)

    var body: some View {
        content
            .task { appViewModel.reloadRegisteredCharacters() }
    }

    @ViewBuilder
    private var content: some View {
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
                managementState: appViewModel.characterManagementState,
                registration: appViewModel.newCharacterRegistration,
                sampleAddition: appViewModel.existingCharacterSampleAddition,
                onSelectManagedCharacter: appViewModel.selectManagedCharacter,
                onBeginRegistration: appViewModel.beginNewCharacterRegistration,
                onUpdateName: appViewModel.updateNewCharacterName,
                onSelectVideo: appViewModel.selectNewCharacterVideo,
                onVideoSelectionFailed: appViewModel.newCharacterVideoSelectionFailed,
                onUpdateCurrentPosition: appViewModel.updateNewCharacterCurrentPosition,
                onSetRangeStart: appViewModel.setNewCharacterRangeStart,
                onSetRangeEnd: appViewModel.setNewCharacterRangeEnd,
                onRequestRegistration: appViewModel.requestNewCharacterRegistration,
                onCancelRegistration: appViewModel.cancelNewCharacterRegistration,
                onBeginSampleAddition: appViewModel.beginExistingCharacterSampleAddition,
                onSelectSampleVideo: appViewModel.selectExistingCharacterSampleVideo,
                onSampleVideoSelectionFailed: appViewModel.existingCharacterSampleVideoSelectionFailed,
                onUpdateSampleCurrentPosition: appViewModel.updateExistingCharacterSampleCurrentPosition,
                onSetSampleRangeStart: appViewModel.setExistingCharacterSampleRangeStart,
                onSetSampleRangeEnd: appViewModel.setExistingCharacterSampleRangeEnd,
                onRequestSampleAddition: appViewModel.requestExistingCharacterSampleAddition,
                onRetrySampleAddition: appViewModel.retryExistingCharacterSampleAddition,
                onCancelSampleAddition: appViewModel.cancelExistingCharacterSampleAddition,
                onReturnHome: appViewModel.returnHome
            )
        }
    }
}
