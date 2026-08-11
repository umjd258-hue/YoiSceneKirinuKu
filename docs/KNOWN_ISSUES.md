# KNOWN_ISSUES.md

## Xcode環境下Python subprocess停止
XcodeテストホストからPythonを起動した際、open/import周辺で長時間停止する場合がある。
複数の無関係スクリプトで発生し得る一方、Xcode外では高速起動する場合がある。

無意味な長時間再試行を避ける。
全体テスト未完走は隠さない。
根本修正は独立タスクとして扱う。
