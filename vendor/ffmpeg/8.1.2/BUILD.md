# FFmpeg 8.1.2 universal2 build record

## Fixed toolchain

- Xcode 26.6 (17F113)
- Apple clang 21.0.0
- macOS SDK 26.5
- Deployment target: macOS 11.0

## Configure

Both architectures used the following common options:

```text
--target-os=darwin
--cc=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang
--host-cc=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang
--host-cflags=--sysroot=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.5.sdk
--host-ldflags=--sysroot=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.5.sdk
--sysroot=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.5.sdk
--disable-autodetect
--disable-network
--disable-doc
--disable-debug
--disable-ffplay
--disable-shared
--enable-static
--disable-programs
--enable-ffmpeg
--enable-ffprobe
--disable-encoders
--enable-encoder=pcm_s16le
--disable-muxers
--enable-muxer=wav
--disable-indevs
--disable-outdevs
--disable-gpl
--disable-nonfree
--disable-x86asm
```

The arm64 build added `--arch=arm64`, `--extra-cflags=-arch arm64 -mmacosx-version-min=11.0`, and `--extra-ldflags=-arch arm64 -mmacosx-version-min=11.0`.

The x86_64 build added `--arch=x86_64`, `--enable-cross-compile`, `--extra-cflags=-arch x86_64 -mmacosx-version-min=11.0`, and `--extra-ldflags=-arch x86_64 -mmacosx-version-min=11.0`.

Built-in audio decoders were retained because the product input codec is not restricted. No third-party libraries were added.

## Universal binary and signing

The arm64 and x86_64 `ffmpeg` outputs were combined with `lipo -create`; the same operation was performed for `ffprobe`. Each resulting inner Mach-O executable was ad-hoc signed before the outer application signing step. The signed universal2 hashes are fixed in `SHA256SUMS`.

Normal Xcode builds consume the verified universal2 binaries and do not rebuild FFmpeg. Source rebuilding is reserved for an independent reproducibility verification script.
