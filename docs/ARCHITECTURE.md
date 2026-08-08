# アーキテクチャ仕様

## 1. 基本構成

macOSネイティブのSwiftUIアプリをフロントエンドとし、解析・変換処理をPython側へ分離する。

重要原則:

- UIと解析ロジックを重複させない。
- Viewの寿命とPythonプロセスの寿命を分離する。
- 同じファイルをSwiftとPythonが無秩序に更新しない。
- 正式成果物とpartialを明確に区別する。

## 2. SwiftUIの担当

SwiftUI側は主に以下を担当する。

- 画面遷移
- MP4選択
- 人物選択
- 解析開始要求
- 停止要求
- 進捗表示
- 結果表示
- AVPlayerによるプレビュー
- 保存対象選択
- `selection.json` 管理
- ジョブ管理
- ユーザー向けエラー表示

## 3. Pythonの担当

Python側は主に以下を担当する。

- 動画Preflight
- 解析用音声作成
- VAD
- Speaker Embedding
- 人物判定
- 品質判定
- `result.json` 生成
- 人物登録用音声生成
- 人物Embedding生成
- 完成動画保存
- `save_state.json` 生成

## 4. ファイル所有権

以下を基本の所有権とする。各schemaと更新契約は、本体接続前に正式化する。

| ファイル | 作成・更新 | 読取 | 削除 |
|---|---|---|---|
| `job.json` | Swift | Python | Swift |
| `stop.requested` | Swift | Python | Swift |
| `analysis.wav` | Python | Python | Swift |
| `vad.json` | Python | Python | Swift |
| `speaker_candidates.json` | Python | Python | Swift |
| `result.json` | Python | Swift | Swift |
| `selection.json` | Swift | Swift | Swift |
| `save_state.json` | Python | Swift | Swift |
| 完成MP4 | Python | ユーザー/アプリ | アプリでは削除しない |

同じ正式ファイルをSwift/Python双方から更新する設計にしない。

## 5. 永続データ共通契約

永続JSONは次の原則に従う。

- schema versionを必須とする。
- 永続データ間の参照には安定した一意IDを使用する。
- 表示名や配列位置を永続的な関連付けへ使用しない。
- 動画内時刻と時間長の基準表現は整数ミリ秒を第一候補とする。
- 未知schema、壊れたJSON、必須項目が不足したJSONを推測で正常処理しない。
- 重要なJSONはpartialまたは一時ファイルへ書き、検証後に正式化する。

ただし、重要資産ではない `selection.json` の破損については、`PRODUCT_SPEC.md` に従って標準の初期選択状態へ戻すことを明示的な例外とする。この復旧を解析結果や保存状態等の必須データへ拡張しない。

schema versionの具体的な番号、ID形式、時刻キー名、丸め規則は未決定とする。第3開始前までに正式決定する。

主要JSONの責務は次のとおり分離する。

| JSON | 責務 | 主な所有者 |
|---|---|---|
| `job.json` | ジョブID、入力、選択人物、Source fingerprint、ジョブ要求情報 | Swift |
| `result.json` | 正式に確定した解析候補 | Python |
| `selection.json` | UI上の保存対象選択 | Swift |
| `save_state.json` | 保存試行と正式保存済み成果物の状態 | Python |

各JSONの全フィールド、必須条件、更新可能範囲、互換性方針は未決定とする。各JSONを初めて本体利用する段階の開始前までに正式schemaを定める。

## 6. 人物データ構造

1人物が1件以上のsampleを持つ構造とする。

```text
characters/
└─ char_xxxxx/
   ├─ character.json
   └─ samples/
      ├─ sample_xxxx/
      │  ├─ source.wav
      │  ├─ embedding
      │  └─ sample.json
      └─ sample_yyyy/
         ├─ source.wav
         ├─ embedding
         └─ sample.json
```

人物名ではなく内部IDを使用する。

`source.wav` は重要資産。
Embeddingは `source.wav` から再生成可能な派生データとする。

人物IDとsample IDには安定した一意IDを使用する。

複数sampleから人物判定用Embeddingをどのように構成するかは未決定とする。平均、最大値、centroid、外れ値除去、重み付け等の方式を推測で採用しない。第8Aまたは第8B開始前までに技術検証結果をもとに正式決定する。

## 7. 人物データのトランザクション

### 新規人物

完成前の人物を正式人物フォルダとして扱わない。

例:

```text
char_xxxxx.partial
```

