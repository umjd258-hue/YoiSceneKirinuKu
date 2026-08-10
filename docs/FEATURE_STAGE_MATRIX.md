# FEATURE_STAGE_MATRIX.md — 機能→工程対応表

この表にない製品機能をCodexが独断で追加しない。

## 正本ルール
- Stage番号・Stage Gate・工程の意味は `IMPLEMENTATION_STEPS.md` を正本とする。
- 高リスク工程の細分化は `SUBSTAGE_PLAN.md` を併用する。
- この表は検索・対応確認用の派生表であり、正本のStage意味を変更しない。

| 機能/責務 | 工程 |
|---|---|
| リポジトリ基盤・正本・安全ルール | Stage 1 |
| SwiftUIアプリ骨格 | Stage 2 |
| 設定・保存先・権限基盤 | Stage 3 |
| 動画選択・Preflight・source metadata | Stage 4 |
| job lifecycle/workspace/復旧土台 | Stage 5 |
| Swift↔Python subprocess/JSON Lines通信 | Stage 6 |
| FFmpeg/Python配置Gate | Stage 7A |
| FFmpeg解析用音声抽出・16kHz mono WAV | Stage 7B |
| 人物管理データ基盤・CRUD・ownership | Stage 8 |
| Speaker Embedding技術Gate | Stage 8A |
| sample/source.wav/Embedding永続化 | Stage 8B |
| 複数sample統合・representation再生成 | Stage 8C |
| 新規人物登録UI・既存人物へのsample追加/確認/削除UI | Stage 9 |
| 解析ジョブ統合基盤 | Stage 10 |
| VAD | Stage 11 |
| candidate生成 | Stage 12 |
| candidate Embedding/Speaker Matching基盤 | Stage 13 |
| job停止・協調停止 | Stage 14 |
| 人物一致/unknown判定・表示閾値 | Stage 15 |
| quality feature/品質評価基盤 | Stage 16 |
| quality判定 | Stage 17 |
| result統合/schema/result.json | Stage 18 |
| Results UI/◎○△/理由 | Stage 19 |
| candidate preview/AVPlayer | Stage 20 |
| MP4 export/高品質切り抜き | Stage 21 |
| 保存/partial/finalize/復旧 | Stage 22 |
| エラー表示/診断UI | Stage 23 |
| 使い方・FAQ・設定仕上げ | Stage 24 |
| 性能・長尺・メモリ・軽量化 | Stage 25 |
| SD抜去/スリープ/異常終了等E2E・回帰 | Stage 26 |
| Release/完成条件/最終検証 | Stage 27 |

Stage番号の意味を後から別用途へ再定義しない。変更が必要なら `CHANGE_CONTROL.md` を通す。
