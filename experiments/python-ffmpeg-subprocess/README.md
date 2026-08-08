# Python → FFmpeg subprocess 技術検証

PythonからローカルのFFmpeg／ffprobeを、shellを介さず引数配列で起動できるか確認するための隔離実験です。

## 検証範囲

- FFmpeg／ffprobeのローカル存在とversion
- `shell=False` と引数配列による起動
- 日本語・空白を含むファイルパス
- stdout／stderr／終了コードの分離
- 起動失敗と起動後FFmpegエラーの区別
- ffprobe JSONのparse
- ファイル存在・非空、video／audio stream、正のdurationの機械検証

## 対象外

- FFmpeg／ffprobe／Pythonの最終配置・同梱方式
- App SandboxおよびSecurity-Scoped Bookmarkの採否
- 本番codec、本番FFmpeg引数、解析用WAV仕様、MP4保存方式
- FFmpeg停止signal、猶予時間、強制終了方式、Process group管理

人工メディアと具体的なFFmpeg引数は技術検証専用です。本番仕様へ転用しません。生成物は `artifacts/` だけに置き、`-n` により既存ファイルを黙って上書きしません。

外部依存および外部アクセスは使用しません。
