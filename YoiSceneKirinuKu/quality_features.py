#!/usr/bin/env python3
from __future__ import annotations

import array
import fcntl
import json
import math
import os
import sys
import wave
from pathlib import Path
from typing import Any

import analysis_job_runner as jobs
import candidate_generation as candidates


PROFILE = {
    "sample_rate_hz": 16_000,
    "clipping_level": 32767,
    "short_interval_minimum_ms": 3_000,
    "maximum_interval_ms": 30_000,
    "maximum_samples_per_candidate": 480_000,
    "processing_passes_per_candidate": 1,
}
UNAVAILABLE_REASON = "not_observable_without_dedicated_model"
ERROR_CODES = {
    "quality_features_busy", "quality_features_job_invalid", "quality_features_input_unavailable",
    "quality_features_input_invalid", "quality_features_processing_failed",
    "quality_features_finalization_failed", "quality_features_reuse_invalid",
    "quality_features_protocol_error",
}


class QualityFeatureFailure(Exception):
    def __init__(self, code: str) -> None:
        self.code = code if code in ERROR_CODES else "quality_features_protocol_error"
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
        raise QualityFeatureFailure(code)


def dbfs(sum_squares: int, count: int) -> float | None:
    if count <= 0 or sum_squares <= 0:
        return None
    return round(20.0 * math.log10(math.sqrt(sum_squares / count) / 32768.0), 6)


def unavailable(reason: str = UNAVAILABLE_REASON) -> dict[str, Any]:
    return {"status": "unavailable", "reason": reason, "values": {}}


def intersections(start_ms: int, end_ms: int, segments: list[dict[str, int]]) -> list[tuple[int, int]]:
    return [
        (max(start_ms, item["start_ms"]), min(end_ms, item["end_ms"]))
        for item in segments
        if item["end_ms"] > start_ms and item["start_ms"] < end_ms
    ]


def measure(path: Path, candidate: dict[str, Any], segments: list[dict[str, int]]) -> dict[str, Any]:
    start_ms = candidate["start_ms"]
    end_ms = candidate["end_ms"]
    duration_ms = candidate["duration_ms"]
    if not PROFILE["short_interval_minimum_ms"] <= duration_ms <= PROFILE["maximum_interval_ms"]:
        raise QualityFeatureFailure("quality_features_input_invalid")
    active = intersections(start_ms, end_ms, segments)
    speech_ms = sum(end - start for start, end in active)
    try:
        with wave.open(str(path), "rb") as source:
            if (source.getnchannels(), source.getsampwidth(), source.getframerate(), source.getcomptype()) != (1, 2, 16_000, "NONE"):
                raise QualityFeatureFailure("quality_features_input_invalid")
            source.setpos(start_ms * 16)
            raw = source.readframes(duration_ms * 16)
    except QualityFeatureFailure:
        raise
    except (EOFError, OSError, wave.Error) as error:
        raise QualityFeatureFailure("quality_features_input_unavailable") from error
    samples = array.array("h")
    samples.frombytes(raw)
    if sys.byteorder != "little":
        samples.byteswap()
    if len(samples) != duration_ms * 16:
        raise QualityFeatureFailure("quality_features_input_invalid")

    total_squares = speech_squares = nonspeech_squares = 0
    speech_count = nonspeech_count = clipped = crossings = 0
    peak = 0
    segment_index = 0
    previous = None
    for offset, sample in enumerate(samples):
        absolute_ms = start_ms + offset // 16
        while segment_index < len(active) and absolute_ms >= active[segment_index][1]:
            segment_index += 1
        is_speech = segment_index < len(active) and active[segment_index][0] <= absolute_ms < active[segment_index][1]
        square = sample * sample
        total_squares += square
        peak = max(peak, abs(sample))
        clipped += int(abs(sample) >= PROFILE["clipping_level"])
        if previous is not None and (sample < 0 <= previous or previous < 0 <= sample):
            crossings += 1
        previous = sample
        if is_speech:
            speech_squares += square
            speech_count += 1
        else:
            nonspeech_squares += square
            nonspeech_count += 1

    overall_dbfs = dbfs(total_squares, len(samples))
    speech_dbfs = dbfs(speech_squares, speech_count)
    nonspeech_dbfs = dbfs(nonspeech_squares, nonspeech_count)
    clarity = {
        "status": "available", "reason": None,
        "values": {
            "speech_coverage_ratio": round(speech_ms / duration_ms, 6),
            "rms_dbfs": overall_dbfs,
            "peak_dbfs": None if peak == 0 else round(20.0 * math.log10(peak / 32768.0), 6),
            "clipping_ratio": round(clipped / len(samples), 9),
            "zero_crossing_rate": round(crossings / max(1, len(samples) - 1), 9),
        },
    }
    if nonspeech_dbfs is None or speech_dbfs is None:
        noise = unavailable("insufficient_speech_or_nonspeech_frames")
    else:
        noise = {
            "status": "available", "reason": None,
            "values": {
                "non_speech_rms_dbfs": nonspeech_dbfs,
                "speech_to_nonspeech_db": round(speech_dbfs - nonspeech_dbfs, 6),
            },
        }
    return {
        "candidate_id": candidate["candidate_id"], "duration_ms": duration_ms,
        "clarity": clarity, "other_speaker": unavailable(), "bgm": unavailable(),
        "sound_effect": unavailable(), "noise": noise,
    }


