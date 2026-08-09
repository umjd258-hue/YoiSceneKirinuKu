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

import analysis_audio as audio
import analysis_job_runner as jobs
import vad


VAD_PROFILE = {
    "frame_ms": 30,
    "threshold_millidecibels": -45_000,
    "minimum_activity_ms": 90,
}
GENERATION_PROFILE = {
    "merge_gap_ms": 500,
    "padding_before_ms": 250,
    "padding_after_ms": 250,
    "minimum_duration_ms": 3_000,
    "maximum_duration_ms": 30_000,
    "split_overlap_ms": 0,
}
ERROR_CODES = {
    "candidate_busy", "candidate_job_invalid", "candidate_input_unavailable",
    "candidate_vad_failed", "candidate_vad_invalid", "candidate_generation_failed",
    "candidate_finalization_failed", "candidate_reuse_invalid", "candidate_protocol_error",
}
PARTIAL_PATTERN = re.compile(
    r"(?:vad|speaker_candidates)_[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-"
    r"[0-9a-f]{4}-[0-9a-f]{12}\.json\.partial\Z"
)
HEX_DIGEST = re.compile(r"[0-9a-f]{64}\Z")


class CandidateFailure(Exception):
    def __init__(self, code: str) -> None:
        self.code = code if code in ERROR_CODES else "candidate_protocol_error"
        super().__init__(self.code)


class Emitter:
    def __init__(self, request_id: str) -> None:
        self.request_id = request_id
        self.sequence = 0

    def emit(self, event_type: str, payload: dict[str, Any]) -> None:
        self.sequence += 1
        event = {
            "protocol_version": 1,
            "type": event_type,
            "request_id": self.request_id,
            "sequence": self.sequence,
            "payload": payload,
        }
        print(json.dumps(event, ensure_ascii=False, separators=(",", ":")), flush=True)


def exact(value: Any, keys: set[str], code: str) -> None:
    if not isinstance(value, dict) or set(value) != keys:
        raise CandidateFailure(code)


def integer(value: Any, minimum: int, code: str) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value < minimum:
        raise CandidateFailure(code)
    return value


def file_fingerprint(path: Path, code: str) -> dict[str, Any]:
    try:
        metadata = path.lstat()
        if not stat.S_ISREG(metadata.st_mode) or path.is_symlink() or metadata.st_size <= 0:
            raise CandidateFailure(code)
        digest = hashlib.sha256()
        byte_count = 0
        with path.open("rb") as source:
            while chunk := source.read(1024 * 1024):
                digest.update(chunk)
                byte_count += len(chunk)
        after = path.lstat()
    except CandidateFailure:
        raise
    except OSError as error:
        raise CandidateFailure(code) from error
    if (
        (metadata.st_dev, metadata.st_ino, metadata.st_size, metadata.st_mtime_ns)
        != (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns)
        or byte_count != after.st_size
    ):
        raise CandidateFailure(code)
    return {"algorithm": "sha256", "byte_count": byte_count, "digest": digest.hexdigest()}


def analysis_fingerprint(current: Path) -> dict[str, Any]:
    wav = file_fingerprint(current / "analysis.wav", "candidate_input_unavailable")
    metadata = file_fingerprint(current / "analysis_audio.json", "candidate_input_unavailable")
    return {
        "algorithm": "sha256",
        "wav_byte_count": wav["byte_count"],
        "wav_digest": wav["digest"],
        "metadata_byte_count": metadata["byte_count"],
        "metadata_digest": metadata["digest"],
    }


def validate_digest(value: Any, code: str) -> str:
    if not isinstance(value, str) or HEX_DIGEST.fullmatch(value) is None:
        raise CandidateFailure(code)
    return value


