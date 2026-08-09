import XCTest
@testable import YoiSceneKirinuKu

@MainActor
final class AppViewModelTests: XCTestCase {
    func testRuntimeInitialStateDoesNotExposeMockCharacters() {
        let subject = AppViewModel(homeState: .runtimeInitial)

        XCTAssertEqual(subject.homeState.characters, .unregistered)
        XCTAssertTrue(subject.homeState.registeredCharacters.isEmpty)
    }

    private let conan = CharacterSummary(
        id: UUID(uuidString: "1c87d576-6f98-4e10-bf44-427cadb4e634")!,
        name: "コナン"
    )

    private let analysisReadyHome = HomeState(
        video: .ready(fileName: "episode01.mp4", duration: "24分12秒"),
        registeredCharacters: [
            CharacterSummary(id: UUID(uuidString: "1c87d576-6f98-4e10-bf44-427cadb4e634")!, name: "コナン"),
        ],
        selectedCharacterIDs: [UUID(uuidString: "1c87d576-6f98-4e10-bf44-427cadb4e634")!],
        isAIModelAvailable: true,
        isWorkspaceAvailable: true,
        isAnalysisSlotAvailable: true
    )

    func testInitialRouteIsHome() {
        let subject = AppViewModel()

        XCTAssertEqual(subject.route, .home)
    }

    func testHomeCanNavigateToAnalysis() {
        let subject = AppViewModel(homeState: analysisReadyHome)

        XCTAssertTrue(subject.navigateToAnalysis())
        XCTAssertEqual(subject.route, .analysis)
    }

    func testHomeCanNavigateToCharacters() {
        let subject = AppViewModel()

        XCTAssertTrue(subject.navigateToCharacters())
        XCTAssertEqual(subject.route, .characters)
    }

    func testAnalysisCanNavigateToResults() {
        let subject = AppViewModel(homeState: analysisReadyHome)
        XCTAssertTrue(subject.navigateToAnalysis())

        XCTAssertTrue(subject.navigateToResults())
        XCTAssertEqual(subject.route, .results)
    }

    func testEveryNonHomeRouteCanReturnHome() {
        let analysis = AppViewModel(homeState: analysisReadyHome)
        XCTAssertTrue(analysis.navigateToAnalysis())
        XCTAssertTrue(analysis.returnHome())
        XCTAssertEqual(analysis.route, .home)

        let results = AppViewModel(homeState: analysisReadyHome)
        XCTAssertTrue(results.navigateToAnalysis())
        XCTAssertTrue(results.navigateToResults())
        XCTAssertTrue(results.returnHome())
        XCTAssertEqual(results.route, .home)

        let characters = AppViewModel()
        XCTAssertTrue(characters.navigateToCharacters())
        XCTAssertTrue(characters.returnHome())
        XCTAssertEqual(characters.route, .home)
    }

    func testInvalidTransitionIsRejectedWithoutChangingRoute() {
        let subject = AppViewModel()

        XCTAssertFalse(subject.navigateToResults())
        XCTAssertEqual(subject.route, .home)

        XCTAssertTrue(subject.navigateToCharacters())
        XCTAssertFalse(subject.navigateToAnalysis())
        XCTAssertEqual(subject.route, .characters)
    }

    func testReturningHomeWhileAlreadyHomeIsRejected() {
        let subject = AppViewModel()

        XCTAssertFalse(subject.returnHome())
        XCTAssertEqual(subject.route, .home)
    }

    func testAnalysisStartRequiresEveryMockPrerequisite() {
        var states = [HomeState]()
        states.append(HomeState(
            video: .unselected,
            registeredCharacters: analysisReadyHome.registeredCharacters,
            selectedCharacterIDs: analysisReadyHome.selectedCharacterIDs,
            isAIModelAvailable: true,
            isWorkspaceAvailable: true,
            isAnalysisSlotAvailable: true
        ))
        states.append(HomeState(
            video: .checking,
            registeredCharacters: analysisReadyHome.registeredCharacters,
            selectedCharacterIDs: analysisReadyHome.selectedCharacterIDs,
            isAIModelAvailable: true,
            isWorkspaceAvailable: true,
            isAnalysisSlotAvailable: true
        ))
        states.append(HomeState(
            video: .failed(message: "音声トラックが見つかりません"),
            registeredCharacters: analysisReadyHome.registeredCharacters,
            selectedCharacterIDs: analysisReadyHome.selectedCharacterIDs,
            isAIModelAvailable: true,
            isWorkspaceAvailable: true,
            isAnalysisSlotAvailable: true
        ))
        states.append(HomeState(
            video: analysisReadyHome.video,
            registeredCharacters: [],
            selectedCharacterIDs: [],
            isAIModelAvailable: true,
            isWorkspaceAvailable: true,
            isAnalysisSlotAvailable: true
        ))
        states.append(HomeState(
            video: analysisReadyHome.video,
            registeredCharacters: [conan],
            selectedCharacterIDs: [],
            isAIModelAvailable: true,
            isWorkspaceAvailable: true,
            isAnalysisSlotAvailable: true
        ))
        states.append(HomeState(
            video: analysisReadyHome.video,
            registeredCharacters: [conan],
            selectedCharacterIDs: [UUID(uuidString: "91ed48b1-fd8a-48d4-aaf3-b7db396971fa")!],
            isAIModelAvailable: true,
            isWorkspaceAvailable: true,
            isAnalysisSlotAvailable: true
        ))
        states.append(HomeState(
            video: analysisReadyHome.video,
            registeredCharacters: analysisReadyHome.registeredCharacters,
            selectedCharacterIDs: analysisReadyHome.selectedCharacterIDs,
            isAIModelAvailable: false,
            isWorkspaceAvailable: true,
            isAnalysisSlotAvailable: true
        ))
        states.append(HomeState(
            video: analysisReadyHome.video,
            registeredCharacters: analysisReadyHome.registeredCharacters,
            selectedCharacterIDs: analysisReadyHome.selectedCharacterIDs,
            isAIModelAvailable: true,
            isWorkspaceAvailable: false,
            isAnalysisSlotAvailable: true
        ))
        states.append(HomeState(
            video: analysisReadyHome.video,
            registeredCharacters: analysisReadyHome.registeredCharacters,
            selectedCharacterIDs: analysisReadyHome.selectedCharacterIDs,
            isAIModelAvailable: true,
            isWorkspaceAvailable: true,
            isAnalysisSlotAvailable: false
        ))

        for state in states {
            XCTAssertFalse(state.canStartAnalysis)
            let subject = AppViewModel(homeState: state)
            XCTAssertFalse(subject.navigateToAnalysis())
            XCTAssertEqual(subject.route, .home)
        }
    }