def validate_output(value: Any, job_id: str, analysis_fp: dict[str, Any], vad_fp: dict[str, Any], candidate_fp: dict[str, Any], ids: list[str]) -> dict[str, Any]:
    code = "quality_features_reuse_invalid"
    exact(value, {"schema_version", "job_id", "analysis_audio_fingerprint", "vad_fingerprint", "speaker_candidates_fingerprint", "profile", "candidates"}, code)
    if value["schema_version"] != 1 or value["job_id"] != job_id or value["analysis_audio_fingerprint"] != analysis_fp or value["vad_fingerprint"] != vad_fp or value["speaker_candidates_fingerprint"] != candidate_fp or value["profile"] != PROFILE:
        raise QualityFeatureFailure(code)
    items = value["candidates"]
    if not isinstance(items, list) or [item.get("candidate_id") if isinstance(item, dict) else None for item in items] != ids:
        raise QualityFeatureFailure(code)
    for item in items:
        exact(item, {"candidate_id", "duration_ms", "clarity", "other_speaker", "bgm", "sound_effect", "noise"}, code)
        if not isinstance(item["duration_ms"], int) or not 3_000 <= item["duration_ms"] <= 30_000:
            raise QualityFeatureFailure(code)
        for name in ("clarity", "other_speaker", "bgm", "sound_effect", "noise"):
            feature = item[name]
            exact(feature, {"status", "reason", "values"}, code)
            if feature["status"] not in {"available", "unavailable"} or not isinstance(feature["values"], dict):
                raise QualityFeatureFailure(code)
            if feature["status"] == "available" and feature["reason"] is not None:
                raise QualityFeatureFailure(code)
            if feature["status"] == "unavailable" and not isinstance(feature["reason"], str):
                raise QualityFeatureFailure(code)
            for number in feature["values"].values():
                if number is not None and (not isinstance(number, (int, float)) or isinstance(number, bool) or not math.isfinite(number)):
                    raise QualityFeatureFailure(code)
    return value


