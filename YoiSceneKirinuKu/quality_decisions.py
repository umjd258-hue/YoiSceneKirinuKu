#!/usr/bin/env python3
from __future__ import annotations

import fcntl
import json
import os
import sys
from pathlib import Path
from typing import Any

import analysis_job_runner as jobs
import candidate_generation as candidates
import quality_features as features


CONTRACT_VERSION = "stage17-human-quality-v1"
LABELS = {"excellent", "good", "needs_review"}
HUMAN_REASONS = {
    "human_clear", "human_usable_with_issue", "reverb", "bgm", "se",
    "overlap_speech", "processed_voice", "uncertain",
}
AUTOMATIC_REASONS = {"low_level", "silence", "clipping", "short_or_boundary", "noise"}
ERROR_CODES = {
    "quality_decisions_busy", "quality_decisions_job_invalid", "quality_decisions_input_unavailable",
    "quality_decisions_input_invalid", "quality_decisions_finalization_failed",
    "quality_decisions_reuse_invalid", "quality_decisions_protocol_error",
}


class QualityDecisionFailure(Exception):
    def __init__(self, code: str) -> None:
        self.code = code if code in ERROR_CODES else "quality_decisions_protocol_error"
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
        raise QualityDecisionFailure(code)


def fallback(candidate_id: str, status: str) -> dict[str, Any]:
    return {
        "candidate_id": candidate_id,
        "label": "needs_review",
        "automatic_reason_codes": [],
        "human_reason_codes": ["uncertain"],
        "human_input_status": status,
    }


def valid_assessment(item: Any, expected_id: str) -> dict[str, Any] | None:
    if not isinstance(item, dict) or set(item) != {"candidate_id", "label", "reason_codes"}:
        return None
    if item["candidate_id"] != expected_id or item["label"] not in LABELS:
        return None
    reasons = item["reason_codes"]
    if not isinstance(reasons, list) or not reasons or len(reasons) != len(set(reasons)):
        return None
    if any(reason not in HUMAN_REASONS for reason in reasons):
        return None
    label = item["label"]
    reason_set = set(reasons)
    if label == "excellent" and reason_set != {"human_clear"}:
        return None
    if label == "good" and ("human_clear" in reason_set or "uncertain" in reason_set):
        return None
    if label == "needs_review" and "human_clear" in reason_set:
        return None
    return item


def combine(candidate_ids: list[str], value: Any | None) -> tuple[list[dict[str, Any]], str]:
    if value is None:
        return [fallback(identifier, "missing") for identifier in candidate_ids], "missing"
    if not isinstance(value, dict) or set(value) != {
        "schema_version", "job_id", "speaker_candidates_fingerprint", "contract_version", "candidates"
    } or value.get("schema_version") != 1 or value.get("contract_version") != CONTRACT_VERSION:
        return [fallback(identifier, "invalid") for identifier in candidate_ids], "invalid"
    items = value.get("candidates")
    if not isinstance(items, list):
        return [fallback(identifier, "invalid") for identifier in candidate_ids], "invalid"
    identifiers = [item.get("candidate_id") if isinstance(item, dict) else None for item in items]
    known = set(candidate_ids)
    if any(not isinstance(identifier, str) or identifier not in known for identifier in identifiers):
        return [fallback(identifier, "invalid") for identifier in candidate_ids], "invalid"
    order = {identifier: index for index, identifier in enumerate(candidate_ids)}
    if identifiers != sorted(identifiers, key=order.get) or len(identifiers) != len(set(identifiers)):
        return [fallback(identifier, "invalid") for identifier in candidate_ids], "invalid"
    by_id: dict[str, Any] = {}
    duplicate_ids: set[str] = set()
    for item in items:
        identifier = item.get("candidate_id") if isinstance(item, dict) else None
        if not isinstance(identifier, str) or identifier in by_id:
            if isinstance(identifier, str):
                duplicate_ids.add(identifier)
            continue
        by_id[identifier] = item
    decisions = []
    for identifier in candidate_ids:
        if identifier in duplicate_ids:
            decisions.append(fallback(identifier, "invalid"))
            continue
        item = valid_assessment(by_id.get(identifier), identifier)
        if item is None:
            decisions.append(fallback(identifier, "missing" if identifier not in by_id else "invalid"))
            continue
        decisions.append({
            "candidate_id": identifier,
            "label": item["label"],
            "automatic_reason_codes": [],
            "human_reason_codes": item["reason_codes"],
            "human_input_status": "available",
        })
    return decisions, "available"


