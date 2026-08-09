# Speaker Embedding 技術検証

第8A開始Gateの判断材料として、SpeechBrain ECAPA-TDNN候補の完全ローカル推論、Embedding再現性、複数sample統合候補、入力音声品質検査を隔離環境で検証する。

本実験は第8A本体ではない。モデル、閾値、統合方式、配置方式を実測前に本番仕様として確定しない。

生成物、仮想環境、取得モデルは `artifacts/` と `.venv/` に限定し、Git管理しない。

## 安全条件

- ユーザー音声を使用しない。
- macOS標準音声で生成した人工音声だけを使用する。
- shell文字列評価を使わない。
- 本体コードと人物データ領域を変更しない。
- モデル取得後の推論はローカルファイルだけを参照する。

## 実行

```sh
.venv/bin/python speaker_embedding_experiment.py
```
