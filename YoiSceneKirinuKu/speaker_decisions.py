#!/usr/bin/env python3
from __future__ import annotations

import fcntl
import hashlib
import json
import math
import os
import stat
import sys
from pathlib import Path
from typing import Any

import analysis_job_runner as jobs


CONTRACT_VERSION = "stage15-mvp-technical-v1"
MATCH_THRESHOLD = 0.8549823165
UNCERTAINTY_MARGIN = 0.0012876395
ACCEPTANCE_THRESHOLD = 0.856269956
EXPECTED_MODEL = {
    "model_id": "speechbrain/spkrec-ecapa-voxceleb",
    "model_revision": "0f99f2d0ebe89ac095bcc5903c4dd8f72b367286",
    "dimension": 192,
    "dtype": "float32",
    "normalization": "l2",
}
ERROR_CODES = {
    "speaker_decisions_busy", "speaker_decisions_job_invalid", "speaker_decisions_input_invalid",
    "speaker_decisions_finalization_failed", "speaker_decisions_reuse_invalid",
    "speaker_decisions_protocol_error",
}


class DecisionFailure(Exception):
    def __init__(self, code: str) -> None:
        self.code = code if code in ERROR_CODES else "speaker_decisions_protocol_error"
        super().__init__(self.code)


class Emitter:
    def __init__(self, request_id: str) -> None:
        self.request_id = request_id
        self.sequence = 0

    def emit(self, event_type: str, payload: dict[str, Any]) -> None:
        self.sequence += 1
        print(json.dumps({
            "protocol_version": 1, "type": event_type, "request_id": self.request_id,
            "sequence": self.sequence, "payload": payload,
        }, separators=(",", ":"), allow_nan=False), flush=True)


def exact(value: Any, keys: set[str], code: str) -> None:
    if not isinstance(value, dict) or set(value) != keys:
        raise DecisionFailure(code)


def fingerprint(path: Path, code: str) -> dict[str, Any]:
    try:
        before = path.lstat()
        if not stat.S_ISREG(before.st_mode) or path.is_symlink() or before.st_size <= 0:
            raise DecisionFailure(code)
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        after = path.lstat()
    except DecisionFailure:
        raise
    except OSError as error:
        raise DecisionFailure(code) from error
    if (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns) != (
        after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns
    ):
        raise DecisionFailure(code)
    return {"algorithm": "sha256", "byte_count": before.st_size, "digest": digest}


def decide(comparisons: Any) -> dict[str, Any]:
    if not isinstance(comparisons, list):
        raise DecisionFailure("speaker_decisions_input_invalid")
    seen: set[str] = set()
    values: list[tuple[float, str]] = []
    for comparison in comparisons:
        exact(comparison, {"character_id", "cosine_similarity"}, "speaker_decisions_input_invalid")
        identifier = comparison["character_id"]
        score = comparison["cosine_similarity"]
        if not isinstance(identifier, str) or not identifier or identifier in seen:
            raise DecisionFailure("speaker_decisions_input_invalid")
        if not isinstance(score, (int, float)) or isinstance(score, bool) or not math.isfinite(score) or not -1 <= score <= 1:
            raise DecisionFailure("speaker_decisions_input_invalid")
        seen.add(identifier)
        values.append((float(score), identifier))
    values.sort(key=lambda item: (-item[0], item[1]))
    if not values:
        return {"decision": "unknown", "character_id": None, "top_similarity": None, "reason": "no_candidates"}
    top_score, top_id = values[0]
    second_score = values[1][0] if len(values) > 1 else None
    if top_score < ACCEPTANCE_THRESHOLD:
        reason = "boundary_uncertain" if top_score >= MATCH_THRESHOLD else "below_threshold"
        return {"decision": "unknown", "character_id": None, "top_similarity": top_score, "reason": reason}
    if second_score is not None and second_score >= ACCEPTANCE_THRESHOLD:
        return {"decision": "unknown", "character_id": None, "top_similarity": top_score, "reason": "multiple_candidates"}
    return {"decision": "matched", "character_id": top_id, "top_similarity": top_score, "reason": "unique_match"}


