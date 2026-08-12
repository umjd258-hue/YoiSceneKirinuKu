# ARCHITECTURE.md

## 技術
- SwiftUI
- AVFoundation / AVPlayer
- Python
- FFmpeg
- ローカルSpeaker Embeddingモデル
- JSON LinesによるSwift↔Python通信

## 原則
- 軽い処理を前、重い処理を後。
- 解析ジョブは原則1件。
- View寿命とsubprocess寿命を分離。
- ジョブ単位で停止/再開/復旧。
- fail-closed。

## subprocess
- `shell=True`禁止。
- executableと引数配列を明示。
- 製品版はPython 3.13.14 runtimeとStage 6スクリプトをBundleに同梱し、固定相対位置からFoundation `Process`で起動する。
- 製品runtimeは`vendor/python/3.13.14/`の固定SHA-256付き公式macOS universal2 installer原本から抽出し、ローカル`/Library/Frameworks`をBuild入力にしない。installer原本はGit LFS、manifest・取得元記録・PSF Licenseは通常Gitで管理する。
- Stage 6製品スクリプトは`Contents/Resources/Stage6/stage6_runtime_probe.py`へ配置し、テストfixtureは製品Bundleへ含めない。
- Python installerは固定SHA-256に加え、standalone `cosign v2.6.2`、固定Sigstore bundle、固定trusted root、固定identity・issuerによるoffline検証を必須とする。cosignは製品Bundleへ含めず、検証時のTUF更新やnetworkアクセスを禁止する。trusted rootはSigstore公式`root-signing` commit `c9bda74ad2221f938f7d2e0295ca3aad2da710a8`の公式raw版、SHA-256 `6494e21ea73fa7ee769f85f57d5a3e6a08725eae1e38c755fc3517c9e6bc0b66`に固定する。
- PATH探索、実行時download、user site package読込みを禁止する。外部注入pathはDebug用途に限定する。
- stdout = JSON Lines protocol専用。
- stderr = ログ。
- 終了コード確認。
- timeout/停止/cleanupを設計する。

## 成果物
途中成果物は `.partial` またはジョブworkspaceへ出す。
schema/内容/必要ファイルを検証後に正式化。
正式成果物以外を完了扱いしない。

## Stage 10 pipeline orchestration
- Swift orchestratorはStage 4〜9の呼出順、総合結果、キャンセルだけを所有し、成果物、Process、IPC、lock、検証を既存ServiceとPython ownerへ委譲する。
- 呼出順はPreflight成功・source一致、人物再読込とmodel互換確認／必要時再生成、job作成または正式再開、`analysis.wav` pairの準備・再利用検証までとし、Stage 10ではVADを起動しない。
- producing Serviceだけが正式成果物の再利用可否と自身の固定partialのreconciliationを判定する。orchestratorはファイルを削除しない。
- job作成後の確定失敗はPython job ownerがrevisionとstable error codeを持つ`failed`へ原子的に更新する。停止は`stopped`、不確定終了は復旧時に`recovery_required`とする。
- `stopped`は`resumeJob`で`preparing`へ戻し、`recovery_required`はユーザー明示再開後に再検証する。`failed`は自動再開しない。
- completed／failedからの新jobは、`.partial/replacement_<new_job_id>`で完成・fsync・再検証後、同一volumeの`RENAME_SWAP`で`current_job`と交換する。旧jobは`archive/job_<old_job_id>`へ移し、衝突時は上書きせずfail-closedとする。
- crash後は有効な`current_job`だけを正本とし、replacement／archiveを自動昇格しない。Stage 10ではarchiveを自動削除しない。

## ID/時刻
- 永続JSONは `schema_version` を持つ。
- 区間時刻は原則整数ms。
- 候補ID等は決定的ID（例: UUIDv5）を使用可能。

## 人物Embedding再生成
- model metadata不一致の人物は、現modelで利用する前に再生成し、古いEmbeddingを使用しない。
- 対象人物の全sampleを人物単位のcopy-on-writeで処理し、`source.wav`とsample IDを維持したままEmbeddingとmodel metadataを再生成する。
- 全sampleの再生成・既存品質条件・schema・相互参照の検証成功後だけ人物ディレクトリを原子的に交換する。
- centroidは交換後に全sample Embeddingから再計算し、永続化しない。
- 1件でも失敗、`source.wav`欠落、品質不適合または検証失敗があれば旧人物データを変更せず、その人物を現modelでは使用不可とする。
- schema version 1かつ同一model metadataの既存データは変更しない。

## 配置
- Python/FFmpeg/AIモデルの開発時配置と製品配布時配置を分離して定義する。
- Pythonの製品配置はStage 6で正本化済み。FFmpeg / ffprobeはupstream `8.1.2`の固定sourceからuniversal2・必要機能限定・LGPL互換configureで構築し、`Contents/MacOS/ffmpeg`と`Contents/MacOS/ffprobe`へ配置する。実行物を内側からad-hoc署名し、最後にappを署名する。
- FFmpegのsource・署名・鍵・検証済みbinary・manifest・ライセンス・build条件は`vendor/ffmpeg/8.1.2/`へ集約する。大容量のsource archiveと完成binary 2件だけをGit LFS管理する。
- 通常Buildは検証済みbinaryをfail-closed検証してBundleへ組み込み、source再buildは独立した再現検証scriptに限定する。
- SwiftがBundle固定相対位置からFFmpeg / ffprobeの絶対pathを導出してPythonへ渡す。Pythonは通常ファイル、実行権限、Bundle配下を検証し、`shell=False`、固定引数配列、PATH探索なしで起動する。
- AIモデルの配置方式は対応するStage Gateで正本化する。
- App Sandbox採否、Security Scoped Bookmark等の外部ストレージアクセス方式もGateで確定する。

## 初期版の軽量化制約
- 同時解析jobは原則1件。
- Pythonを常駐daemon化しない。
- 永続DBを必須にせずJSON＋フォルダを基本とする。
- SDカードへの中間I/Oを抑え、Mac側workspaceを優先する。
- AI modelは必要時にloadし、不要後に解放可能な構造にする。
- 長尺処理はchunk/stream化可能な構造にする。
