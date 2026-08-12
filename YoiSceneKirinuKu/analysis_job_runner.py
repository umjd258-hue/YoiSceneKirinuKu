#!/usr/bin/env python3
from __future__ import annotations

import fcntl
import ctypes
import hashlib
import json
import os
import re
import stat
import sys
import uuid
from pathlib import Path
from typing import Any


JOB_STATES = {
    "start_requested", "preparing", "running", "stop_requested",
    "stopped", "completed", "failed", "recovery_required",
}
ACTIVE_STATES = {"start_requested", "preparing", "running", "stop_requested"}
CHARACTER_ID = re.compile(r"char_[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\Z")
HEX_DIGEST = re.compile(r"[0-9a-f]{64}\Z")


class JobFailure(Exception):
    def __init__(self, code: str) -> None:
        super().__init__(code)
        self.code = code


class Emitter:
    def __init__(self, request_id: str) -> None:
        self.request_id = request_id
        self.sequence = 0

    def emit(self, event_type: str, payload: dict[str, Any]) -> None:
        self.sequence += 1
        value = {
            "protocol_version": 1,
            "type": event_type,
            "request_id": self.request_id,
            "sequence": self.sequence,
            "payload": payload,
        }
        sys.stdout.write(json.dumps(value, ensure_ascii=False, separators=(",", ":")) + "\n")
        sys.stdout.flush()


def exact(value: dict[str, Any], keys: set[str], code: str = "job_invalid") -> None:
    if set(value) != keys:
        raise JobFailure(code)


def canonical_uuid(value: Any, code: str = "job_invalid") -> str:
    if not isinstance(value, str):
        raise JobFailure(code)
    try:
        parsed = uuid.UUID(value)
    except ValueError as error:
        raise JobFailure(code) from error
    if str(parsed) != value or parsed.version != 4:
        raise JobFailure(code)
    return value


def validate_parent_chain(path: Path) -> None:
    current = Path(path.anchor)
    for part in path.parts[1:]:
        current /= part
        if current.exists() and current.is_symlink():
            raise JobFailure("job_workspace_invalid")


def prepare_workspace(raw: Any) -> Path:
    if not isinstance(raw, str) or not raw.startswith("/"):
        raise JobFailure("job_workspace_invalid")
    workspace = Path(raw)
    validate_parent_chain(workspace)
    workspace.mkdir(parents=True, exist_ok=True)
    if not workspace.is_dir() or workspace.is_symlink():
        raise JobFailure("job_workspace_invalid")
    partial = workspace / ".partial"
    partial.mkdir(exist_ok=True)
    if not partial.is_dir() or partial.is_symlink():
        raise JobFailure("job_workspace_invalid")
    return workspace


def validate_fingerprint(value: Any) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise JobFailure("job_invalid")
    exact(value, {"version", "algorithm", "byte_count", "digest"})
    count = value["byte_count"]
    if value["version"] != 1 or value["algorithm"] != "sha256":
        raise JobFailure("job_invalid")
    if not isinstance(count, int) or isinstance(count, bool) or count < 0:
        raise JobFailure("job_invalid")
    if not isinstance(value["digest"], str) or HEX_DIGEST.fullmatch(value["digest"]) is None:
        raise JobFailure("job_invalid")
    return value


def validate_job(value: Any) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise JobFailure("job_invalid")
    exact(value, {
        "schema_version", "job_id", "start_request_id", "state_revision", "state",
        "source", "selected_character_ids", "failure_code",
    })
    if value["schema_version"] != 1:
        raise JobFailure("job_invalid")
    canonical_uuid(value["job_id"])
    canonical_uuid(value["start_request_id"])
    revision = value["state_revision"]
    if not isinstance(revision, int) or isinstance(revision, bool) or revision < 0:
        raise JobFailure("job_invalid")
    state_value = value["state"]
    if state_value not in JOB_STATES:
        raise JobFailure("job_invalid")
    failure_code = value["failure_code"]
    if (state_value == "failed") != isinstance(failure_code, str):
        raise JobFailure("job_invalid")
    if isinstance(failure_code, str) and (not failure_code or len(failure_code) > 100):
        raise JobFailure("job_invalid")
    source = value["source"]
    if not isinstance(source, dict):
        raise JobFailure("job_invalid")
    exact(source, {"path", "fingerprint"})
    if not isinstance(source["path"], str) or not source["path"].startswith("/"):
        raise JobFailure("job_invalid")
    validate_fingerprint(source["fingerprint"])
    characters = value["selected_character_ids"]
    if not isinstance(characters, list) or not characters or len(characters) != len(set(characters)):
        raise JobFailure("job_invalid")
    if any(not isinstance(item, str) or CHARACTER_ID.fullmatch(item) is None for item in characters):
        raise JobFailure("job_invalid")
    return value


