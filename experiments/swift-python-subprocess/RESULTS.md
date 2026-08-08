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

---

## 大量・長時間stdout／stderr同時逐次読取り検証

### 検証方法

Python fixtureがstdoutとstderrへ連番、stream識別子、固定長payloadを持つレコードを出力した。Swift側は子プロセス実行中から両pipeを独立して64 KiB以下のchunkで読み続け、子プロセス終了後に両streamのEOFを待ってから、全レコードを機械的に検証した。

検証項目は、期待件数と実受信件数、欠落、重複、stream内順序、payload長と内容、sentinel、EOF、timeoutとした。stdoutとstderrのpipe間の到着順は保証対象にせず、各stream内の順序を検証した。

以下の件数、payloadサイズ、間隔、deadline、読取りchunkサイズは検証専用の値であり、本番仕様へ転用しない。

| profile | 通常レコード数／stream | payload／record | 出力間隔 | deadline | 反復 |
|---|---:|---:|---:|---:|---:|
| burst | 10,000 | 1,024 bytes | 0 | 20秒 | 3回 |
| paced | 3,000 | 512 bytes | 1,000マイクロ秒 | 15秒 | 3回 |
| trailing | 5,000 | 256 bytes | 0 | 15秒 | 3回 |

`trailing` では両streamのsentinelを明示flushせず、Python終了時のflushとpipe EOFを通じて末尾データを回収できるか確認した。

### 試行結果

| 試行 | 経過秒 | stdout 期待／受信 | stderr 期待／受信 | 欠落 | 重複 | 順序違反 | payload破損 | sentinel | EOF | timeout |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|---|
| burst-1 | 0.121 | 10,000／10,000 | 10,000／10,000 | 0 | 0 | 0 | 0 | 両方1件 | 両方確認 | なし |
| burst-2 | 0.100 | 10,000／10,000 | 10,000／10,000 | 0 | 0 | 0 | 0 | 両方1件 | 両方確認 | なし |
| burst-3 | 0.109 | 10,000／10,000 | 10,000／10,000 | 0 | 0 | 0 | 0 | 両方1件 | 両方確認 | なし |
| paced-1 | 3.902 | 3,000／3,000 | 3,000／3,000 | 0 | 0 | 0 | 0 | 両方1件 | 両方確認 | なし |
| paced-2 | 3.889 | 3,000／3,000 | 3,000／3,000 | 0 | 0 | 0 | 0 | 両方1件 | 両方確認 | なし |
| paced-3 | 3.903 | 3,000／3,000 | 3,000／3,000 | 0 | 0 | 0 | 0 | 両方1件 | 両方確認 | なし |
| trailing-1 | 0.060 | 5,000／5,000 | 5,000／5,000 | 0 | 0 | 0 | 0 | 両方1件 | 両方確認 | なし |
| trailing-2 | 0.050 | 5,000／5,000 | 5,000／5,000 | 0 | 0 | 0 | 0 | 両方1件 | 両方確認 | なし |
| trailing-3 | 0.050 | 5,000／5,000 | 5,000／5,000 | 0 | 0 | 0 | 0 | 両方1件 | 両方確認 | なし |

### 判定

限定した検証条件では、stdoutとstderrを子プロセス実行中から同時に逐次排出することで、全9試行をデッドロックなく完了できた。両streamで期待件数を欠落なく受信し、重複、stream内順序違反、payload破損、sentinel欠落、EOF未確認、timeoutは発生しなかった。

この結果は、今回使用したbufferサイズ、Queue方式、concurrency方式の本番採用を意味しない。実験用timeout時の `terminate()` も後始末専用であり、本番停止方式を決定しない。

### 引き続き未検証・未決定

- 本番JSON Lines schema
- 本番のbufferサイズ
- Queue方式およびconcurrency方式
- さらに大きい出力、さらに長時間の処理、実機負荷下での挙動
- JSON Linesのmalformed JSON、unknown event、protocol violationへの本番対応
- Pythonの最終配置・同梱方式
- App Sandbox採否
- 停止signal、猶予時間、強制終了方式
- FFmpeg子プロセス管理方式
