#!/bin/zsh

set -euo pipefail

readonly expected_ffmpeg_sha256="b54274779b2d3de25aefc1c7b1df3a7ab65fca3dbdd2ad57cb9ccab109915d67"
readonly expected_ffprobe_sha256="a5b19683c2caacd408e57ac3322e56c1dde571bf0c1a565631f9a63bb5d33de2"
readonly vendor_root="${SRCROOT}/vendor/ffmpeg/8.1.2"
readonly manifest_path="${vendor_root}/SHA256SUMS"
readonly ffmpeg_source="${vendor_root}/universal2/bin/ffmpeg"
readonly ffprobe_source="${vendor_root}/universal2/bin/ffprobe"
readonly destination_root="${TARGET_BUILD_DIR}/${EXECUTABLE_FOLDER_PATH}"

function verify_vendor_binary() {
    local source_path="$1"
    local expected_sha256="$2"
    local manifest_entry="$3"

    if [[ ! -f "${source_path}" || -L "${source_path}" || ! -s "${source_path}" ]]; then
        print -u2 "Stage 7 FFmpeg vendor binary is missing or invalid: ${source_path}"
        exit 1
    fi
    if /usr/bin/grep -Fq "version https://git-lfs.github.com/spec/v1" "${source_path}"; then
        print -u2 "Stage 7 FFmpeg Git LFS object is not available: ${source_path}"
        exit 1
    fi
    if [[ ! -x "${source_path}" ]]; then
        print -u2 "Stage 7 FFmpeg vendor binary is not executable: ${source_path}"
        exit 1
    fi
    if [[ "$(/usr/bin/shasum -a 256 "${source_path}" | /usr/bin/awk '{print $1}')" != "${expected_sha256}" ]]; then
        print -u2 "Stage 7 FFmpeg vendor binary SHA-256 mismatch: ${source_path}"
        exit 1
    fi
    if ! /usr/bin/grep -Fqx "${expected_sha256}  ${manifest_entry}" "${manifest_path}"; then
        print -u2 "Stage 7 FFmpeg manifest does not contain the fixed digest: ${manifest_entry}"
        exit 1
    fi
    /usr/bin/lipo "${source_path}" -verify_arch x86_64 arm64
}

if [[ ! -f "${manifest_path}" ]]; then
    print -u2 "Stage 7 FFmpeg SHA256SUMS is missing."
    exit 1
fi

verify_vendor_binary "${ffmpeg_source}" "${expected_ffmpeg_sha256}" "universal2/bin/ffmpeg"
verify_vendor_binary "${ffprobe_source}" "${expected_ffprobe_sha256}" "universal2/bin/ffprobe"

/bin/mkdir -p "${destination_root}"
/usr/bin/install -m 755 "${ffmpeg_source}" "${destination_root}/ffmpeg"
/usr/bin/install -m 755 "${ffprobe_source}" "${destination_root}/ffprobe"
/usr/bin/codesign --force --sign - "${destination_root}/ffmpeg"
/usr/bin/codesign --force --sign - "${destination_root}/ffprobe"
/usr/bin/codesign --verify --strict "${destination_root}/ffmpeg"
/usr/bin/codesign --verify --strict "${destination_root}/ffprobe"

if [[ "$(/usr/bin/shasum -a 256 "${destination_root}/ffmpeg" | /usr/bin/awk '{print $1}')" != "${expected_ffmpeg_sha256}" ]]; then
    print -u2 "Bundled ffmpeg SHA-256 mismatch."
    exit 1
fi
if [[ "$(/usr/bin/shasum -a 256 "${destination_root}/ffprobe" | /usr/bin/awk '{print $1}')" != "${expected_ffprobe_sha256}" ]]; then
    print -u2 "Bundled ffprobe SHA-256 mismatch."
    exit 1
fi