def source_fingerprint(path: Path) -> dict[str, Any]:
    try:
        before = path.lstat()
        if not stat.S_ISREG(before.st_mode) or path.is_symlink():
            raise JobFailure("source_unavailable")
        digest = hashlib.sha256()
        byte_count = 0
        with path.open("rb") as source:
            while chunk := source.read(1024 * 1024):
                digest.update(chunk)
                byte_count += len(chunk)
        after = path.lstat()
    except JobFailure:
        raise
    except OSError as error:
        raise JobFailure("source_unavailable") from error
    identity_before = (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns)
    identity_after = (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns)
    if identity_before != identity_after or byte_count != after.st_size:
        raise JobFailure("source_changed")
    return {"version": 1, "algorithm": "sha256", "byte_count": byte_count, "digest": digest.hexdigest()}


def read_json(path: Path, code: str) -> dict[str, Any]:
    try:
        metadata = path.lstat()
        if not stat.S_ISREG(metadata.st_mode) or path.is_symlink() or metadata.st_size <= 0:
            raise JobFailure(code)
        value = json.loads(path.read_text(encoding="utf-8"))
    except JobFailure:
        raise
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise JobFailure(code) from error
    if not isinstance(value, dict):
        raise JobFailure(code)
    return value


JOB_DIRECTORY_ITEMS = {
    "job.json", "stop.requested", "analysis.wav", "analysis_audio.json",
    "vad.json", "speaker_candidates.json", "speaker_matches.json",
}


def validate_job_directory(directory: Path) -> dict[str, Any]:
    if not directory.is_dir() or directory.is_symlink():
        raise JobFailure("job_workspace_invalid")
    items = {item.name for item in directory.iterdir()}
    if "job.json" not in items or not items.issubset(JOB_DIRECTORY_ITEMS):
        raise JobFailure("job_workspace_invalid")
    for item in directory.iterdir():
        metadata = item.lstat()
        if not stat.S_ISREG(metadata.st_mode) or item.is_symlink():
            raise JobFailure("job_workspace_invalid")
    return validate_job(read_json(directory / "job.json", "job_invalid"))


