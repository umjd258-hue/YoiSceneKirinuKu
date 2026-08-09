# VAD候補方式 技術検証

第11段階開始Gateのため、外部アクセスなしで利用可能なVAD候補を人工WAVだけで比較する。

- Python標準ライブラリによる固定frame RMS判定
- ローカルFFmpegの`silencedetect`
- ローカル`torchaudio.functional.vad`のAPI適合性

生成物と実測JSONは`artifacts/`へ隔離し、Git管理しない。実験値を人物一致、音声品質、候補区間生成の閾値へ転用しない。

```sh
/Library/Frameworks/Python.framework/Versions/3.13/bin/python3 vad_candidates_experiment.py
```
