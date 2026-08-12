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
import quality_decisions as quality
import speaker_decisions as speakers


CONTRACT_VERSION = "stage18-result-v1"
ERROR_CODES = {
    "result_busy", "result_job_invalid", "result_input_invalid",
    "result_finalization_failed", "result_reuse_invalid", "result_protocol_error",
}


class ResultFailure(Exception):
    def __init__(self, code: str) -> None:
        self.code = code if code in ERROR_CODES else "result_protocol_error"
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
        raise ResultFailure(code)


def validate_output(value: Any, job_id: str, sources: dict[str, Any]) -> dict[str, Any]:
    code = "result_reuse_invalid"
    exact(value, {"schema_version", "job_id", "contract_version", "sources", "candidates"}, code)
    if value["schema_version"] != 1 or value["job_id"] != job_id or value["contract_version"] != CONTRACT_VERSION or value["sources"] != sources:
        raise ResultFailure(code)
    items = value["candidates"]
    if not isinstance(items, list):
        raise ResultFailure(code)
    prior: tuple[int, int, str] | None = None
    identifiers: set[str] = set()
    for item in items:
        exact(item, {"candidate_id", "start_ms", "end_ms", "match", "character_id", "match_reason", "top_similarity", "quality", "quality_reasons"}, code)
        identifier, start, end = item["candidate_id"], item["start_ms"], item["end_ms"]
        if not isinstance(identifier, str) or identifier in identifiers or not isinstance(start, int) or isinstance(start, bool) or not isinstance(end, int) or isinstance(end, bool) or start < 0 or end <= start:
            raise ResultFailure(code)
        key = (start, end, identifier)
        if prior is not None and key <= prior:
            raise ResultFailure(code)
        if item["match"] not in {"matched", "unknown"} or item["quality"] not in quality.LABELS:
            raise ResultFailure(code)
        if (item["match"] == "matched") != isinstance(item["character_id"], str):
            raise ResultFailure(code)
        if not isinstance(item["match_reason"], str) or not isinstance(item["quality_reasons"], list) or any(not isinstance(reason, str) for reason in item["quality_reasons"]):
            raise ResultFailure(code)
        score = item["top_similarity"]
        if score is not None and (not isinstance(score, (int, float)) or isinstance(score, bool) or not -1 <= score <= 1):
            raise ResultFailure(code)
        identifiers.add(identifier)
        prior = key
    return value


def load_inputs(current: Path, job_id: str) -> tuple[list[dict[str, Any]], list[dict[str, Any]], list[dict[str, Any]], dict[str, Any]]:
    try:
        analysis_fp = candidates.analysis_fingerprint(current)
        vad_value = candidates.validate_vad(jobs.read_json(current / "vad.json", "candidate_vad_invalid"), job_id, analysis_fp)
        vad_fp = candidates.file_fingerprint(current / "vad.json", "candidate_vad_invalid")
        candidate_path = current / "speaker_candidates.json"
        candidate_value = candidates.validate_candidates(jobs.read_json(candidate_path, "candidate_reuse_invalid"), job_id, vad_fp, vad_value["audio_duration_ms"])
        candidate_fp = candidates.file_fingerprint(candidate_path, "candidate_reuse_invalid")
        candidate_ids = [item["candidate_id"] for item in candidate_value["candidates"]]
        speaker_path = current / "speaker_decisions.json"
        speaker_fp = candidates.file_fingerprint(speaker_path, "speaker_decisions_reuse_invalid")
        speaker_value = speakers.validate_output(jobs.read_json(speaker_path, "speaker_decisions_reuse_invalid"), job_id, candidates.file_fingerprint(current / "speaker_matches.json", "speaker_decisions_input_invalid"), candidate_ids)
        feature_path = current / "quality_features.json"
        feature_fp = candidates.file_fingerprint(feature_path, "quality_features_reuse_invalid")
        quality_path = current / "quality_decisions.json"
        quality_fp = candidates.file_fingerprint(quality_path, "quality_decisions_reuse_invalid")
        quality_value = jobs.read_json(quality_path, "quality_decisions_reuse_invalid")
        exact(quality_value, {"schema_version", "job_id", "quality_features_fingerprint", "human_assessments_source", "contract_version", "candidates"}, "result_input_invalid")
        if quality_value["schema_version"] != 1 or quality_value["job_id"] != job_id or quality_value["quality_features_fingerprint"] != feature_fp or quality_value["contract_version"] != quality.CONTRACT_VERSION:
            raise ResultFailure("result_input_invalid")
        quality.validate_output(quality_value, job_id, feature_fp, quality_value["human_assessments_source"], candidate_ids)
    except (jobs.JobFailure, candidates.CandidateFailure, speakers.DecisionFailure, quality.QualityDecisionFailure, ResultFailure) as error:
        raise ResultFailure("result_input_invalid") from error
    sources = {"speaker_candidates": candidate_fp, "speaker_decisions": speaker_fp, "quality_decisions": quality_fp}
    return candidate_value["candidates"], speaker_value["candidates"], quality_value["candidates"], sources


