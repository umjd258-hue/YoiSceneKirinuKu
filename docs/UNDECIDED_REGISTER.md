# UNDECIDED_REGISTER.md — 未決定事項と決定期限

未決定は「抜け」ではなく、決定期限Stageを持つ管理対象とする。期限を越えて推測実装しない。

| 未決定事項 | 決定期限 |
|---|---|
| Embedding model/version/preprocess | Stage 8A開始Gate |
| 人物削除rollback/ownership | Stage 8開始Gate |
| VAD方式/parameter | Stage 11開始Gate |
| candidate merge/split/padding | Stage 12開始Gate |
| speaker score定義 | Stage 13開始Gate |
| stop polling/safe boundary/process終了 | Stage 14開始Gate |
| 人物一致/unknown閾値 | Stage 15開始Gate。代表的実人物ラベルデータ必須 |
| quality数値閾値 | Stage 17開始Gate |
| ◎/○/△変換 | Stage 17開始Gate |
| export codec/stream copy/re-encode | Stage 21開始Gate |
| 保存先collision | Stage 22開始Gate |
| performance budget正式値 | Stage 25 |
| Release minimum macOS/Xcode/tool versions | Stage 27 |

決定時はDECISIONSと関連正本を更新し、REVALIDATION_MATRIXを確認する。