以下がすべて成功してから正式化する。

1. 登録音声生成
2. 最低限の品質確認
3. Embedding生成
4. 必要メタデータ確定

既存人物へサンプル追加する場合も、新規サンプルだけを一時状態で生成する。失敗しても既存人物データへ影響させない。

### 既存人物へのsample追加

既存人物へsampleを追加する場合は、新sampleだけを一時領域で生成・検証する。`source.wav`、Embedding、メタデータがすべて正式化可能になってから人物データへ関連付ける。

新規人物と既存人物へのsample追加について、正式化の原子性、失敗復旧、品質検証条件は未決定とする。第8A／第8B開始前までに正式決定する。

### 人物削除

人物削除は、固定した人物データルート内だけを対象とする。解析開始要求中、実行中、停止要求中、保存中など、人物データと競合する状態では実行しない。

削除対象の検証、途中失敗時の扱い、symlinkや不正な相対パスへの対策は未決定とし、第8C開始前までに正式決定する。

## 8. current_job

初期版は基本的に1ジョブのみ。

概念例:

```text
current_job/
├─ job.json
├─ analysis.wav
├─ vad.json
├─ speaker_candidates.json
├─ result.json
├─ selection.json
├─ save_state.json
├─ stop.requested
└─ *.partial
```

正式完成済み工程のみ再開時に再利用する。

`current_job` フォルダの存在だけを解析中の根拠にしない。少なくとも次の概念状態を区別する。

- 解析開始要求
- 起動準備中
- 実行中
- 停止要求中
- 停止完了
- 解析正式完了
- 異常終了
- 復旧確認中

アプリ強制終了後は、永続状態と実際のプロセス状態を確認して復旧可否を判定する。staleな `stop.requested` を新しい解析の停止要求として誤用しない。

再開時はSource fingerprintを使って元動画の同一性を確認する。fingerprintの具体方式は未決定とし、ファイルサイズ、更新時刻、部分ハッシュ、全体ハッシュ等から実装者が推測で選択しない。

多重起動・二重解析防止方式、Source fingerprint方式、current_jobの正式な状態機械と復旧契約は、第9開始前までに技術検証結果をもとに正式決定する。

## 9. Swift-Python通信

初期版ではPython stdoutをJSON Lines通信専用とする。

イベント種類は基本的に3つへ絞る。

- `progress`
- `error`
- `finished`

通常ログはstdoutへ出さず、stderrまたはログファイルへ出す。

### progress例

```json
{
  "type": "progress",
  "stage": "speaker",
  "status": "running",
  "current": 42,
  "total": 128
}
```

工程完了は同じ `progress` で `status: "completed"` などを使用可能とする。

通信は次の原則に従う。

- stdoutは1行1JSONのJSON Lines通信専用とする。
- 通常ログはstdoutへ出さない。
- 壊れたJSONや未知eventを通常ログとして読み飛ばし、正常処理を継続しない。
- `finished` はプロセス側の処理終了通知であり、成果物の成功証明ではない。

停止完了を独立eventとして追加するか、既存の `progress` または `finished` に明確な終了理由を持たせるかは未決定とする。基本3種類との整合性を検証し、第14開始前までに正式決定する。独立eventを実装時に推測で追加しない。

## 10. エラー通信

Pythonの技術例外文字列をそのままユーザーUIへ出さない。

Pythonは安定したエラーコードを返し、Swift側がユーザー向け日本語へ変換する。

詳細ログは開発・診断用として別経路に保持する。

エラーコード体系、ユーザー向け文言との対応、ログ保存場所・保存期間・動画パスや人物名等の取扱いは未決定とする。各機能の本体接続前までに必要な範囲を正式決定する。

## 11. 完了判定

`finished` を受信しただけでUIを完成状態にしない。

解析完了例:

1. Pythonから `finished` を受信。
2. 正式 `result.json` の存在を確認。
3. `result.json` を読み込めることを確認。
4. 必要な終了条件を検証。
5. すべて成功してからResultsへ遷移。

保存も同様に、完成MP4と `save_state.json` の正式更新を確認してから「保存済み」とする。

## 12. 解析パイプラインとpartial方式

内部解析は次の責務境界とする。

1. VAD
2. 候補区間生成・結合・分割
3. Speaker Embedding算出
4. 人物判定
5. 音声品質判定
6. `result.json` 構築・検証・正式化

