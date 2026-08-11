# DEVELOPMENT_RULES.md

正本:
1. PRODUCT_SPEC
2. UI_SPEC
3. ARCHITECTURE
4. PREFLIGHT_SPEC / IPC_PROTOCOL / DATA_CONTRACTS / ERROR_CODES / STORAGE_AND_RECOVERY / MODEL_AND_TOOLING
5. DEVELOPMENT_RULES
6. IMPLEMENTATION_STEPS
7. CURRENT_STATUS
8. DECISIONS
9. KNOWN_ISSUES

## 取り違え防止
- 現在Stage番号だけでなく目的も照合。
- 後続Stageを先行しない。
- 古い閾値/方式を自動再利用しない。
- schema ownershipを曖昧にしない。
- 未決定はBlocker。

## 利用上限節約
- 必要箇所だけ読む。
- 既知事項を反復しない。
- 1 Stageずつ。
- 同一検証を理由なく繰り返さない。
- 長時間ハングを放置しない。
- 全体テストを儀式的に毎回実行しない。
- ただし必要なGate・検証・データ整合性確認を省略しない。

## Git
- 無関係ファイルを含めない。
- 未追跡README等に触れない。
- push失敗時は停止。

## 追加正本
- ACCEPTANCE_CRITERIA.md
- MEDIA_IO_SPEC.md
- LIFECYCLE_AND_CLEANUP.md
- CHARACTER_POLICY.md
- PRIVACY_AND_LOCAL_ONLY.md
- TRANSCRIPTION_POLICY.md
- DEPENDENCY_VERSIONS.md

## 最終補助正本
SOURCE_OF_TRUTH_MAP / CHANGE_CONTROL / REFERENCE_HARDWARE / PERFORMANCE_BUDGET /
SECURITY_CHECKLIST / TEST_FIXTURES / BACKUP_RESTORE / REVALIDATION_MATRIX を参照する。
