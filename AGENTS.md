# AGENTS.md

## 開始時
1. `AGENTS.md`
2. `docs/CURRENT_STATUS.md`
3. 現在Stageに必要な正本
4. 変更対象コード
の順で確認する。

リポジトリ全体・全履歴を毎回読み直さない。

## 最優先
- GitHubをChatGPTとCodexの共通正本とする。
- 現在Stage以外を勝手に実装しない。
- Gate未通過を推測で突破しない。
- 元動画・完成成果物を破壊しない。
- 完全ローカルを維持する。
- 利用上限節約は安全性・仕様準拠を維持した範囲でのみ行う。
- 必要なGate・検証・データ整合性確認を、利用上限節約を理由に省略してはならない。

## 省トークン
- 必要な箇所だけ読む。
- 記録済み経緯を反復しない。
- `docs/DECISIONS.md` の確定事項を理由なく再検証しない。
- 1 Stageずつ進める。
- 必要最小限の関連テストを優先する。
- 既知の長時間ハングテストを毎Stage繰り返さない。
- 長時間停止時は限定的に切り分ける。
- 完了報告は「実施・検証・commit・push・Blocker」を中心に簡潔にする。

## 禁止
- 無関係なリファクタリング
- 仕様外機能
- 未決定値の推測
- 後続Stage先行実装
- 不要な依存追加
- `shell=True`
- ルート `README.md` の勝手な追加・変更
- 無関係な未追跡ファイルの追加
- Gateを通すための数値ねつ造
- テストを通すためだけの仕様変更

## Git
- 変更対象だけstageする。
- 必要な検証→差分確認→commit→push。
- push/認証エラー時は追加修正せず停止。
- 各Stage後に `docs/CURRENT_STATUS.md` を更新して共有する。

## ChatGPT ↔ GitHub ↔ Codex
- GitHubを会話間の正本共有場所とする。
- Codex: 実装・検証・記録・commit・push。
- ChatGPT: GitHubのcommit/仕様/状態を確認し、次の短い指示を作る。
- 会話履歴ではなくGitHub上の正本を優先する。

## 仕様参照
仕様の所在が分からない場合は、全ファイル探索の前に `docs/SOURCE_OF_TRUTH_MAP.md` を確認する。
仕様変更が必要な場合は `docs/CHANGE_CONTROL.md`、前提変更時は `docs/REVALIDATION_MATRIX.md` に従う。