人物判定と音声品質判定は独立した工程・結果とする。人物不明判定を音声品質判定で代用しない。

長時間処理・重要ファイルは、処理途中のデータと正式完成データを分離する。

原則:

- 途中ファイルを正式ファイル名として公開しない。
- 完成・検証後に正式化する。
- partialしかない工程は再開時に未完成として扱う。
- 保存先切断などで残ったpartialを完成MP4として扱わない。

候補区間生成、結合、分割に必要な数値規則は未決定とし、第12開始前までに技術検証結果をもとに正式決定する。

人物不明判定、人物一致度の段階表現、音声品質から◎・○・△への変換、品質reason codeは未決定とし、第15開始前までに正式決定する。AIの生スコアをUIへ渡さない。

## 13. 停止

cooperative stopを基本方針とし、`stop.requested` 方式を中心に技術検証する。

1. Swiftが `stop.requested` を作成。
2. UIを「安全に停止しています…」へ移行。
3. Pythonは安全な境界で停止要求を確認。
4. 新しい通常progressが届いても停止要求後のUI進捗へ反映しない。
5. Pythonプロセス停止を確認。
6. UIを「解析を停止しました」へ移行。

FFmpegの長時間ブロック処理については、子プロセスの明示終了方式を技術検証する。

停止成功時もpartialを正式化しない。停止要求、プロセス終了、停止後状態の検証、UI上の停止完了を別の事実として扱う。

具体的なsignal、猶予時間、強制終了条件、プロセスグループ管理、停止完了event形式は未決定とする。第14開始前までに技術検証結果をもとに正式な停止契約を確定する。

## 14. AVPlayer

- Swift側で管理する。
- 基本的に1インスタンス。
- 候補変更時は前候補の再生を止める。
- 選択候補の開始位置へseekする。
- 自動再生しない。
- observerを追加し続けない。適切に解除・再利用する。

## 15. 状態管理

排他的な状態を多数のBooleanで表現しない。

例として、アプリの主要状態はenum等で表現する。

Viewから `screen = .results` のように重要状態を直接変更せず、AppViewModel / Serviceの操作メソッド経由で遷移させる。

UIのdisabledだけに二重実行防止を依存せず、Service層でも防止する。

## 16. 保存トランザクションとreconciliation

完成MP4へ直接書き込まない。保存の基本順序は次のとおりとする。

1. partialへ書き込む。
2. 書込み完了を確認する。
3. MP4を検証する。
4. 既存完成MP4との衝突がないことを正式な規則で確認する。
5. 完成MP4として正式化する。
6. `save_state.json` を原子的に更新する。
7. 必要な成果物と状態を再検証する。

MP4正式化後かつ `save_state.json` 更新前にクラッシュした状態はreconciliation対象とする。保存先切断時のpartialを完成扱いしない。

保存成果物の単位、ディレクトリ構造、ファイル名、既存ファイル衝突方式、`save_state.json` schemaは未決定とし、第19開始前までに正式決定する。

`save_state.json` 破損、完成MP4だけ存在する状態、再保存、保存先切断、partial清掃を含むreconciliation契約は未決定とし、第20開始前までに正式決定する。

第17.3の外部SDカードI/O検証で確認したrenameは、通常接続状態での小容量な単一実験ファイルに対する限定結果である。完成MP4の正式化方式、SHA-256、`fsync`、rename、`Path.unlink()` の本番採用、またはreconciliationの成立を意味しない。sidecarファイルを含む清掃契約は第19／第20の開始Gateまで未決定とし、手動承認を伴った今回の後片付けを本番の自動復旧方式へ転用しない。

## 17. 技術検証項目

本体組み込み前に小さな実験コードで確認する。

- App Sandboxあり／なし
- Swift → Python subprocess
- Python → FFmpeg
- 外部SDカードの通常接続時I/O、切断、再接続
- `stop.requested` 方式
- FFmpeg停止
- Source fingerprint
- Macスリープ抑止
- Python完成版同梱
- FFmpeg同梱
- 人物登録サンプルの適切な長さ

初期版はApp Store配布を前提としないが、App Sandboxの採否は未決定とする。Python、FFmpeg、AIモデルの配置・同梱方式、Security-Scoped Bookmarkの採否、スリープ抑止方式も未決定とし、実装者が推測で確定しない。

各検証には、検証目的、合格条件、影響する仕様、正式決定期限を設ける。検証成功だけで本体仕様を自動変更せず、結果を本書へ正式反映してから関連する本体実装を開始する。

