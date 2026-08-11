# MODEL_AND_TOOLING.md

## Python
- Stage 6はPython `3.13.14`に固定し、第三者packageを使用しない。
- 製品版はPython runtimeとStage 6スクリプトをBundleに同梱する。
- Python 3.13.14公式macOS universal2 installer原本を固定SHA-256付きで`vendor/python/3.13.14/`へGit LFS管理し、保存済み原本から必要runtimeだけを抽出する。SHA manifest・取得元記録・PSF Licenseは通常Gitで管理する。
- LFS object未取得時はfail-closedとし、ローカル`/Library/Frameworks`やBuild時downloadを製品Buildの入力にしない。
- Bundle内の固定相対位置を検証し、Foundation `Process`からshellを介さず起動する。
- PATH探索、実行時download、user site packageの読込みを禁止する。
- 外部注入pathはDebug用途に限定し、製品版の実行経路に使用しない。
- Stage 6製品スクリプトは`Contents/Resources/Stage6/stage6_runtime_probe.py`とする。`operation=runtime_probe`だけをstrictに受理し、socket操作をfail-closedにするaudit hookを設定して、`progress`と`finished(outcome: succeeded)`だけをstdoutへ出力する。第三者packageは使用しない。
- malformed・非0終了等を生成するテストfixtureはTest Bundle専用とし、製品Bundleへ含めない。
- Python installerの配布元検証にはstandalone `cosign v2.6.2`を使用し、製品Bundleへ含めない。cosign macOS arm64実行物は取得元・SHA-256・ライセンスを固定する。
- Sigstore公式trusted rootは`root-signing` commit `c9bda74ad2221f938f7d2e0295ca3aad2da710a8`の公式raw版、SHA-256 `6494e21ea73fa7ee769f85f57d5a3e6a08725eae1e38c755fc3517c9e6bc0b66`に固定し、SOURCE・manifestとともに`vendor/sigstore/trusted_root.json`へ通常Git管理する。実行時TUF更新を禁止する。
- pkg、`.sigstore` bundle、trusted root、identity=`thomas@python.org`、issuer=`https://accounts.google.com`をすべて固定指定し、offlineでfail-closed検証する。
- 後続依存は各Gateで別途固定する。

## FFmpeg
- 開発時と製品配布時の配置方式を明示。
- versionを記録。
- path探索を無制限に行わない。

## AIモデル
- model_id
- version
- file/hash（必要時）
- expected dimension
- preprocessing
- normalization
を記録。

モデル変更時は既存Embedding再生成要否を判定する。

## ネットワーク
製品処理は完全ローカル。
モデルdownload等が必要なら開発準備工程として明示し、実行時必須にしない。
