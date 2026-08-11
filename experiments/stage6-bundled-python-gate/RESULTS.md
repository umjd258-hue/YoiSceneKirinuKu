# Stage 6 bundled Python Gate検証結果

## 結果

PASS。

## 検証構成

- Python: `3.13.14`
- 第三者package: 0件
- Python runtimeとStage 6 fixtureを一時app Bundleに同梱
- Foundation `Process`でBundle内の固定相対位置からshellなし起動
- Pythonは`-I -S`で起動し、`PATH=/nonexistent`、`PYTHONNOUSERSITE=1`を使用

## 確認結果

- `protocol_version` / `type` / `request_id` / `sequence` / `payload`だけを必須Envelopeとするstrict JSON Linesのrequest、`progress`、`finished(outcome: succeeded)`が成立した。
- stdoutはprotocol 2行だけ、stderrは固定診断文字列だけで、Swiftが分離検証した。
- Python audit hookのsocket eventは0件で、socket操作発生時はfail-closedとする構成で実行した。
- Swift/Pythonの両processを対象に、観測待機中の`lsof -i`を5回実行し、Internet socketは検出されなかった。
- 同梱stdlibに`site-packages`、wheel、package metadataがないことを静的検証した。
- Swift Gate sourceに対象network API参照がないことを静的検証した。
- PATH探索、実行時download、user site package読込みに依存せず完了した。

## 観測限界

- `sandbox-exec`は実行環境の権限制約、`nettop`は`NStatManagerCreate failed`のため使用できなかった。
- `lsof -i`は反復時点の観測であり、Python外の極短時間socketを連続的に遮断・観測するものではない。本GateではPython audit hookのfail-closed、Swift network API不使用の静的検証、`lsof -i`5回の併用結果として「外部通信なし」を判定した。

## Gate判定

Stage 6開始GateをPASSとする。Stage 6本実装や後続Stageの完了を意味しない。