実験コードは `experiments/` に分離し、そのまま本体へコピーして完成扱いしない。

### 17.1 Swift → Python subprocess 技術検証結果

`experiments/swift-python-subprocess/` の限定的な実験により、次の技術的成立性を確認した。

#### 確認済みの事実

- macOS上でFoundationの `Process` を使用し、SwiftからPython subprocessを起動できる。
- shellを介さず、実行ファイルURLと引数配列を指定して起動できる。
- 日本語および空白を含む引数を、欠落、分割、文字化けなく渡せる。
- 少量出力の検証では、stdoutとstderrを分離して取得できる。
- プロセスの終了理由と終了コードを取得できる。
- 実行ファイルを起動できない失敗と、起動後の非0終了を区別できる。
- Python実行ファイルのパスを、Swift側の実験プログラムへの外部入力として渡せる。
- 外部依存の追加および外部アクセスなしで、上記の成立性を確認できた。

大量・長時間stdout／stderr同時逐次読取りについて、限定した検証条件で次の事実を確認した。

- stdoutとstderrを子プロセス実行中から独立して逐次読み取りできた。
- `burst`、`paced`、`trailing` の各3回、合計9試行がすべて成功した。
- 全試行でstdoutとstderrそれぞれの期待件数と受信件数が一致した。
- 欠落、重複、stream内順序違反、payload破損は発生しなかった。
- stdoutとstderrそれぞれでsentinelを確認できた。
- 子プロセス終了後もstdoutとstderrそれぞれのEOFまで待つことで、終了直前の残存データを回収できた。
- timeout、デッドロック、ハングは発生しなかった。

実験条件は、`burst` が1 streamあたり10,000件、1 recordあたり1,024 bytesを3回、`paced` が1 streamあたり3,000件、1 recordあたり512 bytes、1ms間隔を3回、`trailing` が1 streamあたり5,000件、1 recordあたり256 bytesを3回である。Swift実験コードの1回の読取りchunk上限は64 KiBとした。これらは実測範囲を示す実験値であり、本番bufferサイズ、通信量上限、Queue設計その他の本番仕様として採用しない。

この確認はFoundationの `Process`、Pythonの配置、同梱方式その他の本番方式の最終採用を意味しない。実測の詳細は `experiments/swift-python-subprocess/RESULTS.md` を参照する。

#### 未検証・未決定の事項

- 今回より長時間または高負荷な条件でのstdout／stderr同時逐次読取りの挙動は未検証とする。今回成立した実験方式を本番実装方式として自動採用せず、Swift–Python通信を本接続する段階の開始Gateまでに必要な条件と正式方式を決定する。
- 本番のbufferサイズ、Queue方式、Concurrency方式は未決定とし、今回の件数、payloadサイズ、出力間隔、64 KiBの読取りchunk上限から推測で決定しない。
- Pythonの最終配置・同梱方式は未決定とし、Python subprocessを本体へ組み込む段階の開始Gateまでに正式決定する。
- App Sandboxの採否は未決定とし、Python subprocess、外部SDカードI/Oその他の影響を受ける本実装より前のGateまでに正式決定する。
- 本番のJSON Lines schema、およびmalformed JSON、unknown event、protocol violationへの正式な処理は未決定とし、Swift–Python通信を本接続する段階の開始Gateまでに正式決定する。
- 停止signal、猶予時間、強制終了方式は未決定とし、第14開始Gateまでに正式決定する。
- FFmpeg子プロセスの起動、監視、停止および異常終了時の管理方式は未検証とし、Python → FFmpegを初めて本実装する段階の開始Gateまでに技術検証し、正式決定する。
- 今回の実験でtimeout時の後始末に使用した `terminate()` は、本番の停止方式として採用しない。
- SwiftおよびClangのmodule cacheを本番でどこへ配置し、どのように扱うかは未決定とする。検証時の `/private/tmp/yoi-scene-swift-python-module-cache` 指定は、検証環境の書込み制約を回避するためだけの措置であり、本番アーキテクチャとして採用しない。

### 17.2 Python → FFmpeg subprocess 技術検証結果

`experiments/python-ffmpeg-subprocess/` の限定的な実験により、次の技術的成立性を確認した。

#### 検証環境の記録

