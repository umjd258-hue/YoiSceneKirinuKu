# stop.requested + FFmpeg 停止 技術検証結果

## 総合判定

今回の限定条件では、Python が実験用 `stop.requested` を検知し、対象の `Popen` インスタンスへ候補となる終了要求を送り、FFmpeg終了後の状態検証を経て停止完了を分類する技術成立性を確認できた。必須ケースはすべて合格した。

これは本番停止契約の確定ではない。今回使用した `Popen.terminate()`、時間値、人工メディア、codec、FFmpeg引数は実験用であり、本番仕様へ転用しない。

## 実行環境

- Python: `3.13.14`
- Python実行ファイル: `/Library/Frameworks/Python.framework/Versions/3.13/bin/python3`
- FFmpeg: `8.1.2`
- FFmpeg入力パス: `/opt/homebrew/bin/ffmpeg`
- FFmpeg解決先: `/opt/homebrew/Cellar/ffmpeg/8.1.2_1/bin/ffmpeg`
- ffprobe: `8.1.2`
- ffprobe入力パス: `/opt/homebrew/bin/ffprobe`
- 外部アクセス・外部依存追加: なし

上記のパスとversionは今回の検証環境の記録であり、本番配置・同梱方式を決定しない。

## 実験条件

- 正常完了ジョブduration: 2.0秒
- 実行中停止ジョブduration: 10.0秒
- 停止要求作成まで: 0.5秒
- `stop.requested` poll間隔: 0.05秒
- ケースdeadline: 15.0秒
- 実験上のterminate猶予: 3.0秒
- 人工入力: FFmpeg `lavfi` の映像・音声
- 人工出力: Matroska、mpeg4映像、aac音声

これらはMacBook Air M4上で短時間に成立性を確認するための実験値であり、本番のpoll間隔、deadline、猶予時間、codec、出力形式、FFmpeg引数ではない。

## ケース結果

### 正常完了

- 結果: 合格
- FFmpeg return code: 0
- partial: FFmpeg終了後に存在・非空を確認
- 最小メディア検証: ffprobe return code 0、video streamあり、audio streamあり、duration 2.021秒
- 正式化: 上記検証後にだけ実験用正式成果物へrename
- 実行後状態: partialなし、正式成果物あり
- 次工程: 検証・正式化後にだけ開始扱い
- 子プロセス残存: なし

### FFmpeg開始前停止

- 結果: 合格
- `stop.requested` をFFmpeg起動前に検知
- FFmpeg: 起動していない
- partial／正式成果物: ともになし
- 次工程: 開始していない
- 分類: ユーザー停止

### FFmpeg実行中停止

- 結果: 合格
- FFmpeg return code: 255
- 終了要求: stop検知後、対象の `Popen` インスタンスだけへ `terminate()` を実行
- イベント順序: 次の順序を機械的に確認

  1. `stop_requested_detected`
  2. `ffmpeg_exit_observed`
  3. `post_stop_state_verified`
  4. `stop_complete_classified`

- partial: 存在・非空だが正式化していない
- 正式成果物: なし
- 次工程: 開始していない
- 子プロセス残存: なし
- 分類: 停止要求がFFmpeg終了より先に検知され、停止後状態検証を通過したためユーザー停止

return code 255だけを停止判定の根拠にはしていない。FFmpeg終了だけでも停止完了扱いにしていない。

### FFmpeg意図的異常終了

- 結果: 合格
- FFmpeg return code: 8
- `stop.requested`: なし
- partial／正式成果物: ともになし
- 次工程: 開始していない
- 子プロセス残存: なし
- 分類: FFmpeg異常終了

## 横断確認

- 停止要求前と停止要求後を状態で区別できた
- 停止要求後に新しい処理を開始しなかった
- 停止・異常終了時にpartialを正式成果物へrenameしなかった
- 正常完了も終了コード0だけでは正式化しなかった
- 正常完了、ユーザー停止、FFmpeg異常終了を区別できた
- 全ケースで対象FFmpegの終了を `Popen` から確認できた
- 全ケースで子プロセス残存なし
- deadline超過なし
- ハングなし
- 実験後始末用terminate: 不要
- 実験後始末用kill: 不要
- `pkill`、プロセス名による一括終了、Process groupへのsignal: 未使用

## 未検証・未決定

- 本番で使用する停止signal
- 停止猶予時間と強制終了までの時間
- 強制終了の採否と方式
- Process group／孫プロセス管理
- SwiftからPythonへの停止通信schema
- `finished`／停止完了eventの正式形式
- `stop.requested` の本番での作成・所有・削除・stale判定
- 実際の長時間・高負荷FFmpeg処理での停止
- 複数のFFmpeg子プロセスやさらに下位の子プロセスがある場合の停止
- 停止と自然終了・異常終了が競合する境界条件
- partialの検証・保持・清掃・reconciliationの正式契約
- 本番FFmpeg引数、codec、解析用WAV、完成MP4保存方式
- App Sandbox／Security-Scoped Bookmark下での停止動作
- アプリ・Pythonの強制終了後の復旧

これらは対応する開始Gateまで未決定とし、Codexが今回の結果から推測して確定してはいけない。

## 第14開始Gate補足：process group停止

`process_group_stop_experiment.py`を同一条件で2回実行し、各実行で次を3試行ずつ確認した。

- FFmpegを新しいsession／process groupで起動し、そのgroupだけへ`SIGTERM`を送った6試行は、return code 255、強制終了なし、process残存なし、partialあり、正式成果物なしだった。
- `SIGTERM`を無視する人工親子processを同じgroupで起動した6試行は、5秒猶予後に同じgroupだけへ`SIGKILL`を送り、return code -9、親子とも残存なしだった。
- 全12試行が機械判定で合格した。`pkill`、process名検索、他groupへのsignalは使用していない。

実験のpoll 0.05秒、起動deadline 3秒、猶予5秒、強制終了後deadline 10秒、人工FFmpeg引数は検証条件である。第14の初期版契約は別途正本化し、App Sandbox下のsignal／process group成立性と配布構成は未検証のまま第22開始Gateへ残す。
