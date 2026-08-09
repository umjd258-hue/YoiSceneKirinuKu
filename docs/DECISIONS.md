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

### 未決定事項

- Python解析と実進捗の接続、`stop.requested`、FFmpeg等の子プロセス停止、停止後成果物検証。
- 本番signal、猶予時間、強制終了、Process group、停止完了event形式。
- Source fingerprint、partial、正式完成済み工程に基づく本番の再開可否判定。

これらは対応する後続段階の開始Gateまで未決定のままとし、第5段階では実装していない。

### Stage判定

第5段階の実装範囲と完了条件を満たしたため、第5段階を完了とする。第6段階以降の機能および本番停止処理は先行実装していない。