- Python 3.13.14: `/Library/Frameworks/Python.framework/Versions/3.13/bin/python3`
- FFmpeg 8.1.2: 入力パス `/opt/homebrew/bin/ffmpeg`、実体パス `/opt/homebrew/Cellar/ffmpeg/8.1.2_1/bin/ffmpeg`
- ffprobe 8.1.2: 入力パス `/opt/homebrew/bin/ffprobe`、実体パス `/opt/homebrew/Cellar/ffmpeg/8.1.2_1/bin/ffprobe`

これらのversionと絶対パスは今回のローカル検証環境の記録であり、Homebrew版、`/opt/homebrew/bin/`、Cellar内のパスを本番配置または本番依存として採用しない。

#### 確認済みの事実

- 今回のローカル環境ではFFmpeg 8.1.2とffprobe 8.1.2が存在し、実行可能だった。
- Python 3.13.14からFFmpegとffprobeを起動できた。
- Python標準ライブラリの `subprocess.run()` を候補として、`shell=False` かつ実行ファイルと引数を分離した配列で起動できた。
- 日本語と空白を含むファイルパスを1つの引数として渡し、生成、FFmpeg読取り、ffprobe解析を実行できた。
- stdout、stderr、終了コードを分離して取得できた。
- FFmpegがstderrへ処理情報を出力すること自体を失敗条件にせず、終了コードと成果物検証を組み合わせられた。
- 存在しない実行ファイルによるプロセス起動失敗と、起動後のFFmpeg非0終了を区別できた。
- ffprobeのJSON出力をPythonでparseし、video stream、audio stream、正のdurationを機械的に確認できた。
- FFmpegの終了コードだけでなく、成果物の存在、非空、FFmpegによる読取り、ffprobeによる検証を組み合わせて確認できた。
- 今回の人工メディア生成では `-n` を指定し、既存出力を黙って上書きしない動作を確認した。
- 外部依存の追加および外部アクセスなしで、上記の成立性を確認できた。

人工メディア生成に使用したmpeg4、aac、160×90、10fps、2秒、48kHz、lavfi入力およびその他の具体的なFFmpeg引数は、技術検証専用の実験値である。本番codec、本番FFmpeg引数、解析用WAV仕様、完成MP4仕様その他の本番メディア仕様として採用しない。

`subprocess.run()` は今回の短時間処理で成立性を確認した候補方式であり、本番の長時間FFmpeg処理、停止、強制終了、Process group管理まで含めた最終方式として確定しない。実測の詳細は `experiments/python-ffmpeg-subprocess/RESULTS.md` を参照する。

#### 未検証・未決定の事項

- FFmpegとffprobeの最終配置・同梱方式、およびHomebrew版へ本番依存するかは未決定とする。
- Pythonの最終配置・同梱方式は未決定とする。
- App SandboxおよびSecurity-Scoped Bookmarkの採否は未決定とする。
- 本番codec、本番FFmpeg引数、解析用WAV正式仕様、完成MP4保存方式は未決定とする。
- FFmpegの長時間処理は未検証とする。
- FFmpeg停止signal、停止猶予時間、強制終了方式は未決定とする。
- Process groupおよび子プロセス管理方式は未決定とする。
- SDカード切断中のFFmpeg挙動は未検証とする。

これらは対応する本実装より前の開始Gateで、必要な追加検証結果をもとに正式決定する。今回の短時間実験から実装者が推測で確定しない。

### 17.3 外部SDカード通常接続I/O 技術検証結果

`experiments/external-storage-io/` の限定的な実機実験により、通常接続状態の外部SDカードに対する次の技術的成立性を確認した。実測の詳細は `experiments/external-storage-io/RESULTS.md` を参照する。

#### 検証環境の記録

- Device Identifier: `disk6s1`
- Device Node: `/dev/disk6s1`
- Volume UUID: `F042C88B-D87C-3882-8F4D-74CAD46B4F46`
- Volume Name: `Untitled`
- Mount Point: `/Volumes/Untitled`
- Filesystem: ExFAT
- Bus: USB
- Python: 3.13.14

これらは今回のローカル検証環境を識別するための記録であり、Device Identifier、Device Node、Volume UUID、Volume Name、Mount Point、ExFAT、USB接続または個別のSDカードを本番仕様として固定しない。今回の結果をExFAT全般または他のSDカードへ一般化しない。

#### 確認済みの事実