    func testAnalysisStartIsEnabledWhenEveryMockPrerequisiteIsReady() {
        XCTAssertTrue(analysisReadyHome.canStartAnalysis)
    }

    func testCharacterSelectionIsAppliedOnlyWhenConfirmed() {
        let ran = CharacterSummary(
            id: UUID(uuidString: "ceae23e4-f6fb-4aa8-860a-2c4a22fe1d07")!,
            name: "蘭"
        )
        var state = analysisReadyHome
        state.registeredCharacters = [conan, ran]
        let subject = AppViewModel(homeState: state)

        XCTAssertTrue(subject.beginCharacterSelection())
        subject.toggleDraftCharacter(conan.id)
        subject.toggleDraftCharacter(ran.id)
        XCTAssertEqual(subject.homeState.selectedCharacterIDs, [conan.id])

        subject.confirmCharacterSelection()

        XCTAssertEqual(subject.homeState.selectedCharacterIDs, [ran.id])
        XCTAssertEqual(subject.homeState.characters, .selected(characters: [ran]))
        XCTAssertNil(subject.draftCharacterIDs)
    }

    func testCancellingCharacterSelectionPreservesConfirmedSelection() {
        let subject = AppViewModel(homeState: analysisReadyHome)

        XCTAssertTrue(subject.beginCharacterSelection())
        subject.toggleDraftCharacter(conan.id)
        subject.cancelCharacterSelection()

        XCTAssertEqual(subject.homeState.selectedCharacterIDs, [conan.id])
        XCTAssertNil(subject.draftCharacterIDs)
    }

    func testCharacterSelectionSupportsZeroOneAndMultipleCharacters() {
        let ran = CharacterSummary(
            id: UUID(uuidString: "ceae23e4-f6fb-4aa8-860a-2c4a22fe1d07")!,
            name: "蘭"
        )
        var state = analysisReadyHome
        state.registeredCharacters = [conan, ran]
        state.selectedCharacterIDs = []
        let subject = AppViewModel(homeState: state)

        XCTAssertEqual(subject.homeState.characters, .unselected)
        XCTAssertTrue(subject.beginCharacterSelection())
        subject.toggleDraftCharacter(conan.id)
        subject.confirmCharacterSelection()
        XCTAssertEqual(subject.homeState.characters, .selected(characters: [conan]))

        XCTAssertTrue(subject.beginCharacterSelection())
        subject.toggleDraftCharacter(ran.id)
        subject.confirmCharacterSelection()
        XCTAssertEqual(subject.homeState.characters, .selected(characters: [conan, ran]))
    }

    func testUnknownCharacterIDCannotRemainSelected() {
        let unknownID = UUID(uuidString: "91ed48b1-fd8a-48d4-aaf3-b7db396971fa")!
        var state = analysisReadyHome
        state.selectedCharacterIDs.insert(unknownID)
        let subject = AppViewModel(homeState: state)

        XCTAssertTrue(subject.beginCharacterSelection())
        XCTAssertEqual(subject.draftCharacterIDs, [conan.id])
        subject.toggleDraftCharacter(unknownID)
        subject.confirmCharacterSelection()

        XCTAssertEqual(subject.homeState.selectedCharacterIDs, [conan.id])
    }

    func testCharacterSelectionCannotBeginWithoutRegisteredCharacters() {
        var state = analysisReadyHome
        state.registeredCharacters = []
        state.selectedCharacterIDs = []
        let subject = AppViewModel(homeState: state)

        XCTAssertFalse(subject.beginCharacterSelection())
        XCTAssertNil(subject.draftCharacterIDs)
        XCTAssertEqual(subject.homeState.characters, .unregistered)
    }

