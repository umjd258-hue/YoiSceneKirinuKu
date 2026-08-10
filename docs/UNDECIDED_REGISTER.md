# UNDECIDED_REGISTER.md — 未決定事項と決定期限

未決定は「抜け」ではなく、決定期限Stageを持つ管理対象とする。期限を越えて推測実装しない。

| 未決定事項 | 決定期限 |
|---|---|
| App Sandbox正式採否 | Stage 3開始Gate |
| bundled Python exact version/package lock | Stage 6開始Gate |
| packaged appでの完全offline subprocess | Stage 6開始Gate |
| source.wav最低品質/長さ条件 | Stage 8A開始Gate |
| Embedding model/version/preprocess | Stage 8A開始Gate |
| 複数sample representation更新規則 | Stage 8C開始Gate |
| 人物削除rollback/ownership | Stage 8開始Gate |
| FFmpeg/ffprobe exact build/version | Stage 7A開始Gate |
| VAD方式/parameter | Stage 11開始Gate |
| candidate merge/split/padding | Stage 12開始Gate |
| speaker score定義 | Stage 13開始Gate |
| stop polling/safe boundary/process終了 | Stage 14開始Gate |
| 人物一致/unknown閾値 | Stage 15開始Gate。代表的実人物ラベルデータ必須 |
| quality数値閾値 | Stage 17開始Gate |
| ◎/○/△変換 | Stage 17開始Gate |
| export codec/stream copy/re-encode | Stage 21開始Gate |
| 保存先bookmark/volume identity/collision | Stage 22開始Gate |
| performance budget正式値 | Stage 25 |
| Release minimum macOS/Xcode/tool versions | Stage 27 |

決定時はDECISIONSと関連正本を更新し、REVALIDATION_MATRIXを確認する。
