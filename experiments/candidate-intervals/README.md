# 候補区間生成 技術検証

第12開始Gateのため、人工VAD区間だけを使用して結合、前後余白、最小・最大長、分割、境界、安定IDを比較する。

実動画、実人物音声、外部アクセス、外部依存は使用しない。生成物は`artifacts/`へ隔離し、Git管理しない。

```sh
/Library/Frameworks/Python.framework/Versions/3.13/bin/python3 candidate_intervals_experiment.py
```
