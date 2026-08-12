# CHARACTER_POLICY.md

## 人物名
内部識別はcharacter_idで行い、display_nameを識別子として使わない。
同名人物を許可するかはUI実装前に決定する。許可する場合もIDで完全分離する。

## sample
極端に短い/長いsampleの正式条件はStage 8A技術検証で決定する。
根拠のない秒数を固定しない。

## 上限
最大人物数/sample数は、性能・UI上の必要性が確認されるまで恣意的な固定上限を設けない。
実用上限が必要になった場合は根拠をDECISIONSへ記録する。

## model更新
embedding metadataのmodel_id/version/dimension/normalization/generation parametersを比較し、
非互換なら古いEmbeddingを使用せず再生成対象とする。
対象人物を現modelで利用する前に、人物単位のcopy-on-writeで全sampleのEmbeddingとmodel metadataを再生成する。
各sampleの `source.wav` とsample IDは維持し、全件の再生成・検証成功後だけ人物ディレクトリを原子的に交換する。
centroidは交換後に全sample Embeddingから再計算し、保存しない。
1件でも再生成失敗、`source.wav` 欠落、確定済み品質条件への不適合、その他の検証失敗があれば旧人物データを変更せず、その人物を現modelでは使用不可とする。
schema version 1かつ同一model metadataの既存データは変更しない。

## source.wav
人物sampleごとに、Embedding再生成の元となる正式登録音声 `source.wav` を保持する。
source.wavはtmpではなく人物登録資産。
人物/sampleの明示削除以外でcleanupしない。
