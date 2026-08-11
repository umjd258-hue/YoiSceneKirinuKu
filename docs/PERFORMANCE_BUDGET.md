# PERFORMANCE_BUDGET.md

Stage 25で基準機上の実測から正式値を決定する。
事前に根拠のない数値上限を固定しない。

測定対象:
- peak memory
- CPU負荷/継続高負荷
- temporary disk usage
- source長に対する処理時間
- Python/AI model起動時間
- UI responsiveness
- 再利用時の短縮効果
- 停止に要する時間

方針:
- 動画全体を不要にRAMへ保持しない。
- 重いAIは候補区間へ限定。
- 既存の検証済み成果物を互換条件下で再利用。
- UI main threadで重い処理をしない。
- 性能改善のために安全性/品質Gateを勝手に削らない。
