# 開発判断履歴

この文書は、仕様検討、開始Gate判定、設計上の推奨案および未決定事項の履歴を残すための記録である。

実装仕様の正本ではない。内容が `PRODUCT_SPEC.md`、`UI_SPEC.md`、`ARCHITECTURE.md`、`IMPLEMENTATION_STEPS.md` その他の正本仕様書と矛盾する場合は、正本仕様書を優先する。推奨案は、承認と正本仕様への反映が完了するまで正式仕様として扱わない。

---

## 2026-08-09：第3段階開始Gateの仕様検討

### 対象Stage

第3段階「MP4選択とPreflight」

### 判定

第3段階の開始Gateは未通過。以下は既存仕様と第0段階の技術検証結果から整理した推奨案であり、まだ正式仕様へ反映されていない。

### 推奨案

- 永続JSONは必須の整数 `schema_version: 1`、通信は別の整数 `protocol_version: 1` を使用し、未知・欠落・型不一致を失敗とする。
- 安定IDは小文字・ハイフン付きUUID v4文字列とし、用途別に `request_id`、`job_id`、`character_id`、`sample_id`、`candidate_id` を使用する。
- 時刻と時間長は非負の64-bit整数ミリ秒とし、`start_ms`、`end_ms`、`duration_ms` を使用する。開始は切り下げ、終了と時間長は切り上げ、区間は `start_ms < end_ms` とする。
- Preflightは1要求1Pythonプロセスとし、Swiftがstdinへ `protocol_version`、`request_id`、`operation: preflight`、絶対 `source_path` を持つUTF-8 JSONを1件渡す。Pythonは入力を読み取り専用で検査する。
- Preflight成功には、入力schema、通常ファイル、読取り可能性、`.mp4`、ffprobe起動・終了コード0・JSON妥当性、MP4系container、video／audio stream、正の有限durationの全確認を要求する。
- Preflight error codeは、入力不正、非対応形式、未検出、読取不能、ffprobe起動失敗・実行失敗・出力不正、video／audio欠落、duration不正、protocol error、internal errorの最小集合とし、Swiftで安定した日本語文言へ変換する。
- JSON Linesは、`protocol_version`、`type`、`request_id`、1始まりで単調増加する `sequence`、`payload` を共通項目とする。malformed JSON、未知type、ID不一致、sequence違反、必須項目不足を安全な失敗とする。
- Preflight成功は、有効な `finished(outcome: succeeded)`とresult、errorなし、protocol違反なし、process exit code 0、stdout／stderr EOF確認のすべてを必要とする。`finished`または終了コードだけでは成功にしない。
- SwiftからPythonは、実験で成立したFoundation `Process`、`executableURL`、引数配列、独立stdin／stdout／stderr Pipeを候補とする。ProcessはViewではなくServiceが所有する。
- 第3段階の開発時はPythonとffprobeの絶対パスをDebug用設定から注入し、`PATH`探索やHomebrew固定パスをソースへハードコードしない。Preflight用Pythonソースはプロジェクト所有Resourceとする。
- 初期開発版の第3段階はApp Sandboxなしを推奨する。これはSandboxなしのsubprocessチェーンが3回成立し、Sandboxありはad-hoc署名構成で起動前abort、有効な開発署名で未検証であるためである。配布版の最終採否とは分離する。

### 理由

- Swift→Python、stdout／stderr同時逐次読取り、Python→ffprobeは、shellと外部依存なしの限定実験で成立している。
- 既存仕様は、未知schema・壊れたJSON・未知event・異常exitを推測で成功扱いせず、`finished`と正式成功を分離することを要求している。
- 初期版は完全ローカルでApp Store配布を前提とせず、未検証のSandbox構成を第3段階へ混在させると、Preflight実装と署名問題を分離できない。
- 実験環境固有のPython／ffprobeパスを製品仕様へ固定せず、第3段階に必要な開発配置だけを最小限に定める必要がある。

### 未決定事項

- 上記推奨案の正式承認と `ARCHITECTURE.md` への反映。
- Preflight timeoutの具体値と、timeout時の第3段階に限定した安全な失敗契約。
- App Sandboxなしを初期開発版の正式方針として採用するか。
- 配布版のApp Sandbox、Security-Scoped Bookmark、正式署名条件での再検証。
- Python／FFmpeg／ffprobe／AIモデルの完成版配置・同梱方式。
- 本番bufferサイズ、Queue／Concurrency方式、停止signal、猶予時間、強制終了方式、停止完了event形式。
- フレーム境界補正、候補区間の結合・分割、FFmpeg引数へ時刻を戻す規則。

---

## 2026-08-09：第3段階開始Gateの正式決定

### 対象Stage

第3段階「MP4選択とPreflight」

### 決定事項

- 先行する「第3段階開始Gateの仕様検討」に記録した推奨案を、第3段階に必要な範囲で正式採用した。
- 永続JSONは `schema_version: 1`、通信は `protocol_version: 1`、安定IDは小文字・ハイフン付きUUID v4とした。
- 時刻と時間長は非負の64-bit整数ミリ秒とし、`start_ms`、`end_ms`、`duration_ms`、開始切り下げ、終了・時間長切り上げを採用した。
- Preflightは1要求1Pythonプロセス、stdinのJSON要求、ffprobeによる読み取り専用検査、video／audio streamと正のdurationを含む複合成功判定とした。
- Preflight deadlineは30秒、Pythonからのffprobe待機上限は20秒とした。timeout後始末は対象のPreflightプロセスだけに限定し、解析停止契約とは分離した。
- Preflight error codeと日本語文言、Stage 3用JSON Lines event schema、protocol violation、process exitを含む正式成功条件を決定した。
- Swift→PythonはFoundation `Process`、shellなし、独立Pipe、Service所有をPreflightの正式方式とした。
- Pythonとffprobeの開発時絶対パスはDebug用設定から注入し、Preflight用PythonソースはアプリResourceとする。環境固有パスはハードコードしない。
- 第3段階からの初期開発構成はApp Sandboxなしとした。配布版の最終採否とは分離する。

### 理由

- 既存の技術検証で、SandboxなしのFoundation `Process`、大量stdout／stderr同時逐次読取り、Python→ffprobeが外部依存追加なしで成立している。
- 未成立のSandboxあり署名構成をPreflight実装へ混在させず、機能と配布・署名問題を分離する必要がある。
- `finished`、終了コード、拡張子のいずれか1つだけに依存せず、安全な失敗と複合成功判定を最小契約で実現するため。

### 後続Gateへ残す未決定事項

- 各永続JSON固有の全schema、ID生成時点と参照関係。
- フレーム境界補正、候補区間の生成・結合・分割、FFmpeg引数への時刻変換。
- 本番bufferサイズ、Queue／Concurrency、長時間解析の停止signal・猶予時間・強制終了・Process group、停止完了event形式。
- Python／FFmpeg／ffprobe／AIモデルの完成版配置・同梱方式。
- 配布版App Sandbox、正式署名条件での再検証、Security-Scoped Bookmark。
- スリープ抑止、外部SDカード切断・再接続、保存reconciliation。

### Gate判定

正本仕様への反映を確認し、2026-08-09に第3段階の開始Gateを通過済みとした。第3段階の実装は別作業として開始する。

---

## 2026-08-09：第3段階最終検証（完了）

### 対象Stage

第3段階「MP4選択とPreflight」

### 確認済み事項

- Python構文検査とDebugビルドは成功した。
- 人工メディアによる正常MP4、音声なしMP4、破損MP4、非MP4のPreflightは期待した結果になった。
- 生成アプリに開発時Python／ffprobeパスと `preflight.py` Resourceが反映されていることを確認した。
- 選択変更時の古い要求結果の排除、未知error codeの安全な変換を追加検証した。
- JSON数値の正常な整数、小数、Booleanを分離して検証し、正常な整数だけを受理することを確認した。
- 最終単体テスト17件がすべて成功した。

### 解消した問題

- Booleanを整数として受理しないための型判定が、正常な整数にも影響していた。
- Core Foundationの実型判定でBooleanだけを拒否する最小修正を行い、正常整数、小数、Booleanの各テストで解消を確認した。

### Stage判定

第3段階の実装範囲、Debugビルド、Python構文検査、人工入力検証、全単体テストの成功を確認したため、第3段階を完了とする。第4段階以降の機能は先行実装していない。

---

## 2026-08-09：第4段階開始Gate

### 対象Stage

第4段階「人物選択とCharactersView入口」

### 決定事項

- 第3段階が完了しているため、第4段階の開始Gateを通過済みとする。
- 第4段階では、安定IDを持つMock人物データを使用して人物選択UIと状態遷移を実装してよい。
- Sheet内の選択は一時状態とし、「決定」時だけHomeへ反映する。キャンセル時は既存選択を変更しない。
- 確定時に登録人物一覧へ存在しないIDを選択状態へ残さない。
- 人物未登録、人物未選択、1人選択、複数人選択を区別し、1人以上の確定選択だけを解析開始条件の人物要件とする。

### 理由

- `IMPLEMENTATION_STEPS.md` が定める第4段階の前提は第3段階完了であり、独立した技術検証Gateはない。
- 第4段階はMockまたは読み取り専用データによるUI成立が目的であり、人物データの永続化契約を先行決定しなくても安全に実装できる。
- 一時選択と確定選択を分離することで、キャンセル操作や不存在IDを安全に扱える。

### 未決定事項

- 人物データの永続化、正式な読込み、`character.json`、`sample.json` のschemaと所有権。
- 新規人物登録、既存人物への音声追加、人物削除の本処理。
- `source.wav`、Embedding生成、複数sampleのEmbedding統合方式。
- 人物選択を実解析ジョブへ渡す正式契約。

これらは対応する後続段階の開始Gateまで未決定とし、第4段階で推測して実装しない。

### Gate判定

2026-08-09に第4段階の開始Gateを通過済みとする。第4段階は人物選択とCharactersView入口の範囲だけを実装し、第5段階以降を先行実装しない。

---

## 2026-08-09：第4段階最終検証（完了）

### 対象Stage

第4段階「人物選択とCharactersView入口」

### 確認済み事項

- 安定したUUIDを持つMock人物一覧と、確定済み選択IDを分離した。
- 人物選択Sheetの一時選択は「決定」時だけHomeへ反映され、キャンセル時には確定済み選択を変更しない。
- 人物未登録、未選択、1人選択、複数人選択を区別し、選択人物チップと人数を表示する。
- 登録人物一覧に存在しないIDを一時選択および確定選択へ残さない。
- 人物が1人以上確定選択されている場合だけ、解析開始条件の人物要件を満たす。
- HomeからCharactersViewへ安全に遷移できる入口を維持した。
- Debugビルドと単体テスト22件がすべて成功し、差分検査にも問題がなかった。
- 完了コミット後の最終再検証でもDebugビルドと単体テスト22件がすべて成功し、追跡対象の作業ツリーがクリーンであることを確認した。

### 未決定事項

