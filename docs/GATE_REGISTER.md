# GATE_REGISTER.md — 開始Gate完全台帳

## 正本ルール
- Stage番号とGateの意味は `IMPLEMENTATION_STEPS.md` を正本とする。
- Substage Gateは `SUBSTAGE_PLAN.md` と整合させる。
- この台帳はGateの横断確認用であり、正本の工程を再定義しない。

| Gate | 条件 | 事前決定 | 技術検証 | 前提Stage |
|---|---|---|---|---|
| Stage 3 | 保存先・権限基盤を安全に構築可能 | bookmark/権限/保存先方針 | 保存先選択・再取得・失敗系 | 1-2 |
| Stage 4 | 動画をfail-closedで受入判定可能 | MP4/source metadata/preflight条件 | 正常/動画なし/音声なし/読取不可/容量不足 | 1-3 |
| Stage 6 | offline subprocessを安全に構築可能 | Sandbox/Python配置/version/IPC | packaged Swift→Python、JSON Lines、通信なし | 1-5 |
| Stage 7A | FFmpeg実行方式が一意 | 開発時/製品時配置・version・実行方式 | ffmpeg/ffprobe起動・version・offline | 3,6 |
| Stage 7B | 解析用WAVを安全に正式化可能 | 16kHz mono WAV/partial/再利用 | MP4→WAV、音声なし、失敗、partial、再利用 | 4,7A |
| Stage 8A | Speaker Embedding方式を再現可能に決定可能 | model/preprocess/dimension/normalization | 同一入力再現・保存互換・基本cost | 6 |
| Stage 8B | 登録資産を壊さず永続化可能 | source.wav/sample metadata/atomicity | 生成・再読込・失敗・rollback | 8A |
| Stage 8C | 複数sample representationを再現可能に生成可能 | 統合方式/model変更時再生成/品質不足 | 複数sample統合・再生成・不十分sample | 8A,8B |
| Stage 9 | 人物登録UIが正式データ契約だけを操作可能 | 区間選択UX/error/CRUD導線 | 登録・追加・確認・削除・キャンセル | 8,8A-8C |
| Stage 10 | 解析ジョブを既存基盤へ安全に統合可能 | 入出力/ownership/状態遷移 | 正常開始・失敗・再開境界 | 4-9 |
| Stage 11 | VAD方式がローカル利用可能 | implementation/model/parameter | speech/silence/noise/短音/cost | 10 |
| Stage 12 | candidate契約が一意 | padding/merge/split/ID | 境界/再利用/partial | 11 |
| Stage 13 | speaker scoreが再現可能 | model/preprocess/score | same/different synthetic/basic cost | 8A-8C,12 |
| Stage 14 | 協調停止が安全 | stop ownership/poll/safe boundary | Python/FFmpeg停止、partial | 10-13 |
| Stage 15 | 実人物閾値を根拠付き決定可能 | match/unknown/表示変換 | 代表的ラベル付き実人物データ | 13 |
| Stage 17 | 品質閾値を根拠付き決定可能 | feature→quality規則 | 代表的音声で誤判定確認 | 16 |
| Stage 21 | export品質/互換性を決定可能 | copy/reencode/codec | keyframe/音ズレ/品質 | 18-20 |
| Stage 22 | SD保存を安全にfinalize可能 | bookmark/volume/collision/naming | 抜去/容量不足/partial/retry | 21 |
| Stage 25 | 性能値を実測可能 | 測定方法 | 長尺/peak memory/disk/UI | 23-24 |
| Stage 26 | 異常系E2E可能 | test matrix | SD抜去/sleep/crash/recovery | 25 |
| Stage 27 | 完成条件を全て判定可能 | release versions/known issues | acceptance/release/offline | 26 |

Gate未通過なら該当Stage本実装禁止。数値を推測してGateを突破しない。
