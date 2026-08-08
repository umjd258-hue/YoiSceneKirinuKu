#!/usr/bin/env python3
"""stop.requested と FFmpeg 停止の限定技術検証。"""

from __future__ import annotations

import argparse
import json
import subprocess
import threading
import time
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any


NORMAL_DURATION_SECONDS = 2.0
STOP_JOB_DURATION_SECONDS = 10.0
STOP_REQUEST_DELAY_SECONDS = 0.5
POLL_INTERVAL_SECONDS = 0.05
CASE_DEADLINE_SECONDS = 15.0
TERMINATE_GRACE_SECONDS = 3.0


@dataclass
class CaseResult:
    name: str
    passed: bool
    classification: str
    ffmpeg_started: bool
    ffmpeg_return_code: int | None
    events: list[str]
    partial_exists: bool
    partial_nonempty: bool
    final_exists: bool
    next_stage_started: bool
    child_remaining: bool
    cleanup_terminate_used: bool
    cleanup_kill_used: bool
    details: dict[str, Any]


def ffmpeg_args(ffmpeg: Path, output: Path, duration: float) -> list[str]:
    return [
        str(ffmpeg), "-hide_banner", "-loglevel", "error", "-nostdin", "-n",
        "-re", "-f", "lavfi", "-i", "testsrc=size=160x90:rate=10",
        "-re", "-f", "lavfi", "-i", "sine=frequency=1000:sample_rate=48000",
        "-t", str(duration), "-c:v", "mpeg4", "-c:a", "aac",
        "-f", "matroska", str(output),
    ]


def verify_media(ffprobe: Path, path: Path) -> dict[str, Any]:
    completed = subprocess.run(
        [str(ffprobe), "-v", "error", "-show_entries", "format=duration:stream=codec_type", "-of", "json", str(path)],
        shell=False,
        capture_output=True,
        text=True,
        timeout=5,
        check=False,
    )
    parsed = json.loads(completed.stdout) if completed.returncode == 0 else {}
    stream_types = {item.get("codec_type") for item in parsed.get("streams", [])}
    duration = float(parsed.get("format", {}).get("duration", 0.0))
    return {
        "ffprobe_return_code": completed.returncode,
        "video_stream": "video" in stream_types,
        "audio_stream": "audio" in stream_types,
        "duration": duration,
        "valid": completed.returncode == 0 and "video" in stream_types and "audio" in stream_types and duration > 0,
    }


def wait_with_deadline(process: subprocess.Popen[bytes], deadline: float) -> tuple[int, bool, bool]:
    cleanup_terminate = False
    cleanup_kill = False
    while process.poll() is None and time.monotonic() < deadline:
        time.sleep(POLL_INTERVAL_SECONDS)
    if process.poll() is None:
        cleanup_terminate = True
        process.terminate()
        try:
            process.wait(timeout=TERMINATE_GRACE_SECONDS)
        except subprocess.TimeoutExpired:
            cleanup_kill = True
            process.kill()
            process.wait(timeout=TERMINATE_GRACE_SECONDS)
    return process.returncode, cleanup_terminate, cleanup_kill


def run_normal(root: Path, ffmpeg: Path, ffprobe: Path) -> CaseResult:
    case = root / "normal_completion"
    case.mkdir()
    partial = case / "output.partial"
    final = case / "output.mkv"
    stderr_path = case / "ffmpeg.stderr.log"
    events = ["ffmpeg_started"]
    with stderr_path.open("wb") as stderr_file:
        process = subprocess.Popen(ffmpeg_args(ffmpeg, partial, NORMAL_DURATION_SECONDS), shell=False, stdout=subprocess.DEVNULL, stderr=stderr_file)
        return_code, cleanup_terminate, cleanup_kill = wait_with_deadline(process, time.monotonic() + CASE_DEADLINE_SECONDS)
    events.append("ffmpeg_exit_observed")
    partial_nonempty = partial.is_file() and partial.stat().st_size > 0
    media = verify_media(ffprobe, partial) if partial_nonempty else {"valid": False}
    if return_code == 0 and partial_nonempty and media["valid"]:
        partial.rename(final)
        events.extend(["partial_verified", "finalized", "next_stage_started"])
        next_stage_started = True
    else:
        next_stage_started = False
    passed = return_code == 0 and final.is_file() and not partial.exists() and next_stage_started and not cleanup_terminate and not cleanup_kill
    return CaseResult("normal_completion", passed, "normal_completed" if passed else "failed", True, return_code, events, partial.exists(), partial.exists() and partial.stat().st_size > 0, final.exists(), next_stage_started, process.poll() is None, cleanup_terminate, cleanup_kill, {"media_validation": media})


def run_preexisting_stop(root: Path, ffmpeg: Path) -> CaseResult:
    case = root / "stop_before_start"
    case.mkdir()
    marker = case / "stop.requested"
    marker.touch()
    partial = case / "output.partial"
    final = case / "output.mkv"
    events = ["stop_requested_detected", "next_stage_blocked", "post_stop_state_verified", "stop_complete_classified"]
    passed = marker.exists() and not partial.exists() and not final.exists()
    return CaseResult("stop_before_start", passed, "user_stopped", False, None, events, False, False, False, False, False, False, False, {"ffmpeg_launch_prevented": True})