def validate_input(value: Any, job_id: str) -> list[dict[str, Any]]:
    exact(value, {"schema_version", "job_id", "speaker_candidates_fingerprint", "model", "selected_characters", "candidates"}, "speaker_decisions_input_invalid")
    if value["schema_version"] != 1 or value["job_id"] != job_id or value["model"] != EXPECTED_MODEL:
        raise DecisionFailure("speaker_decisions_input_invalid")
    selected = value["selected_characters"]
    if not isinstance(selected, list):
        raise DecisionFailure("speaker_decisions_input_invalid")
    selected_ids = [item.get("character_id") if isinstance(item, dict) else None for item in selected]
    if any(not isinstance(identifier, str) for identifier in selected_ids) or len(selected_ids) != len(set(selected_ids)):
        raise DecisionFailure("speaker_decisions_input_invalid")
    candidates = value["candidates"]
    if not isinstance(candidates, list):
        raise DecisionFailure("speaker_decisions_input_invalid")
    candidate_ids: set[str] = set()
    for item in candidates:
        exact(item, {"candidate_id", "comparisons"}, "speaker_decisions_input_invalid")
        identifier = item["candidate_id"]
        if not isinstance(identifier, str) or identifier in candidate_ids:
            raise DecisionFailure("speaker_decisions_input_invalid")
        if [entry.get("character_id") if isinstance(entry, dict) else None for entry in item["comparisons"]] != selected_ids:
            raise DecisionFailure("speaker_decisions_input_invalid")
        decide(item["comparisons"])
        candidate_ids.add(identifier)
    return candidates


def validate_output(value: Any, job_id: str, source: dict[str, Any], candidate_ids: list[str]) -> dict[str, Any]:
    code = "speaker_decisions_reuse_invalid"
    exact(value, {"schema_version", "job_id", "speaker_matches_fingerprint", "contract", "candidates"}, code)
    contract = {
        "version": CONTRACT_VERSION, "match_threshold": MATCH_THRESHOLD,
        "uncertainty_margin": UNCERTAINTY_MARGIN, "acceptance_threshold": ACCEPTANCE_THRESHOLD,
        "multiple_candidate_rule": "unknown_if_multiple_candidates_meet_acceptance_threshold",
        "real_person_accuracy_validated": False,
    }
    if value["schema_version"] != 1 or value["job_id"] != job_id or value["speaker_matches_fingerprint"] != source or value["contract"] != contract:
        raise DecisionFailure(code)
    items = value["candidates"]
    if not isinstance(items, list) or [item.get("candidate_id") if isinstance(item, dict) else None for item in items] != candidate_ids:
        raise DecisionFailure(code)
    for item in items:
        exact(item, {"candidate_id", "decision", "character_id", "top_similarity", "reason"}, code)
        if item["decision"] not in {"matched", "unknown"}:
            raise DecisionFailure(code)
        if item["decision"] == "matched" and not isinstance(item["character_id"], str):
            raise DecisionFailure(code)
        if item["decision"] == "unknown" and item["character_id"] is not None:
            raise DecisionFailure(code)
    return value


