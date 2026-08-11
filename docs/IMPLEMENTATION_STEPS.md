# IMPLEMENTATION_STEPS.md — 27 Stage + 1 Substage

工程の正本。主工程はStage 1〜27。Stage 7A/7BとStage 8A/8B/8Cは `SUBSTAGE_PLAN.md` に定義する補助Substage。

共通サイクル: Gate確認 → 実装 → 必要最小限の検証 → 差分確認 → 記録 → commit → push → CURRENT_STATUS更新。
Gate未通過なら推測せず停止。

## Stage 1: リポジトリ基盤・正本・安全ルール
Gate: 正本ファイル一覧、Git方針、完全ローカル、元動画非破壊、README非操作を確認。
Input: 仕様書一式。
Output: プロジェクト骨格、正本、CURRENT_STATUS。
Scope: ディレクトリ/文書/Gitルールのみ。
Forbidden: 製品機能実装。
Tests: 文書整合、git diff --check。
Done: 正本が参照可能でCURRENT_STATUSがStage 2を指す。

## Stage 2: SwiftUIアプリ骨格
Gate: macOS deployment target、Bundle ID、基本Navigation方針を確認。
Input: Stage 1正本。
Output: 起動可能なSwiftUIアプリ骨格。
Scope: App entry、基本画面枠、Service分離の土台。
Forbidden: Python/FFmpeg本実装。
Tests: Debug build、起動確認。
Done: アプリが起動し基本Navigationが成立。

## Stage 3: 設定・保存先・権限基盤
Gate: App Sandbox採否、外部ストレージアクセス方式、bookmark方針を決定。
Input: Stage 2。
Output: 設定保存、保存先選択、権限保持。
Scope: 設定/権限のみ。
Forbidden: 解析処理。
Tests: bookmark/再起動/権限失効の関連テスト。
Done: 外部保存先を安全に再利用できる。

## Stage 4: 動画選択とPreflight
Gate: PREFLIGHT_SPECの判定項目/schema/error codeを確定。
Input: 動画URL。
Output: preflight result。
Scope: 読取/metadata/環境確認。
Forbidden: 本解析開始。
Tests: 正常、動画なし、音声なし、読取不可、容量不足等。
Done: fail-closedで解析可否を返せる。

## Stage 5: ジョブ管理・workspace
Gate: job schema、workspace構造、source fingerprint、allowlistを確定。
Input: preflight済み動画。
Output: job metadata/workspace。
Scope: job状態、復旧土台。
Forbidden: AI処理。
Tests: 作成、再読込、source変化、未知成果物。
Done: jobを安全に識別/復旧判定できる。

## Stage 6: Python subprocess/JSON Lines通信
Gate: IPC_PROTOCOLのrequest/progress/error/finished(outcome)契約を確定。
Input: job/request。
Output: 安定JSON Lines通信。
Scope: Process Service/parser。
Forbidden: stdoutデバッグprint、shell=True。
Tests: 正常、malformed line、stderr、非0終了、stop。
Done: Swift↔Python通信がstrictに成立。

## Stage 7: FFmpeg解析用音声抽出
詳細は SUBSTAGE_PLAN の Stage 7A/7B を順に完了する。
Gate: FFmpeg/Python配置、出力WAV仕様、再利用判定を確定。
Input: source動画。
Output: 16kHz mono analysis.wav。
Scope: 音声抽出のみ。
Forbidden: 元動画変更。
Tests: 正常、音声なし、FFmpeg失敗、partial、再利用。
Done: WAV検証後に正式成果物化。

## Stage 8: 人物管理データ基盤
AI登録部分は SUBSTAGE_PLAN の Stage 8A/8B/8C を順に完了する。
Gate: character/sample schemaとownership、削除規則を確定。
Input: 人物操作。
Output: Characters配下の正式データ。
Scope: CRUD土台。
Forbidden: Embedding生成。
Tests: 作成/更新/削除、孤児sample防止。
Done: 人物/ sampleを整合的に管理可能。

## Stage 8 Substage概要
Stage 8AはSpeaker Embedding技術Gate、Stage 8Bはsample/source.wav/Embedding永続化、Stage 8Cは複数sample統合・再生成を担当する。
各SubstageのGate、成果物、検証範囲は `SUBSTAGE_PLAN.md` を正本とし、Stage 8Cを人物削除Stageへ再定義しない。

## Stage 9: 人物登録SwiftUI
Gate: 動画sampleの区間選択UX、登録error表示を確認。
Input: 人物名、音声/動画sample。
Output: 登録UIとService連携。
Scope: sample追加/確認/削除。
Forbidden: Stage 15閾値。
Tests: UI関連、登録キャンセル、動画区間。
Done: GUIから人物登録が完結。

## Stage 10: 解析ジョブ統合基盤
Gate: Stage 4〜9成果物のownership/呼出順を確認。
Input: source + selected characters。
Output: 実行可能なanalysis job。
Scope: pipeline orchestration。
Forbidden: VAD方式の推測。
Tests: job開始/失敗/再利用。
Done: VAD前まで一貫して進められる。

## Stage 11: VAD
Gate: VAD実装/model、sample rate、frame size、判定params、error codeを人工WAV等で技術検証。
Input: analysis.wav。
Output: vad.json。
Scope: 発話区間検出。
Forbidden: 独自閾値の推測。
Tests: 発話、無音、雑音、短音、失敗。
Done: vad.jsonをstrict生成/検証/復旧できる。

## Stage 12: 候補区間生成
Gate: padding/merge/split/ID生成/partial/復旧契約を確定。
Input: vad.json。
Output: speaker_candidates.json。
Scope: 候補生成。
Forbidden: 人物判定。
Tests: 安定ID、再実行、vad-only復旧、壊れたpartial。
Done: 同入力で安定候補を再生成できる。