def validate_vad(value: Any, job_id: str, expected_fingerprint: dict[str, Any]) -> dict[str, Any]:
    code = "candidate_vad_invalid"
    exact(value, {"schema_version", "job_id", "analysis_audio_fingerprint", "profile", "audio_duration_ms", "segments"}, code)
    if value["schema_version"] != 1 or value["job_id"] != job_id or value["profile"] != VAD_PROFILE:
        raise CandidateFailure(code)
    fingerprint = value["analysis_audio_fingerprint"]
    exact(fingerprint, {"algorithm", "wav_byte_count", "wav_digest", "metadata_byte_count", "metadata_digest"}, code)
    if fingerprint["algorithm"] != "sha256":
        raise CandidateFailure(code)
    integer(fingerprint["wav_byte_count"], 1, code)
    integer(fingerprint["metadata_byte_count"], 1, code)
    validate_digest(fingerprint["wav_digest"], code)
    validate_digest(fingerprint["metadata_digest"], code)
    if fingerprint != expected_fingerprint:
        raise CandidateFailure(code)
    duration = integer(value["audio_duration_ms"], 1, code)
    if not isinstance(value["segments"], list):
        raise CandidateFailure(code)
    prior_end = 0
    for segment in value["segments"]:
        exact(segment, {"start_ms", "end_ms", "duration_ms"}, code)
        start = integer(segment["start_ms"], 0, code)
        end = integer(segment["end_ms"], 1, code)
        length = integer(segment["duration_ms"], 90, code)
        if start < prior_end or end <= start or end > duration or length != end - start:
            raise CandidateFailure(code)
        prior_end = end
    return value


def validate_candidates(value: Any, job_id: str, vad_fingerprint: dict[str, Any], audio_duration_ms: int) -> dict[str, Any]:
    code = "candidate_reuse_invalid"
    exact(value, {"schema_version", "job_id", "vad_fingerprint", "generation_profile", "candidates"}, code)
    if value["schema_version"] != 1 or value["job_id"] != job_id or value["generation_profile"] != GENERATION_PROFILE:
        raise CandidateFailure(code)
    fingerprint = value["vad_fingerprint"]
    exact(fingerprint, {"algorithm", "byte_count", "digest"}, code)
    if fingerprint["algorithm"] != "sha256":
        raise CandidateFailure(code)
    integer(fingerprint["byte_count"], 1, code)
    validate_digest(fingerprint["digest"], code)
    if fingerprint != vad_fingerprint or not isinstance(value["candidates"], list):
        raise CandidateFailure(code)
    prior_end = 0
    identifiers: set[str] = set()
    for candidate in value["candidates"]:
        exact(candidate, {"candidate_id", "start_ms", "end_ms", "duration_ms"}, code)
        identifier = candidate["candidate_id"]
        start = integer(candidate["start_ms"], 0, code)
        end = integer(candidate["end_ms"], 1, code)
        length = integer(candidate["duration_ms"], 1, code)
        if (
            not isinstance(identifier, str) or not identifier.startswith("candidate_")
            or identifier in identifiers or start < prior_end or end <= start
            or end > audio_duration_ms or length != end - start
            or length < GENERATION_PROFILE["minimum_duration_ms"]
            or length > GENERATION_PROFILE["maximum_duration_ms"]
        ):
            raise CandidateFailure(code)
        try:
            parsed = uuid.UUID(identifier.removeprefix("candidate_"))
        except ValueError as error:
            raise CandidateFailure(code) from error
        if parsed.version != 5 or str(parsed) != identifier.removeprefix("candidate_"):
            raise CandidateFailure(code)
        identifiers.add(identifier)
        prior_end = end
    return value


def expand(start: int, end: int, duration: int) -> tuple[int, int]:
    minimum = GENERATION_PROFILE["minimum_duration_ms"]
    missing = minimum - (end - start)
    if missing <= 0:
        return start, end
    before = missing // 2
    after = missing - before
    start = max(0, start - before)
    end = min(duration, end + after)
    if end - start < minimum:
        if start == 0:
            end = min(duration, minimum)
        elif end == duration:
            start = max(0, duration - minimum)
    return start, end


def split_interval(start: int, end: int) -> list[tuple[int, int]]:
    minimum = GENERATION_PROFILE["minimum_duration_ms"]
    maximum = GENERATION_PROFILE["maximum_duration_ms"]
    result: list[tuple[int, int]] = []
    cursor = start
    while end - cursor > maximum:
        length = maximum
        if end - (cursor + length) < minimum:
            length = end - cursor - minimum
        result.append((cursor, cursor + length))
        cursor += length
    result.append((cursor, end))
    return result


