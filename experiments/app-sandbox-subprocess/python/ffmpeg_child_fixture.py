#!/usr/bin/env python3
"""Sandbox比較用の最小Python → FFmpeg fixture。"""

from __future__ import annotations

import json
import subprocess
import sys


def main() -> int:
    if len(sys.argv) != 2:
        print(json.dumps({"ffmpegStarted": False, "ffmpegExitCode": None, "classification": "invalid_arguments"}))
        return 2

    args = [
        sys.argv[1],
        "-hide_banner",
        "-loglevel",
        "error",
        "-nostdin",
        "-f",
        "lavfi",
        "-i",
        "sine=frequency=1000:sample_rate=16000:duration=0.2",
        "-f",
        "null",
        "-",
    ]
    print("python fixture log", file=sys.stderr, flush=True)
    try:
        completed = subprocess.run(args, shell=False, capture_output=True, check=False, timeout=5)
    except OSError as error:
        print(json.dumps({"ffmpegStarted": False, "ffmpegExitCode": None, "classification": "ffmpeg_launch_failed", "detail": str(error)}))
        return 10
    except subprocess.TimeoutExpired:
        print(json.dumps({"ffmpegStarted": True, "ffmpegExitCode": None, "classification": "ffmpeg_timeout"}))
        return 11

    classification = "ffmpeg_completed" if completed.returncode == 0 else "ffmpeg_nonzero"
    print(json.dumps({"ffmpegStarted": True, "ffmpegExitCode": completed.returncode, "classification": classification}, sort_keys=True))
    return 0 if completed.returncode == 0 else 12


if __name__ == "__main__":
    raise SystemExit(main())