def validate_output(value: Any, job_id: str, feature_fp: dict[str, Any], assessment_source: dict[str, Any], candidate_ids: list[str]) -> dict[str, Any]:
    code = "quality_decisions_reuse_invalid"
    exact(value, {"schema_version", "job_id", "quality_features_fingerprint", "human_assessments_source", "contract_version", "candidates"}, code)
    if value["schema_version"] != 1 or value["job_id"] != job_id or value["quality_features_fingerprint"] != feature_fp or value["human_assessments_source"] != assessment_source or value["contract_version"] != CONTRACT_VERSION:
        raise QualityDecisionFailure(code)
    items = value["candidates"]
    if not isinstance(items, list) or [item.get("candidate_id") if isinstance(item, dict) else None for item in items] != candidate_ids:
        raise QualityDecisionFailure(code)
    for item in items:
        exact(item, {"candidate_id", "label", "automatic_reason_codes", "human_reason_codes", "human_input_status"}, code)
        if item["label"] not in LABELS or item["human_input_status"] not in {"available", "missing", "invalid"}:
            raise QualityDecisionFailure(code)
        if not isinstance(item["automatic_reason_codes"], list) or not isinstance(item["human_reason_codes"], list):
            raise QualityDecisionFailure(code)
        if any(reason not in AUTOMATIC_REASONS for reason in item["automatic_reason_codes"]):
            raise QualityDecisionFailure(code)
        if any(reason not in HUMAN_REASONS for reason in item["human_reason_codes"]):
            raise QualityDecisionFailure(code)
    return value


def load_formal_inputs(current: Path, job_id: str) -> tuple[list[str], dict[str, Any], dict[str, Any]]:
    try:
        analysis_fp = candidates.analysis_fingerprint(current)
        vad_value = candidates.validate_vad(jobs.read_json(current / "vad.json", "candidate_vad_invalid"), job_id, analysis_fp)
        vad_fp = candidates.file_fingerprint(current / "vad.json", "candidate_vad_invalid")
        candidate_value = candidates.validate_candidates(jobs.read_json(current / "speaker_candidates.json", "candidate_reuse_invalid"), job_id, vad_fp, vad_value["audio_duration_ms"])
        candidate_fp = candidates.file_fingerprint(current / "speaker_candidates.json", "candidate_reuse_invalid")
        feature_path = current / "quality_features.json"
        feature_value = features.validate_output(jobs.read_json(feature_path, "quality_features_reuse_invalid"), job_id, analysis_fp, vad_fp, candidate_fp, [item["candidate_id"] for item in candidate_value["candidates"]])
        feature_fp = candidates.file_fingerprint(feature_path, "quality_features_reuse_invalid")
    except (jobs.JobFailure, candidates.CandidateFailure, features.QualityFeatureFailure) as error:
        raise QualityDecisionFailure("quality_decisions_input_invalid") from error
    return [item["candidate_id"] for item in feature_value["candidates"]], feature_fp, candidate_fp


def assessment_input(current: Path, job_id: str, candidate_fp: dict[str, Any]) -> tuple[Any | None, dict[str, Any]]:
    path = current / "quality_human_assessments.json"
    if not path.exists() and not path.is_symlink():
        return None, {"status": "missing", "fingerprint": None}
    try:
        fingerprint = candidates.file_fingerprint(path, "quality_decisions_input_invalid")
        value = jobs.read_json(path, "quality_decisions_input_invalid")
    except (jobs.JobFailure, candidates.CandidateFailure):
        return {}, {"status": "invalid", "fingerprint": None}
    valid_header = isinstance(value, dict) and value.get("job_id") == job_id and value.get("speaker_candidates_fingerprint") == candidate_fp
    return (value if valid_header else {}), {"status": "available" if valid_header else "invalid", "fingerprint": fingerprint}