def generate_candidates(segments: list[dict[str, int]], duration: int, job_id: str) -> list[dict[str, Any]]:
    if duration < GENERATION_PROFILE["minimum_duration_ms"]:
        return []
    merged: list[list[int]] = []
    for segment in segments:
        start, end = segment["start_ms"], segment["end_ms"]
        if merged and start - merged[-1][1] <= GENERATION_PROFILE["merge_gap_ms"]:
            merged[-1][1] = end
        else:
            merged.append([start, end])
    expanded = [
        expand(
            max(0, start - GENERATION_PROFILE["padding_before_ms"]),
            min(duration, end + GENERATION_PROFILE["padding_after_ms"]),
            duration,
        )
        for start, end in merged
    ]
    united: list[list[int]] = []
    for start, end in expanded:
        if united and start <= united[-1][1]:
            united[-1][1] = max(united[-1][1], end)
        else:
            united.append([start, end])
    namespace = uuid.UUID(job_id)
    candidates = []
    for start, end in united:
        for split_start, split_end in split_interval(start, end):
            candidate_uuid = uuid.uuid5(namespace, f"candidate:v1:{split_start}:{split_end}")
            candidates.append({
                "candidate_id": f"candidate_{candidate_uuid}",
                "start_ms": split_start,
                "end_ms": split_end,
                "duration_ms": split_end - split_start,
            })
    return candidates


