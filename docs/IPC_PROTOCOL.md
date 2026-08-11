# IPC_PROTOCOL.md

Swift↔Pythonは1行1JSONのJSON Lines。

## 共通Envelope
必須候補:
- `schema_version`
- `type`
- `request_id`
- `job_id`
- `timestamp_ms`（必要時）

## type
- request
- accepted
- progress
- result
- error
- stopped
- log_ref

## request
コマンド名とpayloadを含む。
Swiftは1 requestごとに一意request_idを生成。

## progress
- stage
- completed
- total
- message_code（必要時）
数値の意味をStageごとに固定する。

## result
- success=true
- payload
- artifact references

## error
- success=false
- error_code
- recoverable
- details_ref（必要時）
生tracebackをprotocol本文の正式契約にしない。

## stop
Swiftから協調停止要求を送る。
Pythonは安全地点で停止し、`stopped`を返す。
強制終了は最終手段。

## parser
- 1行ずつstrict parse。
- JSONでないstdoutはprotocol violation。
- stdoutにデバッグprintしない。
- stderrはログ専用。

具体キーとownershipはStage 6で確定する。