- 外部、removable、writable、mountedであることと、承認されたデバイス識別情報を操作前に確認できた。
- ユーザーが承認した新規の専用実験ルートだけへ操作を限定できた。
- partialファイルの排他的な新規作成、書込み、flush、`fsync`、読戻しが成立した。
- 書込み後に期待bytesとの完全一致とSHA-256一致を確認できた。
- partialから正式名へのrenameと、rename後のbytes完全一致およびSHA-256一致を確認できた。
- 日本語と空白を含むファイル名を扱えた。
- mountpoint、実験ルート、対象ファイルのsymlinkを拒否し、固定ルート、固定ファイル名、path traversal拒否によって操作範囲を制限できた。
- 削除前に想定外項目を検知した際、安全ガードが自動削除を停止した。
- 個別承認と複数回の再確認を経て、実験専用ファイルと空になった専用実験ルートの後片付けを完了できた。
- 後片付け後、専用実験ルートが存在せず、SDカードのmountpointと識別情報が維持されていることを確認した。

#### 想定外項目と安全停止

削除前の専用実験ルート直下に、正式テストファイルに加えて `._日本語 空白 読み書きテスト.txt` が存在した。読み取り専用調査では、同ファイルは通常ファイル、非symlink、4,096 bytesだった。当初の自動削除許可集合に含まれていなかったため、安全ガードが自動削除を停止した。

正式テストファイルを個別に削除した後、`._` ファイルを個別削除しようとした時点では存在せず、その後の読み取り専用確認でも存在しなかった。`._` ファイルの作成主体、生成条件、内容、正式ファイル削除との因果関係および存在しなくなった理由は断定しない。

安全ガードによる停止は、想定外項目を推測で削除しなかったという限定的な確認事実である。一方、当初設計どおりの自動後片付けは未成立だった。個別承認と再確認を伴う手動の後片付け完了を、本番の自動reconciliation成立の根拠にしない。

#### 検証結果の限界

今回成立したpartial書込み、flush、`fsync`、bytes／SHA-256検証、rename、rename後検証および `Path.unlink()` は、小容量な単一実験ファイルと通常接続状態に限定した候補方式である。SHA-256、`fsync`、rename、`Path.unlink()` を本番方式として確定せず、完成MP4保存方式、正式化の原子性、保存トランザクションまたはreconciliationが成立したとは扱わない。

#### 未検証・未決定の事項

- `._` ファイルの生成条件、ライフサイクル、本番での扱い、およびsidecarファイルの安全な清掃契約
- 他のExFAT媒体での再現性、およびAPFS、FAT32、NTFS等での挙動
- 長時間・大容量ファイル、複数ファイル、容量不足、読取り専用化
- 書込み途中、rename途中、rename直後の切断
- 再接続、partial復旧、reconciliation
- App SandboxおよびSecurity-Scoped Bookmarkの採否
- 本番保存先構造、本番ファイル名、衝突方式、完成MP4保存方式
- 本番の削除可能ルート

通常接続時の限定I/O結果を正式反映しても、外部SDカードの切断・再接続を含む第0段階の技術検証全体は完了扱いにしない。保存契約は第19開始Gate、切断・復旧・reconciliationは第20開始Gate、App SandboxとSecurity-Scoped Bookmarkの最終採否は第22開始Gateを維持し、それぞれ必要な追加検証と正式決定を行う。

### 17.4 `stop.requested` とFFmpeg停止 技術検証結果

`experiments/stop-requested-ffmpeg/` の限定的な実験により、`stop.requested` を使うcooperative stop候補と、実行中FFmpegの停止後に状態を検証してから停止完了を分類する方式の技術的成立性を確認した。実測の詳細は `experiments/stop-requested-ffmpeg/RESULTS.md` を参照する。

#### 確認済みの事実

- FFmpeg開始前に `stop.requested` が存在する場合と、FFmpeg実行中に停止要求を検知した場合を区別できた。
- 実行中FFmpegの停止では、`stop_requested_detected`、`ffmpeg_exit_observed`、`post_stop_state_verified`、`stop_complete_classified` の順序を機械的に確認できた。
- 正常完了、ユーザー停止、FFmpeg異常終了を区別できた。
- 停止または異常終了したケースでは、partialを正式成果物へ昇格させなかった。
- 停止要求後およびFFmpeg異常終了後に、後続工程を開始しなかった。
- 全ケースで対象FFmpegプロセスの終了を確認し、対象子プロセスを残さず終了できた。
- FFmpegの終了だけを停止完了の根拠にせず、停止後状態の検証を経てから停止完了を分類する候補方式が成立した。

