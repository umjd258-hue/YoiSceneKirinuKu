# CURRENT_STATUS.md

更新日: 2026-08-11

この文書は、Stage体系整合化commit `2c02aef96a3a3d6b9351f893e710dc96726f3bb9` 後の現行Stage定義に対し、Git履歴と実在成果物を照合して復元した進捗正本である。旧Stage番号は機械変換せず、`IMPLEMENTATION_STEPS.md` と `SUBSTAGE_PLAN.md` の現在の完了条件で再判定した。

## 現在位置

- Current Stage: Stage 3
- Current Substage: なし
- State: Completed
- Current Purpose: 設定・保存先・権限基盤
- Last Confirmed HEAD: `2c02aef96a3a3d6b9351f893e710dc96726f3bb9`
- Next Action: `CURRENT_STATUS.md`を単独commitし、Stage 3関連commitのpush可否を判断する。

## Stage別復元結果

| Stage | 状態 | 根拠 |
|---|---|---|
| Stage 1 リポジトリ基盤・正本・安全ルール | Completed | 初期仕様 `8a14a53`、Stage体系整合化 `2c02aef`、正本・安全ルール・manifestが存在 |
| Stage 2 SwiftUIアプリ骨格 | Completed | `ba9510c`、`YoiSceneKirinuKuApp.swift`、`RootView.swift`、Xcode project、基礎テストが存在 |
| Stage 3 設定・保存先・権限基盤 | Completed | 開始Gateは正式決定済み。設定保存はCompleted（対象なし）。元動画・出力先の明示選択、bookmark永続化、再起動後復元、権限失効・stale・volume UUID不一致時のfail-closed再選択を限定テストで確認済み |
| Stage 4 動画選択とPreflight | Completed | `cff38ff`、`af915ad`、`Preflight.swift`、`preflight.py`、関連テストが存在 |
| Stage 5 ジョブ管理・workspace | Completed | `5f04f63`、`7502951`、`JobManagement.swift`、`analysis_job_runner.py`、関連テストが存在 |
| Stage 6 Python subprocess/JSON Lines通信 | Partial | subprocess検証 `82c3594`、streaming検証 `0dcc1bb` と複数のstrict parserは存在するが、bundled Python exact version/package lockと配布版完全offline構成が未確定 |
| Stage 7 FFmpeg解析用音声抽出 | Partial | Stage 7Aが未完了。Stage 7B相当の解析WAV生成は存在するが、親Stage完了条件を満たさない |
| Stage 7A FFmpeg配置Gate | Partial | Python→FFmpeg検証 `fa590b3` と実行経路は存在するが、配布時FFmpeg/ffprobe exact build/version・配置方式が未確定 |
| Stage 7B 解析用音声抽出 | Partial | `3aa3895`、`044d281`、`AnalysisAudio.swift`、`analysis_audio.py`、関連テストが存在するが、前提のStage 7Aが未完了 |
| Stage 8 人物管理データ基盤・CRUD | Completed | `c922063`、`331c55d`、`1d965ce`、`CharacterRegistration.swift`、`character_registration.py` に作成・追加・読込・削除が存在 |
| Stage 8A Speaker Embedding技術Gate | Completed | 技術検証 `9ced234`、最終検証 `23e66d8`、`experiments/speaker-embedding/` が存在 |
| Stage 8B sample/source.wav/Embedding永続化 | Completed | `c922063`、`331c55d`、`f64c957`。sample単位の `source.wav`、Embedding、metadataの原子的永続化が存在 |
| Stage 8C 複数sample統合・再生成 | Partial | 複数sample追加と読取時centroid生成は `331c55d`、`1a1aeda` に存在するが、model変更時の正式representation再生成契約・実装が完了していない |
| Stage 9 人物登録SwiftUI | Completed | `584262b`、`798540f`、`c922063`、`331c55d`、`1d965ce`。登録・sample追加・確認・削除UIとService連携が存在 |
| Stage 10 解析ジョブ統合基盤 | Partial | job、解析WAV、VAD、候補生成、matchingの各Serviceは存在するが、VAD前までの統一pipeline orchestrationとして完了していない |
| Stage 11 VAD | Completed | `de9b9e0`、`6ab4707`、`7a54fb5`、`VAD.swift`、`vad.py`、関連テストが存在 |
| Stage 12 候補区間生成 | Completed | `e1b5c1c`、`146c58c`、`CandidateGeneration.swift`、`candidate_generation.py`、安定ID・復旧テストが存在 |
| Stage 13 Speaker Matching基盤 | Completed | `eb213aa`、`1a1aeda`、`30903e8`、`SpeakerMatching.swift`、`speaker_matching.py`、raw score生成テストが存在 |
| Stage 14 協調停止 | Completed | `e3ac006`、`947de8d`、`AnalysisStopping.swift`、`analysis_stopping.py`、process group停止実験が存在 |
| Stage 15 人物一致・人物不明・表示閾値 | Blocked | `53a6e8b`。代表性あるラベル付き実人物データ不足のため、人物一致閾値・unknown rule・表示変換を根拠付きで決定できない |
| Stage 16 品質評価基盤 | Not started | raw quality featureの正式実装・成果物が存在しない |
| Stage 17 品質判定契約 | Not started | ラベル付き品質データによる閾値・表示変換の正式記録が存在しない |
| Stage 18 result.json生成 | Not started | 現行schemaに基づく正式 `result.json` 生成実装が存在しない |
| Stage 19 結果一覧UI | Partial | mock UI `4a05dec`、`d2cdff3` と `ResultsView` は存在するが、正式 `result.json` consumerではない |
| Stage 20 AVPlayerプレビュー | Not started | 人物登録用AVPlayerは存在するが、結果candidate境界のpreview完了条件を満たさない |
| Stage 21 高品質切り抜き | Not started | user-selected rangeの正式export実装が存在しない |
| Stage 22 出力正式化・復旧 | Not started | export partialの検証・atomic finalize実装が存在しない |
| Stage 23 エラー・診断UI | Partial | 各Serviceのstable error codeと一部日本語表示は存在するが、横断的な診断UIと主要error code表示が未完了 |
| Stage 24 使い方・FAQ・設定仕上げ | Not started | 対応する正式UI・成果物が存在しない |
| Stage 25 軽量化・長尺安定性 | Not started | 代表長尺動画による性能記録・最適化成果物が存在しない |
| Stage 26 統合・復旧・回帰検証 | Not started | 現行全Stageを対象とするE2E・回帰記録が存在しない |
| Stage 27 リリース最終検証 | Not started | Release完成判定が存在しない |

