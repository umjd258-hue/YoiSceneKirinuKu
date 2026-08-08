# Python → FFmpeg subprocess 検証結果

## 実行環境

- Python入力パス: `/Library/Frameworks/Python.framework/Versions/3.13/bin/python3`
- Python version: 3.13.14
- FFmpeg入力パス: `/opt/homebrew/bin/ffmpeg`
- FFmpeg実体パス: `/opt/homebrew/Cellar/ffmpeg/8.1.2_1/bin/ffmpeg`
- FFmpeg version: 8.1.2
- ffprobe入力パス: `/opt/homebrew/bin/ffprobe`
- ffprobe実体パス: `/opt/homebrew/Cellar/ffmpeg/8.1.2_1/bin/ffprobe`
- ffprobe version: 8.1.2
- 外部依存追加: なし
- 外部アクセス: なし

入力パスと実体パスは今回のローカル環境の記録であり、本番配置・同梱方式を決定しない。

## 起動方式

Python標準ライブラリの `subprocess.run()` へ、実行ファイルを先頭要素とする文字列配列を渡した。全呼出しで `shell=False` を明示し、シェルコマンド文字列の評価は使用しなかった。

## 実行した引数配列

### 人工メディア生成

```text
[
  "/opt/homebrew/Cellar/ffmpeg/8.1.2_1/bin/ffmpeg",
  "-hide_banner", "-nostdin",
  "-f", "lavfi", "-i", "color=c=black:s=160x90:r=10:d=2",
  "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000:duration=2",
  "-c:v", "mpeg4", "-c:a", "aac", "-shortest", "-n",
  ".../artifacts/日本語 空白/人工 テスト動画.mp4"
]
```

### 日本語・空白パス読取り

```text
[
  "/opt/homebrew/Cellar/ffmpeg/8.1.2_1/bin/ffmpeg",
  "-hide_banner", "-nostdin", "-i",
  ".../artifacts/日本語 空白/人工 テスト動画.mp4",
  "-f", "null", "-"
]
```

### 起動後FFmpegエラー

```text
[
  "/opt/homebrew/Cellar/ffmpeg/8.1.2_1/bin/ffmpeg",
  "-hide_banner", "-nostdin", "-i",
  ".../artifacts/日本語 空白/存在しない 入力動画.mp4",
  "-f", "null", "-"
]
```

### ffprobe

```text
[
  "/opt/homebrew/Cellar/ffmpeg/8.1.2_1/bin/ffprobe",
  "-v", "error",
  "-show_entries", "format=duration:stream=index,codec_type,codec_name",
  "-of", "json",
  ".../artifacts/日本語 空白/人工 テスト動画.mp4"
]
```

## 検証結果

### 正常ケース

- 人工メディア生成終了コード: `0`
- 生成済みメディア読取り終了コード: `0`
- stdoutとstderr: 別々に取得
- FFmpegの処理情報を含むstderrを、終了コードだけで失敗扱いしなかった。

### 日本語・空白を含むパス

- 生成、FFmpeg読取り、ffprobe解析のすべてに成功した。
- パスは引数配列の1要素として渡され、分割や文字化けは確認されなかった。
- `-n` を指定し、既存ファイルを黙って上書きしないようにした。

### 起動失敗

- 存在しないFFmpeg実行ファイルパスを指定した。
- `FileNotFoundError` を取得し、`not_started_file_not_found` と分類した。
- FFmpegプロセスは起動しておらず、終了コードは存在しない。

### 起動後FFmpegエラー

- 実在するFFmpegへ存在しない入力ファイルを渡した。
- FFmpegは起動し、終了コード `254` と291 bytesのstderrを取得した。
- `started_nonzero_exit` と分類し、起動失敗と区別した。

### ffprobe JSON

- ffprobe終了コード: `0`
- JSON parse: 成功
- video stream: あり
- audio stream: あり
- duration: `2.0` 秒、0より大きい

### 成果物

- ファイル存在: 確認
- ファイルサイズ: 20,961 bytes、非空
- FFmpegによる全体読取り: 成功
- ffprobeによるstreamとdurationの検証: 成功

終了コード0だけでは成功扱いせず、ファイルの存在・非空、FFmpeg読取り、ffprobe JSON、video／audio stream、正のdurationをすべて確認した。

## 判定

限定した検証環境では、PythonからFFmpeg／ffprobeをshellなしの引数配列で起動し、日本語・空白を含むパス、stdout／stderr、終了コード、起動失敗と起動後エラー、ffprobe JSON、成果物の実体を扱える技術的成立性を確認した。

人工メディアのcodec、duration、解像度、sample rate、FFmpeg引数は技術検証専用であり、本番仕様へ転用しない。

## 引き続き未検証・未決定

- FFmpeg／ffprobeの最終配置・同梱方式
- Pythonの最終配置・同梱方式
- App Sandbox採否
- Security-Scoped Bookmark採否
- 本番codecと本番FFmpeg引数
- 解析用WAVの正式仕様
- MP4保存方式
- FFmpeg停止signal
- 猶予時間・強制終了方式
- Process group管理
- 長時間・高負荷処理、停止、異常中断時の挙動