- 人物データの永続化と正式読込み、人物登録・音声追加・削除の本処理。
- `character.json`、`sample.json`、`source.wav`、Embeddingと実解析への人物ID受渡し契約。

これらは後続段階の開始Gateまで未決定のままとし、第4段階では実装していない。

### Stage判定

第4段階の実装範囲と完了条件を満たしたため、第4段階を完了とする。第5段階以降の機能は先行実装していない。

---

## 2026-08-09：第5段階開始Gate

### 対象Stage

第5段階「AnalysisView Mock」

### 決定事項

- 第1〜4段階が完了しているため、第5段階の開始Gateを通過済みとする。
- 第5段階は、5工程、信用できる実数のMock進捗、停止要求中、停止完了を表すUI状態の実装に限定する。
- 解析中、停止要求中、停止完了は排他的な状態として表現し、停止要求後は通常進捗表示を更新しない。
- 「続きから解析」は、正式完成済み工程を検証できたことを表す明示的なMock条件がある場合だけ表示する。
- 停止ボタン押下だけで停止完了とせず、Mock上でも停止要求中と停止完了を分離する。

### 理由

- `IMPLEMENTATION_STEPS.md` が定める第5段階の前提は第1〜4段階完了であり、独立した技術検証Gateはない。
- 第5段階はUI状態設計を目的とするため、本番プロセス停止契約を先行決定せずに安全に実装できる。
- 本番と同様に要求状態と完了状態を分離することで、後続段階で未確認状態を成功表示する設計を避けられる。

### 未決定事項

- `stop.requested` の本番作成・検知・清掃契約。
- FFmpeg等の子プロセスへ送るsignal、猶予時間、強制終了、Process groupおよび孫プロセス管理方式。
- 停止完了をJSON Lines通信で表す正式形式。
- Source fingerprintの正式方式と、正式完成済み工程・partial・再開可能性の実検証契約。
- Python解析、実進捗、実ジョブ再開との接続。

これらは第9、第14等の対応する後続開始Gateまで未決定とし、第5段階で推測して実装しない。

### Gate判定

2026-08-09に第5段階の開始Gateを通過済みとする。第5段階はAnalysisViewのMock状態と表示だけを実装し、第6段階以降および本番停止処理を先行実装しない。

---

## 2026-08-09：第5段階最終検証（完了）

### 対象Stage

第5段階「AnalysisView Mock」

### 確認済み事項

- ユーザー向けの5工程を固定順序で表示するMockモデルとUIを実装した。
- 件数および時間による実数形式のMock進捗を表示し、全体％、残り時間、CPU、波形、プレビュー、一時停止は追加していない。
- 解析中、停止要求中、停止完了を排他的な状態で表現し、停止ボタン押下だけでは停止完了にしない。
- 停止要求後の通常進捗更新を状態層で拒否することを確認した。
- 「続きから解析」は、再開位置として検証済みであることを表すMock進捗が存在する場合だけ利用可能にした。
- 各工程、件数・時間表示、停止要求、停止完了、再開可能・不可、誤った状態遷移を単体テストで確認した。
- Debugビルドと単体テスト28件がすべて成功し、差分検査にも問題がなかった。
- 完了コミット後の最終再検証でもDebugビルドと単体テスト28件がすべて成功し、第5段階の範囲逸脱や未決定事項の暗黙確定がないことを確認した。

### 未決定事項

- Python解析と実進捗の接続、`stop.requested`、FFmpeg等の子プロセス停止、停止後成果物検証。
- 本番signal、猶予時間、強制終了、Process group、停止完了event形式。
- Source fingerprint、partial、正式完成済み工程に基づく本番の再開可否判定。

これらは対応する後続段階の開始Gateまで未決定のままとし、第5段階では実装していない。

### Stage判定

第5段階の実装範囲と完了条件を満たしたため、第5段階を完了とする。第6段階以降の機能および本番停止処理は先行実装していない。

---

## 2026-08-09：第6段階開始Gate

### 対象Stage

第6段階「ResultsView Mock」

### 決定事項

- 第5段階が完了しているため、第6段階の開始Gateを通過済みとする。
- 第6段階では、安定IDを持つMock候補へ表示用の人物一致ラベルと品質区分を直接設定し、AIスコアや未決定の変換閾値を持たせない。
- 人物不明は人物判定の結果、◎／○／△は音声品質として別の状態で表現する。
- 初期選択は◎と○をON、△と人物不明をOFFとする。人物不明候補の品質が◎または○でも初期選択しない。
- 人物内候補は開始時刻順とし、人物不明グループだけを初期状態で折りたたむ。
- 候補選択状態は将来の `selection.json` 所有を想定して解析結果モデルと分離するが、第6段階では永続化しない。
- 0件結果は正常なEmpty Stateとして扱う。

### 理由

- 第6段階はMock UIと状態設計が目的であり、`result.json` schemaやAI判定規則を先行決定せずに安全に実装できる。
- 表示用ラベルをMockへ直接設定することで、生スコアをUIモデルへ露出せず、人物不明と音声品質の責務を分離できる。

### 未決定事項

- 人物不明判定、人物一致度表示、品質区分、reason codeの正式変換規則と数値閾値。
- `result.json` と `selection.json` の正式schema、検証、正式化、破損時復旧。
- AVPlayerプレビュー、実解析結果の読込み、保存処理との接続。

これらは第11、第15等の対応する後続開始Gateまで未決定とし、第6段階で推測して実装しない。

### Gate判定

2026-08-09に第6段階の開始Gateを通過済みとする。第6段階はResultsViewのMockモデル、表示、選択状態、Empty Stateだけを実装し、第7段階以降を先行実装しない。

---

## 2026-08-09：第6段階最終検証（完了）

### 対象Stage

第6段階「ResultsView Mock」

### 確認済み事項

- 安定IDを持つMock候補を人物別にグループ化し、各人物内を開始時刻順で表示するモデルとUIを実装した。
- 登録人物グループを初期展開し、人物不明グループだけを初期状態で折りたたむことを確認した。
- 人物一致表示と音声品質を別の状態として保持し、人物不明と品質の△を混同しない表示にした。
- 初期選択は◎と○をON、△と人物不明をOFFとし、人物不明候補は品質が◎でも初期選択されないことを確認した。
- 選択状態をMock解析結果から分離し、存在しない候補IDによる選択、フォーカス、グループ展開の変更を拒否することを確認した。
- 0件結果を異常終了ではなく正常なEmpty Stateとして表示する。
- UIモデルにAIの生スコアや確率を持たせず、表示用区分だけを使用した。
- Debugビルドが成功し、単体テスト34件がすべて成功した。
- `git diff --check` が成功し、第7段階以降の機能や未決定の永続化契約を先行実装していないことを確認した。

### 未決定事項

- 人物不明判定、人物一致度表示、◎／○／△、reason codeの正式変換規則とAI数値閾値。
- `result.json` と `selection.json` の正式schema、所有権、検証、正式化、破損時復旧。
- AVPlayerプレビュー、実解析結果の読込み、選択状態の永続化、保存処理との接続。

これらは対応する後続段階の開始Gateまで未決定のままとし、第6段階では実装していない。

### Stage判定

第6段階の実装範囲と完了条件を満たしたため、第6段階を完了とする。第7段階以降の機能は先行実装していない。

---

## 2026-08-09：第6段階完了後の最終再検証

### 対象Stage

第6段階「ResultsView Mock」

### 検証結果

- 実装コミット `4a05dec15c09ec669d95b24191bc3b4b805a5f70` を対象に、正本仕様と実装範囲を再確認した。
- 人物別時間順、人物不明の初期折りたたみ、品質別初期選択、人物一致と品質の分離、選択状態、0件Empty Stateが第6段階の仕様と一致している。
- AI生スコア、手動人物変更、トリム、加工、保存本処理および第7段階以降の機能を追加していない。
- Debugビルドが成功した。
- 単体テスト34件がすべて成功し、失敗およびunexpected failureは0件だった。
- `git diff --check` が成功し、検証前の作業ツリーには対象外の未追跡ルート `README.md` 以外の差分がなかった。

### 判定

第6段階は完了状態を維持している。未決定事項は既存の後続Gateへ残し、本再検証では新たな仕様決定を行っていない。

---

## 2026-08-09：第7A段階開始Gate

### 対象Stage

第7A段階「新規人物登録UI」

### 決定事項

- 前提である第4段階が完了済みのため、第7A段階の開始Gateを通過済みとする。
- 新規人物登録の入力途中、登録要求中、正式登録完了を排他的なUI状態として分離する。
- 人物名、登録元MP4、本人発話区間がすべて有効な場合だけ登録要求を許可する。
- MP4の選択とプレビューにはmacOS標準APIを使用し、外部依存を追加しない。
- 登録要求だけではMock人物一覧および正式人物データを変更しない。

### 理由

- 第7A段階は入力・確認UIと状態境界を作る段階であり、WAV、品質判定、Embedding、永続化契約を先行決定せず実装できる。
- 登録要求と正式完了を分けることで、ボタン押下だけを成功扱いしない共通原則を人物登録にも適用できる。

### 未決定事項

- `character.json`、`sample.json`、`source.wav` の正式化契約と所有権。
- 登録音声の長さ・無音・音量等の品質条件とerror code。
- Embedding保存・再生成および複数sampleの統合方式。
- App Sandbox採否と、Sandbox採用時の動画URL永続アクセス方式。

これらは第8A／第8B等の対応する開始Gateまで未決定とし、第7A段階で推測して実装しない。

### Gate判定

2026-08-09に第7A段階の開始Gateを通過済みとする。第7A段階は新規人物登録UIとMock状態に限定し、第7Bおよび第8A以降を先行実装しない。

---

## 2026-08-09：第7A段階最終検証（完了）

### 対象Stage

第7A段階「新規人物登録UI」

### 確認済み事項

- CharactersViewから新規人物登録を開始し、人物名とローカルMP4を指定するUIを実装した。
- macOS標準の動画選択とAVPlayerによるプレビュー、標準再生、±5秒、開始・終了設定、選択範囲再生のUIを実装した。
- 人物名、動画、有効な開始・終了範囲が揃うまで登録要求を無効にした。
- 入力中、登録要求中、正式登録完了を排他的な状態として分離した。
- 登録ボタン押下だけでは人物一覧および正式人物データを変更しないことを確認した。
- キャンセル時に入力途中の状態を破棄し、人物管理画面を維持することを確認した。
- 登録用WAV、品質判定、Embedding、人物フォルダ、人物永続化を実装していない。
- Debugビルドが成功し、単体テスト39件がすべて成功した。
- `git diff --check` が成功し、第7Bおよび第8A以降を先行実装していないことを確認した。

### 未決定事項

- 人物・sampleの正式schema、登録処理の原子性、失敗復旧、正式一覧への反映方法。
- 登録音声品質条件、WAV生成・検証・正式化、Embedding生成・再生成と複数sample統合方式。
- App Sandbox採否と、採用時のファイルアクセス維持方式。

