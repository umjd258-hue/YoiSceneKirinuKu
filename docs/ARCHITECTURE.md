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
| `job.json` | Swift（内容・状態遷移。Python runnerがlock下で原子的に永続化） | Python | Swift |
| `stop.requested` | Swift | Python | Swift |
| `analysis.wav` | Python | Python | Python（第10の不完全な既知pair）・Swift |
| `analysis_audio.json` | Python | Python・Swift | Python（第10の不完全な既知pair）・Swift |
| `vad.json` | Python | Python | Swift |
| `speaker_candidates.json` | Python | Python | Swift |
| `result.json` | Python | Swift | Swift |
| `selection.json` | Swift | Swift | Swift |
| `save_state.json` | Python | Swift | Swift |
| 完成MP4 | Python | ユーザー/アプリ | アプリでは削除しない |

同じ正式ファイルをSwift/Python双方から更新する設計にしない。

### 4.1 第3段階Preflight正式契約

Preflightは1要求につき1つのPythonプロセスを起動する。Swiftはstdinへ次の必須項目を持つUTF-8 JSON objectを1件だけ送り、入力を閉じる。

```json
{
  "protocol_version": 1,
  "request_id": "550e8400-e29b-41d4-a716-446655440000",
  "operation": "preflight",
  "source_path": "/absolute/path/video.mp4"
}
```

- `request_id` は小文字・ハイフン付きUUID v4文字列とする。
- `source_path` は絶対パスとし、Pythonは対象を読み取り専用で扱う。
- 入力schema不適合、余分な要求、未知operationを推測で処理しない。
- Swiftは選択と要求寿命を所有し、古い `request_id` の結果を現在の選択へ反映しない。

Preflightは次をすべて満たした場合だけ成功とする。

1. 入力が正式schemaに適合する。
2. 対象が存在する通常ファイルで、読み取り可能である。
3. 拡張子が大文字・小文字を問わず `.mp4` である。
4. ffprobeを起動でき、終了コードが0である。
5. ffprobe JSONが構文・必須項目・型の検証に合格する。
6. MP4系containerとして認識される。
7. video streamとaudio streamがそれぞれ1件以上存在する。
8. 有限かつ正のdurationを `duration_ms` へ変換できる。

Preflightは軽量な解析可能性確認であり、本解析の成功、全frameの完全性、対応codec、保存可能性を保証しない。元動画へ書き込まず、変換成果物も生成しない。

第3段階のPreflight deadlineは要求開始から30秒とする。Pythonからのffprobe待機は20秒を上限とし、timeout時は対象のffprobeだけを終了・回収して `probe_timed_out` とする。Swift側で30秒を超えた場合は対象のPython `Process` だけへ `terminate()` を送り、終了を待って失敗扱いとする。この契約は短時間Preflightの異常後始末に限定し、第14段階の解析停止signal、猶予時間、強制終了方式またはProcess group契約を決定しない。

## 5. 永続データ共通契約

永続JSONは次の原則に従う。

- トップレベルの `schema_version` を必須とし、初期versionはJSON整数 `1` とする。
- 永続データ間の参照には、小文字・ハイフン付きUUID v4文字列の安定した一意IDを使用する。
- 表示名や配列位置を永続的な関連付けへ使用しない。
- 動画内時刻と時間長は非負の64-bit整数ミリ秒とし、`start_ms`、`end_ms`、`duration_ms` を使用する。
- 秒から開始時刻へ変換する場合は切り下げ、終了時刻と時間長は切り上げる。区間は `start_ms < end_ms` とする。
- 未知schema、壊れたJSON、必須項目が不足したJSONを推測で正常処理しない。
- 重要なJSONはpartialまたは一時ファイルへ書き、検証後に正式化する。

ただし、重要資産ではない `selection.json` の破損については、`PRODUCT_SPEC.md` に従って標準の初期選択状態へ戻すことを明示的な例外とする。この復旧を解析結果や保存状態等の必須データへ拡張しない。

用途別IDのキー名は `request_id`、`job_id`、`character_id`、`sample_id`、`candidate_id` とする。一度正式化したIDを変更または再利用しない。各JSON固有の生成時点、参照関係、全フィールドは、そのJSONを初めて使用する開始Gateで正式決定する。

主要JSONの責務は次のとおり分離する。

| JSON | 責務 | 主な所有者 |
|---|---|---|
| `job.json` | ジョブID、入力、選択人物、Source fingerprint、ジョブ要求情報 | Swift |
| `result.json` | 正式に確定した解析候補 | Python |
| `selection.json` | UI上の保存対象選択 | Swift |
| `save_state.json` | 保存試行と正式保存済み成果物の状態 | Python |

`job.json` の全フィールド、必須条件、更新可能範囲、正式化方式は第8.1節で決定済みとする。その他のJSONは未決定とし、各JSONを初めて本体利用する段階の開始前までに正式schemaを定める。

## 6. 人物データ構造

1人物が1件以上のsampleを持つ構造とする。

```text
characters/
└─ char_xxxxx/
   ├─ character.json
   └─ samples/
      ├─ sample_xxxx/
      │  ├─ source.wav
      │  ├─ embedding.npy
      │  └─ sample.json
      └─ sample_yyyy/
         ├─ source.wav
         ├─ embedding.npy
         └─ sample.json
```

人物名ではなく内部IDを使用する。

`source.wav` は重要資産。
Embeddingは `source.wav` から再生成可能な派生データとする。

人物IDとsample IDには安定した一意IDを使用する。

各sampleのEmbeddingは192要素のfloat32配列を `.npy` 形式で保存し、読込み時はpickleを禁止する。全要素が有限値であること、shapeが `(192,)` であること、L2 normが許容誤差内で1であること、`sample.json` が記録するモデルID・revision・元 `source.wav` のSHA-256と一致することを検証する。

人物判定用Embeddingは、人物に属する全sampleの検証済みL2正規化Embeddingを算術平均し、その平均をL2正規化したcentroidとする。1 sampleにも同じ規則を適用する。centroidは保存せず、sample構成変更後または利用時に再計算する。平均のnormが0または非有限値なら人物データを無効として推測復旧しない。外れ値除去、重み付け、人物一致閾値は採用せず、第15開始Gateの人物判定検証へ残す。

