# Stage 6 bundled Python Gate検証

Python 3.13.14の最小runtimeとStage 6 fixtureを一時app Bundleへ同梱し、SwiftからFoundation `Process`で起動する隔離実験。

## 検証範囲

- Bundle内の固定相対位置からのshellなし起動
- Python 3.13.14と第三者package 0件
- `protocol_version` / `type` / `request_id` / `sequence` / `payload`のstrict JSON Lines
- stdoutのprotocol専用とstderrの診断専用
- PATH探索、実行時download、user site package読込みの非使用
- Python audit hookとOS sandboxによる外部通信なし

## 実行

```sh
./experiments/stage6-bundled-python-gate/run_gate.sh
```

生成Bundleは`/tmp`へ隔離し、終了時に削除する。製品コード、Xcode project、後続Stageの依存は変更しない。
