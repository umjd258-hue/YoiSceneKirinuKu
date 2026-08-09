import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    let state: HomeState
    let onSelectVideo: (URL) -> Void
    let onVideoSelectionFailed: () -> Void
    let onOpenAnalysis: () -> Bool
    let onOpenCharacters: () -> Bool
    let draftCharacterIDs: Set<UUID>?
    let onBeginCharacterSelection: () -> Bool
    let onToggleDraftCharacter: (UUID) -> Void
    let onConfirmCharacterSelection: () -> Void
    let onCancelCharacterSelection: () -> Void
    @State private var isVideoImporterPresented = false
    @State private var isCharacterSelectionPresented = false

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 6) {
                Text("良いシーン切りぬく〜よ")
                    .font(.largeTitle.bold())
                Text("動画・音声は外部へ送信しません")
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 16) {
                videoCard
                charactersCard
            }
            .frame(maxWidth: 560)

            Button("解析を開始") {
                onOpenAnalysis()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!state.canStartAnalysis)
        }
        .frame(minWidth: 640, minHeight: 520)
        .padding(32)
        .fileImporter(isPresented: $isVideoImporterPresented, allowedContentTypes: [.mpeg4Movie]) { result in
            switch result {
            case .success(let url):
                onSelectVideo(url)
            case .failure:
                onVideoSelectionFailed()
            }
        }
        .sheet(isPresented: $isCharacterSelectionPresented) {
            CharacterSelectionSheet(
                characters: state.registeredCharacters,
                selectedIDs: draftCharacterIDs ?? [],
                onToggle: onToggleDraftCharacter,
                onCancel: {
                    onCancelCharacterSelection()
                    isCharacterSelectionPresented = false
                },
                onConfirm: {
                    onConfirmCharacterSelection()
                    isCharacterSelectionPresented = false
                }
            )
        }
    }

    private var videoCard: some View {
        HomeCard(title: "動画") {
            switch state.video {
            case .unselected:
                Text("動画を選んでください")
                    .foregroundStyle(.secondary)
                videoSelectionButton("動画を選ぶ")
            case .checking:
                ProgressView("動画を確認しています…")
            case .ready(let fileName, let duration):
                Text(fileName)
                    .font(.headline)
                Text(duration)
                    .foregroundStyle(.secondary)
                videoSelectionButton("変更")
            case .failed(let message):
                Label("この動画は解析できません", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .foregroundStyle(.secondary)
                videoSelectionButton("変更")
            }
        }
    }

    private func videoSelectionButton(_ title: String) -> some View {
        Button(title) { isVideoImporterPresented = true }
    }

    private var charactersCard: some View {
        HomeCard(title: "探す人物") {
            switch state.characters {
            case .unregistered:
                Text("まだ人物が登録されていません。")
                Text("最初に、探したい人物の声を登録してください。")
                    .foregroundStyle(.secondary)
                Button("人物を登録") {
                    onOpenCharacters()
                }
            case .unselected:
                Text("人物を選んでください")
                    .foregroundStyle(.secondary)
                characterSelectionButton("人物を選ぶ")
                Button("人物を管理") { onOpenCharacters() }
            case .selected(let characters):
                HStack(spacing: 8) {
                    ForEach(characters) { character in
                        Text(character.name)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.quaternary, in: Capsule())
                    }
                }
                Text("\(characters.count)人")
                    .foregroundStyle(.secondary)
                characterSelectionButton("変更")
                Button("人物を管理") { onOpenCharacters() }
            }
        }
    }

    private func characterSelectionButton(_ title: String) -> some View {
        Button(title) {
            if onBeginCharacterSelection() {
                isCharacterSelectionPresented = true
            }
        }
    }
}

private struct CharacterSelectionSheet: View {
    let characters: [CharacterSummary]
    let selectedIDs: Set<UUID>
    let onToggle: (UUID) -> Void
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("人物を選ぶ")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 12) {
                ForEach(characters) { character in
                    Toggle(
                        character.name,
                        isOn: Binding(
                            get: { selectedIDs.contains(character.id) },
                            set: { _ in onToggle(character.id) }
                        )
                    )
                    .toggleStyle(.checkbox)
                }
            }

            HStack {
                Spacer()
                Button("キャンセル", action: onCancel)
                Button("決定", action: onConfirm)
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(minWidth: 360)
        .padding(24)
    }
}

private struct HomeCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.separator, lineWidth: 1)
        }
    }
}