### 6.1 第8A人物・sample JSON契約

`character.json` と `sample.json` はUTF-8 JSON、`schema_version: 1` とする。未知schema、未知の必須field、壊れたJSONを推測で受理しない。Pythonが生成・検証・正式化を所有し、Swiftは正式化済みデータを読込み表示する。Swiftはこれらを直接更新しない。

人物IDは `char_`、sample IDは `sample_` に小文字のcanonical UUID文字列を続ける。一度正式化したIDを変更・再利用しない。

`character.json` の必須fieldは次のとおりとする。

- `schema_version`: 整数 `1`
- `character_id`: フォルダ名と一致する安定ID
- `display_name`: 前後空白除去後に空でない人物名
- `sample_ids`: 1件以上の重複しないsample ID配列。各sampleフォルダと相互一致する

`sample.json` の必須fieldは次のとおりとする。

- `schema_version`: 整数 `1`
- `sample_id`: sampleフォルダ名と一致する安定ID
- `character_id`: 親人物IDと一致する参照
- `source_interval`: `start_ms`、`end_ms`。ともに整数で `0 <= start_ms < end_ms`
- `source_wav`: 固定相対名 `source.wav`、`sample_rate_hz: 16000`、`channels: 1`、`sample_format: "pcm_s16le"`、整数 `duration_ms`、小文字hexの `sha256`
- `embedding`: 固定相対名 `embedding.npy`、`model_id: "speechbrain/spkrec-ecapa-voxceleb"`、固定revision、`dimension: 192`、`dtype: "float32"`、`normalization: "l2"`、元WAVと同じ `source_wav_sha256`

元MP4の絶対パスは人物資産へ永続化しない。Embedding再生成は、正式 `source.wav` を入力し、`sample.json` と同じモデルID・revision・形式で一時ファイルへ生成・検証後、`embedding.npy`だけを正式化する。`source.wav` は削除・置換しない。

### 6.2 人物登録音声とAI実行契約

`source.wav` はFFmpegをshellなし・引数配列で起動し、`-nostdin`、既存出力を上書きしない指定、16kHz、モノラル、PCM signed 16-bit little-endianでpartial領域へ生成する。終了コード0だけで成功扱いせず、通常ファイル、非symlink、非空、WAV header、sample rate、channel数、sample形式、区間長を再検証する。

初期版の登録区間は3,000ms以上30,000ms以下とする。全sampleが0の音声を `registration_audio_silent`、RMSが-60 dBFS以下またはpeakが-40 dBFS以下の音声を `registration_audio_too_quiet` として拒否する。この値は登録入力の最低安全条件であり、人物一致判定や音声品質表示のAI閾値へ転用しない。

安定error codeは `registration_invalid_request`、`registration_source_unavailable`、`registration_invalid_interval`、`registration_ffmpeg_launch_failed`、`registration_ffmpeg_failed`、`registration_wav_missing`、`registration_wav_invalid_format`、`registration_audio_too_short`、`registration_audio_too_long`、`registration_audio_silent`、`registration_audio_too_quiet`、`registration_model_unavailable`、`registration_embedding_failed`、`registration_embedding_invalid`、`registration_metadata_write_failed`、`registration_finalization_failed`、`registration_character_not_found`、`registration_character_busy`、`registration_protocol_error` とする。未知codeを成功へ読み替えない。

第8A／第8Bの開発時候補はSpeechBrain 1.0.3と `speechbrain/spkrec-ecapa-voxceleb` revision `0f99f2d0ebe89ac095bcc5903c4dd8f72b367286` とする。モデルとPython環境の絶対パスはDebug設定から注入し、存在・通常ファイルまたは所定ディレクトリ・読取り可能性を起動前に検証する。Debug用virtualenvのPython実行パスはvenv判定を保持するため元の絶対パスで起動してよいが、symlink解決先が通常の実行可能ファイルであることを検証する。モデルディレクトリと人物データ境界のsymlinkは許可しない。実行中にモデルをダウンロードしない。完成版のPython・AIモデル配置／同梱方式とApp Sandbox採否は第22開始Gateまで未決定とする。

人工合成音声による限定検証では、CPU上で192次元有限値Embeddingを再現可能に生成し、L2正規化centroidを構成できた。ただし実人物音声、雑音、複数話者、方言、端末差を使った精度検証ではないため、人物一致閾値は第15開始Gateまで未決定とする。実測詳細は `experiments/speaker-embedding/RESULTS.md` を参照する。

## 7. 人物データのトランザクション

### 新規人物

完成前の人物を正式人物フォルダとして扱わない。

固定人物データルートはmacOS Application Support配下の `local.YoiSceneKirinuKu/characters` とする。Swiftがルートを解決し、Pythonへ絶対パスとして渡す。Pythonは標準化後のパスが固定ルート内にあり、親から対象までsymlinkでないことを検証する。

例:

```text
characters/.partial/char_xxxxx
```

一時領域は固定ルート直下の `.partial` のみに置き、正式人物と同じvolume上で作る。以下がすべて成功してから、人物ディレクトリ全体を `characters/char_xxxxx` へ1回のrenameで正式化する。

1. 登録音声生成
2. 最低限の品質確認
3. Embedding生成
4. 必要メタデータ確定

正式化前に `source.wav`、`embedding.npy`、`sample.json`、`character.json` の相互参照と内容を再読込み検証する。正式人物IDとの衝突、想定外項目、symlink、検証失敗があればrenameしない。正式化後にSwiftが再読込みと同じ検証を通過した場合だけ登録成功を表示する。起動時の人物一覧は `.partial` を無視し、正式人物として扱わない。

既存人物へサンプル追加する場合も、新規サンプルだけを一時状態で生成する。失敗しても既存人物データへ影響させない。

### 既存人物へのsample追加

既存人物へsampleを追加する場合は、新sampleだけを一時領域で生成・検証する。`source.wav`、Embedding、メタデータがすべて正式化可能になってから人物データへ関連付ける。

