# STAGE_CONSISTENCY_AUDIT.md

## 問題
Stage 7A/7B、Stage 8C、Stage 9を中心に、派生表・Gate台帳・未決定事項台帳・監査記録へ旧Stage体系が残存していた。

## 根拠
- 全工程とStage Gateの正本は `IMPLEMENTATION_STEPS.md`。
- Stage 7/8の細分化は `SUBSTAGE_PLAN.md` を優先する。
- Stage 7A/7BはFFmpeg配置Gate・解析用音声抽出、Stage 8A/8B/8CはSpeaker Embedding技術Gate・登録資産永続化・複数sample統合/再生成、人物登録UIはStage 9。
- 人物削除はStage 8のCRUD責務であり、Stage 8Cではない。

## 変更内容
- `FEATURE_STAGE_MATRIX.md` と `GATE_REGISTER.md` を正本のStage 1〜10へ再同期した。
- `IMPLEMENTATION_STEPS.md` の旧Stage 8Aまとめ表記を廃止し、8A/8B/8Cの責務を明示した。
- `UNDECIDED_REGISTER.md` のPython、FFmpeg、人物削除、複数sampleに関する決定期限を担当Stageへ移した。
- 監査文書・再検証表に残る旧Stage 0、人物7A/7B等の表記を修正した。

## 影響正本
`IMPLEMENTATION_STEPS.md`、`SUBSTAGE_PLAN.md`、`FEATURE_STAGE_MATRIX.md`、`GATE_REGISTER.md`、`UNDECIDED_REGISTER.md`、`REVALIDATION_MATRIX.md`、関連監査文書。

## 影響Stage
Stage 1〜10。特にStage 6、7A/7B、8、8A/8B/8C、9、10。

## 再検証範囲
Stage番号を責務・Gate・決定期限として記載する全仕様文書の横断検索、Stage 1〜10とSubstageの対応、既存PASS記録、必須ファイル、ZIP CRC、package manifest、`git diff --check`。

## 結果
製品機能、schema、AI閾値、保存/復旧、security、製品コードは変更していない。
Stage番号・責務の横断検索、既存PASS記録の再評価、ZIP CRC、package manifest、`git diff --check` はPASS。旧Stage割当は履歴説明として引用する箇所を除き残存していない。
