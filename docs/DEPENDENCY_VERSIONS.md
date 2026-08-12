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

## Stage 6固定値

- bundled Python: `3.13.14`
- Stage 6 Python packages: 第三者package 0件（標準ライブラリのみ）
- runtime入力はPython 3.13.14公式macOS universal2 installer原本に固定し、原本のSHA-256を`vendor/python/3.13.14/`のmanifestで固定する。
- installer原本はGit LFS、SHA manifest・取得元記録・PSF Licenseは通常Gitで管理する。LFS object未取得時はfail-closedとし、Build時downloadは禁止する。
- offline Sigstore検証toolはstandalone `cosign v2.6.2`に固定する。macOS arm64実行物`cosign-darwin-arm64`は公式releaseを取得元とし、SHA-256を`c01df01bac51714322f17d6416798d8a7b9e903657c6a2f8f09b9aee5ba29f57`、ライセンスをApache License 2.0に固定する。製品Bundleには含めない。
- Sigstore公式`trusted_root.json`は`root-signing` commit `c9bda74ad2221f938f7d2e0295ca3aad2da710a8`の公式raw版、SHA-256 `6494e21ea73fa7ee769f85f57d5a3e6a08725eae1e38c755fc3517c9e6bc0b66`に固定し、`vendor/sigstore/trusted_root.json`として通常Git管理する。実行時TUF更新は禁止する。
- 後続Stageで必要になる依存は、対応する開始Gateでversion/package lockを別途固定する。

## Stage 7A固定方針

- FFmpeg / ffprobeはupstream FFmpeg `8.1.2` sourceから構築する。
- universal2、必要機能限定、LGPL互換configureとし、source SHA-256、build toolchain、configure、完成した`ffmpeg` / `ffprobe`のSHA-256を一体で固定する。
- build toolchainはXcode 26.6（17F113）、Apple clang 21.0.0、macOS SDK 26.5、deployment target macOS 11.0に固定する。製品アプリのminimum macOS最終決定はStage 27に維持する。
- arm64 / x86_64を同一のLGPL互換configureで個別buildし、`lipo -create`でuniversal2化する。現仕様でcodecを限定していないため、内蔵audio decoder群は削減しない。
- source SHA-256は`464beb5e7bf0c311e68b45ae2f04e9cc2af88851abb4082231742a74d97b524c`、GnuPGは`2.5.21`、署名鍵fingerprintは`FCF986EA15E6E293A5644F10B4322F04D67658D8`に固定する。
- ad-hoc署名済みuniversal2 binaryのSHA-256は、`ffmpeg`=`b54274779b2d3de25aefc1c7b1df3a7ab65fca3dbdd2ad57cb9ccab109915d67`、`ffprobe`=`a5b19683c2caacd408e57ac3322e56c1dde571bf0c1a565631f9a63bb5d33de2`に固定する。
- `vendor/ffmpeg/8.1.2/source/`の`ffmpeg-8.1.2.tar.xz`と、`vendor/ffmpeg/8.1.2/universal2/bin/`の`ffmpeg`・`ffprobe`だけを完全一致patternでGit LFS管理する。署名、signing key、`SHA256SUMS`、`SOURCE.md`、`LICENSE.md`、`BUILD.md`は通常Git管理する。
- 通常Buildは固定SHA-256・universal2 architecture・実行権限を確認した検証済みbinaryをBundleへ組み込み、source再buildは独立した再現検証工程でのみ行う。
