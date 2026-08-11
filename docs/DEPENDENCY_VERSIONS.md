# DEPENDENCY_VERSIONS.md

再現性のため、採用時に以下を記録する。

- macOS version / minimum supported version
- Xcode version
- Swift toolchain
- Python version
- Python package versions
- FFmpeg version/build
- Speaker Embedding model id/version/hash（必要時）
- VAD implementation/model version
- schema versions

「latest」を永久契約にしない。
version更新時は互換性、Embedding再生成、schema migration、回帰テスト範囲を判断する。
