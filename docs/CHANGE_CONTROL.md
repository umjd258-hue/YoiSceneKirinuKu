# CHANGE_CONTROL.md

Codexは正本仕様の意味を変える変更を独断で行わない。

仕様変更が必要と判断した場合:
1. 問題
2. 根拠
3. 変更候補
4. 影響する正本
5. 影響Stage
6. 再検証範囲
を整理する。

安全に一意に決められない場合はBlockerとして停止する。
単純な誤字、明白な整合修正を除き、製品挙動・schema・AI閾値・保存/復旧・securityを変える変更は技術判断としてDECISIONSへ記録する。

仕様変更後はREVALIDATION_MATRIXを確認し、既に完了したStageの再検証要否を判断する。
