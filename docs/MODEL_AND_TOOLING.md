# MODEL_AND_TOOLING.md

## Python
- 開発時Pythonの場所を明示。
- 製品配布時にsystem Python依存するか、bundle/venv等にするかをGateで決定。
- versionを記録。

## FFmpeg
- 開発時と製品配布時の配置方式を明示。
- versionを記録。
- path探索を無制限に行わない。

## AIモデル
- model_id
- version
- file/hash（必要時）
- expected dimension
- preprocessing
- normalization
を記録。

モデル変更時は既存Embedding再生成要否を判定する。

## ネットワーク
製品処理は完全ローカル。
モデルdownload等が必要なら開発準備工程として明示し、実行時必須にしない。
