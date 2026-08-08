# Swift → Python subprocess 技術検証

SwiftからローカルPythonを、シェルを経由せず引数配列で起動できるか確認するための隔離実験です。

## 検証範囲

- 正常終了
- 非0終了
- 日本語・空白を含む引数
- stdoutとstderrの分離
- 起動失敗と起動後失敗の区別
- 複数回実行での再現性

## 対象外

- Pythonの最終配置・同梱方式
- App Sandbox採否
- 本番JSON Lines schema
- 停止signal・猶予時間・強制終了方式
- SwiftUI本体への組込み

外部依存は使用しません。SwiftPMの `.build/` はリポジトリの `.gitignore` で除外されます。

