# App Sandbox subprocess 比較検証結果

## 総合判定

同一の最小実装を使用した限定検証では、App SandboxなしのSwift → Python → FFmpeg subprocessチェーンは3回すべて成功した。

App Sandboxありの候補構成は、`com.apple.security.app-sandbox = true`を付与したad-hoc署名bundleがSwiftの最初の実験用段階マーカーを出力する前に終了コード134でabortしたため、成立を確認できなかった。PythonおよびFFmpegの起動処理には到達していない。

ローカル開発署名IDは利用できず、開発署名による再検証は未実施である。この結果だけでApp Sandboxの採否、署名方式または本番配置方式を決定しない。

## 検証条件

- Swift: Foundation `Process`
- Python: 3.13.14（今回のローカル配置）
- FFmpeg: 8.1.2（今回のローカル配置）
- SwiftからPython、PythonからFFmpegはいずれもshellを介さず、実行ファイルと引数配列を分離
- FFmpeg入力: 短時間の人工`lavfi`音声
- Sandboxなし／ありで同一のSwiftバイナリとPython fixtureを使用
- Sandboxあり版: `com.apple.security.app-sandbox = true`を付与してad-hoc署名
- SwiftPMの`--disable-sandbox`は、検証環境でSwiftPM自身のmanifest／build sandboxが使用できなかったことへのビルド時限定の回避であり、比較対象のApp Sandbox設定とは別である

これらのversion、絶対パス、人工入力、署名方法およびビルド方法は今回の検証条件であり、本番仕様ではない。

## Sandboxなし

entitlementが存在しない場合を実効的なSandbox無効として扱うよう実験コードの判定を正規化した後、3回実行した。

- 3回すべて `chain_completed`
- 3回すべてPythonを起動できた
- 3回すべてPython終了コード0
- 3回すべてPython stdoutのJSONをdecodeできた
- 3回すべてPython stderrをstdoutと分離できた
- 3回すべてFFmpegの起動をPython側で確認できた
- 3回すべてFFmpeg終了コード0
- 全段階マーカーを順序どおり確認できた

## Sandboxあり

ad-hoc署名bundleの署名とbundle構造について、次を読み取り専用で確認した。

- `codesign --verify --deep --strict`は成功
- `com.apple.security.app-sandbox = true`を確認
- app bundle、Info.plist、実行ファイル、Python fixtureが存在
- Info.plistとentitlementsのplist構文は正常
- 署名はad-hocで、Team Identifierは設定されていない

実行すると、Swiftの最初の段階マーカー `process_started` より前に終了コード134でabortした。したがって、今回の候補構成ではSwift → Python → FFmpegチェーンの成立を確認できなかった。PythonまたはFFmpegの問題とは判定しない。

Gatekeeperの読み取り専用評価ではCode Signing subsystemのinternal errorが返った。ただし、プロジェクトルールによりmacOS統合ログおよびクラッシュログは読み取っていないため、abortの内部原因は確定していない。

## 未検証・未決定

- 有効なローカル開発署名によるApp Sandboxありbundleの起動
- App SandboxありでのSwift → Python → FFmpegチェーン
- `.app`の直接実行とLaunchServices経由実行の差
- 本番の署名・配布方式
- App Sandbox採否
- Python、FFmpeg、ffprobeおよびAIモデルの最終配置・同梱方式
- Security-Scoped Bookmark採否
- App Sandbox下での外部ストレージアクセス
- App Sandbox下での停止、子プロセスおよびProcess group管理

Sandboxなしでの成功をApp Sandboxなしの正式採用根拠にせず、SandboxありのabortをApp Sandbox不採用の確定根拠にも使用しない。