## Stage 13: Speaker Matching基盤
Gate: score定義、Embedding比較方式、model互換性を確定。
Input: candidates + registered embeddings。
Output: raw speaker match scores。
Scope: 比較基盤のみ。
Forbidden: 人物一致/unknown閾値確定。
Tests: 同一embedding、別embedding、dimension mismatch、欠損。
Done: raw scoreを再現可能に生成できる。

## Stage 14: 協調停止
Gate: stop request、安全地点、timeout、強制終了、cleanup契約を確定。
Input: running job。
Output: stopped/partial/recoverable state。
Scope: Swift/Python/FFmpeg停止。
Forbidden: 無関係PID kill。
Tests: 各工程停止、cleanup、再開判定。
Done: データ破壊なく停止できる。

## Stage 15: 人物一致・人物不明・表示閾値
Gate: 代表性あるラベル付き実人物データセットを用意。最低でも複数人物、同一/別人物、条件差（雑音/残響/端末差等）を含み、正解ラベルを持つ。
Input: raw scores + validation dataset。
Output: match threshold、unknown rule、display mapping、version。
Scope: 閾値検証/正本化。
Forbidden: 人工音声だけで実人物閾値を決める。
Tests: confusion matrix/誤受入/誤拒否等を記録。
Done: Evidence付きで閾値をDECISIONSへ正本化。

## Stage 16: 品質評価基盤
Gate: 利用可能な明瞭度/他話者/BGM/SE/雑音指標と計算コストを技術検証。
Input: candidate audio。
Output: raw quality features。
Scope: 特徴量生成。
Forbidden: 最終品質閾値の推測。
Tests: 人工/実サンプル、欠損、短区間。
Done: raw featureを安定生成。

## Stage 17: 品質判定契約
Gate: ラベル付き品質データで閾値/表示変換を検証。
Input: raw quality features。
Output: quality decision/display version。
Scope: 品質閾値。
Forbidden: 根拠なし固定値。
Tests: 誤分類傾向記録。
Done: 品質判定を正本化。

## Stage 18: result.json生成
Gate: result schema、grouping/sort、unknown/quality表示、ownershipを確定。
Input: matches + quality + candidates。
Output: result.json。
Scope: 最終解析結果統合。
Forbidden: UI選択状態との責務混同。
Tests: schema、sort、unknown、欠損。
Done: UIがstrictに読める。

## Stage 19: 結果一覧UI
Gate: UI表示契約を確認。
Input: result.json。
Output: 人物別結果一覧。
Scope: grouping、折りたたみ、品質/時刻/選択。
Forbidden: 解析ロジック。
Tests: UI/state。
Done: 候補を安全に閲覧/選択可能。

## Stage 20: AVPlayerプレビュー
Gate: seek精度、候補区間境界、再生停止挙動を確認。
Input: source動画 + selected candidate。
Output: 区間preview。
Scope: 再生確認。
Forbidden: source編集。
Tests: seek、連続候補、境界。
Done: 選択区間を安定確認可能。

## Stage 21: 高品質切り抜き
Gate: stream copy vs re-encode、keyframe制約、品質維持、出力命名規則を技術検証。
Input: user-selected ranges。
Output: export `.partial`。
Scope: 選択区間のみ出力。
Forbidden: 元動画変更、完成ファイル上書き。
Tests: copy/reencode、複数区間、失敗。
Done: partialへ正しく出力。

## Stage 22: 出力正式化・復旧
Gate: 検証項目、atomic rename、衝突名、容量不足、再実行規則を確定。
Input: export partial。
Output: 正式MP4。
Scope: finalize/recovery。
Forbidden: 検証前正式化。
Tests: 破損partial、同名、容量不足、SD抜去。
Done: 完成MP4のみ正式成果物。

## Stage 23: エラー・診断UI
Gate: error code→日本語文言、詳細ログ導線を確認。
Input: stable error codes。
Output: エラー/分析画面。
Scope: 表示/診断。
Forbidden: 生traceback常時表示。
Tests: 主要error code表示。
Done: ユーザーが原因/次行動を理解可能。

## Stage 24: 使い方・FAQ・設定仕上げ
Gate: 日常利用導線と設定項目を確認。
Input: 完成機能。
Output: 使い方/FAQ/設定。
Scope: 補助UI。
Forbidden: 新規解析機能。
Tests: UI確認。
Done: 自分用に迷わず利用可能。

## Stage 25: 軽量化・長尺安定性
Gate: 20分〜2.5時間の代表動画、メモリ/一時容量/再処理計測方法を確定。
Input: 長尺動画。
Output: 性能記録/必要最適化。
Scope: 軽量化。
Forbidden: 品質を壊す安易な省略。
Tests: 長尺、再利用、停止。
Done: M4/32GBで現実的に運用可能。

## Stage 26: 統合・復旧・回帰検証
Gate: end-to-endシナリオ一覧を確定。
Input: 全機能。
Output: 統合検証記録。
Scope: 停止/再開/失敗/SD変化/schema/model mismatch等。
Forbidden: 未記録のテスト省略。
Tests: E2E/回帰。
Done: 主要失敗パターンを含めて整合。

## Stage 27: リリース最終検証
Gate: 完成条件、Release構成、既知問題許容範囲を確定。
Input: Stage 26完了版。
Output: 完成判定。
Scope: 正本整合、Debug/Release、Git、既知問題。
Forbidden: 新機能追加。
Tests: 最終必要検証。
Done: CURRENT_STATUSがComplete、Git clean（意図的未追跡除く）、origin一致。

## Substage正本
Stage 7/8の細分化は `SUBSTAGE_PLAN.md` を優先する。
