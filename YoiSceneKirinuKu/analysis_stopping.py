#!/usr/bin/env python3
"""第14段階のcooperative stop共通処理。"""

from __future__ import annotations

import os
import signal
import stat
import subprocess
import time
from pathlib import Path
from typing import Any, Callable

import analysis_job_runner as jobs


POLL_SECONDS = 0.1
TERM_GRACE_SECONDS = 5.0
KILL_WAIT_SECONDS = 5.0


class StopFailure(Exception):
    pass


def requested(current: Path, expected_job_id: str) -> dict[str, Any] | None:
    marker = current / "stop.requested"
    if not marker.exists() and not marker.is_symlink():
        return None
    if marker.is_symlink() or not stat.S_ISREG(marker.lstat().st_mode):
        raise StopFailure("stop_request_invalid")
    try:
        stop = jobs.validate_stop(jobs.read_json(marker, "job_workspace_invalid"))
        job = jobs.validate_job(jobs.read_json(current / "job.json", "job_invalid"))
    except jobs.JobFailure as error:
        raise StopFailure("stop_request_invalid") from error
    if stop["job_id"] != expected_job_id or job["job_id"] != expected_job_id:
        raise StopFailure("stop_request_invalid")
    if job["state"] != "stop_requested":
        return None
    return stop


def complete(workspace: Path, current: Path, stop: dict[str, Any]) -> dict[str, Any]:
    try:
        job = jobs.validate_job(jobs.read_json(current / "job.json", "job_invalid"))
        if job["job_id"] != stop["job_id"] or job["state"] != "stop_requested":
            raise StopFailure("stop_state_invalid")
        job["state_revision"] += 1
        job["state"] = "stopped"
        job["failure_code"] = None
        stored = jobs.replace_job(workspace, job, stop["request_id"])
        marker = current / "stop.requested"
        marker.unlink()
        directory = os.open(current, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
        if marker.exists() or marker.is_symlink():
            raise StopFailure("stop_state_invalid")
        return stored
    except (OSError, jobs.JobFailure) as error:
        raise StopFailure("stop_state_invalid") from error


def run_process(
    arguments: list[str], workspace: Path, current: Path, job_id: str,
    on_event: Callable[[str], None],
) -> tuple[subprocess.CompletedProcess[bytes] | None, dict[str, Any] | None]:
    process = subprocess.Popen(
        arguments, shell=False, stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True,
    )
    group_id = os.getpgid(process.pid)
    stop: dict[str, Any] | None = None
    while process.poll() is None:
        stop = requested(current, job_id)
        if stop is not None:
            on_event("stop_requested_detected")
            try:
                os.killpg(group_id, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                process.wait(timeout=TERM_GRACE_SECONDS)
            except subprocess.TimeoutExpired:
                os.killpg(group_id, signal.SIGKILL)
                process.wait(timeout=KILL_WAIT_SECONDS)
            on_event("child_exit_observed")
            break
        time.sleep(POLL_SECONDS)
    stdout, stderr = process.communicate()
    if stop is None:
        return subprocess.CompletedProcess(arguments, process.returncode, stdout, stderr), None
    deadline = time.monotonic() + KILL_WAIT_SECONDS
    while time.monotonic() < deadline:
        try:
            os.killpg(group_id, 0)
        except ProcessLookupError:
            break
        time.sleep(POLL_SECONDS)
    else:
        raise StopFailure("stop_process_remaining")
    stored = complete(workspace, current, stop)
    on_event("post_stop_state_verified")
    return None, stored
