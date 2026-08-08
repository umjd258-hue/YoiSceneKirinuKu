# stop.requested + FFmpeg 停止 技術検証

Python が実験用 `stop.requested` を検知し、実行中の FFmpeg へ候補となる終了要求を送り、停止後検証を経て停止完了を分類できるかを確認する隔離実験です。

この実験は `subprocess.Popen(..., shell=False)` と引数配列を使用し、ユーザー動画や外部ストレージにはアクセスしません。生成物は `artifacts/` 内だけに置きます。

## 実行

```sh
python3 experiments/stop-requested-ffmpeg/stop_requested_ffmpeg_experiment.py \
  --ffmpeg /absolute/path/to/ffmpeg \
  --ffprobe /absolute/path/to/ffprobe
```

## 注意

`Popen.terminate()`、実験用の猶予時間・deadline・poll間隔・人工メディア条件は技術成立性を調べる候補値です。本番のsignal、猶予時間、強制終了、Process group、FFmpeg引数、保存方式、停止通信schemaを決定するものではありません。deadline後の `terminate()` / `kill()` は実験後始末専用です。