これらは対応する第8A／第8B等の開始Gateまで未決定のままとし、第7A段階では実装していない。

### Stage判定

第7A段階の実装範囲と完了条件を満たしたため、第7A段階を完了とする。第7Bおよび第8A以降の機能は先行実装していない。

---

## 2026-08-09：第7A段階完了後の最終再検証

### 対象Stage

第7A段階「新規人物登録UI」

### 検証結果

- 実装コミット `584262bb0b050949556bac93945d5db3d9e8da31` を対象に、正本仕様と実装範囲を再確認した。
- 人物名入力、MP4選択・プレビュー、標準再生、±5秒、開始・終了設定、選択範囲再生のUI構成が存在することを静的に確認した。
- 不正区間では登録要求できず、登録要求と正式完了が分離され、登録要求だけでは人物一覧を変更しないことを単体テストで確認した。
- 登録用WAV、品質判定、Embedding、正式人物フォルダ、人物永続化、第7Bおよび第8A以降を実装していないことを確認した。
- Debugビルドが成功した。
- 単体テスト39件がすべて成功し、失敗およびunexpected failureは0件だった。
- `git diff --check` が成功し、HEADとローカル追跡中の `origin/main` が一致していた。

### 未実施の確認

- 実MP4を使用した動画選択、標準再生、±5秒、開始・終了設定、選択範囲再生の目視操作は未実施であり、実機能を確認済みとは扱わない。
- App Sandbox採用時のファイルアクセスは未検証・未決定のままとする。

### 判定

自動検証と静的監査の範囲で第7A段階は完了状態を維持している。実MP4による目視確認と後続Gateの未決定事項を推測で完了扱いにしていない。

---

## 2026-08-09：第7B段階開始Gate

### 対象Stage

第7B段階「既存人物への登録音声追加UI」

### 決定事項

- 前提である第7A段階が完了済みのため、第7B段階の開始Gateを通過済みとする。
- 新規人物登録と既存人物へのsample追加は別のUI状態・要求として扱う。
- sample追加の開始時に対象人物IDと表示名を固定し、処理中の人物選択変更を受け付けない。
- 第7AのMP4・発話区間選択操作を同じUI原則で使用するが、人物名入力は追加しない。
- 追加要求中、成功、失敗を排他的なMock状態とし、成功確認前および失敗時に既存sample件数を変更しない。
- 登録済み音声はMock情報から一覧表示し、保存済み `source.wav` との本接続前であることが分かる再生UI骨格だけを置く。

### 理由

- 第7B段階は既存人物を対象とする追加UIの責務境界を作る段階であり、sample生成・永続化を先行実装せずに安全性を確認できる。
- 対象人物の固定と既存データ不変のテストにより、後続の第8Bで失敗時に既存人物を壊さない設計へ接続できる。

### 未決定事項

- 新sample生成・検証・正式化と人物メタデータ更新の原子性、失敗復旧。
- `sample.json`、`source.wav`、Embeddingの正式契約と複数sample統合方式。
- 保存済み `source.wav` の実読込み・再生とSandbox採用時のアクセス方式。

これらは第8A／第8B等の対応する開始Gateまで未決定とし、第7B段階で推測して実装しない。

### Gate判定

2026-08-09に第7B段階の開始Gateを通過済みとする。第7B段階は既存人物への登録音声追加UIとMock状態に限定し、第8A以降を先行実装しない。

---

## 2026-08-09：第7B段階最終検証（完了）

### 対象Stage

第7B段階「既存人物への登録音声追加UI」

### 確認済み事項

- CharactersViewで人物一覧、Mock登録音声件数、選択人物、登録音声一覧、合計時間を表示するUIを実装した。
- 選択人物を明示してから登録音声追加を開始し、追加中は対象人物を固定することを確認した。
- 第7Aと同じ操作原則のMP4選択、プレビュー、±5秒、開始・終了設定、選択範囲再生UIを実装した。
- 追加要求中、成功、失敗を排他的に表現し、失敗後の再試行とキャンセルを実装した。
- 追加成功確認前、成功Mock、失敗、再試行、キャンセルのいずれでも既存人物とMock sample件数を変更しないことを確認した。
- 保存済み `source.wav` との本接続前であることを明示した再生UI骨格を実装した。
- sample生成、Embedding生成、人物データ更新、永続化を実装していない。
- Debugビルドが成功し、単体テスト43件がすべて成功した。
- `git diff --check` が成功し、第8A以降を先行実装していないことを確認した。

### 未決定事項

- 新sample生成・検証・正式化、人物メタデータ更新、失敗復旧の正式契約。
- `sample.json`、`source.wav`、Embedding、複数sample統合方式。
- 登録済み `source.wav` の実読込み・再生とSandbox採用時のアクセス方式。

これらは対応する第8A／第8B等の開始Gateまで未決定のままとし、第7B段階では実装していない。

### Stage判定

第7B段階の実装範囲と完了条件を満たしたため、第7B段階を完了とする。第8A以降の機能は先行実装していない。

---

## 2026-08-09：第7B段階完了後の最終再検証

### 対象Stage

第7B段階「既存人物への登録音声追加UI」

### 検証結果

- 実装コミット `798540ff058e1cf4b8a0651c0e78890a4875c364` を対象に、正本仕様と実装範囲を再確認した。
- 選択人物の明示、MP4・区間選択UI、追加要求中・成功・失敗・再試行の状態、登録済み音声再生UI骨格が存在することを静的に確認した。
- 追加開始時の対象人物固定、キャンセル、失敗、再試行、および成功・失敗時に既存人物とMock sample件数を変更しないことを単体テストで確認した。
- sample生成、Embedding生成、人物データ更新、永続化および第8A以降を実装していないことを確認した。
- Debugビルドが成功した。
- 単体テスト43件がすべて成功し、失敗およびunexpected failureは0件だった。
- `git diff --check` が成功し、HEADとローカル追跡中の `origin/main` が一致していた。

### 未実施の確認

- 実MP4を使用した動画選択、再生、区間指定、選択範囲再生の目視操作は未実施であり、実機能を確認済みとは扱わない。
- 保存済み `source.wav` の実読込み・再生は未接続・未検証のままとする。
- App Sandbox採用時のファイルアクセスは未検証・未決定のままとする。

### 判定

自動検証と静的監査の範囲で第7B段階は完了状態を維持している。実メディア確認と後続Gateの未決定事項を推測で完了扱いにしていない。

---

## 2026-08-09：第8A開始Gate技術検証と契約決定

### 対象Stage

第8A段階「新規人物登録本処理」開始Gate

### 確認済み事項

- SpeechBrain 1.0.3と `speechbrain/spkrec-ecapa-voxceleb` revision `0f99f2d0ebe89ac095bcc5903c4dd8f72b367286` を候補として、人工合成音声によるCPU推論を実施した。
- 16kHz・モノラル音声から192次元float32 Embeddingを生成でき、同一入力の再実行差が0であることを確認した。
- L2正規化sample Embeddingの算術平均を再L2正規化するcentroidを機械的に構成できた。
- 限定人工音声では、3秒未満より3秒以上の入力でfull音声とのEmbedding類似が安定する傾向を確認した。
- 無音でもモデルが有限Embeddingを返すため、Embedding生成前の独立した無音・音量検査が必要であることを確認した。
- 10秒、30秒、60秒の人工音声で有限Embeddingを生成でき、登録入力上限を設けても技術成立性を損なわないことを確認した。

### 決定事項

- `character.json`、`sample.json` はschema version 1とし、Pythonが生成・検証・正式化を所有する。Swiftは正式データを読込む。
- 人物IDとsample IDは接頭辞付きcanonical UUIDとし、フォルダ名・JSON参照を一致させる。
- `source.wav` は16kHz、mono、PCM signed 16-bit little-endianの重要資産とする。
- sample Embeddingは192次元float32のL2正規化配列を `embedding.npy` に保存し、pickleを禁止する。元WAV SHA-256とモデルID・revisionを `sample.json` へ記録する。
- 人物判定用内部表現は、全sampleのL2正規化Embeddingを算術平均し、再L2正規化したcentroidとする。centroidは保存せず再計算する。
- 登録区間は3,000ms以上30,000ms以下とする。全sampleが0、RMS -60dBFS以下、peak -40dBFS以下を安定error codeで拒否する。
- 人物データルートはApplication Support配下の `local.YoiSceneKirinuKu/characters` とし、一時人物は同一volumeの `characters/.partial/` 内だけに作る。
- 全成果物と相互参照の再検証後、人物ディレクトリ全体の1回のrenameで正式化し、Swift再読込み検証後だけ成功表示する。
- 第8A／第8Bの開発時はモデルとPython環境の絶対パスをDebug設定から注入し、実行中にダウンロードしない。

### 理由

- `source.wav` とモデルrevisionを結び付けることでEmbeddingを決定論的に再生成し、派生データ破損から復旧できる。
- 個別sampleを保持してcentroidを再計算する方式は、sample追加時に正本Embeddingを失わず、staleな集約ファイルを避けられる。
- partial人物全体を同一volumeで正式化することで、完成前データを人物一覧へ露出しない。
- 人工音声の実測値は最低入力検査と内部データ契約の判断には使えるが、実人物の一致精度やUI表示閾値の根拠には不足する。

### 未決定事項

- 人物一致閾値、人物不明判定、◎／○／△変換は第15開始Gateまで未決定とする。
- 実人物、雑音、残響、複数話者、マイク差を含む精度評価は未検証とする。
- 外れ値sampleの除外や重み付けは採用せず、必要性が確認された場合に別Gateで判断する。
- 完成版Python、AIモデル、依存ライブラリの配置・同梱方式とApp Sandbox採否は第22開始Gateまで未決定とする。
- 既存人物へsampleを追加する際の `character.json` 更新原子性とクラッシュ復旧は第8B開始Gateで決定する。

### Gate判定

`ARCHITECTURE.md`へ第8Aに必要な人物・sample schema、WAV、Embedding、最低品質、error code、開発時実行、固定ルート、partial正式化契約を反映したため、第8A開始Gateを通過済みとする。第8A本体は未実装であり、完了扱いにしない。

---

## 2026-08-09：第8A段階実装・最終検証

### 対象Stage

第8A段階「新規人物登録本処理」

### 実装・決定事項

- Swiftは人物登録要求とUI状態を所有し、PythonへJSON要求を渡した後、正式人物の再読込み検証が成功した場合だけ登録完了を表示する。
- Pythonは `source.wav`、Embedding、`sample.json`、`character.json` の生成・検証を所有し、同一volumeの `.partial` から人物ディレクトリ全体を1回renameして正式化する。
- 起動時の人物一覧は正式化済み人物だけを再読込みし、開発用Mock人物を実行時の人物として表示しない。
- `source.wav` は削除せず保持し、そのファイル全体のSHA-256を `sample.json` に記録してEmbeddingの再生成元と結び付ける。

### 検証結果

