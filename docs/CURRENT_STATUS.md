# CURRENT_STATUS.md

更新日: 2026-08-12

この文書は、Stage体系整合化commit `2c02aef96a3a3d6b9351f893e710dc96726f3bb9` 後の現行Stage定義に対し、Git履歴と実在成果物を照合して復元した進捗正本である。旧Stage番号は機械変換せず、`IMPLEMENTATION_STEPS.md` と `SUBSTAGE_PLAN.md` の現在の完了条件で再判定した。

## 現在位置

- Current Stage: Stage 16
- Current Substage: なし
- State: Completed
- Current Purpose: Stage 15延期中の非依存作業としてraw quality feature基盤を完了する
- Last Confirmed HEAD: `2c02aef96a3a3d6b9351f893e710dc96726f3bb9`
- Next Action: Stage 16変更をcommit対象として分離確認する。

## Stage別復元結果

| Stage | 状態 | 根拠 |
|---|---|---|
| Stage 1 リポジトリ基盤・正本・安全ルール | Completed | 初期仕様 `8a14a53`、Stage体系整合化 `2c02aef`、正本・安全ルール・manifestが存在 |
| Stage 2 SwiftUIアプリ骨格 | Completed | `ba9510c`、`YoiSceneKirinuKuApp.swift`、`RootView.swift`、Xcode project、基礎テストが存在 |
| Stage 3 設定・保存先・権限基盤 | Completed | 開始Gateは正式決定済み。設定保存はCompleted（対象なし）。元動画・出力先の明示選択、bookmark永続化、再起動後復元、権限失効・stale・volume UUID不一致時のfail-closed再選択を限定テストで確認済み |
| Stage 4 動画選択とPreflight | Completed | `cff38ff`、`af915ad`、`Preflight.swift`、`preflight.py`、関連テストが存在 |
| Stage 5 ジョブ管理・workspace | Completed | `5f04f63`、`7502951`、`JobManagement.swift`、`analysis_job_runner.py`、関連テストが存在 |
| Stage 6 Python subprocess/JSON Lines通信 | Completed | Python 3.13.14、第三者package 0件、固定SHA・Sigstore offline検証済みinstallerから製品runtimeを構築し、Bundle固定相対位置へ配置。strict JSON Lines、stdout/stderr分離、malformed・非0終了・stop、stdlib限定、audit hook、network API不使用、固定相対位置起動を確認し、Swift↔Python通信の完了条件を満たした |
| Stage 7 FFmpeg解析用音声抽出 | Completed | Stage 7A/7B完了。検証済みFFmpeg 8.1.2 universal2をBundle固定位置へ組み込み、16kHz mono PCM s16le WAV生成・partial・検証・正式化・再利用・音声なし・FFmpeg失敗を限定検証済み |
| Stage 7A FFmpeg配置Gate | Completed | source署名、固定toolchain、arm64 / x86_64 build、universal2、binary SHA固定、ad-hoc署名、Bundle固定位置相当からの起動、network無効・system frameworkのみ・PATH探索なしを限定検証済み |
| Stage 7B 解析用音声抽出 | Completed | Bundle固定path導出、PythonのBundle配下・通常ファイル・実行権限検証、PATH非依存、既存音声抽出主要ケース、Swift限定テスト、Debug buildがPASS |
| Stage 8 人物管理データ基盤・CRUD | Completed | CRUD責務、Stage 8A/8B、Stage 8Cの複数sample統合・model変更時再生成がすべて完了 |
| Stage 8A Speaker Embedding技術Gate | Completed | 技術検証 `9ced234`、最終検証 `23e66d8`、`experiments/speaker-embedding/` が存在 |
| Stage 8B sample/source.wav/Embedding永続化 | Completed | `c922063`、`331c55d`、`f64c957`。sample単位の `source.wav`、Embedding、metadataの原子的永続化が存在 |
| Stage 8C 複数sample統合・再生成 | Completed | 人物単位の全sample copy-on-write再生成、原子的交換、同一model無変更、失敗・source欠落・品質不適合時の旧データ不変、model不一致拒否、centroid再計算・非永続化を限定検証済み |
| Stage 9 人物登録SwiftUI | Completed | `584262b`、`798540f`、`c922063`、`331c55d`、`1d965ce`。登録・sample追加・確認・削除UIとService連携が存在 |
| Stage 10 解析ジョブ統合基盤 | Completed | Preflight、人物model互換確認・再生成、job作成・正式再開、解析WAV準備・再利用を既存ownerへ委譲するorchestratorを実装。VAD-readyで停止し、terminal jobの原子的交代、fail-closed、再開・失敗を限定検証済み |
| Stage 11 VAD | Completed | `de9b9e0`、`6ab4707`、`7a54fb5`、`VAD.swift`、`vad.py`、関連テストが存在 |
| Stage 12 候補区間生成 | Completed | `e1b5c1c`、`146c58c`、`CandidateGeneration.swift`、`candidate_generation.py`、安定ID・復旧テストが存在 |
| Stage 13 Speaker Matching基盤 | Completed | `eb213aa`、`1a1aeda`、`30903e8`、`SpeakerMatching.swift`、`speaker_matching.py`、raw score生成テストが存在 |
| Stage 14 協調停止 | Completed | `e3ac006`、`947de8d`、`AnalysisStopping.swift`、`analysis_stopping.py`、process group停止実験が存在 |
| Stage 15 人物一致・人物不明・表示閾値 | Blocked | `53a6e8b`。代表性あるラベル付き実人物データ不足のため、人物一致閾値・unknown rule・表示変換を根拠付きで決定できない |
| Stage 16 品質評価基盤 | Completed | PCM/VAD由来raw quality feature、観測不能カテゴリの理由付きunavailable、strict schema、fingerprint再利用、原子的正式化、Swift Service連携を限定検証済み |
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
- Stage 16開始Gate・実装・限定検証はPASS。Stage 15の人物閾値を参照せず、Stage 17の品質閾値を先行決定しない。
- Stage 3開始Gate: PASS。初期版App Sandbox無効、外部ストレージはユーザー明示選択のみ、bookmark永続化とfail-closed再選択を正式決定。
- Stage 6開始Gate: PASS。Python 3.13.14のBundle同梱起動、strict JSON Lines、stdout/stderr分離、audit hook、`lsof -i`5回、stdlib限定、Swift network API不使用を限定検証済み。`lsof -i`は連続監視ではない。
- Stage 7A: PASS。FFmpeg 8.1.2 universal2 build、固定SHA、署名、固定位置相当からのoffline起動を限定検証済み。
- Stage 7B開始Gate: PASS。既存のWAV・partial・正式化・再利用・失敗契約とStage 7Aの固定配置方式が一意に確定済み。
- Stage 8C: PASS。正式契約、本実装、Python限定18テスト、Stage 13 stale拒否テスト、Stage 9エラー連携Swift限定テスト兼Debug buildがPASS。
- 既知問題: Xcodeテスト環境下で既存Python subprocess起動が長時間停止する場合がある。Stage 12〜14の記録では、該当Stage固有経路外として切り分け済みだが、全体テスト完走済みとは扱わない。

## 既存未コミット変更

- `CURRENT_STATUS.md`以外にも仕様文書・参考画像等の未コミット変更が存在する。
- `DECISIONS.md` はHEADの過去43記録を完全保持する形で復元済みであり、既存技術判断とStage 15保留理由は維持されている。
- その他の未コミット変更を正しいと仮定せず、監査・適用範囲が確定するまでstage、commit、削除を行わない。

## 検証範囲

- 実施: HEADと作業ツリーの `CURRENT_STATUS.md` 差分、Git log、主要実装・最終検証commit、tracked成果物、現行Stage定義の読み取り照合。Stage 3のbookmark再起動後復元、権限失効、stale、volume UUID不一致、再選択の限定7テスト。Stage 6のBundle同梱Python 3.13.14起動、strict JSON Lines、stdout/stderr分離、audit hook、`lsof -i`5回、stdlib限定、Swift network API不使用の限定Gate検証。固定artifactのSigstore offline検証、製品Build Phaseによるruntime組込み、Bundle内固定相対位置からの`-I -S`起動、製品probe疎通を確認。
- 未実施: 通常テスト、実データ検証、外部アクセス。
- この復元は過去commitのテスト結果を根拠としており、現作業ツリーの再テスト成功を意味しない。
