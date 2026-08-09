#!/usr/bin/env python3
from __future__ import annotations

import fcntl
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


def write_job(workspace: Path, job: dict[str, Any], request_id: str) -> None:
    current = workspace / "current_job"
    if current.exists():
        if not current.is_dir() or current.is_symlink():
            raise JobFailure("job_workspace_invalid")
        allowed = {"stop.requested"}
        actual = {item.name for item in current.iterdir()}
        if "job.json" in actual:
            validate_job(read_json(current / "job.json", "job_invalid"))
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
        "vad.json", "speaker_candidates.json",
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
