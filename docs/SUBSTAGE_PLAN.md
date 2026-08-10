# SUBSTAGE_PLAN.md — 高リスク工程の細分化

主工程Stage 1〜27は維持し、高リスク部分だけSubstageに分ける。
CURRENT_STATUSでは主StageとSubstageを両方記録できる。

## 正本との関係
- 親Stageの意味は `IMPLEMENTATION_STEPS.md` を正本とする。
- Stage 7A/7B は Stage 7「FFmpeg解析用音声抽出」の細分化であり、人物登録UIではない。
- Stage 8A/8B/8C は Stage 8「人物管理データ基盤」のうちSpeaker Embedding/登録資産に関する高リスク部分の細分化である。
- 人物登録SwiftUIは Stage 9。人物削除のCRUD責務は親Stage 8で定義し、8Cを「人物削除」に再定義しない。

## Stage 7A — FFmpeg/配置Gate
Python/FFmpegの開発時・製品時配置、version、実行方式を検証・正本化する。

## Stage 7B — 解析用音声抽出
7Aの正式方式だけを使い、16kHz mono WAV生成、partial、検証、再利用を実装する。

## Stage 8A — Speaker Embedding技術Gate
model、preprocess、dimension、normalization、実行コストを検証する。

## Stage 8B — sample/source.wav/Embedding永続化
登録元source.wavを保護し、sample metadataとEmbeddingを正式保存する。

## Stage 8C — 複数sample統合・再生成
複数sampleのcharacter representation、model変更時再生成、品質不足を検証・実装する。

## ルール
Substage未完了なら親Stageを完了扱いしない。
後続Stageは必要なSubstageの正式成果物を前提とする。