    func testAnalysisProgressSupportsEveryFixedStep() {
        let subject = AppViewModel(homeState: analysisReadyHome)
        XCTAssertTrue(subject.navigateToAnalysis())

        for (index, step) in AnalysisStep.allCases.enumerated() {
            let progress = AnalysisProgress(
                step: step,
                value: .count(completed: index + 1, total: AnalysisStep.allCases.count)
            )
            subject.updateAnalysisProgress(progress)
            XCTAssertEqual(subject.analysisState, .running(progress: progress))
        }
    }

    func testAnalysisProgressFormatsCountAndTimeWithoutPercentage() {
        XCTAssertEqual(AnalysisProgressValue.count(completed: 42, total: 128).displayText, "42 / 128")
        XCTAssertEqual(
            AnalysisProgressValue.time(completedMilliseconds: 751_000, totalMilliseconds: 1_452_000).displayText,
            "12分31秒 / 24分12秒"
        )
    }

    func testStopRequestAndCompletionAreSeparateExclusiveStates() {
        let resumeProgress = AnalysisProgress(
            step: .findSpeech,
            value: .time(completedMilliseconds: 30_000, totalMilliseconds: 120_000)
        )
        let subject = AppViewModel(homeState: analysisReadyHome)
        XCTAssertTrue(subject.navigateToAnalysis())

        XCTAssertTrue(subject.requestAnalysisStop())
        XCTAssertEqual(subject.analysisState, .stopRequested)
        XCTAssertFalse(subject.requestAnalysisStop())

        XCTAssertTrue(subject.confirmAnalysisStopped(resumeProgress: resumeProgress))
        XCTAssertEqual(subject.analysisState, .stopped(resumeProgress: resumeProgress))
        XCTAssertFalse(subject.confirmAnalysisStopped(resumeProgress: resumeProgress))
    }

    func testProgressIsIgnoredAfterStopRequest() {
        let subject = AppViewModel(homeState: analysisReadyHome)
        XCTAssertTrue(subject.navigateToAnalysis())
        XCTAssertTrue(subject.requestAnalysisStop())

        subject.updateAnalysisProgress(AnalysisProgress(
            step: .organizeResults,
            value: .count(completed: 128, total: 128)
        ))

        XCTAssertEqual(subject.analysisState, .stopRequested)
    }

    func testResumeRequiresVerifiedMockProgress() {
        let resumableProgress = AnalysisProgress(
            step: .findSpeech,
            value: .count(completed: 20, total: 100)
        )
        let resumable = AppViewModel(homeState: analysisReadyHome)
        XCTAssertTrue(resumable.navigateToAnalysis())
        XCTAssertTrue(resumable.requestAnalysisStop())
        XCTAssertTrue(resumable.confirmAnalysisStopped(resumeProgress: resumableProgress))
        XCTAssertTrue(resumable.resumeAnalysis())
        XCTAssertEqual(resumable.analysisState, .running(progress: resumableProgress))

        let notResumable = AppViewModel(homeState: analysisReadyHome)
        XCTAssertTrue(notResumable.navigateToAnalysis())
        XCTAssertTrue(notResumable.requestAnalysisStop())
        XCTAssertTrue(notResumable.confirmAnalysisStopped(resumeProgress: nil))
        XCTAssertFalse(notResumable.resumeAnalysis())
        XCTAssertEqual(notResumable.analysisState, .stopped(resumeProgress: nil))
    }

    func testStopCannotBeRequestedOutsideAnalysis() {
        let subject = AppViewModel(homeState: analysisReadyHome)

        XCTAssertFalse(subject.requestAnalysisStop())
        XCTAssertEqual(subject.analysisState, .initial)
    }

    func testResultsGroupsAreTimeOrderedAndUnknownStartsCollapsed() {
        let state = ResultsState.initial

        for group in state.groups {
            XCTAssertEqual(group.candidates.map(\.startMilliseconds), group.candidates.map(\.startMilliseconds).sorted())
        }
        XCTAssertFalse(state.expandedGroupIDs.contains(.unknown))
        XCTAssertTrue(state.groups.contains(where: { $0.id == .unknown }))
    }

    func testResultsInitialSelectionUsesQualityAndUnknownRulesSeparately() throws {
        let state = ResultsState.initial
        let candidates = state.groups.flatMap(\.candidates)
        let knownExcellentOrGood = candidates.filter {
            $0.characterMatch != .unknown && $0.quality.isInitiallySelected
        }
        let unknownExcellent = try XCTUnwrap(candidates.first {
            $0.characterMatch == .unknown && $0.quality == .excellent
        })
        let knownReview = try XCTUnwrap(candidates.first {
            $0.characterMatch != .unknown && $0.quality == .needsReview
        })

        XCTAssertEqual(state.selectedCandidateIDs, Set(knownExcellentOrGood.map(\.id)))
        XCTAssertFalse(state.selectedCandidateIDs.contains(unknownExcellent.id))
        XCTAssertFalse(state.selectedCandidateIDs.contains(knownReview.id))
        XCTAssertEqual(unknownExcellent.quality, .excellent)
        XCTAssertEqual(unknownExcellent.characterMatch, .unknown)
    }

