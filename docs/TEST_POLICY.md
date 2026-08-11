# TEST_POLICY.md

## 各Stage
原則:
1. 変更箇所の単体/関連テスト
2. Python構文/関連Pythonテスト
3. Swift関連テスト
4. Debugビルド
5. plist/Xcode project等の必要検査
6. `git diff --check`

## 全体テスト
必要性と既知問題を考慮する。
利用上限節約のためだけに必要検証を省略しない。
一方、既知の環境問題を儀式的に毎Stage再現しない。

## 既知問題
Xcodeテストホストから起動したPython subprocessが、
スクリプト本体到達前のopen/import付近で長時間停止する場合がある。
Xcode外では同一Pythonが高速起動する場合がある。

運用:
- 長時間停止を放置しない。
- 対象PIDを限定してcleanup。
- 今回変更との因果のみ限定的に確認。
- 無関係な既知環境問題なら根拠を記録。
- 全体Swiftテスト未実施/未完走は必ず記録。