def run(payload: dict[str, Any], emitter: Emitter) -> dict[str, Any]:
    exact(payload, {"workspace_root", "job_id"}, "quality_features_job_invalid")
    try:
        job_id = jobs.canonical_uuid(payload["job_id"], "quality_features_job_invalid")
        workspace = jobs.prepare_workspace(payload["workspace_root"])
    except jobs.JobFailure as error:
        raise QualityFeatureFailure("quality_features_job_invalid") from error
    descriptor = os.open(workspace / "analysis.lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise QualityFeatureFailure("quality_features_busy") from error
        current = workspace / "current_job"
        if not current.is_dir() or current.is_symlink():
            raise QualityFeatureFailure("quality_features_job_invalid")
        allowed = {"job.json", "stop.requested", "analysis.wav", "analysis_audio.json", "vad.json", "speaker_candidates.json", "speaker_matches.json", "speaker_decisions.json", "quality_features.json", "quality_human_assessments.json", "quality_decisions.json"}
        if {item.name for item in current.iterdir()} - allowed:
            raise QualityFeatureFailure("quality_features_job_invalid")
        try:
            job = jobs.validate_job(jobs.read_json(current / "job.json", "job_invalid"))
            analysis_fp = candidates.analysis_fingerprint(current)
            vad_value = candidates.validate_vad(jobs.read_json(current / "vad.json", "candidate_vad_invalid"), job_id, analysis_fp)
            vad_fp = candidates.file_fingerprint(current / "vad.json", "candidate_vad_invalid")
            candidate_value = candidates.validate_candidates(jobs.read_json(current / "speaker_candidates.json", "candidate_reuse_invalid"), job_id, vad_fp, vad_value["audio_duration_ms"])
            candidate_fp = candidates.file_fingerprint(current / "speaker_candidates.json", "candidate_reuse_invalid")
        except (jobs.JobFailure, candidates.CandidateFailure) as error:
            raise QualityFeatureFailure("quality_features_input_invalid") from error
        if job["job_id"] != job_id or job["state"] not in {"start_requested", "preparing", "recovery_required"}:
            raise QualityFeatureFailure("quality_features_job_invalid")
        ids = [item["candidate_id"] for item in candidate_value["candidates"]]
        output = current / "quality_features.json"
        if output.exists() or output.is_symlink():
            try:
                reused = validate_output(jobs.read_json(output, "quality_features_reuse_invalid"), job_id, analysis_fp, vad_fp, candidate_fp, ids)
            except (jobs.JobFailure, QualityFeatureFailure) as error:
                raise QualityFeatureFailure("quality_features_reuse_invalid") from error
            return {"reused": True, "candidate_count": len(reused["candidates"])}
        emitter.emit("progress", {"stage": "quality_features", "status": "running"})
        measured = []
        for index, candidate in enumerate(candidate_value["candidates"]):
            measured.append(measure(current / "analysis.wav", candidate, vad_value["segments"]))
            emitter.emit("progress", {"stage": "quality_features", "status": "processing", "completed_count": index + 1, "total_count": len(ids)})
        value = {
            "schema_version": 1, "job_id": job_id, "analysis_audio_fingerprint": analysis_fp,
            "vad_fingerprint": vad_fp, "speaker_candidates_fingerprint": candidate_fp,
            "profile": PROFILE, "candidates": measured,
        }
        validate_output(value, job_id, analysis_fp, vad_fp, candidate_fp, ids)
        partial = workspace / ".partial" / f"quality_features_{emitter.request_id}.json.partial"
        try:
            with partial.open("x", encoding="utf-8") as stream:
                json.dump(value, stream, separators=(",", ":"), sort_keys=True, allow_nan=False)
                stream.write("\n")
                stream.flush()
                os.fsync(stream.fileno())
            validate_output(jobs.read_json(partial, "quality_features_reuse_invalid"), job_id, analysis_fp, vad_fp, candidate_fp, ids)
            os.rename(partial, output)
            directory = os.open(current, os.O_RDONLY | os.O_DIRECTORY)
            try:
                os.fsync(directory)
            finally:
                os.close(directory)
        except (OSError, ValueError, jobs.JobFailure, QualityFeatureFailure) as error:
            raise QualityFeatureFailure("quality_features_finalization_failed") from error
        emitter.emit("progress", {"stage": "quality_features", "status": "completed"})
        return {"reused": False, "candidate_count": len(measured)}
    finally:
        os.close(descriptor)


def main() -> int:
    try:
        line = sys.stdin.buffer.readline()
        if not line or sys.stdin.buffer.read(1):
            return 2
        envelope = json.loads(line)
        exact(envelope, {"protocol_version", "type", "request_id", "sequence", "payload"}, "quality_features_protocol_error")
        if envelope["protocol_version"] != 1 or envelope["type"] != "request" or envelope["sequence"] != 0:
            return 2
        request_id = jobs.canonical_uuid(envelope["request_id"], "quality_features_protocol_error")
    except (UnicodeError, json.JSONDecodeError, jobs.JobFailure, QualityFeatureFailure):
        return 2
    emitter = Emitter(request_id)
    try:
        result = run(envelope["payload"], emitter)
        emitter.emit("finished", {"outcome": "succeeded", "result": result})
    except QualityFeatureFailure as error:
        emitter.emit("error", {"code": error.code})
        emitter.emit("finished", {"outcome": "failed", "code": error.code})
    except Exception:
        emitter.emit("error", {"code": "quality_features_protocol_error"})
        emitter.emit("finished", {"outcome": "failed", "code": "quality_features_protocol_error"})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