- Python単体テスト5件で、正常登録、元動画欠落、無音拒否、Embedding失敗、正式化直前失敗と `.partial` 非表示を確認した。
- 人工MP4、ローカルFFmpeg、Gateで固定したローカルAIモデルを使い、新規人物の正式化と正式人物一覧への再読込みが成立した。
- Debugビルドが成功した。
- Swift単体テストで、正式再読込み後だけの成功表示、失敗時の人物不変、3秒以上30秒以下の区間Gate、正式人物再読込みを確認した。
- `git diff --check` と、第8B／第8C以降を先行実装していないことを確認した。

### 未決定・未検証事項

- 実人物音声での一致精度、人物不明判定、人物一致閾値、◎／○／△変換は第15開始Gateまで未決定とする。
- 完成版Python、FFmpeg、AIモデルの配置・同梱方式とApp Sandbox採否は第22開始Gateまで未決定とする。
- 既存人物へのsample追加と人物削除は第8B／第8Cで扱い、第8Aでは実装しない。
- ユーザーの実MP4を用いた手動UI操作は未検証であり、自動検証の成功と区別する。

### Stage判定

第8Aの実装範囲と完了条件を満たしたため、第8A段階を完了とする。後続段階の未決定事項は対応する開始Gateまで維持する。

---

## 2026-08-09：第8A段階完了後の最終再検証

### 対象Stage

第8A段階「新規人物登録本処理」

### 検証結果

- Python構文検査と `Info.plist` 検査が成功した。
- Python単体テスト5件がすべて成功し、正常登録、元動画欠落、無音拒否、Embedding失敗、正式化直前失敗時の安全性を再確認した。
- Debugビルドが成功した。
- Swift単体テスト47件がすべて成功し、失敗およびunexpected failureは0件だった。
- 正式人物の再読込み後だけ成功表示へ進み、完成前の `.partial` を人物一覧へ出さない実装を維持していることを確認した。
- `git diff --check` が成功し、第8B／第8C以降の機能が混入していないことを確認した。

### 未実施・未決定事項

- ユーザーの実MP4と実人物音声を使った手動UI操作および一致精度は未検証のままとする。
- 人物不明判定、人物一致閾値、◎／○／△変換は第15開始Gateまで未決定とする。
- 完成版Python、FFmpeg、AIモデルの配置・同梱方式とApp Sandbox採否は第22開始Gateまで未決定とする。
- 既存人物へのsample追加と人物削除は第8B／第8Cの範囲とし、今回の再検証で完了扱いにしない。

### 判定

自動検証と静的監査の範囲で第8A段階は完了状態を維持する。未検証事項を検証済みへ変更せず、後続Gateの判断も先行確定していない。

---

## 2026-08-09：第8B開始Gateの原子性・復旧契約

### 対象Stage

第8B段階「既存人物への登録音声追加本処理」開始Gate

### 確認済み事項

- `/private/tmp` の人工ディレクトリを使い、macOSの `renameatx_np(..., RENAME_SWAP)` で2つの非空ディレクトリを原子的に交換できることを確認した。
- 交換後は正式側に新内容、staging側に旧内容があり、正式パスを欠落させる中間状態を作らない候補方式が成立した。

### 決定事項

- 同じ人物への追加は `.partial` 内の人物別lock fileと非待機 `fcntl.flock` で排他し、競合は `registration_character_busy` として拒否する。
- 正式人物を直接変更せず、検証済み人物全体をpartialへcopy-on-writeし、新sampleと更新済み `character.json` を完成させてから人物全体を再検証する。
- 更新済み候補と正式人物を `RENAME_SWAP` で交換し、非原子的な複数renameへfallbackしない。
- swap前のクラッシュでは旧人物、swap後のクラッシュでは事前検証済み新人物を正式状態とする。partial側の残存物は一覧から無視する。
- swap後の正式人物をPythonが再検証し、Swift再読込みで新sample IDを確認した場合だけ追加成功と件数増加を表示する。
- 既存人物不在は `registration_character_not_found`、人物排他競合は `registration_character_busy` とする。

### 理由

- 既存 `character.json` やsampleを直接変更すると、メタデータとフォルダの不一致を観測するクラッシュ窓が生じる。
- 完成人物全体のatomic swapなら、正式パスには旧完全版または新完全版のどちらかだけが存在する。
- OS解放の `flock` はstale時刻、PID再利用、heartbeat、owner tokenの推測を第8Bへ持ち込まずに同時更新を拒否できる。

### 未決定・後続事項

- `RENAME_SWAP` を含む完成版のSandbox下での挙動は第22開始Gateまで未検証とする。
- partialの一般reconciliationと清掃時期は、人物一覧の正しさへ影響させず後続の復旧統合で扱う。
- 人物削除の排他・削除対象・失敗復旧は第8C開始Gateまで未決定とする。

### Gate判定

新sample追加の原子性、人物メタデータ更新順、競合拒否、クラッシュ境界を正本へ反映したため、第8B開始Gateを通過済みとする。第8B本体は未実装であり、完了扱いにしない。

---

## 2026-08-09：第8B段階実装・検証

### 対象Stage

第8B段階「既存人物への登録音声追加本処理」

### 実装内容

- Swiftから対象人物ID、元動画、整数ミリ秒区間を `add_sample` 要求としてPythonへ渡し、正式人物の再読込みで新sample IDを確認した場合だけUIを成功状態へ進める。
- Pythonは人物別の非待機 `flock` を保持し、正式人物全体をpartialへcopy-on-writeしてから新 `source.wav`、Embedding、`sample.json` と更新済み `character.json` を生成する。
- 更新候補の人物全体を検証後、`RENAME_SWAP` で正式人物と原子的に交換し、交換後も正式人物全体を再検証する。
- 失敗時は旧正式人物を変更せず、競合要求、人物不在、未知error codeを成功へ読み替えない。
- Debug用virtualenvのPythonパスはvenv判定を維持したまま起動し、symlink解決先が通常の実行可能ファイルであることを検証する。モデルと人物データ境界のsymlink禁止は維持する。

### 検証結果

- Python単体テスト9件が成功し、正常追加、Embedding失敗、swap直前失敗、人物別排他競合、partial非表示と既存人物不変を確認した。
- 現行第8A処理で作成した人工人物、人工MP4、ローカルFFmpeg、ローカルAIモデルを使い、sample数が1件から2件へ増える実経路を確認した。
- Debugビルドが成功した。
- Swift単体テスト48件が成功し、正式再読込み前の件数不変、重複要求拒否、成功後の件数反映、失敗時不変、再試行を確認した。
- `git diff --check` が成功し、第8C以降の機能を先行実装していないことを確認した。

### 未決定・未検証事項

- 完成版配置とApp Sandbox下でのvirtualenv、`flock`、`RENAME_SWAP` の挙動は第22開始Gateまで未決定・未検証とする。
- 実人物音声の精度、人物一致閾値、人物不明判定、◎／○／△変換は第15開始Gateまで未決定とする。
- 人物削除の排他・削除対象・失敗復旧は第8C開始Gateまで未決定とする。
- ユーザーの実MP4を用いた手動UI操作は未検証とする。

### Stage判定

第8Bの実装範囲と完了条件を満たしたため、第8B段階を完了とする。後続段階の未決定事項は対応する開始Gateまで維持する。

---

## 2026-08-09：第8B段階完了後の最終再検証

### 対象Stage

第8B段階「既存人物への登録音声追加本処理」

### 検証結果

- Python構文検査と `Info.plist` 検査が成功した。
- Python単体テスト9件がすべて成功し、正常追加、Embedding失敗、swap直前失敗、人物別排他競合、既存人物不変を再確認した。
- 第8Bの人工統合成果物を新しいPythonプロセスから正式再読込みし、人物1件とsample 2件が検証済み状態で維持されていることを確認した。
- Debugビルドが成功した。
- Swift単体テスト48件がすべて成功し、失敗およびunexpected failureは0件だった。
- 正式再読込み前にUI件数を増やさず、失敗時に既存人物を変更しない実装を維持していることを確認した。
- `git diff --check` が成功し、第8C以降の機能が混入していないことを確認した。

### 未実施・未決定事項

- ユーザーの実MP4と実人物音声を使った手動UI操作および一致精度は未検証のままとする。
- 人物一致閾値、人物不明判定、◎／○／△変換は第15開始Gateまで未決定とする。
- 完成版配置とApp Sandbox下でのvirtualenv、`flock`、`RENAME_SWAP` の挙動は第22開始Gateまで未決定・未検証とする。
- 人物削除は第8Cの範囲とし、今回の再検証で完了扱いにしない。

### 判定

自動検証、正式再読込み、静的監査の範囲で第8B段階は完了状態を維持する。未検証事項と後続Gateを先行確定していない。

---

## 2026-08-09：第8C開始Gateの人物削除契約

### 対象Stage

第8C段階「人物削除本処理」開始Gate

### 決定事項

- 初期版は人物全体だけを削除対象とし、個別sample削除は実装しない。最後の1sample単独削除も提供しない。
- 削除対象は固定人物ルート直下のcanonical `char_<UUID>` から組み立て、外部からパスを受け取らない。
- 人物と全sampleを既存schemaで検証し、symlink、未知項目、path traversal、ルート自身、他人物、完成MP4を削除対象から除外する。
- `.partial/global.lock` のshared/exclusive `flock` を人物データ利用の共通排他とする。削除はexclusive non-blocking lockを保持し、競合時は既存データを変更しない。
- 検証済み人物全体を `.partial/delete_<UUID>/char_<UUID>` へ1回renameし、正式パス不在確認後に論理削除済みとする。
- tombstone清掃は既知ファイルの個別unlinkと空ディレクトリの非再帰rmdirだけで行う。想定外項目または清掃失敗時は停止してtombstoneを残す。
- Pythonの正式パス不在確認とSwiftの正式一覧再読込み確認が両方成功した場合だけUIへ削除成功を反映する。

### 理由

- 正式人物を直接順次削除すると、途中失敗時に壊れた人物が正式一覧へ残る。
- 1回renameで正式ルートから外すことで、クラッシュ境界をrename前の未削除またはrename後の論理削除済みに限定できる。
- 外部パスを受け取らず既知構造だけを個別削除することで、人物ルート外や完成MP4を削除する余地を閉じられる。
- 共通lockをshared/exclusiveで使うことで、将来の解析を含む人物データ利用中の削除をUI状態だけに依存せず拒否できる。

### 未決定・後続事項

- 将来の解析処理がshared global lockを保持する本接続は、その解析処理を実装する段階で行う。
- partial tombstoneの一般reconciliationと自動清掃時期は後続の復旧統合へ残す。
- App Sandbox下のlock、rename、削除挙動は第22開始Gateまで未検証とする。

### Gate判定

削除対象、削除可能ルート、canonical path、symlink対策、共通排他、クラッシュ境界、UI成功判定を正本へ反映したため、第8C開始Gateを通過済みとする。第8C本体は未実装であり、完了扱いにしない。

