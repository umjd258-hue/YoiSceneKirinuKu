# 検証結果

## 実行環境

- Swift: `/usr/bin/swift`
- Swift version: Apple Swift 6.3.3
- Target: arm64-apple-macosx26.0
- Python: `/Library/Frameworks/Python.framework/Versions/3.13/bin/python3`
- Python version: 3.13.14
- 外部依存: なし
- 外部アクセス: なし

## ビルド

通常の `swift build` は、サンドボックス外のユーザーmodule cacheへ書き込めず失敗した。

module cacheを `/private/tmp/yoi-scene-swift-python-module-cache` へ向けた同一ビルドは成功した。

```text
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/yoi-scene-swift-python-module-cache
CLANG_MODULE_CACHE_PATH=/private/tmp/yoi-scene-swift-python-module-cache
swift build --package-path experiments/swift-python-subprocess
```

このcache指定は検証環境上の制約への対応であり、本番配置方式ではない。

## 実行結果

### 正常終了

- Pythonプロセス起動: 成功
- 終了理由: exit
- 終了コード: `0`
- Swift側の分類: 起動後の正常終了

### 非0終了

- Pythonプロセス起動: 成功
- 終了理由: exit
- 終了コード: `7`
- Swift側の分類: 起動後の非0終了
- 正常終了と混同しなかった。

### 起動失敗

- 存在しないPythonパスを指定した。
- `Process.run()` の起動エラーとして取得できた。
- 起動後の非0終了と区別できた。

### 日本語・空白を含む引数

- 入力: `日本語 と spaces`
- PythonがJSONへ出力した値: `日本語 と spaces`
- 欠落、分割、文字化けは確認されなかった。

### stdout／stderr分離

- stdout: fixtureのJSON 1行
- stderr: fixtureの通常ログ1行
- Swift側で別々に取得できた。

### 再現性

- 正常ケースを3回連続実行した。
- 3回すべて終了コード`0`、引数保持、stdout／stderr分離に成功した。

## 成立した事項

- Foundationの`Process`を候補として、SwiftからローカルPythonを起動できる。
- 実行ファイルURLと引数配列を使い、シェルを経由せず起動できる。
- 小量出力のfixtureではstdoutとstderrを分離できる。
- 終了コードと終了理由を取得できる。
- 起動失敗と起動後失敗を区別できる。
- Python実行ファイルのパスをSwift側への外部入力として渡せる。
- 外部依存の追加および外部アクセスなしで成立性を確認できた。

## 制約・未決定事項

- 本検証は小量出力だけを対象とした。大量・長時間のstdout／stderrをデッドロックなく読む方式は、本番通信契約までに別途検証が必要。
- Pythonの最終配置・同梱方式は未決定。
- App Sandbox採否は未決定。
- 本番JSON Lines schemaは未決定。
- `progress`／`error`／`finished` の正式payloadは未決定。
- 停止signal、猶予時間、強制終了方式は未決定。
- FFmpeg子プロセスの起動、監視、停止および異常終了時の管理方式は未検証・未決定。
- SwiftおよびClangのmodule cacheの本番での扱いは未決定。検証時の `/private/tmp/yoi-scene-swift-python-module-cache` 指定は検証環境上の回避策であり、本番アーキテクチャとして採用しない。
- SwiftUI Viewから分離した本番プロセス所有Serviceの設計は後続段階で決定する。

## 判定

限定した検証範囲では、SwiftからPython subprocessを起動し、引数、stdout、stderr、終了状態を扱う技術的成立性を確認できた。

この結果だけでFoundation `Process`の最終採用、Python配置、同梱、Sandbox、通信schema、停止方式を確定しない。
