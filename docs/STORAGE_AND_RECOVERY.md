# STORAGE_AND_RECOVERY.md

## 外部ストレージ
- 元動画は外部ストレージ上でも読み取り専用扱い。
- 元動画と出力先はユーザーがそれぞれ明示選択し、固定パス探索や自動選択を行わない。
- 出力先は元動画とは別に選択し、元動画を出力先として上書きしない。
- 選択した外部ストレージURLのbookmark dataだけをUserDefaultsへ永続化し、raw pathは保存しない。
- 元動画用と出力先用のbookmark dataは別キーで保存する。
- 選択時のvolume UUID文字列をbookmarkとは別に保存し、復元URLのvolume UUID文字列との完全一致を要求する。
- bookmark解決失敗、stale、volume UUID取得不能・不一致時は自動継続せず、ユーザーへ再選択を要求する。
- 初期版はApp Sandboxを無効とし、Stage 27で再評価する。
- Stage 22ではこのvolume UUID方式を維持し、抜去、衝突、partial、finalizeを追加検証する。

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