def run(payload: dict[str, Any], emitter: Emitter) -> dict[str, Any]:
    exact(payload, {"workspace_root", "job_id"}, "quality_decisions_job_invalid")
    try:
        job_id = jobs.canonical_uuid(payload["job_id"], "quality_decisions_job_invalid")
        workspace = jobs.prepare_workspace(payload["workspace_root"])
    except jobs.JobFailure as error:
        raise QualityDecisionFailure("quality_decisions_job_invalid") from error
    descriptor = os.open(workspace / "analysis.lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise QualityDecisionFailure("quality_decisions_busy") from error
        current = workspace / "current_job"
        if not current.is_dir() or current.is_symlink():
            raise QualityDecisionFailure("quality_decisions_job_invalid")
        allowed = {"job.json", "stop.requested", "analysis.wav", "analysis_audio.json", "vad.json", "speaker_candidates.json", "speaker_matches.json", "speaker_decisions.json", "quality_features.json", "quality_human_assessments.json", "quality_decisions.json"}
        if {item.name for item in current.iterdir()} - allowed:
            raise QualityDecisionFailure("quality_decisions_job_invalid")
        try:
            job = jobs.validate_job(jobs.read_json(current / "job.json", "job_invalid"))
        except jobs.JobFailure as error:
            raise QualityDecisionFailure("quality_decisions_job_invalid") from error
        if job["job_id"] != job_id or job["state"] not in {"start_requested", "preparing", "recovery_required"}:
            raise QualityDecisionFailure("quality_decisions_job_invalid")
        candidate_ids, feature_fp, candidate_fp = load_formal_inputs(current, job_id)
        human_value, human_source = assessment_input(current, job_id, candidate_fp)
        decisions, source_status = combine(candidate_ids, human_value)
        if human_source["status"] == "available" and source_status == "invalid":
            human_source["status"] = "invalid"
        value = {
            "schema_version": 1, "job_id": job_id, "quality_features_fingerprint": feature_fp,
            "human_assessments_source": human_source, "contract_version": CONTRACT_VERSION,
            "candidates": decisions,
        }
        output = current / "quality_decisions.json"
        if output.exists() or output.is_symlink():
            try:
                reused = validate_output(jobs.read_json(output, "quality_decisions_reuse_invalid"), job_id, feature_fp, human_source, candidate_ids)
            except (jobs.JobFailure, QualityDecisionFailure) as error:
                raise QualityDecisionFailure("quality_decisions_reuse_invalid") from error
            return {"reused": True, "candidate_count": len(reused["candidates"])}
        emitter.emit("progress", {"stage": "quality_decisions", "status": "running"})
        validate_output(value, job_id, feature_fp, human_source, candidate_ids)
        partial = workspace / ".partial" / f"quality_decisions_{emitter.request_id}.json.partial"
        try:
            with partial.open("x", encoding="utf-8") as stream:
                json.dump(value, stream, separators=(",", ":"), sort_keys=True, allow_nan=False)
                stream.write("\n")
                stream.flush()
                os.fsync(stream.fileno())
            validate_output(jobs.read_json(partial, "quality_decisions_reuse_invalid"), job_id, feature_fp, human_source, candidate_ids)
            os.rename(partial, output)
            directory = os.open(current, os.O_RDONLY | os.O_DIRECTORY)
            try:
                os.fsync(directory)
            finally:
                os.close(directory)
        except (OSError, ValueError, jobs.JobFailure, QualityDecisionFailure) as error:
            raise QualityDecisionFailure("quality_decisions_finalization_failed") from error
        emitter.emit("progress", {"stage": "quality_decisions", "status": "completed"})
        return {"reused": False, "candidate_count": len(decisions)}
    finally:
        os.close(descriptor)


def main() -> int:
    try:
        line = sys.stdin.buffer.readline()
        if not line or sys.stdin.buffer.read(1):
            return 2
        envelope = json.loads(line)
        exact(envelope, {"protocol_version", "type", "request_id", "sequence", "payload"}, "quality_decisions_protocol_error")
        if envelope["protocol_version"] != 1 or envelope["type"] != "request" or envelope["sequence"] != 0:
            return 2
        request_id = jobs.canonical_uuid(envelope["request_id"], "quality_decisions_protocol_error")
    except (UnicodeError, json.JSONDecodeError, jobs.JobFailure, QualityDecisionFailure):
        return 2
    emitter = Emitter(request_id)
    try:
        result = run(envelope["payload"], emitter)
        emitter.emit("finished", {"outcome": "succeeded", "result": result})
    except QualityDecisionFailure as error:
        emitter.emit("error", {"code": error.code})
        emitter.emit("finished", {"outcome": "failed", "code": error.code})
    except Exception:
        emitter.emit("error", {"code": "quality_decisions_protocol_error"})
        emitter.emit("finished", {"outcome": "failed", "code": "quality_decisions_protocol_error"})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
    raise SystemExit(main())