def run(payload: dict[str, Any], emitter: Emitter) -> dict[str, Any]:
    exact(payload, {"workspace_root", "job_id"}, "speaker_decisions_job_invalid")
    try:
        job_id = jobs.canonical_uuid(payload["job_id"], "speaker_decisions_job_invalid")
        workspace = jobs.prepare_workspace(payload["workspace_root"])
    except jobs.JobFailure as error:
        raise DecisionFailure("speaker_decisions_job_invalid") from error
    descriptor = os.open(workspace / "analysis.lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise DecisionFailure("speaker_decisions_busy") from error
        current = workspace / "current_job"
        if not current.is_dir() or current.is_symlink():
            raise DecisionFailure("speaker_decisions_job_invalid")
        allowed = {"job.json", "stop.requested", "analysis.wav", "analysis_audio.json", "vad.json", "speaker_candidates.json", "speaker_matches.json", "speaker_decisions.json", "quality_features.json", "quality_human_assessments.json", "quality_decisions.json"}
        if {item.name for item in current.iterdir()} - allowed:
            raise DecisionFailure("speaker_decisions_job_invalid")
        try:
            job = jobs.validate_job(jobs.read_json(current / "job.json", "job_invalid"))
            source_path = current / "speaker_matches.json"
            source = fingerprint(source_path, "speaker_decisions_input_invalid")
            matches = jobs.read_json(source_path, "speaker_decisions_input_invalid")
        except jobs.JobFailure as error:
            raise DecisionFailure("speaker_decisions_input_invalid") from error
        if job["job_id"] != job_id or job["state"] not in {"start_requested", "preparing", "recovery_required"}:
            raise DecisionFailure("speaker_decisions_job_invalid")
        candidates = validate_input(matches, job_id)
        candidate_ids = [item["candidate_id"] for item in candidates]
        output_path = current / "speaker_decisions.json"
        if output_path.exists() or output_path.is_symlink():
            try:
                reused = validate_output(jobs.read_json(output_path, "speaker_decisions_reuse_invalid"), job_id, source, candidate_ids)
            except (jobs.JobFailure, DecisionFailure) as error:
                raise DecisionFailure("speaker_decisions_reuse_invalid") from error
            return {"reused": True, "candidate_count": len(reused["candidates"])}
        emitter.emit("progress", {"stage": "speaker_decisions", "status": "running"})
        value = {
            "schema_version": 1, "job_id": job_id, "speaker_matches_fingerprint": source,
            "contract": {
                "version": CONTRACT_VERSION, "match_threshold": MATCH_THRESHOLD,
                "uncertainty_margin": UNCERTAINTY_MARGIN, "acceptance_threshold": ACCEPTANCE_THRESHOLD,
                "multiple_candidate_rule": "unknown_if_multiple_candidates_meet_acceptance_threshold",
                "real_person_accuracy_validated": False,
            },
            "candidates": [{"candidate_id": item["candidate_id"], **decide(item["comparisons"])} for item in candidates],
        }
        validate_output(value, job_id, source, candidate_ids)
        partial = workspace / ".partial" / f"speaker_decisions_{emitter.request_id}.json.partial"
        try:
            with partial.open("x", encoding="utf-8") as stream:
                json.dump(value, stream, separators=(",", ":"), sort_keys=True, allow_nan=False)
                stream.write("\n"); stream.flush(); os.fsync(stream.fileno())
            validate_output(jobs.read_json(partial, "speaker_decisions_reuse_invalid"), job_id, source, candidate_ids)
            os.rename(partial, output_path)
            directory = os.open(current, os.O_RDONLY | os.O_DIRECTORY)
            try: os.fsync(directory)
            finally: os.close(directory)
        except (OSError, ValueError, jobs.JobFailure, DecisionFailure) as error:
            raise DecisionFailure("speaker_decisions_finalization_failed") from error
        emitter.emit("progress", {"stage": "speaker_decisions", "status": "completed"})
        return {"reused": False, "candidate_count": len(candidate_ids)}
    finally:
        os.close(descriptor)


def main() -> int:
    try:
        line = sys.stdin.buffer.readline()
        if not line or sys.stdin.buffer.read(1): return 2
        envelope = json.loads(line)
        exact(envelope, {"protocol_version", "type", "request_id", "sequence", "payload"}, "speaker_decisions_protocol_error")
        if envelope["protocol_version"] != 1 or envelope["type"] != "request" or envelope["sequence"] != 0: return 2
        request_id = jobs.canonical_uuid(envelope["request_id"], "speaker_decisions_protocol_error")
    except (UnicodeError, json.JSONDecodeError, jobs.JobFailure, DecisionFailure):
        return 2
    emitter = Emitter(request_id)
    try:
        result = run(envelope["payload"], emitter)
        emitter.emit("finished", {"outcome": "succeeded", "result": result})
    except DecisionFailure as error:
        emitter.emit("error", {"code": error.code})
        emitter.emit("finished", {"outcome": "failed", "code": error.code})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