---

## 2026-08-09：第8C段階実装・検証

### 対象Stage

第8C段階「人物削除本処理」

### 実装内容

- CharactersViewから選択人物、登録音声件数、取り消し不能であることを明示した確認画面を経て、人物全体削除だけを要求する。
- Swiftは削除要求中の二重要求と画面終了を拒否し、Pythonの削除成功後に正式人物一覧を再読込みして対象人物が存在しない場合だけUIを削除完了へ進める。
- Pythonは外部パスを受け取らず、固定人物ルートとcanonical `char_<UUID>` から削除対象を組み立てる。
- 人物登録とsample追加は共通global shared lock、人物削除はglobal exclusive non-blocking lockを使用し、競合時は既存人物を変更しない。
- 削除前に人物全体を既存schemaで検証し、`.partial/delete_<UUID>/char_<UUID>` への1回rename後に正式パス不在を確認する。
- rename後の清掃は検証済み既知ファイルの個別unlinkと空ディレクトリの非再帰rmdirだけを使用し、清掃できないtombstoneは正式人物一覧から無視する。
- 個別sample削除は実装せず、最後の1sampleだけを削除する経路を設けていない。

### 検証結果

- Python構文検査が成功した。
- Python単体テスト13件が成功し、対象人物だけの削除、rename前失敗時の正式人物維持、清掃失敗時のtombstone維持、canonical ID拒否、symlink拒否、global lock競合拒否を確認した。
- Debugビルドが成功した。
- Swift単体テスト50件が成功し、明示確認、削除中の二重要求拒否、正式再読込み前のUI不変、対象不在確認後のUI更新、失敗時の既存表示維持を確認した。
- `git diff --check` が成功し、第9段階以降の機能を先行実装していないことを確認した。

### 未決定・未検証事項

- 将来の解析処理が人物データ利用中にglobal shared lockを保持する本接続は、その解析処理を実装する段階へ残す。
- 残存tombstoneの一般reconciliationと自動清掃は後続の復旧統合へ残す。
- App Sandbox下の `flock`、rename、unlink、rmdirは第22開始Gateまで未検証とする。
- ユーザーの実人物データを使った手動UI操作は未検証とする。

### Stage判定

許可対象だけを論理削除し、失敗または正式不在未確認時に削除済み表示を行わない完了条件を満たしたため、第8C段階を完了とする。後続段階の排他・reconciliation本接続は対応するStageまで未実装として維持する。

---

## 2026-08-09：第8C段階完了後の最終再検証

### 対象Stage

第8C段階「人物削除本処理」

### 検証結果

- Python構文検査が成功した。
- Python単体テスト13件がすべて成功し、対象人物限定、rename前失敗、清掃失敗、canonical ID、symlink、global lock競合の安全条件を再確認した。
- Sandbox内の初回DebugビルドはDerivedDataへの書込み制限で失敗したが、同一コマンドをSandbox外で再実行して成功し、ソース起因の失敗ではないことを確認した。
- Swift単体テスト50件がすべて成功し、失敗およびunexpected failureは0件だった。
- 明示確認前に削除を開始せず、Pythonの正式パス不在とSwiftの再読込みによる対象不在を確認するまでUIを削除完了へ進めないことを再確認した。
- 一般的な再帰削除、個別sample削除、完成MP4削除、第9段階以降の機能が混入していないことを静的に確認した。
- `git diff --check` が成功した。

### 未実施・未決定事項

- ユーザーの実人物データを使った手動UI操作は未検証のままとする。
- 解析処理によるglobal shared lockの本接続と、残存tombstoneの一般reconciliationは後続段階へ残す。
- App Sandbox下の `flock`、rename、unlink、rmdirは第22開始Gateまで未検証とする。

### 判定

自動検証と静的監査の範囲で問題はなく、第8C段階は完了状態を維持する。未検証事項を検証済みへ変更せず、後続段階の契約を先行実装していない。

---

## 2026-08-09：第9開始Gateの正式決定

### 対象Stage

第9段階「current_job、排他、正式通信基盤」開始Gate

### 決定事項

- `job.json` はSwift所有のschema version 1とし、安定job/request ID、不変の元動画・fingerprint・選択人物、revision付き排他状態を持たせる。
- 状態を開始要求、準備中、実行中、停止要求中、停止完了、正式完了、異常終了、復旧確認中へ分離し、フォルダやprocessの存在だけで状態を推測しない。
- Source fingerprintはbyte数と全byte SHA-256を正式一致条件とし、更新時刻、部分hash、inodeを正式一致根拠に使用しない。
- 排他はPython解析runnerが保持するローカルworkspaceの非待機 `fcntl.flock` を唯一の根拠とし、PID、stale時間、heartbeat、owner tokenは採用しない。
- `stop.requested` はjob/request IDを持つSwift所有JSONとし、lock取得後にjob IDと状態でstaleを判定する。時刻では判定しない。
- workspaceとcurrent_jobをApplication Support配下へ固定し、既知の1ファイルと検証済みpartialだけを個別に清掃する。再帰削除と未知項目削除を禁止する。
- 第9以降のrunnerへ、既存の基本3event、共通フィールド、厳密payload、protocol violation、EOF、exit、正式成果物検証を含む成功条件を適用する。
- 長時間解析・保存にはスリープ抑止が必要と判断するが、第9では実装しない。具体APIと全終了経路の解除契約は第22開始Gateで最終決定する。

### 理由

- 人工ファイル比較では軽量fingerprintが同一サイズ・mtime復元・部分範囲外変更を見逃し、全体SHA-256だけが全内容変更を検出した。
- 排他比較では `flock` が競合時の取得者を1件に限定し、所有process異常終了後にlock fileを削除せずOSがlockを解放した。
- 時刻、PID、heartbeatを実行根拠にしないことで、未検証の時間値とPID再利用を第9へ持ち込まずfail-closedにできる。
- 既存Preflight通信契約と大量stdout／stderr検証を共通runnerへ拡張し、未知入力や`finished`だけを成功へ読み替えないため。

### 後続へ残す事項

- 停止signal、猶予時間、強制終了、Process group、停止完了payloadは第14開始Gateまで未決定とする。
- VAD以降の成果物schema、正式完了条件、再利用条件は対応する開始Gateへ残す。
- App Sandbox、完成版filesystem、スリープ抑止APIと解除契約の最終検証は第22開始Gateへ残す。
- Security-Scoped Bookmarkと外部SDカード上の大容量全体hash性能は未検証のままとする。

### Gate判定

第9開始に必要な状態、所有権、job schema、fingerprint、排他、stale停止要求、削除境界、通信成功条件を正本化したため、第9開始Gateを通過済みとする。第9本体は未実装であり、完了扱いにしない。

---

## 2026-08-09：第9段階実装・検証

### 対象Stage

第9段階「current_job、排他、正式通信基盤」

### 実装内容

- Swiftの単一Serviceから、固定Application Support workspaceを対象にPython runnerをshellなし・引数配列で起動する。
- schema version 1の`job.json`を厳密検証し、Swiftが内容を要求し、正式lockを保持するPython runnerがpartial、flush、fsync、同一volume rename、再読込み検証で永続化する。
- 元動画の全byte SHA-256とbyte数をSwiftとPythonの双方で照合し、計算前後の変更または復旧時の不一致を安全に拒否する。
- 非待機`fcntl.flock`で同時取得を1件に制限し、正式jobが存在する二重要求も既存jobを置換せず拒否する。
- active状態の旧jobを実行中と推測せず`recovery_required`へ移し、元動画不一致は`failed/source_changed`とする。
- job状態と一致しない正しい`stop.requested`だけをstaleとして個別unlinkし、壊れたmarker、symlink、未知workspace項目は削除せずfail-closedとする。
- `job_lock`から`job_ready`の順序、共通フィールド、sequence、terminal、exit、stdout／stderr EOFを厳密検証するJSON Lines通信を実装する。

### 検証結果

- Python構文検査が成功した。
- Python単体テスト20件が成功し、そのうち第9段階7件でjob正式化、二重要求、lock競合、復旧、Source fingerprint不一致、stale停止要求、未知項目、subprocess JSON Linesを確認した。
- DebugビルドとSwift単体テスト全55件が成功した。そのうち第9段階5件で、全体fingerprint、job作成と二重拒否、復旧状態、元動画変更、無効人物選択、protocol violationを確認した。
- 一時テスト領域の親symlinkを正式検証が拒否したため、テストだけを非symlinkの`/private/tmp`へ修正し、製品側の検証条件は弱めていない。

### 未決定・後続へ残す事項

- VAD、解析用WAV、人物判定、品質判定、結果正式化、保存は未実装とする。
- 実解析中に同じrunnerが全子プロセス終了と終了後検証までlockを保持する本接続は、各後続処理を接続する段階で行う。
- 有効な停止要求の作成、signal、猶予時間、強制終了、Process group、停止完了表現は第14開始Gateまで未決定とする。
- スリープ抑止の具体方式、App Sandboxと完成版filesystemでの最終成立性は第22開始Gateまで未決定・未検証とする。
- DebugのPython絶対パスは開発時構成であり、配布時のPython配置・同梱方式を確定しない。

### Stage判定

二重解析拒否、クラッシュ後の実行中誤表示防止、fingerprint不一致時の再利用禁止を自動検証し、全テストと差分監査に成功したため、第9段階を完了とする。

---

## 2026-08-09：第9段階完了後の最終再検証

### 対象Stage

第9段階「current_job、排他、正式通信基盤」

### 検証結果

- Python構文検査と単体テスト全20件が成功した。
- クリーンなDerivedDataを使用したDebugビルドとSwift単体テスト全55件が成功し、失敗およびunexpected failureは0件だった。
- 人工一時データによる追加確認で、未知の`job.json` schemaと壊れたJSONがともに`job_invalid`として拒否されることを確認した。
- 二重要求、lock競合、stale停止要求、クラッシュ後復旧、Source fingerprint不一致、異常exit、protocol violationの安全条件が維持されていることを確認した。
- `git diff --check`が成功し、第10段階以降のVAD、解析用WAV、人物判定、結果正式化、保存が混入していないことを確認した。
- 復旧テストは成功したが、今回のクリーン環境ではApple同梱Pythonの初回起動を含む当該テストに約172秒を要した。機能失敗、timeout、子プロセス残存としては観測されていない。

### 未決定・未検証事項

- 停止signal、猶予時間、強制終了、Process group、停止完了表現は第14開始Gateまで未決定とする。
- App Sandbox、完成版filesystem、スリープ抑止の具体方式は第22開始Gateまで未決定・未検証とする。
- 配布時のPython配置・同梱方式をDebug環境の絶対パスから確定しない。

### 判定

自動検証と静的監査の範囲で新しい問題はなく、第9段階は完了状態を維持する。後続Gate事項を検証済みへ変更していない。

---

## 2026-08-09：第10開始Gateの正式決定

### 対象Stage

第10段階「解析用音声 `analysis.wav`」開始Gate

