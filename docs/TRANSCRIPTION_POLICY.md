# TRANSCRIPTION_POLICY.md — 文字起こし方針

## 現行正本
文字起こし/ASRは、本製品の必須解析パイプラインには含めない。

人物判定の主経路は:
VAD → candidate → Speaker Embedding → speaker matching。

理由:
- 現在の人物識別目的に必須ではない。
- ASRモデルを追加すると容量・処理時間・依存・Gateが増える。
- 利用上限/実装複雑性を増やさず、まず音声特徴による人物判定を完成させる。

## 将来
文字起こしが品質や操作性に明確な利益を持つと検証された場合のみ、
独立した仕様変更として追加する。
その場合はASR model、timestamp schema、配置、性能、error code、Stage/Gateを先に正本化し、
既存Stageへ無断で混入させない。
