# 外部SDカードI/O 技術検証

通常接続状態の外部SDカードについて、ユーザーが承認した専用実験フォルダ内だけで、partial書込み、読戻し、rename、再検証、安全な削除が成立するか確認する隔離実験です。

## 安全制約

- Device Identifier、Device Node、Volume UUID、Mount Pointを操作前に照合する。
- external、removable、writable、mountedでなければ停止する。
- mountpoint、実験ルート、対象ファイルのsymlinkを拒否する。
- 実験ルートが既存なら再利用・削除せず停止する。
- 操作対象は承認済み実験ルート直下のpartialと正式ファイルだけとする。
- `rm -rf`、glob、再帰削除、`shutil.rmtree` を使用しない。
- 想定外項目があれば削除せず停止する。
- 切断試験は行わない。

実験結果だけで、App Sandbox、Security-Scoped Bookmark、本番保存先、本番ファイル名、衝突方式、切断復旧を決定しません。
