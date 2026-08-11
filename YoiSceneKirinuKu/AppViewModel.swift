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
    var outputDirectoryURL: URL? = nil
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

    static let runtimeInitial = HomeState(
        video: .unselected,
        registeredCharacters: [],
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

enum ResultQuality: Equatable, CaseIterable {
    case excellent
    case good
    case needsReview

    var symbol: String {
        switch self {
        case .excellent: "◎"
        case .good: "○"
        case .needsReview: "△"
        }
    }

    var title: String {
        switch self {
        case .excellent: "とても良い"
        case .good: "良い"
        case .needsReview: "要確認"
        }
    }

    var isInitiallySelected: Bool { self != .needsReview }
}

enum CharacterMatchDisplay: Equatable {
    case high
    case medium
    case unknown

    var title: String {
        switch self {
        case .high: "高い"
        case .medium: "中程度"
        case .unknown: "人物不明"
        }
    }
}

struct ResultCandidate: Identifiable, Equatable {
    let id: UUID
    let startMilliseconds: Int64
    let durationMilliseconds: Int64
    let quality: ResultQuality
    let characterMatch: CharacterMatchDisplay
    let qualityReason: String?

    var endMilliseconds: Int64 { startMilliseconds + durationMilliseconds }
}

enum ResultGroupID: Hashable {
    case character(UUID)
    case unknown
}

struct ResultGroup: Identifiable, Equatable {
    let id: ResultGroupID
    let title: String
    let candidates: [ResultCandidate]

    var isUnknown: Bool { id == .unknown }
}

struct ResultSelectionState: Equatable {
    var selectedCandidateIDs: Set<UUID>
}

struct ResultsState: Equatable {
    var groups: [ResultGroup]
    var selection: ResultSelectionState
    var focusedCandidateID: UUID?
    var expandedGroupIDs: Set<ResultGroupID>

    static let empty = ResultsState(
        groups: [],
        selection: ResultSelectionState(selectedCandidateIDs: []),
        focusedCandidateID: nil,
        expandedGroupIDs: []
    )

    static let initial: ResultsState = {
        let conanID = UUID(uuidString: "1c87d576-6f98-4e10-bf44-427cadb4e634")!
        let ranID = UUID(uuidString: "ceae23e4-f6fb-4aa8-860a-2c4a22fe1d07")!
        let excellentID = UUID(uuidString: "04606659-a277-48d8-b89d-5992da0d40cc")!
        let goodID = UUID(uuidString: "1e97d70e-2497-44d0-b558-4dd865792d52")!
        let reviewID = UUID(uuidString: "f1c9b457-0f28-4b91-87cb-065503be87b8")!
        let ranGoodID = UUID(uuidString: "5b8e49d3-6e7e-49a0-99ba-74162236bd29")!
        let unknownExcellentID = UUID(uuidString: "17a9f28a-8505-40a0-9108-fd61ec8cda95")!
        let unknownReviewID = UUID(uuidString: "cdf88239-d285-4025-ac22-8479dbc9e83c")!

        let groups = [
            ResultGroup(id: .character(conanID), title: "コナン", candidates: [
                ResultCandidate(id: excellentID, startMilliseconds: 192_000, durationMilliseconds: 4_000, quality: .excellent, characterMatch: .high, qualityReason: nil),
                ResultCandidate(id: goodID, startMilliseconds: 521_000, durationMilliseconds: 6_000, quality: .good, characterMatch: .high, qualityReason: "背景音がやや強い。"),
                ResultCandidate(id: reviewID, startMilliseconds: 680_000, durationMilliseconds: 3_000, quality: .needsReview, characterMatch: .medium, qualityReason: "声が小さい。"),
            ]),
            ResultGroup(id: .character(ranID), title: "蘭", candidates: [
                ResultCandidate(id: ranGoodID, startMilliseconds: 744_000, durationMilliseconds: 5_000, quality: .good, characterMatch: .medium, qualityReason: nil),
            ]),
            ResultGroup(id: .unknown, title: "人物不明", candidates: [
                ResultCandidate(id: unknownExcellentID, startMilliseconds: 820_000, durationMilliseconds: 4_000, quality: .excellent, characterMatch: .unknown, qualityReason: nil),
                ResultCandidate(id: unknownReviewID, startMilliseconds: 900_000, durationMilliseconds: 2_000, quality: .needsReview, characterMatch: .unknown, qualityReason: "短い発話です。"),
            ]),
        ]
        let selected = Set(groups.flatMap(\.candidates).filter { candidate in
            candidate.quality.isInitiallySelected && candidate.characterMatch != .unknown
        }.map(\.id))
        return ResultsState(
            groups: groups,
            selection: ResultSelectionState(selectedCandidateIDs: selected),
            focusedCandidateID: groups.first?.candidates.first?.id,
            expandedGroupIDs: [.character(conanID), .character(ranID)]
        )
    }()

    var candidateCount: Int { groups.reduce(0) { $0 + $1.candidates.count } }
    var selectedCandidateIDs: Set<UUID> { selection.selectedCandidateIDs }
    var selectedCount: Int { selection.selectedCandidateIDs.count }

    var focusedCandidate: ResultCandidate? {
        groups.lazy.flatMap(\.candidates).first { $0.id == focusedCandidateID }
    }

    var focusedGroupTitle: String? {
        groups.first { group in group.candidates.contains { $0.id == focusedCandidateID } }?.title
    }
}

enum NewCharacterRegistrationPhase: Equatable {
    case editing
    case registrationRequested
    case registered
    case failed(message: String)
}

struct NewCharacterRegistrationState: Equatable {
    var isPresented = false
    var name = ""
    var videoURL: URL?
    var videoDurationMilliseconds: Int64?
    var currentPositionMilliseconds: Int64 = 0
    var startMilliseconds: Int64?
    var endMilliseconds: Int64?
    var phase: NewCharacterRegistrationPhase = .editing
    var videoErrorMessage: String?

    var videoFileName: String? { videoURL?.lastPathComponent }

    var hasValidRange: Bool {
        guard let startMilliseconds,
              let endMilliseconds,
              let videoDurationMilliseconds else { return false }
        let length = endMilliseconds - startMilliseconds
        return startMilliseconds >= 0
            && startMilliseconds < endMilliseconds
            && endMilliseconds <= videoDurationMilliseconds
            && length >= 3_000
            && length <= 30_000
    }

    var canRequestRegistration: Bool {
        phase == .editing
            && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && videoURL != nil
            && hasValidRange
    }
}

struct RegisteredAudioSampleSummary: Identifiable, Equatable, Sendable {
    let id: UUID
    let sourceFileName: String
    let durationMilliseconds: Int64
}

struct CharacterManagementState: Equatable {
    var selectedCharacterID: UUID?
    var samplesByCharacterID: [UUID: [RegisteredAudioSampleSummary]]

    static let initial: CharacterManagementState = {
        let conanID = UUID(uuidString: "1c87d576-6f98-4e10-bf44-427cadb4e634")!
        let ranID = UUID(uuidString: "ceae23e4-f6fb-4aa8-860a-2c4a22fe1d07")!
        let haibaraID = UUID(uuidString: "a0386bc8-7d73-47de-ae6f-7a729255c194")!
        return CharacterManagementState(
            selectedCharacterID: conanID,
            samplesByCharacterID: [
                conanID: [
                    RegisteredAudioSampleSummary(id: UUID(uuidString: "2514fffd-245d-40f2-b215-77949dcc74ae")!, sourceFileName: "episode01.mp4", durationMilliseconds: 7_000),
                    RegisteredAudioSampleSummary(id: UUID(uuidString: "ab0b7819-e9c6-4208-a583-9eed4a6db4b9")!, sourceFileName: "episode03.mp4", durationMilliseconds: 8_000),
                ],
                ranID: [
                    RegisteredAudioSampleSummary(id: UUID(uuidString: "984e2ee1-d0aa-4f31-a3dd-5c133c32b78d")!, sourceFileName: "episode02.mp4", durationMilliseconds: 6_000),
                ],
                haibaraID: [
                    RegisteredAudioSampleSummary(id: UUID(uuidString: "ec0fe8dd-c9c9-4c45-85e5-8b014767297d")!, sourceFileName: "episode05.mp4", durationMilliseconds: 6_000),
                ],
            ]
        )
    }()

    func samples(for characterID: UUID) -> [RegisteredAudioSampleSummary] {
        samplesByCharacterID[characterID] ?? []
    }
}

enum ExistingCharacterSampleAdditionPhase: Equatable {
    case editing
    case additionRequested
    case succeeded
    case failed(message: String)
}

struct ExistingCharacterSampleAdditionState: Equatable {
    var isPresented = false
    var targetCharacterID: UUID?
    var targetCharacterName: String?
    var videoURL: URL?
    var videoDurationMilliseconds: Int64?
    var currentPositionMilliseconds: Int64 = 0
    var startMilliseconds: Int64?
    var endMilliseconds: Int64?
    var phase: ExistingCharacterSampleAdditionPhase = .editing
    var videoErrorMessage: String?

    var videoFileName: String? { videoURL?.lastPathComponent }

    var hasValidRange: Bool {
        guard let startMilliseconds,
              let endMilliseconds,
              let videoDurationMilliseconds else { return false }
        let length = endMilliseconds - startMilliseconds
        return startMilliseconds >= 0
            && startMilliseconds < endMilliseconds
            && endMilliseconds <= videoDurationMilliseconds
            && length >= 3_000
            && length <= 30_000
    }

    var canRequestAddition: Bool {
        phase == .editing
            && targetCharacterID != nil
            && videoURL != nil
            && hasValidRange
    }
}

enum CharacterDeletionPhase: Equatable {
    case confirmation
    case deletionRequested
    case deleted
    case failed(message: String)
}

struct CharacterDeletionState: Equatable {
    var isPresented = false
    var targetCharacterID: UUID?
    var targetCharacterName: String?
    var sampleCount = 0
    var phase: CharacterDeletionPhase = .confirmation
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var route: AppRoute = .home
    @Published private(set) var homeState: HomeState
    @Published private(set) var draftCharacterIDs: Set<UUID>?
    @Published private(set) var analysisState: AnalysisState
    @Published private(set) var resultsState: ResultsState
    @Published private(set) var newCharacterRegistration = NewCharacterRegistrationState()
    @Published private(set) var characterManagementState = CharacterManagementState.initial
    @Published private(set) var existingCharacterSampleAddition = ExistingCharacterSampleAdditionState()
    @Published private(set) var characterDeletion = CharacterDeletionState()
    private let preflightService: any PreflightServicing
    private let characterRegistrationService: any CharacterRegistrationServicing
    private let externalSelectionBookmarks: any ExternalSelectionBookmarkStoring
    private var preflightTask: Task<Void, Never>?
    private var currentPreflightRequestID: UUID?
    private var registrationTask: Task<Void, Never>?
    private var characterReloadTask: Task<Void, Never>?
    private var currentRegistrationRequestID: UUID?
    private var sampleAdditionTask: Task<Void, Never>?
    private var currentSampleAdditionRequestID: UUID?
    private var characterDeletionTask: Task<Void, Never>?
    private var currentCharacterDeletionRequestID: UUID?

    init(
        homeState: HomeState = .initial,
        analysisState: AnalysisState = .initial,
        resultsState: ResultsState = .initial,
        preflightService: any PreflightServicing = PreflightService(),
        characterRegistrationService: any CharacterRegistrationServicing = CharacterRegistrationService(),
        externalSelectionBookmarks: any ExternalSelectionBookmarkStoring = ExternalSelectionBookmarkStore()
    ) {
        self.homeState = homeState
        self.analysisState = analysisState
        self.resultsState = resultsState
        self.preflightService = preflightService
        self.characterRegistrationService = characterRegistrationService
        self.externalSelectionBookmarks = externalSelectionBookmarks
    }

    func selectVideo(_ url: URL) {
        guard externalSelectionBookmarks.save(url, for: .sourceVideo) else {
            resetVideoSelection()
            return
        }
        beginVideoPreflight(url)
    }

    func restoreExternalSelections() {
        homeState.outputDirectoryURL = externalSelectionBookmarks.restore(.outputDirectory)
        if let sourceVideoURL = externalSelectionBookmarks.restore(.sourceVideo) {
            beginVideoPreflight(sourceVideoURL)
        } else {
            resetVideoSelection()
        }
    }

    private func beginVideoPreflight(_ url: URL) {
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

    func selectOutputDirectory(_ url: URL) {
        homeState.outputDirectoryURL = externalSelectionBookmarks.save(url, for: .outputDirectory) ? url : nil
    }

    private func resetVideoSelection() {
        preflightTask?.cancel()
        currentPreflightRequestID = nil
        homeState.video = .unselected
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

    func toggleResultSelection(_ candidateID: UUID) {
        guard resultsState.groups.contains(where: { group in
            group.candidates.contains(where: { $0.id == candidateID })
        }) else { return }
        if resultsState.selection.selectedCandidateIDs.contains(candidateID) {
            resultsState.selection.selectedCandidateIDs.remove(candidateID)
        } else {
            resultsState.selection.selectedCandidateIDs.insert(candidateID)
        }
    }

    func focusResultCandidate(_ candidateID: UUID) {
        guard resultsState.groups.contains(where: { group in
            group.candidates.contains(where: { $0.id == candidateID })
        }) else { return }
        resultsState.focusedCandidateID = candidateID
    }

    func toggleResultGroup(_ groupID: ResultGroupID) {
        guard resultsState.groups.contains(where: { $0.id == groupID }) else { return }
        if resultsState.expandedGroupIDs.contains(groupID) {
            resultsState.expandedGroupIDs.remove(groupID)
        } else {
            resultsState.expandedGroupIDs.insert(groupID)
        }
    }

    @discardableResult
    func beginNewCharacterRegistration() -> Bool {
        guard route == .characters,
              !newCharacterRegistration.isPresented,
              !characterDeletion.isPresented else { return false }
        newCharacterRegistration = NewCharacterRegistrationState(isPresented: true)
        return true
    }

    func updateNewCharacterName(_ name: String) {
        guard newCharacterRegistration.isPresented,
              newCharacterRegistration.phase == .editing else { return }
        newCharacterRegistration.name = name
    }

    func selectNewCharacterVideo(_ url: URL, durationMilliseconds: Int64) {
        guard newCharacterRegistration.isPresented,
              newCharacterRegistration.phase == .editing else { return }
        guard durationMilliseconds > 0 else {
            newCharacterRegistration.videoURL = nil
            newCharacterRegistration.videoDurationMilliseconds = nil
            newCharacterRegistration.videoErrorMessage = "動画を読み込めませんでした。"
            return
        }
        newCharacterRegistration.videoURL = url
        newCharacterRegistration.videoDurationMilliseconds = durationMilliseconds
        newCharacterRegistration.currentPositionMilliseconds = 0
        newCharacterRegistration.startMilliseconds = nil
        newCharacterRegistration.endMilliseconds = nil
        newCharacterRegistration.videoErrorMessage = nil
    }

    func newCharacterVideoSelectionFailed() {
        guard newCharacterRegistration.isPresented,
              newCharacterRegistration.phase == .editing else { return }
        newCharacterRegistration.videoURL = nil
        newCharacterRegistration.videoDurationMilliseconds = nil
        newCharacterRegistration.videoErrorMessage = "動画を読み込めませんでした。"
    }

    func updateNewCharacterCurrentPosition(_ milliseconds: Int64) {
        guard newCharacterRegistration.isPresented,
              let duration = newCharacterRegistration.videoDurationMilliseconds else { return }
        newCharacterRegistration.currentPositionMilliseconds = min(max(0, milliseconds), duration)
    }

    func setNewCharacterRangeStart() {
        guard newCharacterRegistration.isPresented,
              newCharacterRegistration.phase == .editing,
              newCharacterRegistration.videoURL != nil else { return }
        newCharacterRegistration.startMilliseconds = newCharacterRegistration.currentPositionMilliseconds
    }

    func setNewCharacterRangeEnd() {
        guard newCharacterRegistration.isPresented,
              newCharacterRegistration.phase == .editing,
              newCharacterRegistration.videoURL != nil else { return }
        newCharacterRegistration.endMilliseconds = newCharacterRegistration.currentPositionMilliseconds
    }

    @discardableResult
    func requestNewCharacterRegistration() -> Bool {
        guard newCharacterRegistration.canRequestRegistration,
              let sourceURL = newCharacterRegistration.videoURL,
              let startMilliseconds = newCharacterRegistration.startMilliseconds,
              let endMilliseconds = newCharacterRegistration.endMilliseconds else { return false }
        let request = CharacterRegistrationRequest(
            displayName: newCharacterRegistration.name.trimmingCharacters(in: .whitespacesAndNewlines),
            sourceURL: sourceURL,
            startMilliseconds: startMilliseconds,
            endMilliseconds: endMilliseconds
        )
        let requestID = UUID()
        currentRegistrationRequestID = requestID
        newCharacterRegistration.phase = .registrationRequested
        registrationTask = Task { [weak self, characterRegistrationService] in
            let outcome = await characterRegistrationService.register(request, requestID: requestID)
            guard !Task.isCancelled else { return }
            switch outcome {
            case .success:
                let reload = await characterRegistrationService.loadCharacters(requestID: UUID())
                guard !Task.isCancelled else { return }
                self?.applyRegistration(outcome, reload: reload, requestID: requestID)
            case .failure:
                self?.applyRegistration(outcome, reload: nil, requestID: requestID)
            }
        }
        return true
    }

    func reloadRegisteredCharacters() {
        let requestID = UUID()
        characterReloadTask = Task { [weak self, characterRegistrationService] in
            let outcome = await characterRegistrationService.loadCharacters(requestID: requestID)
            guard !Task.isCancelled else { return }
            if case .success(let characters) = outcome {
                self?.replaceRegisteredCharacters(with: characters)
            }
        }
    }

    func waitForCharacterRegistrationForTesting() async {
        await registrationTask?.value
    }

    func waitForCharacterReloadForTesting() async {
        await characterReloadTask?.value
    }

    func cancelNewCharacterRegistration() {
        guard newCharacterRegistration.phase != .registrationRequested else { return }
        currentRegistrationRequestID = nil
        newCharacterRegistration = NewCharacterRegistrationState()
    }

    func selectManagedCharacter(_ characterID: UUID) {
        guard route == .characters,
              !existingCharacterSampleAddition.isPresented,
              !characterDeletion.isPresented,
              homeState.registeredCharacters.contains(where: { $0.id == characterID }) else { return }
        characterManagementState.selectedCharacterID = characterID
    }

    @discardableResult
    func beginCharacterDeletion() -> Bool {
        guard route == .characters,
              !characterDeletion.isPresented,
              !newCharacterRegistration.isPresented,
              !existingCharacterSampleAddition.isPresented,
              let characterID = characterManagementState.selectedCharacterID,
              let character = homeState.registeredCharacters.first(where: { $0.id == characterID }) else {
            return false
        }
        characterDeletion = CharacterDeletionState(
            isPresented: true,
            targetCharacterID: characterID,
            targetCharacterName: character.name,
            sampleCount: characterManagementState.samples(for: characterID).count
        )
        return true
    }

    @discardableResult
    func requestCharacterDeletion() -> Bool {
        guard characterDeletion.isPresented,
              characterDeletion.phase != .deletionRequested,
              let characterID = characterDeletion.targetCharacterID else { return false }
        let requestID = UUID()
        currentCharacterDeletionRequestID = requestID
        characterDeletion.phase = .deletionRequested
        characterDeletionTask = Task { [weak self, characterRegistrationService] in
            let outcome = await characterRegistrationService.deleteCharacter(characterID, requestID: requestID)
            guard !Task.isCancelled else { return }
            switch outcome {
            case .success:
                let reload = await characterRegistrationService.loadCharacters(requestID: UUID())
                guard !Task.isCancelled else { return }
                self?.applyDeletion(outcome, reload: reload, requestID: requestID, targetCharacterID: characterID)
            case .failure:
                self?.applyDeletion(outcome, reload: nil, requestID: requestID, targetCharacterID: characterID)
            }
        }
        return true
    }

    func cancelCharacterDeletion() {
        guard characterDeletion.phase != .deletionRequested else { return }
        currentCharacterDeletionRequestID = nil
        characterDeletion = CharacterDeletionState()
    }

    func waitForCharacterDeletionForTesting() async {
        await characterDeletionTask?.value
    }

    @discardableResult
    func beginExistingCharacterSampleAddition() -> Bool {
        guard route == .characters,
              !newCharacterRegistration.isPresented,
              !existingCharacterSampleAddition.isPresented,
              !characterDeletion.isPresented,
              let characterID = characterManagementState.selectedCharacterID,
              let character = homeState.registeredCharacters.first(where: { $0.id == characterID }) else { return false }
        existingCharacterSampleAddition = ExistingCharacterSampleAdditionState(
            isPresented: true,
            targetCharacterID: character.id,
            targetCharacterName: character.name
        )
        return true
    }

    func selectExistingCharacterSampleVideo(_ url: URL, durationMilliseconds: Int64) {
        guard existingCharacterSampleAddition.isPresented,
              existingCharacterSampleAddition.phase == .editing else { return }
        guard durationMilliseconds > 0 else {
            existingCharacterSampleAddition.videoURL = nil
            existingCharacterSampleAddition.videoDurationMilliseconds = nil
            existingCharacterSampleAddition.videoErrorMessage = "動画を読み込めませんでした。"
            return
        }
        existingCharacterSampleAddition.videoURL = url
        existingCharacterSampleAddition.videoDurationMilliseconds = durationMilliseconds
        existingCharacterSampleAddition.currentPositionMilliseconds = 0
        existingCharacterSampleAddition.startMilliseconds = nil
        existingCharacterSampleAddition.endMilliseconds = nil
        existingCharacterSampleAddition.videoErrorMessage = nil
    }

    func existingCharacterSampleVideoSelectionFailed() {
        guard existingCharacterSampleAddition.isPresented,
              existingCharacterSampleAddition.phase == .editing else { return }
        existingCharacterSampleAddition.videoURL = nil
        existingCharacterSampleAddition.videoDurationMilliseconds = nil
        existingCharacterSampleAddition.videoErrorMessage = "動画を読み込めませんでした。"
    }

    func updateExistingCharacterSampleCurrentPosition(_ milliseconds: Int64) {
        guard existingCharacterSampleAddition.isPresented,
              let duration = existingCharacterSampleAddition.videoDurationMilliseconds else { return }
        existingCharacterSampleAddition.currentPositionMilliseconds = min(max(0, milliseconds), duration)
    }

    func setExistingCharacterSampleRangeStart() {
        guard existingCharacterSampleAddition.isPresented,
              existingCharacterSampleAddition.phase == .editing,
              existingCharacterSampleAddition.videoURL != nil else { return }
        existingCharacterSampleAddition.startMilliseconds = existingCharacterSampleAddition.currentPositionMilliseconds
    }

    func setExistingCharacterSampleRangeEnd() {
        guard existingCharacterSampleAddition.isPresented,
              existingCharacterSampleAddition.phase == .editing,
              existingCharacterSampleAddition.videoURL != nil else { return }
        existingCharacterSampleAddition.endMilliseconds = existingCharacterSampleAddition.currentPositionMilliseconds
    }

    @discardableResult
    func requestExistingCharacterSampleAddition() -> Bool {
        guard existingCharacterSampleAddition.canRequestAddition,
              let characterID = existingCharacterSampleAddition.targetCharacterID,
              let sourceURL = existingCharacterSampleAddition.videoURL,
              let startMilliseconds = existingCharacterSampleAddition.startMilliseconds,
              let endMilliseconds = existingCharacterSampleAddition.endMilliseconds else { return false }
        let previousSampleIDs = Set(characterManagementState.samples(for: characterID).map(\.id))
        let request = CharacterSampleAdditionRequest(
            characterID: characterID,
            sourceURL: sourceURL,
            startMilliseconds: startMilliseconds,
            endMilliseconds: endMilliseconds
        )
        let requestID = UUID()
        currentSampleAdditionRequestID = requestID
        existingCharacterSampleAddition.phase = .additionRequested
        sampleAdditionTask = Task { [weak self, characterRegistrationService] in
            let outcome = await characterRegistrationService.addSample(request, requestID: requestID)
            guard !Task.isCancelled else { return }
            switch outcome {
            case .success:
                let reload = await characterRegistrationService.loadCharacters(requestID: UUID())
                guard !Task.isCancelled else { return }
                self?.applySampleAddition(
                    outcome,
                    reload: reload,
                    requestID: requestID,
                    targetCharacterID: characterID,
                    previousSampleIDs: previousSampleIDs
                )
            case .failure:
                self?.applySampleAddition(
                    outcome,
                    reload: nil,
                    requestID: requestID,
                    targetCharacterID: characterID,
                    previousSampleIDs: previousSampleIDs
                )
            }
        }
        return true
    }

    func waitForExistingCharacterSampleAdditionForTesting() async {
        await sampleAdditionTask?.value
    }

    @discardableResult
    func retryExistingCharacterSampleAddition() -> Bool {
        guard case .failed = existingCharacterSampleAddition.phase else { return false }
        existingCharacterSampleAddition.phase = .editing
        return true
    }

    func cancelExistingCharacterSampleAddition() {
        guard existingCharacterSampleAddition.phase != .additionRequested else { return }
        currentSampleAdditionRequestID = nil
        existingCharacterSampleAddition = ExistingCharacterSampleAdditionState()
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

    private func applyRegistration(
        _ outcome: CharacterRegistrationOutcome,
        reload: CharacterLoadOutcome?,
        requestID: UUID
    ) {
        guard currentRegistrationRequestID == requestID,
              newCharacterRegistration.phase == .registrationRequested else { return }
        switch outcome {
        case .success(let registered):
            guard case .success(let characters) = reload,
                  characters.contains(where: { $0.characterID == registered.characterID }) else {
                newCharacterRegistration.phase = .failed(message: CharacterRegistrationErrorCode.protocolError.userMessage)
                return
            }
            replaceRegisteredCharacters(with: characters)
            newCharacterRegistration.phase = .registered
        case .failure(let code):
            newCharacterRegistration.phase = .failed(message: code.userMessage)
        }
        currentRegistrationRequestID = nil
    }

    private func applySampleAddition(
        _ outcome: CharacterRegistrationOutcome,
        reload: CharacterLoadOutcome?,
        requestID: UUID,
        targetCharacterID: UUID,
        previousSampleIDs: Set<UUID>
    ) {
        guard currentSampleAdditionRequestID == requestID,
              existingCharacterSampleAddition.phase == .additionRequested,
              existingCharacterSampleAddition.targetCharacterID == targetCharacterID else { return }
        switch outcome {
        case .success(let updated):
            guard updated.characterID == targetCharacterID,
                  case .success(let characters) = reload,
                  let reloaded = characters.first(where: { $0.characterID == targetCharacterID }),
                  Set(reloaded.samples.map(\.id)).isStrictSuperset(of: previousSampleIDs),
                  reloaded.samples == updated.samples else {
                existingCharacterSampleAddition.phase = .failed(message: CharacterRegistrationErrorCode.protocolError.userMessage)
                currentSampleAdditionRequestID = nil
                return
            }
            replaceRegisteredCharacters(with: characters)
            existingCharacterSampleAddition.phase = .succeeded
        case .failure(let code):
            existingCharacterSampleAddition.phase = .failed(message: code.userMessage)
        }
        currentSampleAdditionRequestID = nil
    }

    private func applyDeletion(
        _ outcome: CharacterDeletionOutcome,
        reload: CharacterLoadOutcome?,
        requestID: UUID,
        targetCharacterID: UUID
    ) {
        guard currentCharacterDeletionRequestID == requestID,
              characterDeletion.phase == .deletionRequested,
              characterDeletion.targetCharacterID == targetCharacterID else { return }
        switch outcome {
        case .success(let deletedID):
            guard deletedID == targetCharacterID,
                  case .success(let characters) = reload,
                  !characters.contains(where: { $0.characterID == targetCharacterID }) else {
                characterDeletion.phase = .failed(message: CharacterRegistrationErrorCode.protocolError.userMessage)
                currentCharacterDeletionRequestID = nil
                return
            }
            replaceRegisteredCharacters(with: characters)
            characterDeletion.phase = .deleted
        case .failure(let code):
            characterDeletion.phase = .failed(message: code.userMessage)
        }
        currentCharacterDeletionRequestID = nil
    }

    private func replaceRegisteredCharacters(with characters: [RegisteredCharacter]) {
        let summaries = characters.map { CharacterSummary(id: $0.characterID, name: $0.displayName) }
        homeState.registeredCharacters = summaries
        let availableIDs = Set(summaries.map(\.id))
        homeState.selectedCharacterIDs.formIntersection(availableIDs)
        characterManagementState.samplesByCharacterID = Dictionary(uniqueKeysWithValues: characters.map {
            ($0.characterID, $0.samples)
        })
        if let selected = characterManagementState.selectedCharacterID, availableIDs.contains(selected) {
            return
        }
        characterManagementState.selectedCharacterID = summaries.first?.id
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