def write_json_partial(path: Path, value: dict[str, Any], code: str) -> None:
    try:
        with path.open("x", encoding="utf-8") as output:
            json.dump(value, output, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
            output.write("\n")
            output.flush()
            os.fsync(output.fileno())
    except OSError as error:
        raise CandidateFailure(code) from error


def remove_known_partial(path: Path) -> None:
    if not path.exists() and not path.is_symlink():
        return
    try:
        metadata = path.lstat()
        if not stat.S_ISREG(metadata.st_mode) or path.is_symlink():
            raise CandidateFailure("candidate_reuse_invalid")
        path.unlink()
    except OSError as error:
        raise CandidateFailure("candidate_reuse_invalid") from error


def reconcile_partials(workspace: Path) -> None:
    for item in (workspace / ".partial").iterdir():
        if PARTIAL_PATTERN.fullmatch(item.name):
            remove_known_partial(item)


def build_vad(current: Path, job: dict[str, Any], fingerprint: dict[str, Any]) -> dict[str, Any]:
    try:
        verified = audio.reuse(current, job)
    except (audio.AudioFailure, jobs.JobFailure) as error:
        raise CandidateFailure("candidate_input_unavailable") from error
    if verified is None:
        raise CandidateFailure("candidate_input_unavailable")
    try:
        raw_segments = vad.detect_segments(current / "analysis.wav")
    except vad.VADFailure as error:
        raise CandidateFailure("candidate_vad_failed") from error
    return {
        "schema_version": 1,
        "job_id": job["job_id"],
        "analysis_audio_fingerprint": fingerprint,
        "profile": VAD_PROFILE,
        "audio_duration_ms": verified["duration_ms"],
        "segments": [
            {"start_ms": item["start_ms"], "end_ms": item["end_ms"], "duration_ms": item["end_ms"] - item["start_ms"]}
            for item in raw_segments
        ],
    }


def run(request: dict[str, Any], emitter: Emitter) -> dict[str, Any]:
    exact(request, {"protocol_version", "request_id", "workspace_root", "job_id"}, "candidate_job_invalid")
    if request["protocol_version"] != 1:
        raise CandidateFailure("candidate_job_invalid")
    request_id = jobs.canonical_uuid(request["request_id"], "candidate_job_invalid")
    job_id = jobs.canonical_uuid(request["job_id"], "candidate_job_invalid")
    try:
        workspace = jobs.prepare_workspace(request["workspace_root"])
    except jobs.JobFailure as error:
        raise CandidateFailure("candidate_job_invalid") from error
    descriptor = os.open(workspace / "analysis.lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise CandidateFailure("candidate_busy") from error
        emitter.emit("progress", {"stage": "candidate_generation", "status": "running"})
        current = workspace / "current_job"
        if not current.is_dir() or current.is_symlink():
            raise CandidateFailure("candidate_job_invalid")
        allowed = {"job.json", "stop.requested", "analysis.wav", "analysis_audio.json", "vad.json", "speaker_candidates.json", "speaker_matches.json"}
        if {item.name for item in current.iterdir()} - allowed:
            raise CandidateFailure("candidate_job_invalid")
        try:
            job = jobs.validate_job(jobs.read_json(current / "job.json", "job_invalid"))
        except jobs.JobFailure as error:
            raise CandidateFailure("candidate_job_invalid") from error
        if job["job_id"] != job_id or job["state"] not in {"start_requested", "preparing", "recovery_required"}:
            raise CandidateFailure("candidate_job_invalid")
        reconcile_partials(workspace)
        input_fingerprint = analysis_fingerprint(current)
        vad_path = current / "vad.json"
        candidates_path = current / "speaker_candidates.json"
        vad_present = vad_path.exists() or vad_path.is_symlink()
        candidates_present = candidates_path.exists() or candidates_path.is_symlink()
        if candidates_present and not vad_present:
            raise CandidateFailure("candidate_reuse_invalid")
        if vad_present:
            try:
                vad_value = validate_vad(jobs.read_json(vad_path, "candidate_vad_invalid"), job_id, input_fingerprint)
            except jobs.JobFailure as error:
                raise CandidateFailure("candidate_vad_invalid") from error
            emitter.emit("progress", {"stage": "candidate_generation", "status": "vad_completed"})
            vad_fingerprint = file_fingerprint(vad_path, "candidate_vad_invalid")
            if candidates_present:
                try:
                    value = validate_candidates(
                        jobs.read_json(candidates_path, "candidate_reuse_invalid"), job_id,
                        vad_fingerprint, vad_value["audio_duration_ms"],
                    )
                except jobs.JobFailure as error:
                    raise CandidateFailure("candidate_reuse_invalid") from error
                emitter.emit("progress", {"stage": "candidate_generation", "status": "completed"})
                return {"reused": True, "vad_segment_count": len(vad_value["segments"]), "candidate_count": len(value["candidates"])}
        else:
            vad_value = build_vad(current, job, input_fingerprint)
            validate_vad(vad_value, job_id, input_fingerprint)
            vad_partial = workspace / ".partial" / f"vad_{request_id}.json.partial"
            write_json_partial(vad_partial, vad_value, "candidate_finalization_failed")
            try:
                validate_vad(jobs.read_json(vad_partial, "candidate_vad_invalid"), job_id, input_fingerprint)
                os.rename(vad_partial, vad_path)
            except (OSError, jobs.JobFailure) as error:
                raise CandidateFailure("candidate_finalization_failed") from error
            emitter.emit("progress", {"stage": "candidate_generation", "status": "vad_completed"})
            vad_fingerprint = file_fingerprint(vad_path, "candidate_vad_invalid")
        try:
            generated = generate_candidates(vad_value["segments"], vad_value["audio_duration_ms"], job_id)
        except Exception as error:
            raise CandidateFailure("candidate_generation_failed") from error
        candidate_value = {
            "schema_version": 1,
            "job_id": job_id,
            "vad_fingerprint": vad_fingerprint,
            "generation_profile": GENERATION_PROFILE,
            "candidates": generated,
        }
        candidate_partial = workspace / ".partial" / f"speaker_candidates_{request_id}.json.partial"
        write_json_partial(candidate_partial, candidate_value, "candidate_finalization_failed")
        try:
            validate_candidates(
                jobs.read_json(candidate_partial, "candidate_reuse_invalid"), job_id,
                vad_fingerprint, vad_value["audio_duration_ms"],
            )
            os.rename(candidate_partial, candidates_path)
            directory = os.open(current, os.O_RDONLY | os.O_DIRECTORY)
            try:
                os.fsync(directory)
            finally:
                os.close(directory)
            final_vad = validate_vad(jobs.read_json(vad_path, "candidate_vad_invalid"), job_id, input_fingerprint)
            final_fingerprint = file_fingerprint(vad_path, "candidate_vad_invalid")
            final_candidates = validate_candidates(
                jobs.read_json(candidates_path, "candidate_reuse_invalid"), job_id,
                final_fingerprint, final_vad["audio_duration_ms"],
            )
        except (OSError, jobs.JobFailure) as error:
            raise CandidateFailure("candidate_finalization_failed") from error
        emitter.emit("progress", {"stage": "candidate_generation", "status": "completed"})
        return {"reused": False, "vad_segment_count": len(final_vad["segments"]), "candidate_count": len(final_candidates["candidates"])}
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
        request_id = jobs.canonical_uuid(request.get("request_id"), "candidate_job_invalid")
    except (UnicodeError, json.JSONDecodeError, jobs.JobFailure):
        return 2
    emitter = Emitter(request_id)
    try:
        result = run(request, emitter)
        emitter.emit("finished", {"outcome": "succeeded", "result": result})
    except CandidateFailure as error:
        emitter.emit("error", {"code": error.code})
        emitter.emit("finished", {"outcome": "failed", "code": error.code})
    except Exception:
        emitter.emit("error", {"code": "candidate_protocol_error"})
        emitter.emit("finished", {"outcome": "failed", "code": "candidate_protocol_error"})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