    func testResultSelectionCountChangesOnlyForExistingCandidates() throws {
        let subject = AppViewModel()
        let candidate = try XCTUnwrap(subject.resultsState.groups.flatMap(\.candidates).first)
        let initialCount = subject.resultsState.selectedCount

        subject.toggleResultSelection(candidate.id)
        XCTAssertEqual(subject.resultsState.selectedCount, initialCount - 1)

        subject.toggleResultSelection(candidate.id)
        XCTAssertEqual(subject.resultsState.selectedCount, initialCount)

        subject.toggleResultSelection(UUID())
        XCTAssertEqual(subject.resultsState.selectedCount, initialCount)
    }

    func testResultFocusAndGroupExpansionRejectUnknownIDs() throws {
        let subject = AppViewModel()
        let unknownGroup = try XCTUnwrap(subject.resultsState.groups.first(where: { $0.id == .unknown }))
        let candidate = try XCTUnwrap(unknownGroup.candidates.first)

        subject.toggleResultGroup(.unknown)
        XCTAssertTrue(subject.resultsState.expandedGroupIDs.contains(.unknown))
        subject.focusResultCandidate(candidate.id)
        XCTAssertEqual(subject.resultsState.focusedCandidateID, candidate.id)
        XCTAssertEqual(subject.resultsState.focusedGroupTitle, "人物不明")

        let missingID = UUID()
        subject.focusResultCandidate(missingID)
        subject.toggleResultGroup(.character(missingID))
        XCTAssertEqual(subject.resultsState.focusedCandidateID, candidate.id)
        XCTAssertFalse(subject.resultsState.expandedGroupIDs.contains(.character(missingID)))
    }

    func testEmptyResultsAreNormalAndHaveNoSelection() {
        let state = ResultsState.empty

        XCTAssertEqual(state.candidateCount, 0)
        XCTAssertEqual(state.selectedCount, 0)
        XCTAssertNil(state.focusedCandidate)
        XCTAssertNil(state.focusedGroupTitle)
    }

    func testResultUIModelContainsLabelsInsteadOfRawAIScores() {
        let candidateMirrorLabels = Set(Mirror(reflecting: ResultCandidate(
            id: UUID(),
            startMilliseconds: 0,
            durationMilliseconds: 1_000,
            quality: .good,
            characterMatch: .medium,
            qualityReason: nil
        )).children.compactMap(\.label))

        XCTAssertEqual(candidateMirrorLabels, [
            "id",
            "startMilliseconds",
            "durationMilliseconds",
            "quality",
            "characterMatch",
            "qualityReason",
        ])
        XCTAssertFalse(candidateMirrorLabels.contains(where: { $0.lowercased().contains("score") }))
        XCTAssertFalse(candidateMirrorLabels.contains(where: { $0.lowercased().contains("probability") }))
    }

    func testNewCharacterRegistrationCanBeginOnlyFromCharacters() {
        let subject = AppViewModel()

        XCTAssertFalse(subject.beginNewCharacterRegistration())
        XCTAssertTrue(subject.navigateToCharacters())
        XCTAssertTrue(subject.beginNewCharacterRegistration())
        XCTAssertTrue(subject.newCharacterRegistration.isPresented)
        XCTAssertFalse(subject.beginNewCharacterRegistration())
    }

    func testNewCharacterRegistrationRequiresNameVideoAndValidRange() {
        let subject = AppViewModel()
        XCTAssertTrue(subject.navigateToCharacters())
        XCTAssertTrue(subject.beginNewCharacterRegistration())

        subject.updateNewCharacterName("コナン")
        subject.selectNewCharacterVideo(
            URL(fileURLWithPath: "/tmp/episode01.mp4"),
            durationMilliseconds: 20_000
        )
        XCTAssertFalse(subject.newCharacterRegistration.canRequestRegistration)

        subject.updateNewCharacterCurrentPosition(10_000)
        subject.setNewCharacterRangeStart()
        subject.updateNewCharacterCurrentPosition(5_000)
        subject.setNewCharacterRangeEnd()
        XCTAssertFalse(subject.newCharacterRegistration.hasValidRange)
        XCTAssertFalse(subject.requestNewCharacterRegistration())

        subject.updateNewCharacterCurrentPosition(15_000)
        subject.setNewCharacterRangeEnd()
        XCTAssertTrue(subject.newCharacterRegistration.hasValidRange)
        XCTAssertTrue(subject.newCharacterRegistration.canRequestRegistration)
    }