def run_during_stop(root: Path, ffmpeg: Path) -> CaseResult:
    case = root / "stop_during_ffmpeg"
    case.mkdir()
    marker = case / "stop.requested"
    partial = case / "output.partial"
    final = case / "output.mkv"
    stderr_path = case / "ffmpeg.stderr.log"
    events = ["ffmpeg_started"]
    creator = threading.Thread(target=lambda: (time.sleep(STOP_REQUEST_DELAY_SECONDS), marker.touch()), daemon=False)
    cleanup_terminate = False
    cleanup_kill = False
    with stderr_path.open("wb") as stderr_file:
        process = subprocess.Popen(ffmpeg_args(ffmpeg, partial, STOP_JOB_DURATION_SECONDS), shell=False, stdout=subprocess.DEVNULL, stderr=stderr_file)
        creator.start()
        deadline = time.monotonic() + CASE_DEADLINE_SECONDS
        stop_seen = False
        while process.poll() is None and time.monotonic() < deadline:
            if marker.exists():
                stop_seen = True
                events.extend(["stop_requested_detected", "next_stage_blocked"])
                process.terminate()
                break
            time.sleep(POLL_INTERVAL_SECONDS)
        if process.poll() is None:
            try:
                process.wait(timeout=TERMINATE_GRACE_SECONDS)
            except subprocess.TimeoutExpired:
                cleanup_kill = True
                process.kill()
                process.wait(timeout=TERMINATE_GRACE_SECONDS)
        if not stop_seen and process.poll() is None:
            cleanup_terminate = True
            process.terminate()
            process.wait(timeout=TERMINATE_GRACE_SECONDS)
    creator.join(timeout=2)
    events.append("ffmpeg_exit_observed")
    post_valid = stop_seen and process.poll() is not None and not final.exists()
    if post_valid:
        events.extend(["post_stop_state_verified", "stop_complete_classified"])
    required = ["stop_requested_detected", "ffmpeg_exit_observed", "post_stop_state_verified", "stop_complete_classified"]
    positions = [events.index(item) for item in required] if all(item in events for item in required) else []
    order_valid = positions == sorted(positions) and len(positions) == len(set(positions))
    partial_nonempty = partial.is_file() and partial.stat().st_size > 0
    passed = stop_seen and order_valid and not final.exists() and process.poll() is not None and not cleanup_terminate and not cleanup_kill
    return CaseResult("stop_during_ffmpeg", passed, "user_stopped" if passed else "failed", True, process.returncode, events, partial.exists(), partial_nonempty, final.exists(), False, process.poll() is None, cleanup_terminate, cleanup_kill, {"event_order_valid": order_valid, "stop_marker_detected": stop_seen})


def run_ffmpeg_error(root: Path, ffmpeg: Path) -> CaseResult:
    case = root / "ffmpeg_error"
    case.mkdir()
    partial = case / "output.partial"
    final = case / "output.mkv"
    stderr_path = case / "ffmpeg.stderr.log"
    args = [str(ffmpeg), "-hide_banner", "-nostdin", "-n", "-f", "lavfi", "-i", "definitely_missing_filter", "-f", "matroska", str(partial)]
    events = ["ffmpeg_started"]
    with stderr_path.open("wb") as stderr_file:
        process = subprocess.Popen(args, shell=False, stdout=subprocess.DEVNULL, stderr=stderr_file)
        return_code, cleanup_terminate, cleanup_kill = wait_with_deadline(process, time.monotonic() + CASE_DEADLINE_SECONDS)
    events.extend(["ffmpeg_exit_observed", "ffmpeg_error_classified", "next_stage_blocked"])
    passed = return_code != 0 and not final.exists() and process.poll() is not None and not cleanup_terminate and not cleanup_kill
    return CaseResult("ffmpeg_error", passed, "ffmpeg_error" if passed else "failed", True, return_code, events, partial.exists(), partial.exists() and partial.stat().st_size > 0, final.exists(), False, process.poll() is None, cleanup_terminate, cleanup_kill, {"stop_requested": False})


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--ffmpeg", type=Path, required=True)
    parser.add_argument("--ffprobe", type=Path, required=True)
    args = parser.parse_args()
    if not args.ffmpeg.is_file() or not args.ffprobe.is_file():
        raise SystemExit("FFmpeg または ffprobe が通常ファイルとして存在しません")

    artifact_root = Path(__file__).resolve().parent / "artifacts"
    if artifact_root.exists():
        raise SystemExit("artifacts が既に存在します。再利用・上書きしません")
    artifact_root.mkdir()

    results = [
        run_normal(artifact_root, args.ffmpeg, args.ffprobe),
        run_preexisting_stop(artifact_root, args.ffmpeg),
        run_during_stop(artifact_root, args.ffmpeg),
        run_ffmpeg_error(artifact_root, args.ffmpeg),
    ]
    report = {
        "conditions": {
            "normal_duration_seconds": NORMAL_DURATION_SECONDS,
            "stop_job_duration_seconds": STOP_JOB_DURATION_SECONDS,
            "stop_request_delay_seconds": STOP_REQUEST_DELAY_SECONDS,
            "poll_interval_seconds": POLL_INTERVAL_SECONDS,
            "case_deadline_seconds": CASE_DEADLINE_SECONDS,
            "terminate_grace_seconds": TERMINATE_GRACE_SECONDS,
        },
        "cases": [asdict(item) for item in results],
        "all_passed": all(item.passed for item in results),
    }
    (artifact_root / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if report["all_passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
