# VAD候補方式 技術検証結果

## 総合判定

外部アクセスなしの人工WAV比較では、Python標準ライブラリの固定frame RMS方式とローカルFFmpeg 8.1.2の`silencedetect`が、無音、2区間、-40 dBFSの小音量区間、-55 dBFSの低レベルnoise、30ms短音の全期待結果に3回とも一致した。壊れたWAVと8kHz WAVも両方式が`vad_input_invalid`として拒否できた。

第11段階では、追加依存やFFmpeg subprocessを増やさず、正式`analysis.wav`を直接検証・逐次処理できるPython frame RMS方式を採用する。これは音声活動の軽量な一次検出であり、人の声とBGM・環境音を識別するAIではない。人物判定、音声品質判定、候補区間生成の代替にはしない。

## 実験条件

- 入力: 16,000 Hz、mono、PCM s16leの人工WAV
- frame: 30ms
- activity判定: frame RMSが-45 dBFS以上
- 最小連続activity: 90ms
- 各方式の処理時間: 同じ2秒WAVを7回測定
- 全実験を3回実行し、検出結果の再現を確認

上記数値は第11段階の一次VAD条件としてのみ採用する。人物一致、◎／○／△、第12段階の候補結合・分割・最小候補長へ転用しない。

## 候補比較

| 候補 | 全人工ケース | 2秒処理の最終測定 | 判定 |
|---|---:|---:|---|
| Python frame RMS | 5/5成功 | 中央値1.192ms（1.176〜1.227ms） | 採用 |
| FFmpeg `silencedetect` | 5/5成功 | 中央値20.469ms（19.460〜20.872ms） | fallback候補。追加processとstderr解析が不要なため本体では不採用 |
| `torchaudio.functional.vad` 2.8.0 | 今回の2区間人工信号を既定条件で検出せず | 未測定 | 全activity区間一覧を返すAPIではなく、第11段階の責務に不適合 |

## 判定条件

- frame境界はサンプル位置から整数ミリ秒へ変換する。
- 最終frameは短くても処理し、連続するactive frameだけを一つのメモリ内区間として表現する。
- 90ms未満の連続activityは第11段階のVAD結果へ含めない。
- 発話0件は正常結果でありerrorにしない。
- 候補同士の結合、間隔補完、前後余白、候補長による分割は第12段階まで行わない。

## 限界と未検証事項

- 人工toneと人工noiseだけの成立確認であり、実人物、BGM、SE、複数話者、残響、端末差に対する精度は未検証である。
- RMS方式は人の声と同程度以上の非音声をactivityとして検出し得る。後段の人物判定・品質判定で安全に区別する必要がある。
- 正式な`vad.json` schema、再利用・正式化、候補ID、候補結合・分割規則は第12開始Gateまで未決定とする。
- 本番配布時のPython配置とApp Sandbox下の挙動は第22開始Gateまで未決定とする。

実測詳細はGit管理外の`artifacts/report.json`に記録した。
