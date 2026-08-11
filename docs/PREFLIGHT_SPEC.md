# PREFLIGHT_SPEC.md

## 目的
解析開始前に、入力動画・保存先・必要実行環境が安全に利用できるか確認する。

## 最低確認
- source存在
- regular fileであること
- 読取可能
- 対応拡張子/コンテナ
- 基本duration取得可能
- audio stream存在
- duration > 0
- 保存先存在/作成可能
- 必要空き容量の最低確認
- FFmpeg実行可否
- Python実行可否
- 必要モデル/スクリプト存在
- 外部ストレージのbookmark/アクセス有効性

## 出力
成功時は正規化されたPreflight結果。
失敗時は安定error code。

## 主なerror code
- PREFLIGHT_SOURCE_MISSING
- PREFLIGHT_SOURCE_UNREADABLE
- PREFLIGHT_UNSUPPORTED_MEDIA
- PREFLIGHT_NO_AUDIO_STREAM
- PREFLIGHT_INVALID_DURATION
- PREFLIGHT_OUTPUT_UNAVAILABLE
- PREFLIGHT_INSUFFICIENT_SPACE
- PREFLIGHT_PYTHON_UNAVAILABLE
- PREFLIGHT_FFMPEG_UNAVAILABLE
- PREFLIGHT_MODEL_UNAVAILABLE
- PREFLIGHT_STORAGE_ACCESS_DENIED

具体的schemaはStage 4で正本化する。