正常完了ケースでは、FFmpegの終了コード0だけで正式化せず、partialの存在・非空とffprobeによるvideo stream、audio stream、正のdurationを確認した後にだけ、実験用正式成果物へrenameした。

#### 検証条件と限界

今回の実験では、Python標準ライブラリの `subprocess.Popen(..., shell=False)` と引数配列を使用し、実行中停止の候補操作として対象の `Popen` インスタンスだけへ `terminate()` を実行した。正常ジョブ2秒、停止対象ジョブ10秒、停止要求まで0.5秒、poll間隔0.05秒、ケースdeadline 15秒、実験上のterminate猶予3秒、人工入力、Matroska、mpeg4、aacその他の値と方式は検証専用である。これらを本番のsignal、時間値、codec、コンテナ、FFmpegコマンドまたは停止契約へ昇格させない。

#### 未検証・未決定の事項

- 本番で使用する停止signal
- 停止猶予時間と強制終了条件
- 強制終了の採否と方式
- Process group方式と孫プロセス管理
- SwiftからPythonへの停止通信schema、および停止完了event形式
- `stop.requested` の本番での作成、所有、削除、stale判定
- 本番FFmpegコマンド、codec、解析用WAV、完成MP4保存方式
- 実際の長時間・高負荷処理、複数子プロセス、停止と自然終了・異常終了が競合する境界での挙動
- partialの保持、検証、清掃、reconciliationの正式契約
- App SandboxおよびSecurity-Scoped Bookmark下での停止動作
- アプリまたはPythonの強制終了後の復旧

これらは第14その他の対応する開始Gateまで未決定とし、今回の限定実験から推測で確定しない。今回の結果を反映しても、停止契約全体または第0段階全体を完了扱いにしない。

### 17.5 App Sandboxあり／なし subprocess比較検証結果

`experiments/app-sandbox-subprocess/` の限定的な実験で、同一の最小実装によるSwift → Python → FFmpeg subprocessチェーンをApp Sandboxなし／ありの候補構成で比較した。実測の詳細は `experiments/app-sandbox-subprocess/RESULTS.md` を参照する。

#### 確認済みの事実

- App Sandboxなしでは、Foundation `Process` によるSwiftからPythonの起動と、Python標準ライブラリからのFFmpeg起動が3回すべて成功した。
- 3回すべてでPythonおよびFFmpegの終了コード0、Python stdoutのJSON decode、stdout／stderr分離を確認した。
- App Sandboxありの候補として、同一バイナリを `com.apple.security.app-sandbox = true` 付きでad-hoc署名したbundleは、Swiftの最初の実験用段階マーカーより前に終了コード134でabortした。
- Sandboxあり版はPythonおよびFFmpegの起動処理へ到達していないため、PythonまたはFFmpegの問題とは判定しない。
- bundle構造、Info.plist、entitlementsおよび署名の静的検証は成功した一方、Gatekeeperの読み取り専用評価ではCode Signing subsystemのinternal errorが返った。
- ローカル開発署名IDは利用できず、開発署名によるApp Sandboxあり版の再検証は未実施である。

#### 検証結果の限界と未決定事項

今回のSandboxあり版は、Team Identifierを持たないad-hoc署名と実験用bundleの直接起動による候補構成に限定される。プロジェクトルールによりmacOS統合ログおよびクラッシュログは確認していないため、起動前abortの内部原因は確定していない。

SwiftPMの `--disable-sandbox` は、検証環境でSwiftPM自身のmanifest／build sandboxが使用できなかったことへのビルド時限定の回避であり、比較対象のApp Sandbox設定または本番方式として採用しない。

App Sandboxの採否、有効な開発署名または配布署名での挙動、本番の署名・配布方式、Python／FFmpeg／ffprobe／AIモデルの最終配置・同梱方式、Security-Scoped Bookmarkの採否、Sandbox下の外部ストレージアクセスおよび子プロセス停止方式は未検証・未決定のまま維持する。

Sandboxなしで3回成功したことをApp Sandboxなしの正式採用根拠にせず、Sandboxありのad-hoc署名構成がabortしたことをApp Sandbox不採用の確定根拠にも使用しない。必要な本実装より前の開始Gateで、利用可能な正式署名条件と配布条件に基づいて再検証し、App Sandbox採否を正式決定する。今回の結果を反映しても第0段階全体を完了扱いにしない。