    func testRegistrationRequestAddsCharacterOnlyAfterFormalReload() async {
        let characterID = UUID(uuidString: "f66e4bc4-2cff-402e-a8fb-735c5c5f702a")!
        let sampleID = UUID(uuidString: "64af25dd-177f-4d90-a5fc-1a17e538c4d7")!
        let registered = RegisteredCharacter(
            characterID: characterID,
            displayName: "新規人物",
            samples: [RegisteredAudioSampleSummary(id: sampleID, sourceFileName: "source.wav", durationMilliseconds: 7_000)]
        )
        let service = ImmediateCharacterRegistrationService(
            registration: .success(registered),
            load: .success([registered])
        )
        let subject = AppViewModel(characterRegistrationService: service)
        let initialCharacters = subject.homeState.registeredCharacters
        XCTAssertTrue(subject.navigateToCharacters())
        XCTAssertTrue(subject.beginNewCharacterRegistration())
        subject.updateNewCharacterName("新規人物")
        subject.selectNewCharacterVideo(
            URL(fileURLWithPath: "/tmp/registration.mp4"),
            durationMilliseconds: 30_000
        )
        subject.updateNewCharacterCurrentPosition(2_000)
        subject.setNewCharacterRangeStart()
        subject.updateNewCharacterCurrentPosition(9_000)
        subject.setNewCharacterRangeEnd()

        XCTAssertTrue(subject.requestNewCharacterRegistration())
        XCTAssertEqual(subject.newCharacterRegistration.phase, .registrationRequested)
        XCTAssertEqual(subject.homeState.registeredCharacters, initialCharacters)
        await subject.waitForCharacterRegistrationForTesting()

        XCTAssertEqual(subject.newCharacterRegistration.phase, .registered)
        XCTAssertEqual(subject.homeState.registeredCharacters, [CharacterSummary(id: characterID, name: "新規人物")])
        XCTAssertEqual(subject.characterManagementState.samples(for: characterID), registered.samples)
    }

    func testRegistrationFailureDoesNotAddCharacter() async {
        let subject = AppViewModel(characterRegistrationService: ImmediateCharacterRegistrationService(
            registration: .failure(.audioTooQuiet),
            load: .success([])
        ))
        let initialCharacters = subject.homeState.registeredCharacters
        XCTAssertTrue(subject.navigateToCharacters())
        XCTAssertTrue(subject.beginNewCharacterRegistration())
        subject.updateNewCharacterName("新規人物")
        subject.selectNewCharacterVideo(URL(fileURLWithPath: "/tmp/registration.mp4"), durationMilliseconds: 30_000)
        subject.updateNewCharacterCurrentPosition(2_000)
        subject.setNewCharacterRangeStart()
        subject.updateNewCharacterCurrentPosition(9_000)
        subject.setNewCharacterRangeEnd()

        XCTAssertTrue(subject.requestNewCharacterRegistration())
        await subject.waitForCharacterRegistrationForTesting()

        XCTAssertEqual(subject.newCharacterRegistration.phase, .failed(message: CharacterRegistrationErrorCode.audioTooQuiet.userMessage))
        XCTAssertEqual(subject.homeState.registeredCharacters, initialCharacters)
    }

    func testRegistrationRangeUsesGateLimits() {
        let subject = AppViewModel()
        XCTAssertTrue(subject.navigateToCharacters())
        XCTAssertTrue(subject.beginNewCharacterRegistration())
        subject.updateNewCharacterName("新規人物")
        subject.selectNewCharacterVideo(URL(fileURLWithPath: "/tmp/registration.mp4"), durationMilliseconds: 60_000)

        subject.updateNewCharacterCurrentPosition(1_000)
        subject.setNewCharacterRangeStart()
        subject.updateNewCharacterCurrentPosition(3_999)
        subject.setNewCharacterRangeEnd()
        XCTAssertFalse(subject.newCharacterRegistration.hasValidRange)

        subject.updateNewCharacterCurrentPosition(4_000)
        subject.setNewCharacterRangeEnd()
        XCTAssertTrue(subject.newCharacterRegistration.hasValidRange)

        subject.updateNewCharacterCurrentPosition(31_001)
        subject.setNewCharacterRangeEnd()
        XCTAssertFalse(subject.newCharacterRegistration.hasValidRange)
    }

    func testReloadUsesOnlyValidatedServiceResults() async {
        let characterID = UUID(uuidString: "f66e4bc4-2cff-402e-a8fb-735c5c5f702a")!
        let registered = RegisteredCharacter(
            characterID: characterID,
            displayName: "正式人物",
            samples: [RegisteredAudioSampleSummary(
                id: UUID(uuidString: "64af25dd-177f-4d90-a5fc-1a17e538c4d7")!,
                sourceFileName: "source.wav",
                durationMilliseconds: 5_000
            )]
        )
        let subject = AppViewModel(characterRegistrationService: ImmediateCharacterRegistrationService(
            registration: .failure(.invalidRequest),
            load: .success([registered])
        ))

        subject.reloadRegisteredCharacters()
        await subject.waitForCharacterReloadForTesting()

        XCTAssertEqual(subject.homeState.registeredCharacters, [CharacterSummary(id: characterID, name: "正式人物")])
        XCTAssertEqual(subject.characterManagementState.selectedCharacterID, characterID)
    }

    func testCancellingNewCharacterRegistrationDiscardsDraft() {
        let subject = AppViewModel()
        XCTAssertTrue(subject.navigateToCharacters())
        XCTAssertTrue(subject.beginNewCharacterRegistration())
        subject.updateNewCharacterName("一時入力")
        subject.selectNewCharacterVideo(
            URL(fileURLWithPath: "/tmp/registration.mp4"),
            durationMilliseconds: 30_000
        )

        subject.cancelNewCharacterRegistration()

        XCTAssertEqual(subject.newCharacterRegistration, NewCharacterRegistrationState())
        XCTAssertEqual(subject.route, .characters)
    }

