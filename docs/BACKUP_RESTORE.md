# BACKUP_RESTORE.md

人物登録は再作成コストが高いため、バックアップ対象として扱える設計を許可する。

候補対象:
- Characters/
- character.json
- sample.json
- 登録sample
- Embedding
- model/schema metadata

復元時:
- schema version検証
- model compatibility検証
- embedding dimension/normalization検証
- 非互換Embeddingは再生成対象
- 壊れたbackupを部分的に正式化しない

解析job/tmp/log/exportは人物登録backupとは分離する。
バックアップ機能を製品UIへ実装するかは必要性を確認してから決め、勝手にscopeを拡大しない。