### 決定事項

- 元動画の先頭音声streamだけを16 kHz、mono、PCM s16leのWAVへ変換する。
- 固定workspaceのpartialへ排他的に生成し、WAV実体とmetadataを検証後、metadata、最後にWAVの順で正式化する。
- `analysis_audio.json` schema version 1を追加し、job ID、元動画fingerprint、固定変換profile、stream index、frame数、整数ミリ秒durationを再利用証明とする。
- 正式WAVとmetadataの両方がjobおよび実体と一致する場合だけ再利用し、一方だけ、partialだけ、未知schema、内容不一致は再利用しない。
- 変換前後に元動画fingerprintを再確認し、途中変更、読取不能、容量不足、FFmpeg失敗、WAV検証失敗では正式化しない。
- 開発時は検証済みローカルFFmpeg／ffprobeを設定経由で使用し、配布時配置は決定しない。

### 理由

- WAV単体では元動画と変換条件の対応を証明できないため、最小の厳密metadataを一組にする必要がある。
- WAVを最後のcommit markerとして正式化すれば、クラッシュ途中のmetadataだけを完成音声と誤認しない。
- 先頭音声streamと固定PCM profileに限定することで、初期版に音声track選択UIや未検証codec条件を追加しない。

### 未決定・未検証事項

- 配布時のPython／FFmpeg／ffprobe配置・同梱方式とApp Sandbox下の挙動は未決定とする。
- 実SDカード切断中の読取・変換挙動は未検証とし、自動試験の人工的な読取不能と区別する。
- VAD、候補生成、停止signal、保存容量契約を先行決定しない。

### Gate判定

第10開始に必要な変換、partial、検証、正式化、再利用、容量、error code、開発時実行契約を正本化したため、第10開始Gateを通過済みとする。第10本体は未実装であり、完了扱いにしない。

---

## 2026-08-09：第10段階実装・検証

### 対象Stage

第10段階「解析用音声 `analysis.wav`」

### 実装内容

- Pythonが正式jobとSource fingerprintを検証し、同じ`analysis.lock`を保持してから、先頭音声streamを固定16 kHz・mono・PCM s16leのWAVへ変換する。
- FFmpeg／ffprobeはshellなし・引数配列で起動し、元動画を変更せず、固定workspaceのpartialだけへ出力する。
- FFmpeg終了コードに加え、WAV header、sample rate、channel、sample幅、非圧縮PCM、frame数、整数ミリ秒durationを再読込み検証する。
- `analysis_audio.json`へjob ID、Source fingerprint、変換profile、選択stream、frame数、durationを保存し、metadata、最後にWAVの順で正式化する。
- 正式pairの完全一致時だけ再利用し、一方だけの正式成果物とstaleな既知partialはlock下で固定名・通常ファイル・非symlinkを確認して個別にreconciliationする。
- Swift Serviceは開発設定の実行ファイルを外部入力としてPythonへ渡し、`running`、`completed`、terminal、exit、両EOFを満たした結果だけを成功として受理する。

### 検証結果

- Python構文検査と単体テスト全28件が成功した。そのうち第10段階8件で正常生成・再利用、容量不足、FFmpeg失敗、元動画読取不能、音声stream不在、fingerprint変更、未知metadata schema、orphan／partial復旧、dangling symlink拒否を確認した。
- DebugビルドとSwift単体テスト全58件が成功した。そのうち第10段階3件で成功event順序、検証完了欠落、未知event、error一致、異常exitの拒否を確認した。
- 人工MP4だけを使用し、正式WAVが16 kHz、mono、PCM s16leで正のframe数とdurationを持つことを機械的に確認した。
- `git diff --check`が成功し、VAD、候補生成、人物判定、停止、保存を先行実装していないことを確認した。

### 未決定・未検証事項

- 実SDカードの処理中切断、App Sandbox、配布時のPython／FFmpeg／ffprobe配置は未検証・未決定のままとする。
- FFmpeg長時間処理の停止signal、猶予時間、強制終了、Process groupは第14開始Gateまで未決定とする。
- VAD以降の成果物と解析完了状態への遷移は後続段階へ残す。

### Stage判定

正式WAVが入力fingerprintおよび固定変換profileと対応し、失敗時または不完全pairを正式完成として再利用しないことを自動検証できたため、第10段階を完了とする。

---

## 2026-08-09：第10段階完了後の最終再検証

### 対象Stage

第10段階「解析用音声 `analysis.wav`」

### 検証結果

- `Info.plist`とXcode project設定の構文検査が成功した。
- Python構文検査と単体テスト全28件が成功し、第10段階の正常生成・厳密再利用、容量不足、FFmpeg失敗、元動画読取不能、音声stream不在、fingerprint変更、未知metadata schema、不完全成果物復旧、symlink拒否を再確認した。
- クリーンなDerivedDataを使用したDebugビルドとSwift単体テスト全58件が成功し、失敗およびunexpected failureは0件だった。
- Swift側が正式な完了条件とevent順序を要求し、検証完了欠落、未知event、error不一致、異常exitを成功扱いしないことを再確認した。
- `git diff --check`が成功し、VAD、候補生成、人物判定、停止、保存など第11段階以降の機能が混入していないことを確認した。

### 未決定・未検証事項

- 実SDカードの処理中切断は未検証であり、人工的な元動画読取不能試験と同一視しない。
- App Sandbox、配布時のPython／FFmpeg／ffprobe配置・同梱方式は未決定・未検証のままとする。
- FFmpeg長時間処理の停止signal、猶予時間、強制終了、Process groupは第14開始Gateまで未決定とする。
- VAD以降の成果物および解析完了状態は後続段階へ残す。

### 判定

最終再検証で新しい問題はなく、第10段階は完了状態を維持する。後続Gateの未決定・未検証事項を検証済みまたは本番方式へ変更していない。

---

## 2026-08-09：第11開始GateのVAD候補検証と正式決定

### 対象Stage

第11段階「VAD」開始Gate

### 決定事項

- 第11段階はPython標準ライブラリによる固定frame RMS方式を採用する。
- 正式`analysis.wav`と`analysis_audio.json`のpairを再検証し、16 kHz、mono、PCM s16leだけを入力とする。
- 30ms frameのRMSが-45 dBFS以上ならactiveとし、連続90ms以上だけをメモリ内の整数ミリ秒半開区間として返す。
- 発話0件は正常結果とする。
- 進捗は`stage: vad`の`running`、`completed`、error codeは`vad_busy`、`vad_job_invalid`、`vad_input_unavailable`、`vad_input_invalid`、`vad_processing_failed`、`vad_protocol_error`とする。

### 理由

- 人工WAVの3回比較でPython方式とFFmpeg `silencedetect`は全ケースに一致し、Python方式は2秒入力で約1.1〜1.3ms、FFmpeg方式は約20〜22msだった。
- Python方式は追加依存と追加processがなく、正式WAVを逐次処理しやすい。
- `torchaudio.functional.vad`は全activity区間を返すAPIではなく、今回の人工2区間信号も既定条件で検出しなかったため採用しない。

### 検証結果

- 人工WAV実験の構文検査と自己判定が成功し、無音、2区間、小音量、低レベルnoise、短音、壊れたWAV、形式違反WAVを機械的に確認した。
- 既存Python単体テスト全28件が成功した。
- クリーンなDerivedDataを使用したDebugビルドとSwift単体テスト全58件が成功し、失敗およびunexpected failureは0件だった。
- 既存の復旧テストは成功したが、Apple同梱Python起動を含む当該テストに約577秒を要した。今回のVAD候補実験による製品コード変更や機能失敗ではない。
- `git diff --check`が成功し、第11段階本体および第12段階以降の機能を実装していないことを確認した。

### 未決定・未検証事項

- 実人物、BGM、SE、残響、複数話者、端末差での検出精度は未検証とする。RMS方式は大きな非音声をactivityとして検出し得る。
- `vad.json` schema、正式化、再利用、候補ID、候補結合・分割・余白・長さは第12開始Gateまで未決定とする。
- 今回のVAD条件を人物一致閾値、音声品質の◎／○／△、第12段階の候補長へ転用しない。
- 配布時Python配置とApp Sandbox下の挙動は第22開始Gateまで未決定とする。

### Gate判定

方式、入力、判定条件、正常0件、進捗、error code、後続責務を正本化したため、第11開始Gateを通過済みとする。第11本体は未実装であり、完了扱いにしない。

---

## 2026-08-09：第11段階実装・検証

### 対象Stage

第11段階「VAD」

### 実装内容

- Pythonが正式`job.json`と第10契約の`analysis.wav`／`analysis_audio.json` pairをlock下で再検証してから、30ms frame RMS方式でactivityを検出する。
- 連続するactive frameを整数ミリ秒の半開区間へ変換し、90ms未満を除外する。発話0件は正常な空配列として返す。
- 検出区間はJSON Linesの実行結果としてメモリ内で受け渡し、永続`vad.json`、再利用成果物、候補IDを作成しない。
- Pythonは`running`、`completed`、`finished`の順序と安定error codeを出力し、Swift Serviceは正常exit、完全なevent順序、厳密payload、非重複区間、最小長を検証してから成功を受理する。
- Debugだけに既存ローカルPythonを設定し、Release配置は空のままとした。

### 検証結果

- Python構文検査と単体テスト全35件が成功した。そのうち第11段階7件で2区間検出、発話0件、短音除外、正式pair欠落・未知schema・dangling symlink拒否、partial非消費、処理失敗error、実CLI event順序を確認した。
- DebugビルドとSwift単体テスト全61件が成功した。そのうち第11段階3件で正常区間と0件、重複・短すぎる区間、完了進捗欠落、既知error一致、異常exitの拒否を確認した。
- `Info.plist`とXcode project設定の構文検査、`git diff --check`が成功した。
- 既存の復旧テストは成功したが、Apple同梱Python起動を含む当該テストに約193秒を要した。第11実装の機能失敗、timeout、子プロセス残存ではない。
- `vad.json`、候補結合・分割、人物判定、品質判定、停止、保存を先行実装していないことを確認した。

### 未決定・未検証事項

- 実人物、BGM、SE、残響、複数話者、端末差での検出精度は未検証のままとする。
- 永続VAD schema、正式化・再利用、候補生成規則、候補IDは第12開始Gateまで未決定とする。
- App Sandboxと配布時Python配置は第22開始Gate、停止方式は第14開始Gateまで未決定とする。
- 今回のactivity条件を人物一致、音声品質、候補長の閾値へ転用しない。

### Stage判定

正式入力だけを処理し、発話あり・0件・失敗を単体検証でき、テスト専用／メモリ内区間を正式後段成果物にしていないため、第11段階を完了とする。

---

## 2026-08-09：第11段階完了後の最終再検証

### 対象Stage

第11段階「VAD」

### 検証結果

