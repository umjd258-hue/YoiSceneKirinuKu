import SwiftUI

struct HomeView: View {
    let onOpenAnalysis: () -> Bool
    let onOpenCharacters: () -> Bool

    var body: some View {
        PlaceholderContainer(title: "ホーム") {
            Button("解析画面（仮）へ") {
                onOpenAnalysis()
            }
            Button("人物管理画面（仮）へ") {
                onOpenCharacters()
            }
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