新規人物の正式化、失敗時の不変条件、品質検証条件は本節の契約とする。第8Bでは、人物IDごとの固定lock fileを `.partial` 内に置き、非待機の `fcntl.flock` 排他を追加開始前から正式化後の検証完了まで保持する。同じ人物への競合要求は `registration_character_busy` で拒否し、既存人物を変更しない。lock fileは削除・置換せず、プロセス終了時にOSが排他を解放する。待機時間、PID、heartbeat、owner tokenは導入しない。

追加処理は既存人物ディレクトリを直接更新しない。正式人物を検証後、通常ファイルだけを `.partial/update_<UUID>/char_<UUID>` へcopy-on-writeで複製し、その複製内で新sampleを生成・検証する。新 `sample.json` を確定後、追加後の全 `sample_ids` を持つ `character.json` を複製内で最後に更新し、人物全体を再読込み検証する。既存IDの再利用、symlink、想定外項目、人物ID不一致は拒否する。

検証済み更新候補と正式人物は、同一volume上でmacOSの `renameatx_np(..., RENAME_SWAP)` により原子的に交換する。限定人工ディレクトリ検証では、交換後に正式パスへ新内容、partial側へ旧内容が一操作で移ることを確認した。交換前に停止・失敗・クラッシュした場合は旧人物だけが正式であり、交換後にクラッシュした場合は事前検証済みの新人物だけが正式となる。partial側の旧人物または未完成更新候補は人物一覧から無視する。交換後に正式人物を再検証し、Swiftが再読込みして新sample IDを確認した場合だけUI件数を増やす。

交換後の旧人物コピーは、正式人物の再検証後に限り、固定 `.partial/update_<UUID>` 配下で期待構造と非symlinkを再確認して清掃できる。清掃失敗は正式人物を失敗へ戻さず、無視可能なpartialとして残す。`renameatx_np` が利用できない場合やatomic swapに失敗した場合は `registration_finalization_failed` とし、非原子的な複数renameへfallbackしない。存在しない人物は `registration_character_not_found` とする。

### 人物削除

初期版の削除対象は人物全体だけとし、個別sample削除は実装しない。最後の1sampleを単独削除する操作も提供しない。人物全体を削除する場合は、その人物の `character.json`、`samples/`、全 `sample.json`、`source.wav`、`embedding.npy` だけを対象とする。完成MP4、元動画、`current_job`、他人物、人物データルート自身は削除対象にしない。

削除可能ルートはApplication Support配下の固定 `local.YoiSceneKirinuKu/characters` に限定する。Swiftまたは外部入力から削除対象パスを受け取らず、canonicalな `char_<UUID>` だけを受け取って固定ルート直下の1階層として組み立てる。固定ルート、`.partial`、対象人物、全親と全子についてcanonical path、期待した種類、非symlink、既知項目だけであることを検証する。`..`、区切り文字、絶対パス、未知項目、IDとフォルダ名・JSONの不一致、ルート自身を拒否する。

人物データ利用の共通排他は `.partial/global.lock` と `fcntl.flock` を使用する。人物登録・sample追加、および将来の解析等で人物データを読む処理はshared lockを保持し、人物削除はexclusive non-blocking lockを削除要求から正式削除確認まで保持する。sample追加はshared global lock取得後に既存の人物別exclusive lockを取得する。削除競合は `registration_character_busy` として拒否する。Swift側でも、解析開始要求中、解析中、停止要求中、保存中、新規登録中、sample追加中は削除要求を作らないが、UIのdisabledだけを排他根拠にしない。

削除前に正式人物全体を再検証し、同一volumeの `.partial/delete_<UUID>/char_<UUID>` へ人物ディレクトリ全体を1回renameする。rename前の失敗・クラッシュでは正式人物を維持し、rename後は正式パスが存在しないことを再確認した時点で論理削除済みとする。rename後のtombstoneは人物一覧から無視し、既知構造・非symlinkを再検証した場合だけファイルを個別unlinkし、空ディレクトリを内側から非再帰rmdirする。glob、パスから推測した対象、一般的な再帰削除を使用しない。清掃失敗時はtombstoneを残して論理削除成功とし、他の項目を代替削除しない。

Pythonが正式パス不在を確認し、Swiftが正式人物一覧を再読込みして対象人物不在を確認した場合だけUIを削除完了へ進める。削除要求、rename、Python確認、Swift再読込みのいずれかが未完了なら削除済み表示にしない。存在しない人物は `registration_character_not_found`、安全検証またはrename失敗は `registration_character_delete_failed` とする。partial tombstoneの一般reconciliation時期は後続復旧統合へ残すが、正式人物一覧の正しさには影響させない。

## 8. current_job

初期版は基本的に1ジョブのみ。

概念例:

