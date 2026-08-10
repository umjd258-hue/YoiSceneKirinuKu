# REVALIDATION_MATRIX.md

完了済みStageの前提が変わった場合の再検証指針。

- Python/IPC契約変更 → Stage 6以降の関連subprocess Stageを再検証
- FFmpeg/version/音声抽出変更 → Stage 7A/7B、11以降の音声依存Stageを確認
- Speaker Embedding model/preprocess変更 → Stage 8A、13、15以降を再検証。既存Embedding再生成判定
- character/sample schema変更 → Stage 8、8A/8B/8C、9および読取側を再検証
- VAD方式/parameter変更 → Stage 11、12、13以降の候補依存結果を再検証
- candidate padding/merge/split変更 → Stage 12以降を再検証
- speaker score定義変更 → Stage 13、15以降を再検証
- 人物閾値変更 → Stage 15、18、19等表示/結果依存を再検証
- quality feature変更 → Stage 16、17、18以降を再検証
- result schema変更 → Stage 18、19、20、21等consumerを再検証
- export方式変更 → Stage 21、22、26、27を再検証
- storage/recovery変更 → Stage 3、5、14、22、26、27の関連箇所を再検証
- security重要変更 → 影響範囲を広めに再検証

これは最低範囲。変更内容によって影響が広い場合は拡張する。
再検証範囲を利用上限節約だけを理由に狭めない。
