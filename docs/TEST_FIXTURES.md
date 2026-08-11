# TEST_FIXTURES.md

## 用途
再現可能な小さいテストデータを使用し、毎回大きな実動画を必要としない。

fixture候補:
- silence WAV
- tone/synthetic speech-like WAV
- short valid WAV
- malformed WAV
- short valid video
- video without audio
- corrupted/unsupported media
- valid/invalid JSON Lines
- valid/invalid schema JSON
- partial artifacts
- source-changed job metadata

## 重要
人工音声/人工fixtureはpipeline、error handling、schema、VAD基本挙動等の検証用。
人物一致閾値、人物不明精度、実人物識別精度、実環境品質閾値へ転用禁止。

実人物データが必要なGateでは、ユーザーが用意した適切なラベル付きローカルデータを使う。
fixtureに個人データを無断追加しない。