```text
current_job/
├─ job.json
├─ analysis.wav
├─ analysis_audio.json
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

### 8.1 第9段階の正式状態機械

`job.json.state` は `start_requested`、`preparing`、`running`、`stop_requested`、`stopped`、`completed`、`failed`、`recovery_required` のいずれかとする。フォルダ、lock file、Pythonプロセスの存在だけから状態を推測しない。

- 新規要求は `start_requested` から始まり、排他取得と入力検証後に `preparing`、Python runnerの開始確認後に `running` へ進む。
- `running` からだけ `stop_requested` へ進める。`stopped` への遷移は第14段階の停止後検証を満たした場合だけ許可する。
- `completed` は第15段階で正式 `result.json` を検証した場合だけ許可し、`finished` 受信だけでは遷移しない。
- 準備・通信・process・永続化の失敗は `failed` とする。ただし、アプリ起動時に旧jobがactive状態のまま正式lock所有者を確認できない場合は、推測で失敗または実行中にせず `recovery_required` とする。
- `recovery_required` からの再開は、排他取得、Source fingerprint一致、stale停止要求処理、各正式成果物のschema検証をすべて満たす場合だけ許可する。未実装の後続成果物を再利用しない。

`job.json` の内容と状態遷移はSwiftが要求し、正本契約で固定した復旧監査結果だけは正式lockを保持するPython runnerが判定する。物理的なファイル作成・更新はrunnerが、Swiftから受け取って厳密検証したdocument、または契約どおりの復旧遷移だけを原子的に永続化する。Pythonがそれ以外の状態や入力を独自に決定してはならない。トップレベルは次の必須項目だけに限定する。

```json
{
  "schema_version": 1,
  "job_id": "550e8400-e29b-41d4-a716-446655440000",
  "start_request_id": "6ba7b810-9dad-4f75-a0a7-6f55b7de34aa",
  "state_revision": 0,
  "state": "start_requested",
  "source": {
    "path": "/absolute/path/video.mp4",
    "fingerprint": {
      "version": 1,
      "algorithm": "sha256",
      "byte_count": 123456,
      "digest": "64文字の小文字16進数"
    }
  },
  "selected_character_ids": ["char_550e8400-e29b-41d4-a716-446655440000"],
  "failure_code": null
}
```

`job_id` と `start_request_id`、`source`、`selected_character_ids` は作成後に変更しない。`selected_character_ids` は1件以上で重複を許さない。Swiftが更新を指示できるのは `state_revision`、`state`、`failure_code` だけとし、更新ごとにrevisionを1増やす。`failure_code` は `failed` の場合だけ安定error code文字列、それ以外はnullとする。全項目と入れ子objectは余分な項目を拒否する。Python runnerは固定 `.partial/job_<request_id>.json.partial` へ排他的に書き、flush、fsync、再読込み検証後に `job.json` へ同一volume renameし、正式ファイルも再読込み検証する。

### 8.2 Source fingerprint

正式な同一性判定は、通常ファイルの全byteを対象とするSHA-256とbyte数の組合せとする。更新時刻、部分hash、inodeは正式な一致根拠に使用しない。計算前後に同じ通常ファイル・非symlinkであること、byte数、更新時刻のナノ秒値、filesystem上のfile identityが変わっていないことを確認し、途中変更、読取失敗、切断はfingerprint計算失敗としてjobを開始しない。計算途中のdigestを保存または再利用しない。

再開・復旧時は元動画を再度全体hashし、`version`、`algorithm`、`byte_count`、`digest` がすべて一致する場合だけ後続の正式成果物検証へ進む。不一致または再計算不能時は中間成果物を再利用せず、`source_changed` または `source_unavailable` として安全に失敗する。今回の方式は検出能力を優先した初期版契約であり、将来軽量化する場合はschema versionを変更して別Gateで再決定する。

### 8.3 多重起動・二重解析防止

固定workspace直下の `analysis.lock` に対する非待機 `fcntl.flock(LOCK_EX | LOCK_NB)` を唯一の実行排他根拠とする。lock fileの存在、`current_job` の存在、`job.json.state`、PID、時刻をlock所有の根拠にしない。初期版ではstale時間、PID照合、heartbeat、owner token、所有者メタデータを採用しない。

lockはSwiftUI ViewではなくPython解析runnerが、解析要求を受理する前に取得し、全子プロセス終了と終了後状態検証が終わるまで同じfile descriptorで保持する。Swiftはrunnerから要求と一致する `progress(stage: "job_lock", status: "completed")` を受信するまで `job.json` を正式化せず、lock競合は `analysis_busy` として後続処理を開始しない。runnerの異常終了時はOSによるlock解放を利用し、lock fileを削除しない。新しいアプリがactive状態の旧jobを発見した場合、lock取得できても直ちに新解析を始めず `recovery_required` として復旧監査する。

`flock` はadvisory lockであるため、解析runner、復旧、停止、current_jobを変更する全Serviceが同じ取得規約を守る。App Sandboxと完成版filesystemでの最終成立性は第22開始Gateまで未検証とする。

### 8.4 `stop.requested` とworkspace境界

`stop.requested` はSwift所有の永続JSONとし、`schema_version: 1`、対象 `job_id`、停止操作の `request_id` だけを必須とする。固定partialへ排他的に書き、flush、fsync、再読込み検証後に正式化する。Pythonは正式ファイルだけを読み、壊れたJSON、未知schema、job不一致を停止要求として推測しない。

新規開始または復旧監査時、正式lockを取得したServiceだけが `stop.requested` を判定する。現在の `job.json.state == stop_requested` かつjob ID一致の場合だけ有効要求とする。それ以外の正しく検証できる停止要求はstaleとし、固定ファイル1件だけを個別unlinkして不在を確認する。symlink、未知項目、壊れたJSONは削除せず `job_workspace_invalid` でfail-closedとする。時刻や経過秒数でstaleを推測しない。停止完了表現と停止後清掃は第14開始Gateで確定する。

workspaceはApplication Support配下の固定 `local.YoiSceneKirinuKu/workspace`、job領域はその直下の固定 `current_job` とする。第9段階で作成・更新・清掃できるのは `analysis.lock`、`current_job/job.json`、`current_job/stop.requested`、および名前とrequest IDを検証した対応partialだけとする。外部入力から削除パスを受け取らず、全親と対象の非symlink、canonicalな1階層、既知種類を検証する。glob、一般的な再帰削除、未知項目の削除、workspace root自身の削除を禁止する。後続段階が成果物を追加するたびに許可リストと清掃責務をその開始Gateで拡張する。

### 8.6 第10段階の解析用音声契約

`analysis.wav` は元動画の先頭音声stream（FFmpeg stream specifier `0:a:0`）だけを、16,000 Hz、1 channel、PCM signed 16-bit little-endian、WAV containerへ変換した解析専用成果物とする。動画、字幕、data streamを出力へ含めない。先頭音声streamが存在しない、正のdurationを取得できない、または読取りに失敗した場合は生成しない。

Pythonはshellを介さず、設定から渡された検証済みFFmpeg／ffprobe実行ファイルと引数配列を使用する。開発時は既存のローカル `/opt/homebrew/bin/ffmpeg` と `/opt/homebrew/bin/ffprobe` を使用し、Release設定は空のままとする。この開発時配置を配布時の配置・同梱方式へ昇格させない。

生成先はworkspace直下の固定 `.partial/analysis_<request_id>.wav.partial` とし、FFmpegへ `-nostdin`、既存出力を上書きしない指定、明示的なWAV formatを渡す。FFmpeg終了コード0だけで成功扱いせず、通常ファイル、非symlink、非空、WAV header、16,000 Hz、1 channel、sample幅2 byte、非圧縮PCM、正のframe数と整数ミリ秒durationをPython標準ライブラリで再読込み検証する。

正式な再利用根拠は `analysis.wav` と `analysis_audio.json` の一組とする。metadata schema version 1は、`job_id`、`source_fingerprint`、固定変換profile、選択stream index、frame数、整数ミリ秒durationを余分な項目なしで持つ。Source fingerprint全項目とjob IDが正式 `job.json` に一致し、profileとWAV実体を再検証できる場合だけ再利用する。一方だけ存在する、partialだけ存在する、schema不明、内容不一致、symlinkまたは未知項目がある場合は再利用しない。

正式化は、両partialの書込完了、flush／fsync、再読込み検証後に、`analysis_audio.json`、最後に成功commit markerとなる `analysis.wav` の順で同一volume renameし、directory fsync後に両方を再検証する。正式化途中で一方だけ残った既知の派生成果物は、正式lock下で通常ファイル・非symlink・固定名を再確認した場合だけ個別unlinkして最初から生成し直す。再帰削除、glob、未知項目削除を行わない。

変換前にSource fingerprintを再計算し、変換後・正式化前にも再計算する。途中変更、不一致、読取不能ではpartialを正式化しない。必要空き容量は、ffprobeの正のdurationから算出した理論PCM byte数にWAV header用1 MiBを加えた値以上とし、不足時はFFmpegを起動しない。この1 MiBはファイル形式上の保守的な検証値であり、保存機能の容量契約へ転用しない。

error codeは `analysis_audio_busy`、`analysis_audio_job_invalid`、`analysis_audio_source_unavailable`、`analysis_audio_source_changed`、`analysis_audio_probe_failed`、`analysis_audio_duration_invalid`、`analysis_audio_insufficient_space`、`analysis_audio_ffmpeg_failed`、`analysis_audio_invalid`、`analysis_audio_finalization_failed`、`analysis_audio_reuse_invalid`、`analysis_audio_protocol_error` とする。実ストレージ切断は未検証とし、読取不能・書込不能を安全に失敗させる自動試験と区別する。

### 8.7 第11段階のVAD契約

第11段階は、正式な`analysis.wav`と`analysis_audio.json`のpairを第10契約で再検証してから、Python標準ライブラリによる固定frame RMS方式で音声activityを一次検出する。追加のPython packageやFFmpeg subprocessは使用しない。この方式は人の声とBGM・SE・環境音を識別するAIではなく、候補生成前の軽量なactivity検出だけを担当する。

入力は16,000 Hz、mono、PCM signed 16-bit little-endianの正式WAVに限定する。30ms単位でRMSを計算し、-45 dBFS以上をactive frameとする。連続するactive frameを整数ミリ秒の半開区間`[start_ms, end_ms)`としてメモリ内だけで表現し、連続90ms未満は除外する。最終frameが30ms未満でも処理する。発話0件は正常結果とする。

この連続化はframe判定結果の表現に限る。離れた区間の結合、間隔補完、前後余白、候補の最小・最大長、分割、候補IDは第12開始Gateまで決定・実装しない。第11段階では`vad.json`その他の永続成果物を作成せず、検出区間を正式な後段入力または再利用根拠にしない。

JSON Linesの`progress`は`stage: vad`と`status: running`／`completed`を順に使用する。安定error codeは`vad_busy`、`vad_job_invalid`、`vad_input_unavailable`、`vad_input_invalid`、`vad_processing_failed`、`vad_protocol_error`とする。壊れたWAV、未知metadata、pair不一致、symlink、非正式入力を推測で処理しない。発話0件をerrorへ変換しない。

人工tone・noiseを使った限定比較では、Python frame RMS方式とFFmpeg `silencedetect`が全ケースに一致し、Python方式は同じ2秒入力で約1.1〜1.3ms、FFmpeg方式は約20〜22msだった。`torchaudio.functional.vad`は全activity区間を返すAPIではなく今回の責務に不適合だった。実人物、BGM、SE、残響、複数話者での検出精度は未検証であり、この条件を人物一致、音声品質、候補生成の閾値へ転用しない。実測詳細は`experiments/vad-candidates/RESULTS.md`を参照する。

### 8.8 第12段階のVAD・候補成果物契約

第12段階は、第11契約のVAD処理結果を`vad.json` schema version 1として初めて永続化し、そこから`speaker_candidates.json` schema version 1を生成する。両JSONはPythonが作成・更新・検証し、Swiftは更新しない。すべてUTF-8、余分なfieldなしの厳密JSONとし、配列順序は開始時刻昇順、区間は非重複の半開区間`[start_ms, end_ms)`とする。

`vad.json`の必須fieldは`schema_version`、`job_id`、`analysis_audio_fingerprint`、`profile`、`audio_duration_ms`、`segments`とする。`analysis_audio_fingerprint`は`algorithm: "sha256"`、`wav_byte_count`、`wav_digest`、`metadata_byte_count`、`metadata_digest`を持ち、正式`analysis.wav`と`analysis_audio.json`それぞれのbyte数と全byte SHA-256を記録する。`profile`は`frame_ms: 30`、`threshold_millidecibels: -45000`、`minimum_activity_ms: 90`とする。各segmentは`start_ms`、`end_ms`、`duration_ms`を持ち、`duration_ms == end_ms - start_ms`、90ms以上、`0 <= start_ms < end_ms <= audio_duration_ms`を必須とする。0件配列は正常な正式成果物とする。

`speaker_candidates.json`の必須fieldは`schema_version`、`job_id`、`vad_fingerprint`、`generation_profile`、`candidates`とする。`vad_fingerprint`は`algorithm: "sha256"`、`byte_count`、`digest`を持ち、正式`vad.json`のbyte数と全byte SHA-256を記録する。`generation_profile`は`merge_gap_ms: 500`、`padding_before_ms: 250`、`padding_after_ms: 250`、`minimum_duration_ms: 3000`、`maximum_duration_ms: 30000`、`split_overlap_ms: 0`とする。各candidateは`candidate_id`、`start_ms`、`end_ms`、`duration_ms`を持ち、範囲、順序、非重複、長さ、IDの一意性を厳密検証する。0件配列を正常とする。

候補生成は、隣接VAD区間のgapが500ms以下なら結合し、その後に前後各250msを加えて`0...audio_duration_ms`へclampする。3,000ms未満は中心基準で拡張し、動画端へ達した分を反対側へ移す。拡張後に接触または重複した区間はunionする。30,000ms超はoverlapなしで時刻順に分割し、最後が3,000ms未満になる場合は直前の分割点を前へ移して両方を範囲内にする。動画全体が3,000ms未満なら候補0件とする。候補同士の追加余白、人物・品質に基づく再結合は行わない。

`candidate_id`は`candidate_`に小文字canonical UUIDv5を続ける。namespaceはcanonical `job_id` UUID、nameはUTF-8の`candidate:v1:<start_ms>:<end_ms>`とする。同一job、同一schema・profile、同一区間から同じIDを再生成し、一度正式化したIDを別区間へ再利用しない。

partialは固定`.partial/vad_<request_id>.json.partial`と`.partial/speaker_candidates_<request_id>.json.partial`だけを使用する。書込、flush、fsync、再読込み検証後に`vad.json`、最後に第12完了markerとなる`speaker_candidates.json`の順で同一volume renameし、directory fsync後にpairを再検証する。正式`vad.json`だけが残り、入力fingerprintとprofileが一致する場合は候補だけを再生成できる。両方が厳密に一致する場合だけ再利用する。候補だけ、未知schema、不一致、symlink、未知項目は推測復旧せずfail-closedとする。既知のstale partialだけを正式lock下で個別unlinkできる。

進捗は`stage: candidate_generation`で`running`、`vad_completed`、`completed`の順とする。安定error codeは`candidate_busy`、`candidate_job_invalid`、`candidate_input_unavailable`、`candidate_vad_failed`、`candidate_vad_invalid`、`candidate_generation_failed`、`candidate_finalization_failed`、`candidate_reuse_invalid`、`candidate_protocol_error`とする。`finished`、正常exit、両EOFだけでは成功扱いせず、正式pairの再読込み検証を必須とする。

人工区間比較では、balanced profileが400ms gapを結合し800ms gapを分離し、端点拡張、65秒区間の非重複分割、0件、UUIDv5再現、重複入力拒否に成功した。実会話での体感品質は未検証であり、人物一致・音声品質・保存MP4切出しの閾値へ転用しない。実測詳細は`experiments/candidate-intervals/RESULTS.md`を参照する。

### 8.5 スリープ抑止

長時間の解析・保存中は意図しないidle sleepによる中断を避ける必要がある。ただし第9段階は実解析を行わないため、スリープ抑止を実装しない。具体API、開始・解除・異常終了時の最終契約、App Sandbox下の挙動は第22開始Gateで正式決定する。採用時はServiceが長時間処理開始直前に取得し、全子プロセス終了と状態検証後に正常・失敗・停止の全経路で解除するものとし、Viewの寿命には結び付けない。

## 9. Swift-Python通信

初期版ではPython stdoutをJSON Lines通信専用とする。

イベント種類は基本的に3つへ絞る。

- `progress`
- `error`
- `finished`

通常ログはstdoutへ出さず、stderrまたはログファイルへ出す。

通信schemaと永続JSON schemaは別契約とし、通信の初期versionはJSON整数 `protocol_version: 1` とする。各eventは次の共通項目を必須とする。

- `protocol_version`
- `type`: `progress`、`error`、`finished` のいずれか
- `request_id`: 要求と一致するUUID v4文字列
- `sequence`: 1から始まり1ずつ増加する整数
- `payload`: JSON object

### progress例

```json
{
  "protocol_version": 1,
  "type": "progress",
  "request_id": "550e8400-e29b-41d4-a716-446655440000",
  "sequence": 1,
  "payload": {
    "stage": "preflight",
    "status": "running"
  }
}
```

第3段階では `progress.payload.stage` は `preflight`、`status` は `running` または `completed` とする。Preflightのprogress送信は任意であり、Swiftは要求開始時点で動画カードを確認中へ移す。

`error.payload` は正式な `code` を必須とする。Preflight失敗時は1件の `error` の後、同じcodeを持つ `finished.payload.outcome: "failed"` を送る。技術例外文字列やffprobe stderrをstdout payloadへ含めない。

Preflight成功時の `finished.payload` は、`outcome: "succeeded"` と、少なくとも `file_name`、`duration_ms`、`container_format`、`video_stream_count`、`audio_stream_count` を持つ `result` を必須とする。terminal `finished` は1件だけとする。

通信は次の原則に従う。

- stdoutは1行1JSONのJSON Lines通信専用とする。
- 通常ログはstdoutへ出さない。
- 壊れたJSONや未知eventを通常ログとして読み飛ばし、正常処理を継続しない。
- `finished` はプロセス側の処理終了通知であり、成果物の成功証明ではない。
- 未知protocol version、malformed JSON、未知type、必須項目不足、型不一致、`request_id` 不一致、sequenceの重複・欠落・逆行、terminal event後のeventはprotocol violationとし、要求全体を `protocol_error` で失敗扱いにする。
- protocol violation発生後に受信したeventを成功根拠に使用しない。

第3段階のPreflight成功には、起動成功、protocol violationなし、要求と一致するID、`error`なし、妥当な `finished(outcome: succeeded)` とresult、process exit code 0、stdout／stderr双方のEOF確認をすべて必要とする。終了コード0だけ、または `finished` だけでは成功にしない。exit code非0、signal終了、起動失敗、terminal event欠落は失敗とする。

第9段階以降の共通runnerも同じ共通フィールド、sequence、EOF、exit、terminal規則を使用する。`progress.payload` はoperationごとに正本化した `stage` と `status` の完全一致、`error.payload` は安定 `code` だけ、`finished.payload` は成功時に `outcome: "succeeded"` とoperation固有の検証可能な `result`、失敗時に `outcome: "failed"` と直前errorと同じ `code` を必須とし、余分な項目を拒否する。Stage 9のrunnerは `job_lock` と `job_ready` のstage、`running` と `completed` のstatusだけを使用し、成功resultは一致する `job_id` と最終 `state` だけを返す。

malformed JSON、未知event、未知stage/status、未知error code、型不一致、要求IDまたはjob ID不一致、sequence違反、error後の成功、terminal欠落・重複・後続eventをすべて `protocol_error` とする。protocol violation後はrunnerを成功根拠にせず、対象process終了、stdout／stderr双方のEOF、正式 `job.json` 再検証まで完了して失敗状態を確定する。大量・長時間stdout／stderrの読取りは第0段階で成立した独立逐次読取りを使用し、具体buffer、Queue、Concurrency方式は実装詳細として固定しない。

停止完了を独立eventとして追加するか、既存の `progress` または `finished` に明確な終了理由を持たせるかは未決定とする。基本3種類との整合性を検証し、第14開始前までに正式決定する。独立eventを実装時に推測で追加しない。

## 10. エラー通信

Pythonの技術例外文字列をそのままユーザーUIへ出さない。

Pythonは安定したエラーコードを返し、Swift側がユーザー向け日本語へ変換する。

詳細ログは開発・診断用として別経路に保持する。

第3段階のPreflight error codeは、`invalid_request`、`unsupported_file_type`、`input_not_found`、`input_not_readable`、`probe_not_started`、`probe_timed_out`、`probe_failed`、`invalid_probe_output`、`video_stream_missing`、`audio_stream_missing`、`invalid_duration`、`protocol_error`、`internal_error` とする。UI文言は `UI_SPEC.md` を正本とする。未知codeは成功扱いせず、Swiftで `internal_error` 相当の一般文言へ変換する。

ログ保存場所・保存期間・動画パスや人物名等の取扱い、および後続機能固有のerror codeは未決定とし、対応する本体接続前までに正式決定する。

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

候補区間生成、結合、分割、境界、ID、永続化規則は第8.8節を正本とする。

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

初期版はApp Store配布を前提としない。第3段階からの初期開発構成はApp Sandboxなしとする。これはSandboxなしのSwift→Python→FFmpegチェーンが限定実験で3回成立し、Sandboxありはad-hoc署名構成で起動前abort、有効な開発署名で未検証であるため、Preflight実装と署名問題を分離するための開発時決定である。Sandboxが技術的に不可能という判定ではなく、配布版の最終採否は第22開始Gateまで未決定とする。

第3段階では、Foundation `Process` をSwift→Python subprocessの正式方式として採用する。`executableURL`と引数配列を分離し、shellを介さず、stdin／stdout／stderrを独立Pipeで扱い、stdout／stderrを実行中から読み、終了後に両EOFを確認する。ProcessはViewではなくServiceが所有する。この採用範囲はPreflightまでとし、長時間解析のbuffer、Queue、Concurrency、停止およびProcess group方式を決定しない。

第3段階の開発時は、Pythonとffprobeの絶対パスをDebug用設定から注入し、起動前に絶対パス、通常ファイル、実行可能性を検証する。`PATH`探索、Homebrew固定パス、検証環境のCellarパスをソースへハードコードしない。Preflight用Pythonソースはプロジェクト所有のアプリResourceとする。Python、FFmpeg、ffprobe、AIモデルの完成版配置・同梱方式は第22開始Gateまで未決定とする。

Security-Scoped Bookmark、配布版App Sandbox、スリープ抑止方式も未決定とし、対応する後続Gateで正式決定する。

各検証には、検証目的、合格条件、影響する仕様、正式決定期限を設ける。検証成功だけで本体仕様を自動変更せず、結果を本書へ正式反映してから関連する本体実装を開始する。

第1段階に必要な技術成立性が確認され、残る未検証・未決定事項が対応する後続段階の開始Gateへ明示的に割り当てられている場合、第0段階を完了できる。後続Gateへの繰延べは、未検証事項を検証済みに変更すること、候補方式を本番採用すること、または後続Gateを省略することを意味しない。

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
- この技術検証時点ではApp Sandboxの採否は未決定だった。第3段階の開発構成と配布版の最終採否は、本書第17節冒頭の方針に従って分離する。
- この技術検証時点ではJSON Lines schemaとprotocol violation処理は未決定だった。第3段階Preflightの正式契約は本書第9節に従い、後続段階で追加が必要な契約は対応する開始Gateで決定する。
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

外部SDカードの切断・再接続は未検証のまま維持する。通常接続時の限定I/O結果を本番保存方式の成立根拠にせず、保存契約は第19開始Gate、切断・復旧・reconciliationは第20開始Gate、App SandboxとSecurity-Scoped Bookmarkの最終採否は第22開始Gateを維持し、それぞれ必要な追加検証と正式決定を行う。この明示的な繰延べを前提に、同項目の未検証だけを理由として第0段階の完了を妨げない。

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

これらは第14その他の対応する開始Gateまで未決定とし、今回の限定実験から推測で確定しない。停止契約全体は完了扱いにしないが、対応する開始Gateへの明示的な繰延べを前提に、同項目の未決定だけを理由として第0段階の完了を妨げない。

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

Sandboxなしで3回成功したことだけを配布版App Sandboxなしの正式採用根拠にせず、Sandboxありのad-hoc署名構成がabortしたことをApp Sandbox不採用の確定根拠にも使用しない。第3段階の開発構成は本書第17節冒頭の方針に従い、最終採否は第22開始Gateまでに、利用可能な正式署名条件と配布条件に基づいて必要な再検証と正式決定を行う。この明示的な繰延べを前提に、有効な開発署名による再検証が未実施であることだけを理由として第0段階の完了を妨げない。

### 17.6 Source fingerprint候補比較検証結果

`experiments/source-fingerprint/` の限定的な実験により、プロジェクト内の人工ファイルを使ってSource fingerprint候補の変更検出能力、見逃し、処理時間および読取り量を比較した。実測の詳細は `experiments/source-fingerprint/RESULTS.md` を参照する。

#### 確認済みの事実

- ファイルサイズだけでは、追記とtruncateを検出できた一方、同一サイズの内容変更を検出できなかった。
- ファイルサイズと更新時刻の組合せは、通常の書込みによる変更を低コストで検出できた一方、内容変更後に更新時刻を復元したケースと、同一サイズ・同一更新時刻の別内容への置換を検出できなかった。
- ファイルサイズと部分SHA-256の組合せは、読取り対象範囲内の変更を検出できた一方、読取り対象範囲外の変更を検出できなかった。
- ファイルサイズ、更新時刻、部分SHA-256の組合せも、部分hash範囲外を変更して更新時刻を復元したケースを検出できなかった。
- ファイルサイズと全体SHA-256の組合せは、今回用意した全内容変更ケースを検出し、内容が同一で更新時刻だけが変化したケースを内容変更とは判定しなかった。
- 今回の部分hash候補はファイルサイズにかかわらず一定量だけを読み取り、全体hash候補はファイル全体を読み取った。全体hashの処理時間は人工ファイルのサイズに応じて増加した。
- 同一条件の実験を2回実行し、いずれも機械検証に成功した。

#### 検証条件と限界

人工ファイルは1 MiB、64 MiB、256 MiBとし、部分hash候補は先頭、中央、末尾から各64 KiBを読み取り、各性能測定を5回実行した。これらのファイルサイズ、読取り位置、読取り範囲、反復回数および今回の処理時間は検証専用の値である。OSファイルキャッシュの影響を含み、実動画、外部SDカード、cold-cacheまたは他のMacでの性能へ一般化しない。

#### 未決定事項

- Source fingerprintの正式な構成フィールドとschema
- hash algorithm、hash範囲、chunkサイズおよびversion管理
- 全体hashを常に要求するか、軽量fingerprintとの段階的確認を許容するか
- fingerprintの計算時点、保存先、所有者および再検証時点
- fingerprint計算中に元動画が変更された場合の検出、失敗および再試行契約
- 実動画サイズと保存媒体、特に外部SDカード上での処理時間とI/O負荷
- ファイル置換やinode等の追加メタデータを扱うか
- 不一致、計算失敗、読取り途中の切断に対する状態遷移

検出能力を優先する候補としてサイズと全体SHA-256、明白な不一致を低コストで検出する候補としてサイズ、更新時刻、部分SHA-256の組合せが考えられる。ただし、軽量候補の一致だけを正式な同一性確認として扱うと、今回実測した変更を見逃し得る。今回の結果から本番方式、hash範囲または数値パラメータを確定せず、第9開始Gateまでに再利用契約と必要な追加検証を含めて正式決定する。

### 17.7 多重起動・二重解析防止候補の比較検証結果

`experiments/concurrent-job-lock/` の限定的な実験により、プロジェクト内の人工ジョブを使って排他的ファイル作成、排他的ディレクトリ作成、`fcntl.flock`、`flock`＋所有者メタデータの候補を比較した。実測の詳細は `experiments/concurrent-job-lock/RESULTS.md` を参照する。

#### 確認済みの事実

- 同一人工ジョブへ6プロセスを同時競合させた結果、全4候補で取得成功1件、競合拒否5件、処理開始1件となった。同一条件で2回実行し、いずれも同じ排他結果だった。
- 排他的ファイル作成および排他的ディレクトリ作成では、保持プロセスの異常終了後も排他物が残り、最初の再取得は拒否された。
- 排他的ファイル／ディレクトリは、実験用所有者の終了を親プロセスが確認し、既知の実験用stale排他だけを明示回収した後に再取得できた。
- `fcntl.flock` は、保持プロセスの異常終了後にOS lockが解放され、ロックファイル自体を削除せず次のプロセスが再取得できた。
- `flock`＋所有者メタデータは、OS lockによる排他と診断・復旧判断用情報を分離できる候補として成立した。壊れた所有者JSONは `metadata_invalid` として処理を開始せず、推測で正常扱いしなかった。
- 全クラッシュケースで対象の実験用子プロセスが残っていないことを確認した。
- 人工的な `current_job` 相当フォルダだけが存在する状態を実行中とは分類せず、フォルダ存在と正式な排他所有状態を分離できた。

#### 検証条件と限界

今回の競合数6、排他保持0.30秒、ケースdeadline 5秒、終了コード、ファイル名およびメタデータ項目は検証専用の値である。結果は今回のプロジェクトが置かれたローカルfilesystemと、同じ排他規約に従う実験プロセスに限定される。外部SDカード、ネットワークfilesystem、複数Mac、App Sandboxまたは本番プロセス構成へ一般化しない。

`flock` はadvisory lockであり、関係する全プロセスが正式な取得規約を守らなければ排他を保証しない。ロックファイルや `current_job` フォルダの存在自体を実行状態または所有権の根拠にしない。

#### 第9開始Gateの第一候補

ローカルfilesystem上では、`fcntl.flock` を排他の根拠とし、所有者・ジョブ状態のメタデータを診断および復旧判断用として分離する方式を、第9開始Gateで正式検討する第一候補とする。

これは今回の限定条件で、競合時の取得者を1件に限定し、保持プロセスの異常終了後にOS lockが解放され、残ったファイルの存在を実行中と誤認せず再取得できたためである。第一候補という位置づけは本番採用の決定ではない。

#### 未決定事項

- 本番の排他方式と対応filesystem
- Swift、Pythonその他のどのプロセスがlockを所有するか
- lock scope、job IDおよび永続状態との対応
- 所有者メタデータのschema、安定ID、書込みおよび正式化方式
- PID再利用を避けるprocess identity方式
- stale判定条件と時間値
- heartbeatの採否と間隔
- owner tokenの採否と形式
- 所有者以外からの解放拒否と権限境界
- 壊れた、欠落した、意味的に不整合なメタデータの復旧契約
- lock取得後かつジョブ状態永続化前のクラッシュ境界
- stale排他の削除可能ルートと安全な回収手順
- App Sandbox、外部SDカードおよび対象filesystemでの挙動

これらは今回の結果から推測で決定せず、第9開始Gateまでに `current_job` の正式な状態機械、Source fingerprint、staleな `stop.requested`、クラッシュ復旧と合わせて正式決定する。
