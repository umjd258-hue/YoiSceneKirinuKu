import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    let state: HomeState
    let onSelectVideo: (URL) -> Void
    let onVideoSelectionFailed: () -> Void
    let onOpenAnalysis: () -> Bool
    let onOpenCharacters: () -> Bool
    @State private var isVideoImporterPresented = false

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
                mockButton("人物を選ぶ")
            case .selected(let names):
                HStack(spacing: 8) {
                    ForEach(names, id: \.self) { name in
                        Text(name)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.quaternary, in: Capsule())
                    }
                }
                Text("\(names.count)人")
                    .foregroundStyle(.secondary)
                mockButton("変更")
            }
        }
    }

    private func mockButton(_ title: String) -> some View {
        Button(title) {
            // 第2段階では実操作へ接続しない。
        }
        .disabled(true)
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
    let onOpenResults: () -> Bool
    let onReturnHome: () -> Bool

    var body: some View {
        PlaceholderContainer(title: "解析（仮画面）") {
            Button("結果画面（仮）へ") {
                onOpenResults()
            }
            Button("ホームへ戻る") {
                onReturnHome()
            }
        }
    }
}

struct ResultsView: View {
    let onReturnHome: () -> Bool

    var body: some View {
        PlaceholderContainer(title: "結果（仮画面）") {
            Button("ホームへ戻る") {
                onReturnHome()
            }
        }
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
