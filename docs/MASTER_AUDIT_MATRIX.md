# MASTER_AUDIT_MATRIX.md — 原本→最終仕様照合

| 領域 | 判定 | 正本 |
|---|---|---|
| 製品目的/完全ローカル | PASS | PRODUCT_SPEC / PRIVACY_AND_LOCAL_ONLY |
| MP4入力/元動画非破壊 | PASS | PRODUCT_SPEC / MEDIA_IO_SPEC |
| UI主要4系統 | PASS | UI_SPEC |
| UI参考画像9枚 | PASS | UI_REFERENCE_INDEX / UI_REFERENCE_AUDIT |
| FFmpeg 7A/7B・人物8A/8B/8C | PASS | SUBSTAGE_PLAN |
| source.wav保護 | PASS | CHARACTER_POLICY |
| Swift↔Python IPC | PASS | IPC_PROTOCOL |
| SD/保存/partial | PASS/Gate管理 | STORAGE_AND_RECOVERY / GATE_REGISTER |
| Sandbox/bookmark | PASS/Gate管理 | SECURITY関連 / GATE_REGISTER |
| Python/FFmpeg | PASS/Gate管理 | MODEL_AND_TOOLING / MEDIA_IO_SPEC / GATE_REGISTER |
| stop/recovery | PASS/Gate管理 | STORAGE_AND_RECOVERY / GATE_REGISTER |
| 全機能→Stage | PASS | FEATURE_STAGE_MATRIX |
| 未決定事項 | PASS | UNDECIDED_REGISTER |
| 完成条件 | PASS | ACCEPTANCE_CRITERIA |
| 利用上限節約/取り違え防止 | PASS | AGENTS / CURRENT_STATUS / GitHub連携文書 |

未決定の技術数値・方式は欠落として推測補完せず、決定期限Stage付きGateで管理する。
