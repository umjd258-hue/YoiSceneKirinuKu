# App Sandbox subprocess 比較検証

同一の最小実装で、App Sandbox entitlementなし／ありのSwift → Python → FFmpeg subprocessチェーンを比較する隔離実験です。

SwiftはFoundation `Process`、Pythonは標準ライブラリの`subprocess.run(..., shell=False)`を使用し、すべて実行ファイルと引数配列を分離します。FFmpegは短時間の人工`lavfi`入力をnull出力へ処理し、ユーザー動画や外部ストレージを使用しません。

Sandbox版は実験専用app bundleへ`com.apple.security.app-sandbox = true`を付けてad-hoc署名します。Sandboxなし版は同一バイナリ・同一fixtureをentitlementなしでad-hoc署名します。

この実験は、App Sandboxの採否、Python／FFmpegの本番配置・同梱方式、署名・配布方式を決定しません。Sandbox版だけが失敗しても、今回の候補配置で成立を確認できなかったという限定結果として扱います。
