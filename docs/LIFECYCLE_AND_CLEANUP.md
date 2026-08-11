# LIFECYCLE_AND_CLEANUP.md

## job削除
ユーザー操作で解析済みjobを削除できる設計にする場合、削除対象を明示する。
元動画と正式exportは既定で削除対象に含めない。

## 人物削除
人物削除時は確認UIを出す。
character配下のsample/Embeddingのownershipに従って削除する。
他人物やexportを巻き込まない。

## 一時ファイル
tmp/partial/logの削除条件をStage 5/22/27で確定する。
実行中・復旧可能なjobの必要成果物を自動cleanupで消さない。

## ログ
ログ保存場所、最大量、rotation/削除条件を決める。
音声内容、文字起こし、個人情報を必要以上にログへ残さない。

## アプリ終了
解析中は協調停止または安全な中断状態への移行を優先する。
必要なら終了確認UIを表示する。
強制終了後は次回起動時にjob metadataから復旧判定する。

## macOSスリープ
スリープ/復帰によるsubprocess・外部ストレージ状態変化を検知し、
処理継続を無条件に信用しない。Stage 26で検証する。

## SDカード抜去
I/O失敗として停止し、partialを正式化しない。
再接続後もsource fingerprint/保存先アクセスを再確認する。

## 再解析
同じ動画でもsource fingerprint、schema/model/parametersが互換の場合のみ
既存成果物再利用を許可する。互換性がなければ必要範囲を再生成する。

## 削除禁止の追加契約
- 完成済みexport MP4を自動cleanupしない。
- 人物登録 `source.wav` をtmp扱いしない。
- 保存対象はユーザーが明示選択した候補だけ。