    func testRegistrationPositionAndInvalidVideoAreSafelyBounded() {
        let subject = AppViewModel()
        XCTAssertTrue(subject.navigateToCharacters())
        XCTAssertTrue(subject.beginNewCharacterRegistration())

        subject.selectNewCharacterVideo(
            URL(fileURLWithPath: "/tmp/registration.mp4"),
            durationMilliseconds: 10_000
        )
        subject.updateNewCharacterCurrentPosition(-1_000)
        XCTAssertEqual(subject.newCharacterRegistration.currentPositionMilliseconds, 0)
        subject.updateNewCharacterCurrentPosition(50_000)
        XCTAssertEqual(subject.newCharacterRegistration.currentPositionMilliseconds, 10_000)

        subject.selectNewCharacterVideo(
            URL(fileURLWithPath: "/tmp/broken.mp4"),
            durationMilliseconds: 0
        )
        XCTAssertNil(subject.newCharacterRegistration.videoURL)
        XCTAssertFalse(subject.newCharacterRegistration.canRequestRegistration)
        XCTAssertNotNil(subject.newCharacterRegistration.videoErrorMessage)
    }

    func testExistingSampleAdditionTargetsExplicitlySelectedCharacter() throws {
        let subject = AppViewModel()
        XCTAssertTrue(subject.navigateToCharacters())
        let ran = try XCTUnwrap(subject.homeState.registeredCharacters.first(where: { $0.name == "蘭" }))

        subject.selectManagedCharacter(ran.id)
        XCTAssertEqual(subject.characterManagementState.selectedCharacterID, ran.id)
        XCTAssertTrue(subject.beginExistingCharacterSampleAddition())
        XCTAssertEqual(subject.existingCharacterSampleAddition.targetCharacterID, ran.id)
        XCTAssertEqual(subject.existingCharacterSampleAddition.targetCharacterName, "蘭")

        let conan = try XCTUnwrap(subject.homeState.registeredCharacters.first(where: { $0.name == "コナン" }))
        subject.selectManagedCharacter(conan.id)
        XCTAssertEqual(subject.characterManagementState.selectedCharacterID, ran.id)
        XCTAssertEqual(subject.existingCharacterSampleAddition.targetCharacterID, ran.id)
    }

    func testExistingSampleAdditionRequiresVideoAndValidRange() {
        let subject = AppViewModel()
        XCTAssertTrue(subject.navigateToCharacters())
        XCTAssertTrue(subject.beginExistingCharacterSampleAddition())
        XCTAssertFalse(subject.requestExistingCharacterSampleAddition())

        subject.selectExistingCharacterSampleVideo(
            URL(fileURLWithPath: "/tmp/addition.mp4"),
            durationMilliseconds: 20_000
        )
        subject.updateExistingCharacterSampleCurrentPosition(12_000)
        subject.setExistingCharacterSampleRangeStart()
        subject.updateExistingCharacterSampleCurrentPosition(4_000)
        subject.setExistingCharacterSampleRangeEnd()
        XCTAssertFalse(subject.existingCharacterSampleAddition.canRequestAddition)

        subject.updateExistingCharacterSampleCurrentPosition(18_000)
        subject.setExistingCharacterSampleRangeEnd()
        XCTAssertTrue(subject.existingCharacterSampleAddition.canRequestAddition)
        XCTAssertTrue(subject.requestExistingCharacterSampleAddition())
        XCTAssertEqual(subject.existingCharacterSampleAddition.phase, .additionRequested)
    }

    func testExistingSampleSuccessAndFailureDoNotChangeExistingData() throws {
        let successSubject = AppViewModel()
        XCTAssertTrue(successSubject.navigateToCharacters())
        let targetID = try XCTUnwrap(successSubject.characterManagementState.selectedCharacterID)
        let originalCharacters = successSubject.homeState.registeredCharacters
        let originalSamples = successSubject.characterManagementState.samples(for: targetID)
        prepareValidExistingSampleAddition(successSubject)
        XCTAssertTrue(successSubject.requestExistingCharacterSampleAddition())
        XCTAssertTrue(successSubject.confirmExistingCharacterSampleAdditionSucceeded())
        XCTAssertEqual(successSubject.existingCharacterSampleAddition.phase, .succeeded)
        XCTAssertEqual(successSubject.homeState.registeredCharacters, originalCharacters)
        XCTAssertEqual(successSubject.characterManagementState.samples(for: targetID), originalSamples)

        let failureSubject = AppViewModel()
        XCTAssertTrue(failureSubject.navigateToCharacters())
        let failureTargetID = try XCTUnwrap(failureSubject.characterManagementState.selectedCharacterID)
        let failureCharacters = failureSubject.homeState.registeredCharacters
        let failureSamples = failureSubject.characterManagementState.samples(for: failureTargetID)
        prepareValidExistingSampleAddition(failureSubject)
        XCTAssertTrue(failureSubject.requestExistingCharacterSampleAddition())
        failureSubject.confirmExistingCharacterSampleAdditionFailed(message: "Mock failure")
        XCTAssertEqual(failureSubject.existingCharacterSampleAddition.phase, .failed(message: "Mock failure"))
        XCTAssertEqual(failureSubject.homeState.registeredCharacters, failureCharacters)
        XCTAssertEqual(failureSubject.characterManagementState.samples(for: failureTargetID), failureSamples)
    }

