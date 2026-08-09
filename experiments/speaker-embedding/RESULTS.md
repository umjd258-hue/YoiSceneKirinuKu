# Speaker Embedding 技術検証結果

## 総合判定

第8A開始Gateに必要な候補方式の限定的な技術成立性を確認した。SpeechBrain ECAPA-TDNN候補は、取得後のローカルCPU推論で16kHz・モノラル人工音声から再現可能な192次元Embeddingを生成できた。L2正規化したsample Embeddingの算術平均を再度L2正規化するcentroidも機械的に構成できた。

この結果は人工合成音声2話者・限定環境での成立確認であり、実人物に対する識別精度、人物一致閾値、完成版のモデル同梱方式を確定しない。

## 検証環境と候補

- Python: 3.13系の実験専用venv（system site packages利用）
- SpeechBrain: 1.0.3
- PyTorch: 2.8.0
- FFmpeg: 8.1.2
- Model: `speechbrain/spkrec-ecapa-voxceleb`
- Revision: `0f99f2d0ebe89ac095bcc5903c4dd8f72b367286`
- Model card license表示: Apache-2.0
- 実験実行: CPU
- 入力: macOS標準音声KyokoとEddyで作成した人工音声のみ

モデルは実験時に公式Hugging Faceリポジトリから取得した。SpeechBrainの `savedir` はグローバルHugging Face cacheへのsymlinkを生成したため、これは本番配置方式として採用しない。モデル取得後の品質・長時間probeは `HF_HUB_OFFLINE=1` で実行した。

## Embedding結果

- shape: `(192,)`
- dtype: float32
- 全要素有限値: 成立
- L2正規化: 成立
- 同一入力の再実行最大絶対差: `0.0`
- 初回モデル読込み: 約13.85秒（cacheおよび実験環境依存）
- 約4.7〜5.2秒音声の推論: 約0.025〜0.034秒／件

人工音声で観測したcosine similarity:

| 比較 | 実測値 |
|---|---:|
| Kyoko別文 | 0.8813 |
| Eddy別文 | 0.9095 |
| Kyoko/Eddy同文 | 0.1962 |
| Kyoko/Eddy別文 | 0.2357 |
| 2 sample centroid同士 | 0.2256 |
| Kyoko各sample/centroid | 0.9699 |

これらは人工音声での傾向確認値であり、人物一致閾値やUI表示変換へ使用しない。

## 入力長と最低品質

同じ約5.1秒音声を短縮してfull Embeddingと比較した。

| 長さ | fullとのcosine similarity |
|---|---:|
| 0.5秒 | 0.6148 |
| 1.0秒 | 0.6307 |
| 2.0秒 | 0.9248 |
| 3.0秒 | 0.9712 |
| 4.0秒 | 0.9856 |

3秒以上で限定入力に対する安定傾向が確認できたため、登録入力の最低長候補を3,000msとした。10秒、30秒、60秒の繰返し人工音声でも192次元有限値を生成でき、CPU推論時間はそれぞれ約0.050秒、0.139秒、0.277秒だった。初期版の操作範囲と処理量を限定する上限として30,000msを採用し、60秒の成立値を本番上限にはしない。

無音でもモデル自体は有限Embeddingを返したため、Embedding生成前の明示的な無音検査が必須である。元音声を20／30／40dB減衰しても人工音声上ではEmbedding生成できたが、実収録ノイズを検証していない。最低安全条件として、全sampleが0、RMS -60dBFS以下、peak -40dBFS以下を拒否する。この閾値は人物一致や結果画面の音声品質閾値へ転用しない。

## 決定に使える範囲

- `source.wav`: 16kHz、mono、PCM signed 16-bit little-endian
- sample Embedding: 192次元float32、L2正規化、`.npy`、pickle禁止
- Embeddingと元WAV SHA-256、model ID、revisionをメタデータで結び付ける
- 複数sample: 各sampleをL2正規化し、算術平均後に再L2正規化したcentroid
- centroidは派生値として保存せず再計算する
- 3,000〜30,000msおよび最低振幅検査を登録入力Gateに使う
- モデルは実行中に取得せず、起動前にローカル配置を検証する

## 未検証・未決定

- 実人物の同一人物／別人物比較
- 雑音、残響、複数話者、方言、年齢、マイク差、端末差
- 人物一致閾値および◎／○／△変換
- 外れ値sampleの検出・除外、重み付け
- VADと人物登録品質検査の連携
- 完成版Python、SpeechBrain、PyTorch、モデルの配置・同梱方式
- App Sandbox下でのモデル読込み
- モデル更新方針
- 長時間連続実行時のmemoryとthermal挙動

人物一致とUI変換は第15開始Gate、完成版同梱とSandboxは第22開始Gateまで未決定とする。

## 警告

SpeechBrain 1.0.3とtorchaudio 2.8.0の組合せでは、torchaudio backendおよびAMP APIの将来廃止警告が出た。今回の推論は成功したが、完成版依存を固定する際に互換性を再検証する必要がある。
