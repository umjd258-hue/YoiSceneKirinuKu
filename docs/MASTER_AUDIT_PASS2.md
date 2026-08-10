# MASTER_AUDIT_PASS2.md
高リスク領域の第2巡監査。

## SD/保存
PASS: 元動画非破壊、選択candidateのみ、人物別保存、完成MP4上書き禁止、partial分離、SD切断時は完成扱い禁止、自動再開禁止。
Gateへ: volume識別、bookmark実機復元、一部保存済みからのcandidate単位再保存。

## Sandbox
PASS: security-scoped access方針、current_jobのapp-owned保存。
Gateへ: Sandbox採否、外部SD、再起動bookmark、bundled Python/FFmpeg subprocessの実機検証。

## Python/FFmpeg
PASS: system Python/PATH依存回避、完全ローカル方針、引数配列、partial検証後final。
Gateへ: exact version/package/build、配布版offline、FFmpeg stop/watchdog、ライセンス。

## stop/recovery
PASS: stop要求と完了の分離、partial非完成、decode失敗fail-closed、fingerprint mismatch時自動再開禁止。
Gateへ: stop.requested ownership、safe boundary、FFmpeg停止、Python polling、fingerprint algorithm、人物revision。

## 結論
Stage 1から文書/UI骨格を進めるBlockerは現時点でなし。ただしGate未決定のまま該当高リスクStage本実装へ進まない。