## Blocker・未決定事項

- Stage 15: 代表性あるラベル付き実人物データが不足している。人工音声2話者の値から人物一致閾値、人物不明判定、表示変換を推測しない。
- Stage 3開始Gate: PASS。初期版App Sandbox無効、外部ストレージはユーザー明示選択のみ、bookmark永続化とfail-closed再選択を正式決定。
- Stage 6/7A: 配布時のPython・FFmpeg・ffprobe exact version/package/buildと完全offline配置が正式未確定。
- Stage 8C: 複数sample representation更新とmodel変更時再生成の正式契約が未完了。
- 既知問題: Xcodeテスト環境下で既存Python subprocess起動が長時間停止する場合がある。Stage 12〜14の記録では、該当Stage固有経路外として切り分け済みだが、全体テスト完走済みとは扱わない。

## 既存未コミット変更

- `CURRENT_STATUS.md`以外にも仕様文書・参考画像等の未コミット変更が存在する。
- `DECISIONS.md` はHEADの過去43記録を完全保持する形で復元済みであり、既存技術判断とStage 15保留理由は維持されている。
- その他の未コミット変更を正しいと仮定せず、監査・適用範囲が確定するまでstage、commit、削除を行わない。

## 検証範囲

- 実施: HEADと作業ツリーの `CURRENT_STATUS.md` 差分、Git log、主要実装・最終検証commit、tracked成果物、現行Stage定義の読み取り照合。Stage 3のbookmark再起動後復元、権限失効、stale、volume UUID不一致、再選択の限定7テスト。
- 未実施: 通常テスト、実データ検証、外部アクセス。
- この復元は過去commitのテスト結果を根拠としており、現作業ツリーの再テスト成功を意味しない。
