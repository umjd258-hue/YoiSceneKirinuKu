# STORAGE_AND_RECOVERY.md

## 外部ストレージ
- 元動画は外部ストレージ上でも読み取り専用扱い。
- 保存先アクセスはmacOSの正式な権限方式を使用する。
- App Sandbox採否とSecurity Scoped Bookmark方式をGateで確定。

## source fingerprint
復旧時に元動画が同一か確認できるよう、
pathだけでなくsize/mtime等のfingerprintを保持する。
必要ならhashはコストを考えて限定利用する。

## source変化
元動画の抜去・差替え・mtime/size変化を検知した場合、
古い解析成果物を無条件再利用しない。

## partial正式化
- 一時ファイルに出力
- 内容検証
- 同一filesystem上で可能ならatomic rename
- 正式名衝突時のルールを適用
- 成功前に既存完成ファイルを削除しない

## 出力ファイル名
人物名・元動画名・開始時刻等を使う場合でも、
禁止文字、長さ、同名衝突を処理する。
正式ルールはStage 21/22で固定。

## 容量不足
事前推定と実書込時エラーの両方を扱う。
容量不足時に元動画や完成済み成果物を削除しない。

## アプリ終了/再起動
解析中にアプリ終了した場合、
job状態を中断/要復旧として残す。
macOS再起動後もjob metadataから復旧判定できるようにする。
