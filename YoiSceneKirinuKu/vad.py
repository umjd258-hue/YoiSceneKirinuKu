#!/usr/bin/env python3
from __future__ import annotations

import array
import fcntl
import json
import math
import os
import sys
import uuid
import wave
from pathlib import Path
from typing import Any

import analysis_audio as audio
import analysis_job_runner as jobs


FRAME_MS = 30
THRESHOLD_DBFS = -45.0
MIN_ACTIVE_MS = 90
SAMPLE_RATE = 16_000
FRAME_SAMPLES = SAMPLE_RATE * FRAME_MS // 1000
ERROR_CODES = {
    "vad_busy", "vad_job_invalid", "vad_input_unavailable",
    "vad_input_invalid", "vad_processing_failed", "vad_protocol_error",
}


class VADFailure(Exception):
    def __init__(self, code: str) -> None:
        if code not in ERROR_CODES:
            code = "vad_protocol_error"
        self.code = code
        super().__init__(code)


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
        raise VADFailure(code)


def validate_formal_input(current: Path, job: dict[str, Any]) -> Path:
    wav_path = current / "analysis.wav"
    metadata_path = current / "analysis_audio.json"
    wav_present = wav_path.exists() or wav_path.is_symlink()
    metadata_present = metadata_path.exists() or metadata_path.is_symlink()
    if not wav_present and not metadata_present:
        raise VADFailure("vad_input_unavailable")
    if not wav_present or not metadata_present:
        raise VADFailure("vad_input_invalid")
    try:
        verified = audio.reuse(current, job)
    except (audio.AudioFailure, jobs.JobFailure) as error:
        raise VADFailure("vad_input_invalid") from error
    if verified is None:
        raise VADFailure("vad_input_unavailable")
    return wav_path


def detect_segments(path: Path) -> list[dict[str, int]]:
    threshold = 32767 * (10 ** (THRESHOLD_DBFS / 20))
    active_frames: list[tuple[int, int]] = []
    try:
        with wave.open(str(path), "rb") as source:
            if (
                source.getnchannels() != 1
                or source.getsampwidth() != 2
                or source.getframerate() != SAMPLE_RATE
                or source.getcomptype() != "NONE"
                or source.getnframes() <= 0
            ):
                raise VADFailure("vad_input_invalid")
            total_frames = source.getnframes()
            start_sample = 0
            while start_sample < total_frames:
                raw = source.readframes(min(FRAME_SAMPLES, total_frames - start_sample))
                samples = array.array("h")
                samples.frombytes(raw)
                if sys.byteorder != "little":
                    samples.byteswap()
                if not samples:
                    raise VADFailure("vad_input_invalid")
                rms = math.sqrt(sum(sample * sample for sample in samples) / len(samples))
                end_sample = start_sample + len(samples)
                if rms >= threshold:
                    active_frames.append((start_sample, end_sample))
                start_sample = end_sample
    except VADFailure:
        raise
    except (EOFError, OSError, wave.Error) as error:
        raise VADFailure("vad_input_invalid") from error

    grouped: list[list[int]] = []
    for start_sample, end_sample in active_frames:
        start_ms = start_sample * 1000 // SAMPLE_RATE
        end_ms = math.ceil(end_sample * 1000 / SAMPLE_RATE)
        if grouped and grouped[-1][1] == start_ms:
            grouped[-1][1] = end_ms
        else:
            grouped.append([start_ms, end_ms])
    return [
        {"start_ms": start, "end_ms": end}
        for start, end in grouped
        if end - start >= MIN_ACTIVE_MS
    ]


def process(request: dict[str, Any], emitter: Emitter) -> dict[str, Any]:
    exact(request, {"protocol_version", "request_id", "workspace_root", "job_id"}, "vad_job_invalid")
    if request["protocol_version"] != 1:
        raise VADFailure("vad_job_invalid")
    request_id = jobs.canonical_uuid(request["request_id"], "vad_job_invalid")
    job_id = jobs.canonical_uuid(request["job_id"], "vad_job_invalid")
    try:
        workspace = jobs.prepare_workspace(request["workspace_root"])
    except jobs.JobFailure as error:
        raise VADFailure("vad_job_invalid") from error
    descriptor = os.open(workspace / "analysis.lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise VADFailure("vad_busy") from error
        emitter.emit("progress", {"stage": "vad", "status": "running"})
        current = workspace / "current_job"
        if not current.is_dir() or current.is_symlink():
            raise VADFailure("vad_job_invalid")
        allowed = {
            "job.json", "stop.requested", "analysis.wav", "analysis_audio.json",
            "vad.json", "speaker_candidates.json", "speaker_matches.json", "quality_features.json",
            "speaker_decisions.json", "quality_human_assessments.json", "quality_decisions.json",
        }
        if {item.name for item in current.iterdir()} - allowed:
            raise VADFailure("vad_job_invalid")
        try:
            job = jobs.validate_job(jobs.read_json(current / "job.json", "job_invalid"))
        except jobs.JobFailure as error:
            raise VADFailure("vad_job_invalid") from error
        if job["job_id"] != job_id or job["state"] not in {"start_requested", "preparing", "recovery_required"}:
            raise VADFailure("vad_job_invalid")
        wav_path = validate_formal_input(current, job)
        try:
            segments = detect_segments(wav_path)
        except VADFailure:
            raise
        except Exception as error:
            raise VADFailure("vad_processing_failed") from error
        emitter.emit("progress", {"stage": "vad", "status": "completed"})
        return {"frame_ms": FRAME_MS, "segment_count": len(segments), "segments": segments}
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
        request_id = jobs.canonical_uuid(request.get("request_id"), "vad_job_invalid")
    except (UnicodeError, json.JSONDecodeError, jobs.JobFailure):
        return 2
    emitter = Emitter(request_id)
    try:
        result = process(request, emitter)
        emitter.emit("finished", {"outcome": "succeeded", "result": result})
    except VADFailure as error:
        emitter.emit("error", {"code": error.code})
        emitter.emit("finished", {"outcome": "failed", "code": error.code})
    except Exception:
        emitter.emit("error", {"code": "vad_protocol_error"})
        emitter.emit("finished", {"outcome": "failed", "code": "vad_protocol_error"})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
