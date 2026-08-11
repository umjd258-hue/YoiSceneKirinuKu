# SECURITY_CHECKLIST.md

ローカル専用でも最低限確認する。

- shell=True禁止
- Process引数を配列で渡す
- user-controlled pathをshell文字列連結しない
- path traversalを防ぐ
- symlinkによるworkspace外参照/削除を無条件に信用しない
- 削除対象が許可されたworkspace/character領域内か確認
- 元動画/正式exportをcleanup対象に誤認しない
- ファイル名sanitize
- JSON strict validation
- 巨大/異常JSONへの防御
- subprocess timeout/stop/cleanup
- unknown artifact fail-closed
- 外部通信なし
- ログへ不要な音声内容/秘密情報を残さない
- bookmark/外部ストレージ権限を必要範囲に限定
