# ERROR_CODES.md

生例外をUI契約にしない。

分類:
- PREFLIGHT_*
- AUDIO_EXTRACT_*
- VAD_*
- CHARACTER_*
- SAMPLE_*
- EMBEDDING_*
- CANDIDATE_*
- SPEAKER_MATCH_*
- QUALITY_*
- RESULT_*
- EXPORT_*
- JOB_*
- PROCESS_*
- STORAGE_*
- IPC_*

ルール:
- codeは安定させる。
- UI文言と内部詳細を分離。
- 未確定codeを推測で増やさない。
- retryable/recoverableの意味を明示する。