- 正本の開始Gate、実装範囲、完了条件と実装を再照合し、正式`analysis.wav` pairの再検証後だけVAD処理へ進むことを確認した。
- `Info.plist`、Xcode project、Python構文検査が成功した。
- Python単体テスト全35件が成功し、発話あり、0件、短音除外、入力欠落・未知schema・dangling symlink拒否、partial非消費、安定error、実CLI event順序を再確認した。
- クリーンなDerivedDataを使用したDebugビルドとSwift単体テスト全61件が成功し、失敗およびunexpected failureは0件だった。
- Swift側が正常exit、`running`、`completed`、`finished`、厳密payload、非重複区間、90ms以上を満たす場合だけ成功を受理することを再確認した。
- `git diff --check`が成功し、`vad.json`、候補生成、人物判定、品質判定、停止、保存が混入していないことを確認した。
- 既存の復旧テストは成功したが、Apple同梱Python起動を含む当該テストに約152秒を要した。機能失敗、timeout、子プロセス残存としては観測されていない。

### 未決定・未検証事項

- 実人物、BGM、SE、残響、複数話者、端末差でのVAD精度は未検証のままとする。
- 永続VAD schema、正式化・再利用、候補生成規則、候補IDは第12開始Gateまで未決定とする。
- App Sandbox、配布時Python配置、停止方式は対応する後続Gateまで未決定・未検証とする。
- 第11のactivity条件を人物一致、音声品質、候補長の閾値へ転用しない。

### 判定

最終再検証で新しい問題はなく、第11段階は完了状態を維持する。後続Gate事項を検証済みまたは本番仕様へ変更していない。

---

## 2026-08-09：第12開始Gateの候補区間検証と正式決定

### 対象Stage

第12段階「候補区間生成」開始Gate

### 決定事項

- `vad.json`と`speaker_candidates.json`をPython所有の厳密なschema version 1として正式化する。
- `vad.json`は正式解析音声pairの全byte SHA-256とbyte数、VAD profile、音声長、整数ミリ秒区間を持つ。
- `speaker_candidates.json`は正式`vad.json` fingerprint、生成profile、安定候補ID、整数ミリ秒区間を持つ。
- 500ms以下のVAD gapを結合し、前後各250msを加える。候補は原則3,000〜30,000msとし、短区間は範囲内で拡張、長区間はoverlapなしで分割する。
- 動画全体が3,000ms未満の場合とVAD 0件は候補0件の正常成果物とする。
- 候補IDはjob UUIDをnamespace、`candidate:v1:<start_ms>:<end_ms>`をnameとするUUIDv5へ`candidate_`を付ける。
- partial、正式化順序、厳密再利用、進捗、安定error codeを`ARCHITECTURE.md`第8.8節のとおり確定する。

### 理由

- 第8A技術検証で3〜30秒はEmbedding入力の限定的な安定傾向と処理上限として採用済みであり、未検証の別範囲を増やさず再利用できる。
- 人工区間比較でbalanced方式だけが400msの短い間を結合し、800msの間を別候補として維持した。
- UUIDv5をjobと確定区間から生成すれば、同じ正式入力と契約でIDを再現でき、配列位置や表示名へ依存しない。
- VADと候補成果物をfingerprintで連結し、候補側を最後のcommit markerにすることで、不完全なpairを完成扱いしない。

### 検証結果

- compact、balanced、broadを、0件、400ms／800ms gap、動画両端の短区間、2秒短尺、65秒長区間、重複入力で比較した。
- balancedは期待した結合・分離、3秒への端点拡張、30秒以下の非重複分割、短尺0件を満たした。
- 同一入力の3回再実行で候補配列とUUIDv5が一致し、重複VAD入力を拒否した。
- 既存Pythonテスト35件とDebug構成のSwift単体テスト61件はすべて成功した。
- `git diff --check`に問題はなかった。

### 未決定・未検証事項

- 実人物会話における500ms gap、250ms余白、3〜30秒候補の体感品質は未検証とする。
- 候補Embedding、人物判定、人物不明、品質判定、`result.json`は後続Gateへ残す。
- 保存MP4の切出し境界とcandidate境界の関係は第19開始Gateまで未決定とする。
- App Sandboxと配布時Python配置は第22開始Gateまで未決定とする。

### Gate判定

schema、正式化・再利用、生成数値、境界、安定ID、所有権、進捗、error codeを正本化したため、第12開始Gateを通過済みとする。第12本体は未実装であり、完了扱いにしない。

---

## 2026-08-09：第12段階の実装・最終検証

### 対象Stage

第12段階「候補区間生成」

### 実装内容

- 正式`vad.json`から候補区間を生成し、安定候補IDを付与した正式`speaker_candidates.json`をPython所有で生成する。
- 入力fingerprint、schema、区間境界、候補生成profileを厳密に検証し、partialへの書込み、同期、rename、正式成果物の再読込み検証を経て完成扱いとする。
- SwiftはJSON Linesの進捗・error・finishedとプロセス終了を検証し、正式成果物の検証完了前に成功扱いしない。
- 第12成果物を既存ジョブ復旧処理の既知項目へ追加し、未知項目を許容する方式には変更していない。

### 成功した検証

- Python構文検査が成功した。
- Python単体テスト全41件が成功した。第12段階の6件を含み、0件、端点、近接区間、長区間、安定ID、再利用、不正入力、partial非完成扱いを確認した。
- Debugビルドが成功した。
- 第12段階のSwift単体テスト3件が成功し、正常応答、厳密なイベント・payload検証、異常応答の拒否を確認した。
- `git diff --check`が成功した。

### 既存Swiftテストの停止に関する切り分け

- Swift全体テストは、既存の`JobManagementTests.testRecoverySeparatesFolderFromRunningAndDetectsSourceChange`が完了せず、手動で中断した。このため、Swift全体テストを成功とは記録しない。
- 当該テスト単独でも同じ停止を再現した。Xcodeテスト環境から起動されたPythonは、対象script本体へ到達する前のPython起動・import処理中の`open`で停止していた。
- 同じ`analysis_job_runner.py`をXcodeテスト環境外から起動した場合は約0.033秒で起動・終了し、空入力に対する期待どおりのerror終了を確認した。
- 第12変更が当該scriptへ加えた内容は復旧時の既知成果物名の追加だけであり、停止したテストの人工領域には第12成果物が存在しないため、その分岐は実行されない。第12の`CandidateGenerationService`も当該テストから呼び出されない。
- 過去の第11段階検証記録でも同じ既存復旧テストに約577秒、193秒、152秒を要した履歴がある。
- 以上から、今回の停止は第12変更による機能不良ではなく、Xcodeテスト環境下の既存Python subprocess起動問題として扱う。原因となる環境問題の修正は第12段階の範囲外であり、今回追加修正・再テストは行わない。

### 未決定・未検証事項

- 実人物会話に対する候補区間の体感品質は未検証とする。
- Embedding、人物判定、人物不明判定、音声品質判定、`result.json`は後続段階へ残す。
- 候補境界と完成MP4切出し境界の正式な関係は第19開始Gateまで未決定とする。
- App Sandboxと配布時Python配置は対応する後続Gateまで未決定・未検証とする。
- Xcodeテスト環境下の既存Python subprocess起動停止は、別途扱う環境課題として残す。

### Stage判定

第12固有の実装、Debugビルド、Python全テスト、第12固有Swiftテスト、差分検査が成功し、既存Swiftテストの停止が第12変更の実行経路外であることを切り分けたため、第12段階を完了とする。Swift全体テスト完走およびXcodeテスト環境問題の解消を意味しない。

---

## 2026-08-09：第13開始Gateの候補Embedding・人物比較契約

### 対象Stage

第13段階「Speaker Embeddingと人物判定」開始Gate

### 確認済み事項

- 既存の人工合成音声技術検証で、固定モデルにより3〜30秒の16kHz mono入力から再現可能な192次元float32・有限・L2正規化Embeddingを生成できた。
- 同じモデル・revisionの複数sample Embeddingから再L2正規化centroidを構成し、候補Embeddingとのcosine similarityを算出できた。
- 無音でも有限Embeddingを返し得るため、Embedding生成成功を音声品質や人物一致の成功へ読み替えてはいけないことを確認済みである。

### 決定事項

- 候補区間は正式`analysis.wav`からメモリ内tensorとして読み、登録sampleと同じ固定モデル・revisionで192次元L2正規化Embeddingを生成する。候補Embedding自体は永続化しない。
- 比較対象は正式`job.json`の選択人物だけとし、全sampleを厳密検証してcentroidを都度再計算する。非選択人物の資産は読まず、非選択人物との一致を推測しない。
- Python内部の後段入力として`speaker_matches.json` schema version 1を所有し、正式候補、モデル、選択人物sample構成をfingerprintで結び付ける。
- 各候補について選択人物全件との有限なcosine similarityだけを内部保存する。本人確率、最高人物、人物不明、表示段階は保存せず、Swift UIへ生スコアを渡さない。
- partial、fsync、rename、正式再検証、厳密再利用、進捗、安定error codeは`ARCHITECTURE.md`第8.9節を正本とする。
- 開発時は既存Debug設定からローカルPython virtualenvとモデルを注入し、Release設定は空、実行中downloadは禁止とする。

### 理由

- 候補Embeddingを永続化せず比較結果だけを保持すると、再生成可能な派生ファイルと清掃対象を増やさず、第15段階に必要な内部材料を残せる。
- 選択人物だけを読むことで解析対象をjob要求と一致させ、非選択人物を暗黙の識別候補へ加えない。
- 人物資産のsample fingerprintを再利用条件へ含めれば、sample追加・再生成後にstaleな比較結果を正式成果物として扱わない。
- 既存技術検証は生成・比較の成立性には十分だが、実人物閾値や完成版配置の決定材料には不足するため、責務別に後続Gateへ残す。

### 未決定・未検証事項

- 人物一致閾値、人物不明判定、人物一致表示変換は第15開始Gateまで未決定とする。
- 実人物、雑音、残響、複数話者、マイク・端末差での識別精度は未検証とする。
- 音声品質判定と◎／○／△は第15開始Gateまで独立した未決定事項とする。
- 完成版Python、SpeechBrain、PyTorch、モデルの配置・同梱方式とApp Sandbox採否は第22開始Gateまで未決定とする。

### Gate判定

解析候補Embedding、選択人物比較、内部score範囲、正式中間成果物、再利用、開発時モデル配置を正本化したため、第13開始Gateを通過済みとする。第13本体は未実装であり、完了扱いにしない。

---

## 2026-08-10：第13段階の実装・最終検証

### 対象Stage

第13段階「Speaker Embeddingと人物判定」

### 実装内容