    func testExistingSampleFailureCanRetryAndCancelWithoutChangingTargetData() throws {
        let subject = AppViewModel()
        XCTAssertTrue(subject.navigateToCharacters())
        let targetID = try XCTUnwrap(subject.characterManagementState.selectedCharacterID)
        let originalSamples = subject.characterManagementState.samples(for: targetID)
        prepareValidExistingSampleAddition(subject)
        XCTAssertTrue(subject.requestExistingCharacterSampleAddition())
        subject.confirmExistingCharacterSampleAdditionFailed(message: "再試行できます。")

        XCTAssertTrue(subject.retryExistingCharacterSampleAddition())
        XCTAssertEqual(subject.existingCharacterSampleAddition.phase, .editing)
        XCTAssertEqual(subject.existingCharacterSampleAddition.targetCharacterID, targetID)
        XCTAssertTrue(subject.existingCharacterSampleAddition.canRequestAddition)

        subject.cancelExistingCharacterSampleAddition()
        XCTAssertEqual(subject.existingCharacterSampleAddition, ExistingCharacterSampleAdditionState())
        XCTAssertEqual(subject.characterManagementState.samples(for: targetID), originalSamples)
    }

    private func prepareValidExistingSampleAddition(_ subject: AppViewModel) {
        XCTAssertTrue(subject.beginExistingCharacterSampleAddition())
        subject.selectExistingCharacterSampleVideo(
            URL(fileURLWithPath: "/tmp/addition.mp4"),
            durationMilliseconds: 20_000
        )
        subject.updateExistingCharacterSampleCurrentPosition(2_000)
        subject.setExistingCharacterSampleRangeStart()
        subject.updateExistingCharacterSampleCurrentPosition(9_000)
        subject.setExistingCharacterSampleRangeEnd()
    }

    func testSuccessfulPreflightUpdatesOnlyVideoState() async {
        let result = PreflightResult(
            fileName: "episode01.mp4",
            durationMilliseconds: 1_452_001,
            containerFormat: "mov,mp4,m4a,3gp,3g2,mj2",
            videoStreamCount: 1,
            audioStreamCount: 1
        )
        let subject = AppViewModel(preflightService: ImmediatePreflightService(outcome: .success(result)))

        subject.selectVideo(URL(fileURLWithPath: "/tmp/episode01.mp4"))
        await Task.yield()

        XCTAssertEqual(subject.homeState.video, .ready(fileName: "episode01.mp4", duration: "24分12秒"))
        XCTAssertEqual(subject.homeState.characters, .unselected)
    }

    func testPreflightFailureUsesStableUserMessage() async {
        let subject = AppViewModel(preflightService: ImmediatePreflightService(outcome: .failure(.audioStreamMissing)))

        subject.selectVideo(URL(fileURLWithPath: "/tmp/no-audio.mp4"))
        await Task.yield()

        XCTAssertEqual(subject.homeState.video, .failed(message: "音声トラックが見つかりません"))
        XCTAssertFalse(subject.homeState.canStartAnalysis)
    }

    func testOlderPreflightResultDoesNotReplaceNewSelection() async {
        let service = ControlledPreflightService()
        let subject = AppViewModel(preflightService: service)
        subject.selectVideo(URL(fileURLWithPath: "/tmp/old.mp4"))
        await Task.yield()
        subject.selectVideo(URL(fileURLWithPath: "/tmp/new.mp4"))
        await Task.yield()

        await service.resume(fileName: "old.mp4", with: .success(PreflightResult(
            fileName: "old.mp4",
            durationMilliseconds: 1_000,
            containerFormat: "mp4",
            videoStreamCount: 1,
            audioStreamCount: 1
        )))
        await Task.yield()

        XCTAssertEqual(subject.homeState.video, .checking)

        await service.resume(fileName: "new.mp4", with: .success(PreflightResult(
            fileName: "new.mp4",
            durationMilliseconds: 2_000,
            containerFormat: "mp4",
            videoStreamCount: 1,
            audioStreamCount: 1
        )))
        await Task.yield()

        XCTAssertEqual(subject.homeState.video, .ready(fileName: "new.mp4", duration: "2秒"))
    }

