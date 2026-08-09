#!/usr/bin/env python3
"""第14開始Gate用の限定的なprocess group停止検証。"""

from __future__ import annotations

import argparse
import json
import os
import signal
import subprocess
import sys
import time
from pathlib import Path
from typing import Any


TRIALS = 3
POLL_SECONDS = 0.05
STARTUP_DEADLINE_SECONDS = 3.0
TERM_GRACE_SECONDS = 5.0
CASE_DEADLINE_SECONDS = 10.0


def wait_until(predicate: object, deadline: float) -> bool:
    callback = predicate
    while time.monotonic() < deadline:
        if callback():  # type: ignore[operator]
            return True
        time.sleep(POLL_SECONDS)
    return bool(callback())  # type: ignore[operator]


def pid_exists(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def fixture_child(pid_path: Path) -> int:
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    pid_path.write_text(f"{os.getpid()}\n", encoding="utf-8")
    while True:
        time.sleep(1)


def fixture_parent(parent_pid_path: Path, child_pid_path: Path) -> int:
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    child = subprocess.Popen(
        [sys.executable, str(Path(__file__).resolve()), "--fixture-child", str(child_pid_path)],
        shell=False,
    )
    parent_pid_path.write_text(f"{os.getpid()}\n", encoding="utf-8")
    return child.wait()


def ffmpeg_args(ffmpeg: Path, output: Path) -> list[str]:
    return [
        str(ffmpeg), "-hide_banner", "-loglevel", "error", "-nostdin", "-n",
        "-re", "-f", "lavfi", "-i", "sine=frequency=1000:sample_rate=16000",
        "-t", "30", "-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le",
        "-f", "wav", str(output),
    ]


def graceful_ffmpeg_trial(root: Path, ffmpeg: Path, trial: int) -> dict[str, Any]:
    case = root / f"graceful_{trial}"
    case.mkdir()
    partial = case / "analysis.wav.partial"
    with (case / "stderr.log").open("wb") as stderr_file:
        process = subprocess.Popen(
            ffmpeg_args(ffmpeg, partial),
            shell=False,
            stdout=subprocess.DEVNULL,
            stderr=stderr_file,
            start_new_session=True,
        )
        group_id = os.getpgid(process.pid)
        time.sleep(0.4)
        os.killpg(group_id, signal.SIGTERM)
        forced = False
        try:
            return_code = process.wait(timeout=TERM_GRACE_SECONDS)
        except subprocess.TimeoutExpired:
            forced = True
            os.killpg(group_id, signal.SIGKILL)
            return_code = process.wait(timeout=CASE_DEADLINE_SECONDS)
    group_gone = wait_until(lambda: not pid_exists(process.pid), time.monotonic() + 1.0)
    passed = return_code != 0 and not forced and group_gone
    return {
        "trial": trial,
        "passed": passed,
        "return_code": return_code,
        "forced_kill_used": forced,
        "process_remaining": not group_gone,
        "partial_exists": partial.exists(),
        "formal_output_exists": False,
    }


def forced_group_trial(root: Path, trial: int) -> dict[str, Any]:
    case = root / f"forced_{trial}"
    case.mkdir()
    parent_pid_path = case / "parent.pid"
    child_pid_path = case / "child.pid"
    process = subprocess.Popen(
        [
            sys.executable,
            str(Path(__file__).resolve()),
            "--fixture-parent",
            str(parent_pid_path),
            str(child_pid_path),
        ],
        shell=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    ready = wait_until(
        lambda: parent_pid_path.is_file() and child_pid_path.is_file(),
        time.monotonic() + STARTUP_DEADLINE_SECONDS,
    )
    if not ready:
        os.killpg(os.getpgid(process.pid), signal.SIGKILL)
        process.wait(timeout=CASE_DEADLINE_SECONDS)
        return {"trial": trial, "passed": False, "reason": "fixture_not_ready"}

    parent_pid = int(parent_pid_path.read_text(encoding="utf-8").strip())
    child_pid = int(child_pid_path.read_text(encoding="utf-8").strip())
    group_id = os.getpgid(process.pid)
    os.killpg(group_id, signal.SIGTERM)
    time.sleep(TERM_GRACE_SECONDS)
    term_ignored = process.poll() is None and pid_exists(child_pid)
    os.killpg(group_id, signal.SIGKILL)
    return_code = process.wait(timeout=CASE_DEADLINE_SECONDS)
    parent_gone = wait_until(lambda: not pid_exists(parent_pid), time.monotonic() + 2.0)
    child_gone = wait_until(lambda: not pid_exists(child_pid), time.monotonic() + 2.0)
    passed = term_ignored and return_code != 0 and parent_gone and child_gone
    return {
        "trial": trial,
        "passed": passed,
        "return_code": return_code,
        "term_ignored": term_ignored,
        "sigkill_used": True,
        "parent_remaining": not parent_gone,
        "child_remaining": not child_gone,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--ffmpeg", type=Path)
    parser.add_argument("--fixture-parent", nargs=2, type=Path)
    parser.add_argument("--fixture-child", type=Path)
    args = parser.parse_args()

    if args.fixture_child:
        return fixture_child(args.fixture_child)
    if args.fixture_parent:
        return fixture_parent(args.fixture_parent[0], args.fixture_parent[1])
    if args.ffmpeg is None or not args.ffmpeg.is_file():
        raise SystemExit("FFmpegが実行可能ファイルとして確認できません")

    root_name = os.environ.get("STOP_EXPERIMENT_ARTIFACT_ROOT", "process-group-artifacts")
    if root_name not in {"process-group-artifacts", "process-group-artifacts-rerun"}:
        raise SystemExit("許可されていない実験成果物ルートです")
    root = Path(__file__).resolve().parent / root_name
    if root.exists():
        raise SystemExit("process-group-artifactsが既に存在します。再利用・上書きしません")
    root.mkdir()
    graceful = [graceful_ffmpeg_trial(root, args.ffmpeg, trial) for trial in range(1, TRIALS + 1)]
    forced = [forced_group_trial(root, trial) for trial in range(1, TRIALS + 1)]
    report = {
        "conditions": {
            "trials": TRIALS,
            "poll_seconds": POLL_SECONDS,
            "startup_deadline_seconds": STARTUP_DEADLINE_SECONDS,
            "term_grace_seconds": TERM_GRACE_SECONDS,
            "case_deadline_seconds": CASE_DEADLINE_SECONDS,
        },
        "graceful_ffmpeg": graceful,
        "forced_process_group": forced,
        "all_passed": all(item["passed"] for item in graceful + forced),
    }
    (root / "report.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if report["all_passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
