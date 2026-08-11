# ARCHITECTURE.md

## 技術
- SwiftUI
- AVFoundation / AVPlayer
- Python
- FFmpeg
- ローカルSpeaker Embeddingモデル
- JSON LinesによるSwift↔Python通信

## 原則
- 軽い処理を前、重い処理を後。
- 解析ジョブは原則1件。
- View寿命とsubprocess寿命を分離。
- ジョブ単位で停止/再開/復旧。
- fail-closed。

## subprocess
- `shell=True`禁止。
- executableと引数配列を明示。
- stdout = JSON Lines protocol専用。
- stderr = ログ。
- 終了コード確認。
- timeout/停止/cleanupを設計する。

## 成果物
途中成果物は `.partial` またはジョブworkspaceへ出す。
schema/内容/必要ファイルを検証後に正式化。
正式成果物以外を完了扱いしない。

## ID/時刻
- 永続JSONは `schema_version` を持つ。
- 区間時刻は原則整数ms。
- 候補ID等は決定的ID（例: UUIDv5）を使用可能。

## 配置
- Python/FFmpeg/AIモデルの開発時配置と製品配布時配置を分離して定義する。
- 配置方式はStage Gateで正本化する。
- App Sandbox採否、Security Scoped Bookmark等の外部ストレージアクセス方式もGateで確定する。

## 初期版の軽量化制約
- 同時解析jobは原則1件。
- Pythonを常駐daemon化しない。
- 永続DBを必須にせずJSON＋フォルダを基本とする。
- SDカードへの中間I/Oを抑え、Mac側workspaceを優先する。
- AI modelは必要時にloadし、不要後に解放可能な構造にする。
- 長尺処理はchunk/stream化可能な構造にする。