struct AnalysisView: View {
    let state: AnalysisState
    let onRequestStop: () -> Bool
    let onResume: () -> Bool
    let onReturnHome: () -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            switch state {
            case .running(let progress):
                runningContent(progress: progress)
            case .stopRequested:
                stoppingContent
            case .stopped(let resumeProgress):
                stoppedContent(canResume: resumeProgress != nil)
            }
        }
        .frame(minWidth: 640, minHeight: 520)
        .padding(32)
    }

    private func runningContent(progress: AnalysisProgress) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("解析中")
                .font(.largeTitle.bold())
            VStack(alignment: .leading, spacing: 6) {
                Text(progress.step.title)
                    .font(.title2)
                Text(progress.value.displayText)
                    .font(.title3.monospacedDigit())
            }
            analysisSteps(currentStep: progress.step)
            Button("停止") { onRequestStop() }
                .buttonStyle(.bordered)
        }
    }

    private var stoppingContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProgressView()
            Text("安全に停止しています…")
                .font(.title2.bold())
            Text("安全に停止できる状態を確認しています。")
                .foregroundStyle(.secondary)
            Button("停止") {}
                .disabled(true)
        }
    }

    private func stoppedContent(canResume: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("解析を停止しました")
                .font(.title2.bold())
            Text("完成済みの処理は残っています。")
                .foregroundStyle(.secondary)
            if canResume {
                Button("続きから解析") { onResume() }
                    .buttonStyle(.borderedProminent)
            }
            Button("ホームへ戻る") { onReturnHome() }
        }
    }

    private func analysisSteps(currentStep: AnalysisStep) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(AnalysisStep.allCases) { step in
                Label {
                    Text(step.title)
                } icon: {
                    Image(systemName: iconName(for: step, currentStep: currentStep))
                        .foregroundStyle(iconColor(for: step, currentStep: currentStep))
                }
            }
        }
    }

    private func iconName(for step: AnalysisStep, currentStep: AnalysisStep) -> String {
        if step.rawValue < currentStep.rawValue { return "checkmark.circle.fill" }
        if step == currentStep { return "circle.fill" }
        return "circle"
    }

    private func iconColor(for step: AnalysisStep, currentStep: AnalysisStep) -> Color {
        step.rawValue <= currentStep.rawValue ? .blue : .secondary
    }
}

struct ResultsView: View {
    let state: ResultsState
    let onToggleSelection: (UUID) -> Void
    let onFocusCandidate: (UUID) -> Void
    let onToggleGroup: (ResultGroupID) -> Void
    let onReturnHome: () -> Bool

    var body: some View {
        if state.candidateCount == 0 {
            VStack(spacing: 20) {
                Text("今回は条件に合う場面が見つかりませんでした。")
                    .font(.title2)
                Button("ホームへ戻る") { onReturnHome() }
            }
            .frame(minWidth: 720, minHeight: 520)
            .padding(32)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                Text("解析結果 \(state.candidateCount)件")
                    .font(.largeTitle.bold())

                HSplitView {
                    candidateList
                        .frame(minWidth: 320)
                    candidateDetail
                        .frame(minWidth: 320)
                }

                HStack {
                    Text("\(state.selectedCount)件を選択中")
                        .font(.headline)
                    Spacer()
                    Button("ホームへ戻る") { onReturnHome() }
                }
            }
            .frame(minWidth: 760, minHeight: 560)
            .padding(24)
        }
    }

    private var candidateList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(state.groups) { group in
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { state.expandedGroupIDs.contains(group.id) },
                            set: { _ in onToggleGroup(group.id) }
                        )
                    ) {
                        VStack(spacing: 6) {
                            ForEach(group.candidates) { candidate in
                                candidateRow(candidate)
                            }
                        }
                        .padding(.top, 6)
                    } label: {
                        Text("\(group.title) \(group.candidates.count)件")
                            .font(.headline)
                    }
                }
            }
            .padding(12)
        }
    }

    private func candidateRow(_ candidate: ResultCandidate) -> some View {
        HStack(spacing: 8) {
            Toggle(
                "",
                isOn: Binding(
                    get: { state.selectedCandidateIDs.contains(candidate.id) },
                    set: { _ in onToggleSelection(candidate.id) }
                )
            )
            .labelsHidden()
            .toggleStyle(.checkbox)

            Button {
                onFocusCandidate(candidate.id)
            } label: {
                HStack {
                    Text(Self.formatTimestamp(candidate.startMilliseconds))
                        .monospacedDigit()
                    Text(Self.formatDuration(candidate.durationMilliseconds))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(candidate.quality.symbol)
                        .font(.headline)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(
            state.focusedCandidateID == candidate.id ? Color.accentColor.opacity(0.12) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    @ViewBuilder
    private var candidateDetail: some View {
        if let candidate = state.focusedCandidate {
            VStack(alignment: .leading, spacing: 16) {
                Text(state.focusedGroupTitle ?? "人物不明")
                    .font(.title2.bold())
                Text("\(Self.formatTimestamp(candidate.startMilliseconds)) - \(Self.formatTimestamp(candidate.endMilliseconds))")
                    .monospacedDigit()
                Divider()
                LabeledContent("人物一致", value: candidate.characterMatch.title)
                LabeledContent("品質", value: "\(candidate.quality.symbol) \(candidate.quality.title)")
                if let qualityReason = candidate.qualityReason {
                    Text(qualityReason)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(20)
        } else {
            ContentUnavailableView("候補を選んでください", systemImage: "list.bullet.rectangle")
        }
    }

    private static func formatTimestamp(_ milliseconds: Int64) -> String {
        let seconds = max(0, milliseconds) / 1_000
        return String(format: "%02lld:%02lld:%02lld", seconds / 3_600, (seconds % 3_600) / 60, seconds % 60)
    }

    private static func formatDuration(_ milliseconds: Int64) -> String {
        let seconds = max(0, milliseconds) / 1_000
        return "\(seconds)秒"
    }
}

struct CharactersView: View {
    let onReturnHome: () -> Bool

    var body: some View {
        PlaceholderContainer(title: "人物管理（仮画面）") {
            Button("ホームへ戻る") {
                onReturnHome()
            }
        }
    }
}

private struct PlaceholderContainer<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.title)
            content
        }
        .frame(minWidth: 640, minHeight: 420)
        .padding(24)
    }
}