- 正式`analysis.wav`、`vad.json`、`speaker_candidates.json`を再検証し、候補区間のPCM sampleから192次元L2正規化Embeddingを生成するPython処理を追加した。
- 正式jobで選択された人物だけを読み、各人物の全sampleを厳密検証してcentroidを再計算し、候補とのcosine similarityを内部`speaker_matches.json`へ保存する。
- 候補・人物sample構成・モデルをfingerprintで結び付け、partial、fsync、rename、正式再読込み後だけ完成扱いとする。人物資産変更後のstale結果は再利用しない。
- Swift Serviceは設定済みPython・モデル・jobを検証し、stdout JSON Linesの順序、件数progress、安定error、finished、正常exitを検証する。progressとSwift結果へ生スコアを含めない。
- 後続段階から認識できるよう、既存ジョブ成果物の許可リストへ`speaker_matches.json`だけを追加した。

### 成功した検証

- Python構文検査が成功した。
- Python単体テスト全46件が成功した。第13段階の5件で、選択人物2件との比較、正式化・再利用、候補0件、壊れた非選択人物を読まないこと、人物Embedding変更後のstale拒否、モデル欠損時の正式成果物非生成を確認した。
- `Info.plist`とXcode projectの構文検査が成功した。
- Debugビルドが成功した。
- 第13段階のSwift単体テスト3件が成功した。厳密な進捗順序、候補0件、生スコアを混入したprogress、件数飛びを検証した。
- `git diff --check`が成功した。

### Swift全体テストの2分中断

- Swift全体テストは、第13テストより前に実行される既存`JobManagementTests.testRecoverySeparatesFolderFromRunningAndDetectsSourceChange`で停止し、指示された2分上限で中断した。このためSwift全体テストを完走・成功とは記録しない。
- 中断前にAnalysisAudio 3件、AppViewModel 50件、CandidateGeneration 3件など、当該テストより前のテストはすべて成功した。
- 停止時に動作していた対象は既存`analysis_job_runner.py`と既存人物登録Python subprocessであり、第13の`SpeakerMatchingService`および`speaker_matching.py`は当該テストから呼ばれない。
- 第12段階で同じ既存テストを単独再現し、Xcodeテスト環境下ではscript本体へ到達する前のPython起動・import中に停止する一方、Xcode外では同じrunnerが約0.033秒で起動・終了することを確認済みである。
- 以上から、今回の停止は第13変更による機能不良ではなく、既知のXcodeテスト環境下Python subprocess問題として扱う。追加修正・再テストは行わない。

### 未決定・未検証事項

- 実人物、雑音、残響、複数話者、マイク・端末差での識別精度は未検証とする。
- 人物一致閾値、人物不明判定、人物一致表示変換は第15開始Gateまで未決定とする。
- 音声品質判定と◎／○／△は人物比較から独立した後続責務とする。
- 完成版Python、SpeechBrain、PyTorch、モデルの配置・同梱方式とApp Sandbox採否は第22開始Gateまで未決定とする。
- Xcodeテスト環境下の既存Python subprocess起動停止は別の環境課題として残す。

### Stage判定

第13固有の実装、Python全テスト、第13固有Swiftテスト、Debugビルド、設定・差分検査が成功し、Swift全体テストの停止が第13実行経路外の既知問題であるため、第13段階を完了とする。人物一致閾値、人物不明、音声品質または完成版モデル配置の完了を意味しない。

---

## 2026-08-10：第13段階完了後の最終再検証

### 対象Stage

第13段階「Speaker Embeddingと人物判定」

### 再検証結果

- `Info.plist`とXcode projectの構文検査が成功した。
- Python単体テスト全46件が成功した。
- Debugビルドが成功した。
- 第13段階のSwift単体テスト3件が成功した。
- Swift全体テストは、Codex実行Sandbox内では`testmanagerd`への接続拒否により開始できなかったため、同一内容をSandbox外で再実行した。
- Sandbox外のSwift全体テストでは、既存の人物登録Python subprocessが残る既知の停止状態が再発した。2分上限を超えたため、今回起動したXcode・アプリ・Pythonプロセスだけを終了し、全体テストを成功とは記録しない。
- 停止時に第13の`speaker_matching.py`は動作しておらず、第13固有SwiftテストとPython全テストは別途成功している。従って、今回の停止は第13変更の実行経路外にある既知のXcodeテスト環境問題と判断する。
- テスト中断後、今回起動したテスト関連プロセスが残っていないことを確認した。

### 未決定・未検証事項

- Swift全体テストの完走は未確認である。
- Xcodeテスト環境下の既存Python subprocess起動停止は別の環境課題として残す。
- 人物一致閾値、人物不明判定、人物一致表示変換は第15開始Gateまで未決定とする。
- 完成版Python、AI依存、モデルの配置・同梱方式とApp Sandbox採否は第22開始Gateまで未決定とする。

### Stage判定

第13固有の自動テスト、Python全テスト、Debugビルドが再度成功し、全体テストの停止が第13変更の実行経路外であるため、第13段階の完了判定を維持する。Swift全体テスト完走または後続Gateの未決定事項解消を意味しない。

---

## 2026-08-10：第14開始Gateの停止・再開契約

### 対象Stage

第14段階「解析停止と途中再開」開始Gate

### 決定事項

- Swift所有の`stop.requested`と`job.json.stop_requested`を停止要求とし、停止要求と停止完了を分離する。
- Pythonは長時間FFmpegを新しいprocess groupで所有し、有効要求時にそのgroupだけへ`SIGTERM`、5秒後も残る場合だけ同じgroupへ`SIGKILL`を送り、終了を確認する。
- 独立eventは追加せず、順序付き`progress`後の`finished(outcome: stopped)`を停止完了通信に使用する。
- process終了、partial非正式化、後続工程非開始、Source fingerprint、正式job状態を検証後にだけ`stopped`へ進める。
- 再開は正式`stopped`、marker不在、fingerprint一致、許可された正式成果物の再検証を必須とし、partialを再利用しない。

### 理由

既存実験に加え、process group限定`SIGTERM`と、signalを無視する人工親子への限定`SIGKILL`を各6回確認し、対象外processへ広げず親子残存なしを確認できた。基本3eventを維持すれば、未知event追加を避けつつ停止理由をterminal outcomeとして厳密に表せる。

### 未決定・未検証事項

- App Sandbox下のprocess group／signalと、完成版Python・FFmpeg配置は第22開始Gateまで未検証・未決定とする。
- アプリ自体の異常終了後に外部processが残る条件は配布構成と合わせて第22開始Gateで再検証する。

### Gate判定

第14開始に必要な停止要求、子process終了、signal・猶予・強制終了、通信、停止後検証、再開契約を正本化したため、第14開始Gateを通過済みとする。第14本体は未完了である。

---

## 2026-08-10：第14段階の実装・最終検証

### 対象Stage

第14段階「解析停止と途中再開」

### 実装内容

- Swiftの停止要求Serviceが、正式`running` jobだけに厳密な`stop.requested`を作成し、jobを次revisionの`stop_requested`へ更新するようにした。
- Python共通停止処理が有効markerを検証し、所有するFFmpeg process groupだけを正式契約のsignal・猶予で終了するようにした。
- 解析用音声生成を`Popen`へ移し、FFmpeg開始前と実行中の停止を検知してpartialを正式化せず、停止後検証後だけjobを`stopped`へ進めるようにした。
- 停止完了は独立eventを増やさず、3件の順序付き`progress`と`finished(outcome: stopped)`としてSwiftで厳密検証する。
- 正式`stopped` jobは、marker不在、Source fingerprint一致、許可された正式成果物だけを確認後に`preparing`へ再開できるようにした。

### 検証結果

- process group補足実験は初回・再実行とも、FFmpeg終了3件と強制終了が必要な人工親子3件の全試行が成功し、計12試行で対象process残存なしだった。
- Python構文検査と単体テスト全49件が成功した。第14固有3件でmarker・job状態、停止後正式化、process group終了順序、再開、未知schemaのfail-closedを確認した。
- `Info.plist`とXcode projectの構文検査が成功した。
- Debugビルドが成功した。
- 第14関連Swift単体テスト5件が成功し、停止要求永続化、停止progress順序、`finished(outcome: stopped)`、順序違反拒否を確認した。
- `git diff --check`が成功した。
- 既知のXcodeテスト環境下Python subprocess停止を含むSwift全体テストは、ユーザー指示に従い再実行していない。

### 未決定・未検証事項

- App Sandbox下のprocess group／signal、配布版Python・FFmpeg配置、アプリ自体の異常終了後に残る外部processは第22開始Gateまで未検証・未決定とする。
- 第15以降の人物不明・品質判定・正式結果は先行実装していない。

### Stage判定

Gate契約、停止要求Service、子process停止、停止後検証、停止通信、正式成果物だけの再開と第14固有検証が完了したため、第14段階を完了とする。Swift全体テスト完走または第22 Gateの未検証事項解消を意味しない。

---

## 2026-08-10：第14段階完了後の最終再検証

### 対象Stage

第14段階「解析停止と途中再開」

### 再検証結果

- 第14関連Python構文検査が成功した。
- 第14停止処理と解析用音声のPython単体テスト11件が成功した。
- `Info.plist`とXcode projectの構文検査が成功した。
- Debugビルドが成功した。
- 第14関連Swift単体テスト5件が成功した。
- `git diff --check`が成功した。
- 既知のXcodeテスト環境下Python subprocess停止を含むSwift全体テストは、ユーザー指示に従い再実行していない。

### 仕様整合性監査

技術検証当時の未決定事項を現在形で残していた`ARCHITECTURE.md`の記述を、検証当時は未決定だったことと、現在の正式契約が第8.10節であることを区別する表現へ修正した。App Sandbox、配布構成、アプリ異常終了後の外部processなど第22開始Gateへ残した事項は未検証・未決定のまま維持した。

### Stage判定

第14固有の停止要求、process group終了、停止後検証、停止通信、再開契約と必要最小限の自動検証が再度成立したため、第14段階の完了判定を維持する。Swift全体テスト完走または第22 Gateの未検証事項解消を意味しない。

---

## 2026-08-10：第15保留時の後続Stage依存監査

### 対象Stage

第15〜23段階

### 確認結果

- 第15開始Gateは、代表的な実人物データによる人物一致閾値・人物不明判定・表示変換の技術検証が不足しているため未通過のままとする。既存の人工音声2話者の実測値から閾値を推測しない。
- 第16段階は第15完了を明示的な前提とし、正式`result.json`検証後のResults遷移を担当するため先行できない。
- 第17段階は第15・16完了、第18段階は第17完了、第19段階は第17・18完了、第20段階は第19完了を明示的な前提とする。
- 第21段階は第0〜20完了、第22段階は第0〜21完了、第23段階は第0〜22完了を前提とする。

### 判断

第15未完了のまま安全に実装できる後続Stageは存在しない。AVPlayer、保存、配布構成等を独立機能として先行実装すると、唯一の正式工程表の前提と後続段階先行実装禁止に反するため実施しない。第15の検証用実人物データと正解ラベルを安全に用意できるまで、第15および第16以降を保留する。

### 未決定事項

人物一致閾値、人物不明判定、人物一致表示変換、音声品質の◎／○／△変換は未決定のまま維持する。今回の依存監査は、第15開始Gateの通過または後続Stageの開始を意味しない。
