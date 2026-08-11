# MEDIA_IO_SPEC.md — 動画入出力仕様

## 入力
初期版の正式対応形式は MP4 とする。
拡張子だけで判断せず、FFmpeg/AVFoundationで実読取を確認する。
MOV/MKV等は初期版の正式対応へ勝手に追加しない。将来対応は独立した仕様変更とする。

## 出力
正式成果物はMP4を基本とする。

Stage 21 Gateで以下を技術検証して決定する。
- stream copy可能条件
- keyframe境界
- 必要時のre-encode
- codec
- pixel format
- fps
- resolution
- audio codec/sample rate/channel
- metadata扱い

原則は元品質を不必要に落とさない。

## ファイル名
正式ルールはStage 21/22で確定する。
最低条件:
- 日本語人物名対応
- macOSで不適切な文字をsanitize
- 長すぎる名前を制限
- 同名衝突時に既存完成ファイルを上書きしない
- candidate/開始時刻等で一意性を確保可能にする
