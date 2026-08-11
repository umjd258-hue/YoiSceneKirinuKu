# DATA_CONTRACTS.md

UTF-8 JSON、`schema_version`、整数ms、strict validation、fail-closed。
partialを正式データとして読まない。

## job workspace例
`Jobs/<job_id>/`
- `job.json`
- `source/`
- `analysis/`
  - `analysis.wav`
  - `vad.json`
  - `speaker_candidates.json`
  - `speaker_matches.json`
  - `quality.json`
  - `result.json`
- `logs/`
- `tmp/`
- `export/`

## allowlist
job復旧時に認識する成果物名はStageごとに明示的allowlistへ追加する。
未知ファイルを正式成果物として信用しない。

## character
`Characters/<character_id>/`
- `character.json`
- `samples/<sample_id>/sample.json`
- sample audio
- embedding

## character.json
- schema_version
- character_id
- display_name
- sample_ids
- embedding metadata
- created_at
- updated_at

## sample.json
- schema_version
- sample_id
- character_id
- source metadata
- selected_range_ms
- validation state
- embedding reference
- created_at

## Embedding metadata
- model_id
- model_version
- dimension
- normalization
- generation parameters
- source sample ids

モデル/version/dimension等が変わった場合は再生成判定を行う。

## vad.json
- schema_version
- source fingerprint
- sample_rate
- frame settings
- VAD parameters
- segments[start_ms,end_ms]

## speaker_candidates.json
- schema_version
- candidate_id
- start_ms
- end_ms
- generation parameters
- source vad reference

candidateのpadding/merge/split条件を保存する。

## speaker_matches.json
- candidate_id
- compared character ids
- raw score
- score definition/version
- threshold version（閾値確定後）
- final label

## result.json
- candidate_id
- character_id or unknown
- start_ms/end_ms
- match display
- quality display
- preview metadata
- export selectionのownershipはUI状態と永続結果を分離して定義

## migration
schema version変更時は、
- read compatibility
- migrate
- regenerate
- unsupported
のどれかを明示する。
黙って旧schemaを書き換えない。
