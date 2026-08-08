#!/usr/bin/env python3
"""人工ジョブによる多重起動・二重解析防止候補の比較実験。"""

from __future__ import annotations

import argparse
import fcntl
import json
import os
import subprocess
import sys
import time
import uuid
from pathlib import Path


ROOT = Path(__file__).resolve().parent
ARTIFACTS = ROOT / "artifacts"
CONTENDERS = 6
HOLD_SECONDS = 0.30
DEADLINE_SECONDS = 5.0
METHODS = ("exclusive_file", "exclusive_directory", "flock", "flock_metadata")


def ensure_inside(path: Path) -> None:
    resolved = path.resolve(strict=False)
    root = ARTIFACTS.resolve(strict=False)
    if resolved != root and root not in resolved.parents:
        raise RuntimeError(f"path escaped experiment root: {resolved}")


def emit(value: dict[str, object]) -> None:
    print(json.dumps(value, ensure_ascii=False, sort_keys=True), flush=True)


def owner_payload(token: str) -> bytes:
    return (json.dumps({"job_id": "artificial-job", "pid": os.getpid(), "owner_token": token, "created_ns": time.time_ns()}, sort_keys=True) + "\n").encode()


def worker(method: str, lock_path: Path, barrier: Path, ready: Path, crash: bool) -> int:
    for path in (lock_path, barrier, ready):
        ensure_inside(path)
    deadline = time.monotonic() + DEADLINE_SECONDS
    waiting = ready.with_suffix(ready.suffix + ".waiting")
    ensure_inside(waiting)
    waiting.touch()
    while not barrier.exists():
        if time.monotonic() >= deadline:
            emit({"status": "timeout_waiting_barrier", "processing_started": False})
            return 30
        time.sleep(0.005)

    token = uuid.uuid4().hex
    started = time.perf_counter_ns()
    file_handle = None
    owner_path = lock_path / "owner.json" if method == "exclusive_directory" else lock_path.with_suffix(lock_path.suffix + ".owner.json")
    acquired = False
    try:
        if method == "exclusive_file":
            try:
                descriptor = os.open(lock_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            except FileExistsError:
                emit({"status": "rejected", "processing_started": False, "elapsed_ns": time.perf_counter_ns() - started})
                return 0
            file_handle = os.fdopen(descriptor, "wb")
            file_handle.write(owner_payload(token))
            file_handle.flush()
            acquired = True
        elif method == "exclusive_directory":
            try:
                lock_path.mkdir()
            except FileExistsError:
                emit({"status": "rejected", "processing_started": False, "elapsed_ns": time.perf_counter_ns() - started})
                return 0
            owner_path.write_bytes(owner_payload(token))
            acquired = True
        elif method in {"flock", "flock_metadata"}:
            file_handle = lock_path.open("a+b")
            try:
                fcntl.flock(file_handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                file_handle.close()
                emit({"status": "rejected", "processing_started": False, "elapsed_ns": time.perf_counter_ns() - started})
                return 0
            if method == "flock_metadata":
                if owner_path.exists():
                    try:
                        json.loads(owner_path.read_text(encoding="utf-8"))
                    except (json.JSONDecodeError, OSError):
                        fcntl.flock(file_handle.fileno(), fcntl.LOCK_UN)
                        file_handle.close()
                        emit({"status": "metadata_invalid", "processing_started": False, "elapsed_ns": time.perf_counter_ns() - started})
                        return 0
                owner_path.write_bytes(owner_payload(token))
            acquired = True
        else:
            raise ValueError(method)

        ready.write_text(token, encoding="utf-8")
        acquired_ns = time.perf_counter_ns() - started
        if crash:
            os._exit(42)
        time.sleep(HOLD_SECONDS)
        emit({"status": "acquired", "processing_started": True, "elapsed_ns": acquired_ns})
        return 0
    finally:
        if acquired and not crash:
            if method == "exclusive_file":
                assert file_handle is not None
                file_handle.close()
                if lock_path.read_text(encoding="utf-8").find(token) >= 0:
                    lock_path.unlink()
            elif method == "exclusive_directory":
                if owner_path.read_text(encoding="utf-8").find(token) >= 0:
                    owner_path.unlink()
                    lock_path.rmdir()
            else:
                if method == "flock_metadata" and owner_path.exists() and owner_path.read_text(encoding="utf-8").find(token) >= 0:
                    owner_path.unlink()
                assert file_handle is not None
                fcntl.flock(file_handle.fileno(), fcntl.LOCK_UN)
                file_handle.close()


def run_worker(method: str, lock_path: Path, barrier: Path, ready: Path, crash: bool = False) -> subprocess.Popen[str]:
    args = [sys.executable, str(Path(__file__).resolve()), "--worker", method, str(lock_path), str(barrier), str(ready)]
    if crash:
        args.append("--crash")
    return subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, shell=False)


def parse_result(process: subprocess.Popen[str]) -> dict[str, object]:
    stdout, stderr = process.communicate(timeout=DEADLINE_SECONDS)
    if stderr:
        raise RuntimeError(f"worker stderr was not empty: {stderr}")
    lines = stdout.splitlines()
    if len(lines) != 1:
        raise RuntimeError(f"worker emitted unexpected stdout: {stdout!r}")
    value = json.loads(lines[0])
    value["return_code"] = process.returncode
    return value


def wait_for_paths(paths: list[Path], processes: list[subprocess.Popen[str]]) -> None:
    deadline = time.monotonic() + DEADLINE_SECONDS
    while not all(path.exists() for path in paths):
        failed = [process.returncode for process in processes if process.poll() is not None]
        if failed:
            raise RuntimeError(f"worker exited before barrier: {failed}")
        if time.monotonic() >= deadline:
            for process in processes:
                if process.poll() is None:
                    process.terminate()
            raise RuntimeError("workers did not become ready before deadline")
        time.sleep(0.005)


def single_and_contention(run_root: Path, method: str) -> dict[str, object]:
    method_root = run_root / method
    method_root.mkdir()
    lock_path = method_root / ("lockdir" if method == "exclusive_directory" else "job.lock")

    single_barrier = method_root / "single.barrier"
    single_ready = method_root / "single.ready"
    single = run_worker(method, lock_path, single_barrier, single_ready)
    wait_for_paths([single_ready.with_suffix(".ready.waiting")], [single])
    single_barrier.touch()
    single_result = parse_result(single)
    if single_result["status"] != "acquired":
        raise RuntimeError(f"single acquire failed for {method}: {single_result}")

    barrier = method_root / "contention.barrier"
    contender_ready = [method_root / f"contender-{index}.ready" for index in range(CONTENDERS)]
    workers = [run_worker(method, lock_path, barrier, ready) for ready in contender_ready]
    wait_for_paths([path.with_suffix(".ready.waiting") for path in contender_ready], workers)
    barrier.touch()
    contention = [parse_result(process) for process in workers]
    acquired = [value for value in contention if value["status"] == "acquired"]
    rejected = [value for value in contention if value["status"] == "rejected"]
    if len(acquired) != 1 or len(rejected) != CONTENDERS - 1:
        raise RuntimeError(f"contention invariant failed for {method}: {contention}")

    return {
        "single": single_result,
        "contention": {
            "contenders": CONTENDERS,
            "acquired": len(acquired),
            "rejected": len(rejected),
            "processing_started": sum(bool(value["processing_started"]) for value in contention),
            "acquire_elapsed_ns": acquired[0]["elapsed_ns"],
            "reject_elapsed_ns": [value["elapsed_ns"] for value in rejected],
        },
        "lock_path": str(lock_path),
    }


def crash_and_recovery(run_root: Path, method: str) -> dict[str, object]:
    method_root = run_root / method
    lock_path = Path(single_and_contention_results[method]["lock_path"])
    barrier = method_root / "crash.barrier"
    ready = method_root / "crash.ready"
    process = run_worker(method, lock_path, barrier, ready, crash=True)
    wait_for_paths([ready.with_suffix(".ready.waiting")], [process])
    barrier.touch()
    deadline = time.monotonic() + DEADLINE_SECONDS
    while not ready.exists() and process.poll() is None:
        if time.monotonic() >= deadline:
            process.terminate()
            raise RuntimeError(f"crash worker readiness timeout for {method}")
        time.sleep(0.005)
    return_code = process.wait(timeout=DEADLINE_SECONDS)
    if return_code != 42:
        raise RuntimeError(f"crash worker did not exit as planned for {method}: {return_code}")

    probe_barrier = method_root / "post-crash.barrier"
    probe_ready = method_root / "post-crash.ready"
    probe = run_worker(method, lock_path, probe_barrier, probe_ready)
    wait_for_paths([probe_ready.with_suffix(".ready.waiting")], [probe])
    probe_barrier.touch()
    post_crash = parse_result(probe)
    stale_artifact_remained = lock_path.exists()

    explicit_recovery = "not_needed"
    recovered = post_crash["status"] == "acquired"
    if method == "exclusive_file":
        if post_crash["status"] != "rejected":
            raise RuntimeError("exclusive file unexpectedly recovered without stale handling")
        lock_path.unlink()
        explicit_recovery = "removed_known_stale_lock_after_owner_exit_confirmed"
    elif method == "exclusive_directory":
        if post_crash["status"] != "rejected":
            raise RuntimeError("exclusive directory unexpectedly recovered without stale handling")
        owner_path = lock_path / "owner.json"
        owner_path.unlink()
        lock_path.rmdir()
        explicit_recovery = "removed_known_stale_owner_and_directory_after_owner_exit_confirmed"

    if not recovered:
        recovery_barrier = method_root / "recovery.barrier"
        recovery_ready = method_root / "recovery.ready"
        recovery = run_worker(method, lock_path, recovery_barrier, recovery_ready)
        wait_for_paths([recovery_ready.with_suffix(".ready.waiting")], [recovery])
        recovery_barrier.touch()
        recovery_result = parse_result(recovery)
        recovered = recovery_result["status"] == "acquired"
    else:
        recovery_result = post_crash
    if not recovered:
        raise RuntimeError(f"recovery failed for {method}: {recovery_result}")

    return {
        "crash_return_code": return_code,
        "post_crash_first_attempt": post_crash,
        "stale_artifact_remained": stale_artifact_remained,
        "explicit_recovery": explicit_recovery,
        "recovery_result": recovery_result,
        "child_process_remaining": process.poll() is None,
    }


def metadata_and_folder_checks(run_root: Path) -> dict[str, object]:
    folder = run_root / "current_job_only"
    folder.mkdir()
    folder_only_means_running = False

    method_root = run_root / "flock_metadata"
    lock_path = Path(single_and_contention_results["flock_metadata"]["lock_path"])
    owner_path = lock_path.with_suffix(lock_path.suffix + ".owner.json")
    owner_path.write_text("{broken json", encoding="utf-8")
    barrier = method_root / "malformed.barrier"
    ready = method_root / "malformed.ready"
    malformed_process = run_worker("flock_metadata", lock_path, barrier, ready)
    wait_for_paths([ready.with_suffix(".ready.waiting")], [malformed_process])
    barrier.touch()
    malformed = parse_result(malformed_process)
    if malformed["status"] != "metadata_invalid" or malformed["processing_started"]:
        raise RuntimeError(f"malformed metadata was not fail-closed: {malformed}")
    return {"current_job_folder_only_means_running": folder_only_means_running, "malformed_metadata": malformed}


def orchestrate() -> int:
    ARTIFACTS.mkdir(exist_ok=True)
    run_root = ARTIFACTS / f"run-{time.time_ns()}"
    ensure_inside(run_root)
    run_root.mkdir()

    global single_and_contention_results
    single_and_contention_results = {method: single_and_contention(run_root, method) for method in METHODS}
    crash_results = {method: crash_and_recovery(run_root, method) for method in METHODS}
    additional = metadata_and_folder_checks(run_root)

    report = {
        "status": "PASS",
        "conditions": {"contenders": CONTENDERS, "hold_seconds": HOLD_SECONDS, "deadline_seconds": DEADLINE_SECONDS},
        "single_and_contention": single_and_contention_results,
        "crash_and_recovery": crash_results,
        "additional_checks": additional,
        "limitations": [
            "local project filesystem only",
            "timing and process counts are experiment values",
            "stale policy and production lock ownership are not decided",
        ],
    }
    report_path = run_root / "report.json"
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    emit({"status": "PASS", "report": str(report_path)})
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--worker", action="store_true")
    parser.add_argument("method", nargs="?")
    parser.add_argument("lock_path", nargs="?", type=Path)
    parser.add_argument("barrier", nargs="?", type=Path)
    parser.add_argument("ready", nargs="?", type=Path)
    parser.add_argument("--crash", action="store_true")
    return parser.parse_args()


if __name__ == "__main__":
    arguments = parse_args()
    if arguments.worker:
        if arguments.method not in METHODS or None in (arguments.lock_path, arguments.barrier, arguments.ready):
            raise SystemExit(2)
        raise SystemExit(worker(arguments.method, arguments.lock_path, arguments.barrier, arguments.ready, arguments.crash))
    raise SystemExit(orchestrate())
