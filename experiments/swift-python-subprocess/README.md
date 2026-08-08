# Swift → Python subprocess 技術検証

SwiftからローカルPythonを、シェルを経由せず引数配列で起動できるか確認するための隔離実験です。

## 検証範囲

- 正常終了
- 非0終了
- 日本語・空白を含む引数
- stdoutとstderrの分離
- 起動失敗と起動後失敗の区別
- 複数回実行での再現性
- 大量・長時間のstdout／stderr同時逐次読取り
- 両streamの件数、欠落、重複、stream内順序、payload、sentinel、EOFの機械検証

## 対象外

- Pythonの最終配置・同梱方式
- App Sandbox採否
- 本番JSON Lines schema
- 停止signal・猶予時間・強制終了方式
- SwiftUI本体への組込み
- 本番のbufferサイズ、Queue方式、concurrency方式

## 大量・長時間出力の検証方針

Python fixtureはstdoutとstderrへ連番と固定長payloadを持つレコードを交互に出力する。Swift側は両pipeを子プロセス実行中から独立して読み取り、終了後に各streamの期待件数、欠落、重複、stream内順序、payload、sentinel、EOFを機械的に検証する。

`burst`、`paced`、`trailing` の各値とdeadlineは実験負荷であり、本番仕様へ転用しない。timeout時の子プロセス終了処理も実験の後始末専用であり、本番停止方式を決定しない。

外部依存は使用しません。SwiftPMの `.build/` はリポジトリの `.gitignore` で除外されます。