def generate(candidate_items: list[dict[str, Any]], speaker_items: list[dict[str, Any]], quality_items: list[dict[str, Any]]) -> list[dict[str, Any]]:
    speakers_by_id = {item["candidate_id"]: item for item in speaker_items}
    quality_by_id = {item["candidate_id"]: item for item in quality_items}
    if set(speakers_by_id) != {item["candidate_id"] for item in candidate_items} or set(quality_by_id) != set(speakers_by_id):
        raise ResultFailure("result_input_invalid")
    result = []
    for candidate in candidate_items:
        identifier = candidate["candidate_id"]
        speaker = speakers_by_id[identifier]
        quality_item = quality_by_id[identifier]
        reasons = sorted(set(quality_item["automatic_reason_codes"] + quality_item["human_reason_codes"]))
        result.append({
            "candidate_id": identifier, "start_ms": candidate["start_ms"], "end_ms": candidate["end_ms"],
            "match": speaker["decision"], "character_id": speaker["character_id"],
            "match_reason": speaker["reason"], "top_similarity": speaker["top_similarity"],
            "quality": quality_item["label"], "quality_reasons": reasons,
        })
    return sorted(result, key=lambda item: (item["start_ms"], item["end_ms"], item["candidate_id"]))


def run(payload: dict[str, Any], emitter: Emitter) -> dict[str, Any]:
    exact(payload, {"workspace_root", "job_id"}, "result_job_invalid")
    try:
        job_id = jobs.canonical_uuid(payload["job_id"], "result_job_invalid")
        workspace = jobs.prepare_workspace(payload["workspace_root"])
    except jobs.JobFailure as error:
        raise ResultFailure("result_job_invalid") from error
    descriptor = os.open(workspace / "analysis.lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise ResultFailure("result_busy") from error
        current = workspace / "current_job"
        if not current.is_dir() or current.is_symlink() or {item.name for item in current.iterdir()} - (jobs.JOB_DIRECTORY_ITEMS | {"result.json"}):
            raise ResultFailure("result_job_invalid")
        try:
            job = jobs.validate_job(jobs.read_json(current / "job.json", "job_invalid"))
        except jobs.JobFailure as error:
            raise ResultFailure("result_job_invalid") from error
        if job["job_id"] != job_id or job["state"] not in {"start_requested", "preparing", "recovery_required"}:
            raise ResultFailure("result_job_invalid")
        candidate_items, speaker_items, quality_items, sources = load_inputs(current, job_id)
        output_path = current / "result.json"
        if output_path.exists() or output_path.is_symlink():
            try:
                reused = validate_output(jobs.read_json(output_path, "result_reuse_invalid"), job_id, sources)
            except (jobs.JobFailure, ResultFailure) as error:
                raise ResultFailure("result_reuse_invalid") from error
            return {"reused": True, "candidate_count": len(reused["candidates"])}
        emitter.emit("progress", {"stage": "result_generation", "status": "running"})
        value = {"schema_version": 1, "job_id": job_id, "contract_version": CONTRACT_VERSION, "sources": sources, "candidates": generate(candidate_items, speaker_items, quality_items)}
        validate_output(value, job_id, sources)
        partial = workspace / ".partial" / f"result_{emitter.request_id}.json.partial"
        try:
            with partial.open("x", encoding="utf-8") as stream:
                json.dump(value, stream, separators=(",", ":"), sort_keys=True, allow_nan=False)
                stream.write("\n"); stream.flush(); os.fsync(stream.fileno())
            validate_output(jobs.read_json(partial, "result_reuse_invalid"), job_id, sources)
            os.rename(partial, output_path)
            directory = os.open(current, os.O_RDONLY | os.O_DIRECTORY)
            try: os.fsync(directory)
            finally: os.close(directory)
        except (OSError, ValueError, jobs.JobFailure, ResultFailure) as error:
            raise ResultFailure("result_finalization_failed") from error
        emitter.emit("progress", {"stage": "result_generation", "status": "completed"})
        return {"reused": False, "candidate_count": len(value["candidates"])}
    finally:
        os.close(descriptor)


def main() -> int:
    try:
        line = sys.stdin.buffer.readline()
        if not line or sys.stdin.buffer.read(1): return 2
        envelope = json.loads(line)
        exact(envelope, {"protocol_version", "type", "request_id", "sequence", "payload"}, "result_protocol_error")
        if envelope["protocol_version"] != 1 or envelope["type"] != "request" or envelope["sequence"] != 0: return 2
        request_id = jobs.canonical_uuid(envelope["request_id"], "result_protocol_error")
    except (UnicodeError, json.JSONDecodeError, jobs.JobFailure, ResultFailure):
        return 2
    emitter = Emitter(request_id)
    try:
        result = run(envelope["payload"], emitter)
        emitter.emit("finished", {"outcome": "succeeded", "result": result})
    except ResultFailure as error:
        emitter.emit("error", {"code": error.code})
        emitter.emit("finished", {"outcome": "failed", "code": error.code})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
