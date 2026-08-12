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
- rootは`schema_version: 1`、`job_id`、`contract_version: stage18-result-v1`、入力3成果物のSHA-256 fingerprint、`candidates`だけを持つstrict JSONとする。
- candidateは`candidate_id`、整数`start_ms`／`end_ms`、`match`（`matched`／`unknown`）、nullable `character_id`、`match_reason`、nullable `top_similarity`、`quality`（`excellent`／`good`／`needs_review`）、`quality_reasons`だけを持つ。
- candidateは`start_ms`、`end_ms`、`candidate_id`の昇順で決定論的に並べる。
- previewはsource動画と整数ms境界からStage 20が導出し、export selectionはStage 19 UI状態が所有する。どちらも`result.json`へ永続化しない。
- Stage 19は3入力fingerprintを現行正式成果物と照合してからread-onlyで読み込み、candidate IDとStage 18の順序を変更しない。人物groupは最初に現れるcandidate順、group内は`result.json`順とし、UI選択は最大1件の一時状態とする。

## migration
schema version変更時は、
- read compatibility
- migrate
- regenerate
- unsupported
のどれかを明示する。
黙って旧schemaを書き換えない。