def fsync_directory(directory: Path) -> None:
    descriptor = os.open(directory, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def exchange_directories(first: Path, second: Path) -> None:
    rename = ctypes.CDLL(None, use_errno=True).renameatx_np
    rename.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
    rename.restype = ctypes.c_int
    if rename(-2, os.fsencode(first), -2, os.fsencode(second), 0x00000002) != 0:
        raise JobFailure("job_write_failed")


def replace_current_job(
    workspace: Path,
    new_job: dict[str, Any],
    fail_after_swap: bool = False,
    fail_archive_move: bool = False,
) -> None:
    current = workspace / "current_job"
    old_job = validate_job_directory(current)
    if old_job["state"] not in {"completed", "failed"}:
        raise JobFailure("job_already_exists")
    if source_fingerprint(Path(new_job["source"]["path"])) != new_job["source"]["fingerprint"]:
        raise JobFailure("source_changed")

    replacement = workspace / ".partial" / f"replacement_{new_job['job_id']}"
    archive_root = workspace / "archive"
    archive = archive_root / f"job_{old_job['job_id']}"
    if replacement.exists() or replacement.is_symlink() or archive.exists() or archive.is_symlink():
        raise JobFailure("job_workspace_invalid")
    try:
        archive_root.mkdir(exist_ok=True)
        if not archive_root.is_dir() or archive_root.is_symlink():
            raise JobFailure("job_workspace_invalid")
        replacement.mkdir()
        job_path = replacement / "job.json"
        data = json.dumps(validate_job(new_job), ensure_ascii=False, separators=(",", ":"), sort_keys=True) + "\n"
        with job_path.open("x", encoding="utf-8") as output:
            output.write(data)
            output.flush()
            os.fsync(output.fileno())
        if validate_job_directory(replacement) != new_job:
            raise JobFailure("job_invalid")
        fsync_directory(replacement)
        fsync_directory(workspace / ".partial")
    except JobFailure:
        raise
    except OSError as error:
        raise JobFailure("job_write_failed") from error

    exchange_directories(current, replacement)
    try:
        if fail_after_swap or validate_job_directory(current) != new_job:
            raise JobFailure("job_write_failed")
    except JobFailure:
        try:
            exchange_directories(current, replacement)
        except JobFailure:
            pass
        raise

    try:
        if fail_archive_move:
            raise OSError("injected archive failure")
        os.rename(replacement, archive)
        fsync_directory(archive_root)
        fsync_directory(workspace)
    except OSError as error:
        raise JobFailure("job_write_failed") from error


def write_job(workspace: Path, job: dict[str, Any], request_id: str) -> None:
    current = workspace / "current_job"
    if current.exists():
        if not current.is_dir() or current.is_symlink():
            raise JobFailure("job_workspace_invalid")
        allowed = {"stop.requested"}
        actual = {item.name for item in current.iterdir()}
        if "job.json" in actual:
            existing = validate_job_directory(current)
            if existing["state"] in {"completed", "failed"}:
                replace_current_job(workspace, job)
                return
            raise JobFailure("job_already_exists")
        if not actual.issubset(allowed):
            raise JobFailure("job_workspace_invalid")
        remove_stale_stop(current, job["job_id"], None)
    else:
        current.mkdir()
    temporary = workspace / ".partial" / f"job_{request_id}.json.partial"
    if temporary.exists():
        raise JobFailure("job_workspace_invalid")
    data = json.dumps(job, ensure_ascii=False, separators=(",", ":"), sort_keys=True) + "\n"
    try:
        with temporary.open("x", encoding="utf-8") as output:
            output.write(data)
            output.flush()
            os.fsync(output.fileno())
        validate_job(read_json(temporary, "job_invalid"))
        os.rename(temporary, current / "job.json")
        directory = os.open(current, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    except JobFailure:
        raise
    except OSError as error:
        raise JobFailure("job_write_failed") from error
    validate_job(read_json(current / "job.json", "job_invalid"))


def replace_job(workspace: Path, job: dict[str, Any], request_id: str) -> dict[str, Any]:
    """既存jobを検証済みの次revisionへ原子的に置換する。"""
    current = workspace / "current_job"
    path = current / "job.json"
    temporary = workspace / ".partial" / f"job_{request_id}.json.partial"
    data = json.dumps(validate_job(job), ensure_ascii=False, separators=(",", ":"), sort_keys=True) + "\n"
    try:
        with temporary.open("x", encoding="utf-8") as output:
            output.write(data)
            output.flush()
            os.fsync(output.fileno())
        validate_job(read_json(temporary, "job_invalid"))
        os.replace(temporary, path)
        directory = os.open(current, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    except OSError as error:
        raise JobFailure("job_write_failed") from error
    return validate_job(read_json(path, "job_invalid"))


def validate_stop(value: Any) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise JobFailure("job_workspace_invalid")
    exact(value, {"schema_version", "job_id", "request_id"}, "job_workspace_invalid")
    if value["schema_version"] != 1:
        raise JobFailure("job_workspace_invalid")
    canonical_uuid(value["job_id"], "job_workspace_invalid")
    canonical_uuid(value["request_id"], "job_workspace_invalid")
    return value


def remove_stale_stop(current: Path, job_id: str, state_value: str | None) -> None:
    marker = current / "stop.requested"
    if not marker.exists() and not marker.is_symlink():
        return
    stop = validate_stop(read_json(marker, "job_workspace_invalid"))
    if stop["job_id"] == job_id and state_value == "stop_requested":
        return
    try:
        marker.unlink()
    except OSError as error:
        raise JobFailure("job_workspace_invalid") from error
    if marker.exists() or marker.is_symlink():
        raise JobFailure("job_workspace_invalid")


def recover_job(workspace: Path) -> dict[str, Any]:
    current = workspace / "current_job"
    if not current.is_dir() or current.is_symlink():
        raise JobFailure("job_not_found")
    allowed = {
        "job.json", "stop.requested", "analysis.wav", "analysis_audio.json",
        "vad.json", "speaker_candidates.json", "speaker_matches.json",
    }
    if {item.name for item in current.iterdir()} - allowed:
        raise JobFailure("job_workspace_invalid")
    path = current / "job.json"
    job = validate_job(read_json(path, "job_invalid"))
    actual = source_fingerprint(Path(job["source"]["path"]))
    if actual != job["source"]["fingerprint"]:
        job["state_revision"] += 1
        job["state"] = "failed"
        job["failure_code"] = "source_changed"
    elif job["state"] in ACTIVE_STATES:
        job["state_revision"] += 1
        job["state"] = "recovery_required"
        job["failure_code"] = None
    remove_stale_stop(current, job["job_id"], job["state"])
    temporary = workspace / ".partial" / f"job_{uuid.uuid4()}.json.partial"
    data = json.dumps(job, ensure_ascii=False, separators=(",", ":"), sort_keys=True) + "\n"
    try:
        with temporary.open("x", encoding="utf-8") as output:
            output.write(data)
            output.flush()
            os.fsync(output.fileno())
        validate_job(read_json(temporary, "job_invalid"))
        os.replace(temporary, path)
        directory = os.open(current, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    except OSError as error:
        raise JobFailure("job_write_failed") from error
    return validate_job(read_json(path, "job_invalid"))


def resume_job(
    workspace: Path, requested_job_id: str, request_id: str, expected_state: str = "stopped"
) -> dict[str, Any]:
    current = workspace / "current_job"
    if not current.is_dir() or current.is_symlink():
        raise JobFailure("job_not_found")
    job = validate_job(read_json(current / "job.json", "job_invalid"))
    if job["job_id"] != requested_job_id or job["state"] != expected_state:
        raise JobFailure("job_invalid")
    marker = current / "stop.requested"
    if marker.exists() or marker.is_symlink():
        raise JobFailure("job_workspace_invalid")
    if source_fingerprint(Path(job["source"]["path"])) != job["source"]["fingerprint"]:
        raise JobFailure("source_changed")
    allowed = {
        "job.json", "analysis.wav", "analysis_audio.json", "vad.json",
        "speaker_candidates.json", "speaker_matches.json",
    }
    for item in current.iterdir():
        if item.name not in allowed or item.is_symlink() or not item.is_file():
            raise JobFailure("job_workspace_invalid")
    job["state_revision"] += 1
    job["state"] = "preparing"
    job["failure_code"] = None
    return replace_job(workspace, job, request_id)


def fail_job(workspace: Path, requested: dict[str, Any], request_id: str) -> dict[str, Any]:
    current = validate_job_directory(workspace / "current_job")
    if current["job_id"] != requested["job_id"] or current["state"] in {"completed", "failed", "stopped"}:
        raise JobFailure("job_invalid")
    expected = {
        **current,
        "state_revision": current["state_revision"] + 1,
        "state": "failed",
        "failure_code": requested["failure_code"],
    }
    if requested != expected:
        raise JobFailure("job_invalid")
    return replace_job(workspace, expected, request_id)


def prepare_job(workspace: Path, requested: dict[str, Any], request_id: str) -> dict[str, Any]:
    current = validate_job_directory(workspace / "current_job")
    expected = {**current, "state_revision": current["state_revision"] + 1, "state": "preparing"}
    if current["state"] != "start_requested" or requested != expected:
        raise JobFailure("job_invalid")
    return replace_job(workspace, expected, request_id)


def run(request: dict[str, Any], emitter: Emitter) -> dict[str, Any]:
    exact(request, {"protocol_version", "request_id", "operation", "workspace_root", "job"})
    if request["protocol_version"] != 1:
        raise JobFailure("job_invalid")
    job = validate_job(request["job"])
    workspace = prepare_workspace(request["workspace_root"])
    descriptor = os.open(workspace / "analysis.lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        if not stat.S_ISREG(os.fstat(descriptor).st_mode):
            raise JobFailure("job_workspace_invalid")
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise JobFailure("analysis_busy") from error
        emitter.emit("progress", {"stage": "job_lock", "status": "completed"})
        operation = request["operation"]
        if operation == "create_job":
            if job["start_request_id"] != request["request_id"]:
                raise JobFailure("job_invalid")
            if source_fingerprint(Path(job["source"]["path"])) != job["source"]["fingerprint"]:
                raise JobFailure("source_changed")
            write_job(workspace, job, request["request_id"])
            result = job
        elif operation == "recover_job":
            result = recover_job(workspace)
            if result["job_id"] != job["job_id"]:
                raise JobFailure("job_invalid")
        elif operation == "resume_job":
            result = resume_job(workspace, job["job_id"], request["request_id"])
        elif operation == "resume_recovery_job":
            result = resume_job(
                workspace, job["job_id"], request["request_id"], "recovery_required"
            )
        elif operation == "fail_job":
            result = fail_job(workspace, job, request["request_id"])
        elif operation == "prepare_job":
            result = prepare_job(workspace, job, request["request_id"])
        else:
            raise JobFailure("job_invalid")
        emitter.emit("progress", {"stage": "job_ready", "status": "completed"})
        return {"job_id": result["job_id"], "state": result["state"]}
    finally:
        os.close(descriptor)


def main() -> int:
    try:
        line = sys.stdin.buffer.readline()
        if not line or sys.stdin.buffer.read(1):
            return 2
        request = json.loads(line)
        if not isinstance(request, dict):
            return 2
        request_id = canonical_uuid(request.get("request_id"), "job_invalid")
    except (UnicodeError, json.JSONDecodeError, JobFailure):
        return 2
    emitter = Emitter(request_id)
    try:
        result = run(request, emitter)
        emitter.emit("finished", {"outcome": "succeeded", "result": result})
    except JobFailure as error:
        emitter.emit("error", {"code": error.code})
        emitter.emit("finished", {"outcome": "failed", "code": error.code})
    except Exception:
        emitter.emit("error", {"code": "protocol_error"})
        emitter.emit("finished", {"outcome": "failed", "code": "protocol_error"})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
