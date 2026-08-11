# IPC_PROTOCOL.md

Swift↔Pythonは1行1JSONのJSON Lines。

## 共通Envelope
全messageの必須key:
- `protocol_version`
- `type`
- `request_id`
- `sequence`
- `payload`

## type
- request
- progress
- error
- finished

## request
コマンド名とpayloadを含む。
Swiftは1 requestごとに一意request_idを生成。

## progress
- stage
- completed
- total
- message_code（必要時）
数値の意味をStageごとに固定する。

## error
- error_code
- recoverable
- details_ref（必要時）
生tracebackをprotocol本文の正式契約にしない。

## finished
成功・失敗・停止のterminal通知は、既存の`finished(outcome)`方式を使用する。停止用の独立eeventは追加しない。

## ownership
- Swift Serviceがrequest IDの生成、`Process`、stdin送信、Envelope・sequence・terminalの検証を所有する。
- Pythonがeventを生成する。
- stdoutはJSON Lines protocol専用、stderrはログ専用とする。

## parser
- 1行ずつstrict parse。
- JSONでないstdoutはprotocol violation。
- stdoutにデバッグprintしない。
- stderrはログ専用。