    func testProtocolParserAcceptsCompleteSuccessfulContract() throws {
        let requestID = UUID()
        let lines = [
            event(type: "progress", requestID: requestID, sequence: 1, payload: ["stage": "preflight", "status": "running"]),
            event(type: "finished", requestID: requestID, sequence: 2, payload: [
                "outcome": "succeeded",
                "result": [
                    "file_name": "sample.mp4",
                    "duration_ms": 1_001,
                    "container_format": "mp4",
                    "video_stream_count": 1,
                    "audio_stream_count": 1,
                ],
            ]),
        ]
        let stdout = try lines.map {
            try JSONSerialization.data(withJSONObject: $0)
        }.reduce(into: Data()) {
            $0.append($1)
            $0.append(0x0A)
        }

        XCTAssertEqual(
            PreflightProtocolParser.parse(stdout: stdout, requestID: requestID, terminationStatus: 0, terminationReason: .exit),
            .success(PreflightResult(
                fileName: "sample.mp4",
                durationMilliseconds: 1_001,
                containerFormat: "mp4",
                videoStreamCount: 1,
                audioStreamCount: 1
            ))
        )
    }

    func testProtocolParserRejectsMalformedUnknownAndAbnormalExit() throws {
        let requestID = UUID()
        XCTAssertEqual(
            PreflightProtocolParser.parse(stdout: Data("not-json\n".utf8), requestID: requestID, terminationStatus: 0, terminationReason: .exit),
            .failure(.protocolError)
        )

        let unknown = try JSONSerialization.data(withJSONObject: event(
            type: "unknown",
            requestID: requestID,
            sequence: 1,
            payload: [:]
        )) + Data([0x0A])
        XCTAssertEqual(
            PreflightProtocolParser.parse(stdout: unknown, requestID: requestID, terminationStatus: 0, terminationReason: .exit),
            .failure(.protocolError)
        )

        XCTAssertEqual(
            PreflightProtocolParser.parse(stdout: Data(), requestID: requestID, terminationStatus: 1, terminationReason: .exit),
            .failure(.protocolError)
        )
    }

    func testProtocolParserMapsUnknownErrorCodeToInternalError() throws {
        let requestID = UUID()
        let events = [
            event(type: "error", requestID: requestID, sequence: 1, payload: ["code": "future_error"]),
            event(type: "finished", requestID: requestID, sequence: 2, payload: ["outcome": "failed", "code": "future_error"]),
        ]
        let stdout = try events.map {
            try JSONSerialization.data(withJSONObject: $0)
        }.reduce(into: Data()) {
            $0.append($1)
            $0.append(0x0A)
        }

        XCTAssertEqual(
            PreflightProtocolParser.parse(stdout: stdout, requestID: requestID, terminationStatus: 0, terminationReason: .exit),
            .failure(.internalError)
        )
    }

    func testProtocolParserRejectsNonIntegerDuration() throws {
        let requestID = UUID()
        let finished = event(type: "finished", requestID: requestID, sequence: 1, payload: [
            "outcome": "succeeded",
            "result": [
                "file_name": "sample.mp4",
                "duration_ms": 1.5,
                "container_format": "mp4",
                "video_stream_count": 1,
                "audio_stream_count": 1,
            ],
        ])
        let stdout = try JSONSerialization.data(withJSONObject: finished) + Data([0x0A])

        XCTAssertEqual(
            PreflightProtocolParser.parse(stdout: stdout, requestID: requestID, terminationStatus: 0, terminationReason: .exit),
            .failure(.protocolError)
        )
    }

    func testProtocolParserRejectsBooleanDuration() throws {
        let requestID = UUID()
        let finished = event(type: "finished", requestID: requestID, sequence: 1, payload: [
            "outcome": "succeeded",
            "result": [
                "file_name": "sample.mp4",
                "duration_ms": true,
                "container_format": "mp4",
                "video_stream_count": 1,
                "audio_stream_count": 1,
            ],
        ])
        let stdout = try JSONSerialization.data(withJSONObject: finished) + Data([0x0A])

        XCTAssertEqual(
            PreflightProtocolParser.parse(stdout: stdout, requestID: requestID, terminationStatus: 0, terminationReason: .exit),
            .failure(.protocolError)
        )
    }

    private func event(type: String, requestID: UUID, sequence: Int, payload: [String: Any]) -> [String: Any] {
        [
            "protocol_version": 1,
            "type": type,
            "request_id": requestID.uuidString.lowercased(),
            "sequence": sequence,
            "payload": payload,
        ]
    }
}

private struct ImmediatePreflightService: PreflightServicing {
    let outcome: PreflightOutcome

    func run(sourceURL: URL, requestID: UUID) async -> PreflightOutcome { outcome }
}

private struct ImmediateCharacterRegistrationService: CharacterRegistrationServicing {
    let registration: CharacterRegistrationOutcome
    let load: CharacterLoadOutcome

    func register(_ request: CharacterRegistrationRequest, requestID: UUID) async -> CharacterRegistrationOutcome {
        registration
    }

    func loadCharacters(requestID: UUID) async -> CharacterLoadOutcome {
        load
    }
}

private actor ControlledPreflightService: PreflightServicing {
    private var continuations = [String: CheckedContinuation<PreflightOutcome, Never>]()

    func run(sourceURL: URL, requestID: UUID) async -> PreflightOutcome {
        await withCheckedContinuation { continuations[sourceURL.lastPathComponent] = $0 }
    }

    func resume(fileName: String, with outcome: PreflightOutcome) {
        continuations.removeValue(forKey: fileName)?.resume(returning: outcome)
    }
}
