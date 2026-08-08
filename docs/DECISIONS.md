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

正本仕様への反映完了後、第3段階の開始Gateは通過とする。第3段階の実装は別作業として開始する。
