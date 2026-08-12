#!/usr/bin/env python3
from __future__ import annotations

import fcntl
import json
import math
import os
import re
import shutil
import stat
import subprocess
import sys
import uuid
import wave
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Any

import analysis_job_runner as jobs
import analysis_stopping as stopping


PROFILE = {
    "audio_stream_ordinal": 0,
    "sample_rate_hz": 16_000,
    "channels": 1,
    "sample_format": "s16le",
    "container": "wav",
}
ERROR_CODES = {
    "analysis_audio_busy", "analysis_audio_job_invalid",
    "analysis_audio_source_unavailable", "analysis_audio_source_changed",
    "analysis_audio_probe_failed", "analysis_audio_duration_invalid",
    "analysis_audio_insufficient_space", "analysis_audio_ffmpeg_failed",
    "analysis_audio_invalid", "analysis_audio_finalization_failed",
    "analysis_audio_reuse_invalid", "analysis_audio_protocol_error",
}
AUDIO_PARTIAL = re.compile(
    r"analysis_[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
    r"\.(?:wav|json)\.partial\Z"
)


class AudioFailure(Exception):
    def __init__(self, code: str) -> None:
        super().__init__(code)
        self.code = code


class AudioStopped(Exception):
    def __init__(self, job_id: str) -> None:
        super().__init__(job_id)
        self.job_id = job_id


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
        sys.stdout.write(json.dumps(event, ensure_ascii=False, separators=(",", ":")) + "\n")
        sys.stdout.flush()


def exact(value: dict[str, Any], keys: set[str], code: str) -> None:
    if set(value) != keys:
        raise AudioFailure(code)


def bundled_executable(raw: Any, raw_bundle: Any, expected_name: str) -> Path:
    if (
        not isinstance(raw, str) or not raw.startswith("/")
        or not isinstance(raw_bundle, str) or not raw_bundle.startswith("/")
    ):
        raise AudioFailure("analysis_audio_job_invalid")
    path = Path(raw)
    try:
        bundle = Path(raw_bundle).resolve(strict=True)
        expected = bundle / "Contents" / "MacOS" / expected_name
        metadata = path.lstat()
        resolved = path.resolve(strict=True)
        expected_resolved = expected.resolve(strict=True)
    except OSError as error:
        raise AudioFailure("analysis_audio_job_invalid") from error
    if (
        not bundle.is_dir()
        or path.is_symlink()
        or not stat.S_ISREG(metadata.st_mode)
        or not os.access(resolved, os.X_OK)
        or resolved != expected_resolved
    ):
        raise AudioFailure("analysis_audio_job_invalid")
    return resolved


def source_duration(ffprobe: Path, source: Path) -> tuple[int, int]:
    arguments = [
        str(ffprobe), "-v", "error", "-select_streams", "a:0",
        "-show_entries", "stream=index,duration:format=duration", "-of", "json", str(source),
    ]
    try:
        completed = subprocess.run(
            arguments, shell=False, capture_output=True, timeout=20, check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise AudioFailure("analysis_audio_probe_failed") from error
    if completed.returncode != 0:
        raise AudioFailure("analysis_audio_probe_failed")
    try:
        value = json.loads(completed.stdout)
        streams = value["streams"]
        if not isinstance(streams, list) or len(streams) != 1:
            raise AudioFailure("analysis_audio_probe_failed")
        stream = streams[0]
        if not isinstance(stream, dict) or isinstance(stream.get("index"), bool):
            raise AudioFailure("analysis_audio_probe_failed")
        stream_index = int(stream["index"])
        raw_duration = stream.get("duration") or value.get("format", {}).get("duration")
        duration = Decimal(str(raw_duration))
    except AudioFailure:
        raise
    except (KeyError, TypeError, ValueError, InvalidOperation, json.JSONDecodeError) as error:
        raise AudioFailure("analysis_audio_duration_invalid") from error
    if not duration.is_finite() or duration <= 0:
        raise AudioFailure("analysis_audio_duration_invalid")
    duration_ms = int(duration * 1000)
    if duration_ms <= 0:
        raise AudioFailure("analysis_audio_duration_invalid")
    return stream_index, duration_ms


def required_bytes(duration_ms: int) -> int:
    frames = math.ceil(Decimal(duration_ms) * PROFILE["sample_rate_hz"] / 1000)
    return int(frames) * PROFILE["channels"] * 2 + 1024 * 1024


def validate_wav(path: Path) -> dict[str, int]:
    try:
        metadata = path.lstat()
        if not stat.S_ISREG(metadata.st_mode) or path.is_symlink() or metadata.st_size <= 44:
            raise AudioFailure("analysis_audio_invalid")
        with wave.open(str(path), "rb") as audio:
            if (
                audio.getframerate() != PROFILE["sample_rate_hz"]
                or audio.getnchannels() != PROFILE["channels"]
                or audio.getsampwidth() != 2
                or audio.getcomptype() != "NONE"
                or audio.getnframes() <= 0
            ):
                raise AudioFailure("analysis_audio_invalid")
            frames = audio.getnframes()
    except AudioFailure:
        raise
    except (OSError, EOFError, wave.Error) as error:
        raise AudioFailure("analysis_audio_invalid") from error
    duration_ms = frames * 1000 // PROFILE["sample_rate_hz"]
    if duration_ms <= 0:
        raise AudioFailure("analysis_audio_invalid")
    return {"frame_count": frames, "duration_ms": duration_ms}


def validate_metadata(value: Any, job: dict[str, Any], wav: dict[str, int]) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise AudioFailure("analysis_audio_reuse_invalid")
    exact(value, {
        "schema_version", "job_id", "source_fingerprint", "profile",
        "selected_stream_index", "frame_count", "duration_ms",
    }, "analysis_audio_reuse_invalid")
    if (
        value["schema_version"] != 1
        or value["job_id"] != job["job_id"]
        or value["source_fingerprint"] != job["source"]["fingerprint"]
        or value["profile"] != PROFILE
        or not isinstance(value["selected_stream_index"], int)
        or isinstance(value["selected_stream_index"], bool)
        or value["frame_count"] != wav["frame_count"]
        or value["duration_ms"] != wav["duration_ms"]
    ):
        raise AudioFailure("analysis_audio_reuse_invalid")
    return value


def remove_known(path: Path) -> None:
    if not path.exists() and not path.is_symlink():
        return
    metadata = path.lstat()
    if not stat.S_ISREG(metadata.st_mode) or path.is_symlink():
        raise AudioFailure("analysis_audio_reuse_invalid")
    path.unlink()


def reconcile(workspace: Path, current: Path) -> None:
    partial = workspace / ".partial"
    for item in partial.iterdir():
        if AUDIO_PARTIAL.fullmatch(item.name):
            remove_known(item)
    wav = current / "analysis.wav"
    metadata = current / "analysis_audio.json"
    wav_present = wav.exists() or wav.is_symlink()
    metadata_present = metadata.exists() or metadata.is_symlink()
    if wav_present != metadata_present:
        remove_known(wav)
        remove_known(metadata)


def reuse(current: Path, job: dict[str, Any]) -> dict[str, Any] | None:
    wav_path = current / "analysis.wav"
    metadata_path = current / "analysis_audio.json"
    wav_present = wav_path.exists() or wav_path.is_symlink()
    metadata_present = metadata_path.exists() or metadata_path.is_symlink()
    if not wav_present and not metadata_present:
        return None
    try:
        wav = validate_wav(wav_path)
        metadata = validate_metadata(
            jobs.read_json(metadata_path, "analysis_audio_reuse_invalid"), job, wav,
        )
        if jobs.source_fingerprint(Path(job["source"]["path"])) != job["source"]["fingerprint"]:
            raise AudioFailure("analysis_audio_source_changed")
    except jobs.JobFailure as error:
        raise AudioFailure("analysis_audio_reuse_invalid") from error
    return {"reused": True, **wav, "selected_stream_index": metadata["selected_stream_index"]}


def generate(
    request: dict[str, Any], emitter: Emitter, available_bytes: int | None = None,
) -> dict[str, Any]:
    exact(request, {
        "protocol_version", "request_id", "workspace_root", "job_id",
        "bundle_root", "ffmpeg_path", "ffprobe_path",
    }, "analysis_audio_job_invalid")
    if request["protocol_version"] != 1:
        raise AudioFailure("analysis_audio_job_invalid")
    request_id = jobs.canonical_uuid(request["request_id"], "analysis_audio_job_invalid")
    job_id = jobs.canonical_uuid(request["job_id"], "analysis_audio_job_invalid")
    ffmpeg = bundled_executable(request["ffmpeg_path"], request["bundle_root"], "ffmpeg")
    ffprobe = bundled_executable(request["ffprobe_path"], request["bundle_root"], "ffprobe")
    try:
        workspace = jobs.prepare_workspace(request["workspace_root"])
    except jobs.JobFailure as error:
        raise AudioFailure("analysis_audio_job_invalid") from error
    descriptor = os.open(workspace / "analysis.lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise AudioFailure("analysis_audio_busy") from error
        emitter.emit("progress", {"stage": "analysis_audio", "status": "running"})
        current = workspace / "current_job"
        if not current.is_dir() or current.is_symlink():
            raise AudioFailure("analysis_audio_job_invalid")
        allowed = {
            "job.json", "stop.requested", "analysis.wav", "analysis_audio.json",
            "vad.json", "speaker_candidates.json", "speaker_matches.json", "quality_features.json",
            "speaker_decisions.json", "quality_human_assessments.json", "quality_decisions.json", "result.json",
        }
        if {item.name for item in current.iterdir()} - allowed:
            raise AudioFailure("analysis_audio_job_invalid")
        try:
            job = jobs.validate_job(jobs.read_json(current / "job.json", "job_invalid"))
        except jobs.JobFailure as error:
            raise AudioFailure("analysis_audio_job_invalid") from error
        if job["job_id"] != job_id or job["state"] not in {
            "start_requested", "preparing", "running", "stop_requested", "recovery_required",
        }:
            raise AudioFailure("analysis_audio_job_invalid")
        pending_stop = stopping.requested(current, job_id)
        if pending_stop is not None:
            emitter.emit("progress", {"stage": "analysis_stop", "status": "stop_requested_detected"})
            emitter.emit("progress", {"stage": "analysis_stop", "status": "child_exit_observed"})
            stored = stopping.complete(workspace, current, pending_stop)
            emitter.emit("progress", {"stage": "analysis_stop", "status": "post_stop_state_verified"})
            raise AudioStopped(stored["job_id"])
        reconcile(workspace, current)
        reused = reuse(current, job)
        if reused is not None:
            emitter.emit("progress", {"stage": "analysis_audio", "status": "completed"})
            return reused
        source = Path(job["source"]["path"])
        try:
            before = jobs.source_fingerprint(source)
        except jobs.JobFailure as error:
            raise AudioFailure("analysis_audio_source_unavailable") from error
        if before != job["source"]["fingerprint"]:
            raise AudioFailure("analysis_audio_source_changed")
        stream_index, source_duration_ms = source_duration(ffprobe, source)
        free = available_bytes if available_bytes is not None else shutil.disk_usage(workspace).free
        if free < required_bytes(source_duration_ms):
            raise AudioFailure("analysis_audio_insufficient_space")
        wav_partial = workspace / ".partial" / f"analysis_{request_id}.wav.partial"
        json_partial = workspace / ".partial" / f"analysis_{request_id}.json.partial"
        arguments = [
            str(ffmpeg), "-nostdin", "-hide_banner", "-loglevel", "error", "-n",
            "-i", str(source), "-map", "0:a:0", "-vn", "-sn", "-dn",
            "-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le", "-f", "wav", str(wav_partial),
        ]
        try:
            stop_events: list[str] = []
            completed, stopped_job = stopping.run_process(
                arguments, workspace, current, job_id, stop_events.append,
            )
        except (OSError, stopping.StopFailure, subprocess.TimeoutExpired) as error:
            raise AudioFailure("analysis_audio_ffmpeg_failed") from error
        if stopped_job is not None:
            for status in stop_events:
                emitter.emit("progress", {"stage": "analysis_stop", "status": status})
            raise AudioStopped(stopped_job["job_id"])
        assert completed is not None
        if completed.returncode != 0:
            raise AudioFailure("analysis_audio_ffmpeg_failed")
        wav = validate_wav(wav_partial)
        try:
            after = jobs.source_fingerprint(source)
        except jobs.JobFailure as error:
            raise AudioFailure("analysis_audio_source_unavailable") from error
        if before != after:
            raise AudioFailure("analysis_audio_source_changed")
        metadata = {
            "schema_version": 1,
            "job_id": job_id,
            "source_fingerprint": before,
            "profile": PROFILE,
            "selected_stream_index": stream_index,
            **wav,
        }
        try:
            with json_partial.open("x", encoding="utf-8") as output:
                json.dump(metadata, output, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
                output.write("\n")
                output.flush()
                os.fsync(output.fileno())
            validate_metadata(jobs.read_json(json_partial, "analysis_audio_invalid"), job, wav)
            os.rename(json_partial, current / "analysis_audio.json")
            os.rename(wav_partial, current / "analysis.wav")
            directory = os.open(current, os.O_RDONLY | os.O_DIRECTORY)
            try:
                os.fsync(directory)
            finally:
                os.close(directory)
        except (OSError, jobs.JobFailure) as error:
            raise AudioFailure("analysis_audio_finalization_failed") from error
        final_wav = validate_wav(current / "analysis.wav")
        validate_metadata(
            jobs.read_json(current / "analysis_audio.json", "analysis_audio_invalid"), job, final_wav,
        )
        emitter.emit("progress", {"stage": "analysis_audio", "status": "completed"})
        return {"reused": False, **final_wav, "selected_stream_index": stream_index}
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
        request_id = jobs.canonical_uuid(request.get("request_id"), "analysis_audio_job_invalid")
    except (UnicodeError, json.JSONDecodeError, jobs.JobFailure):
        return 2
    emitter = Emitter(request_id)
    try:
        result = generate(request, emitter)
        emitter.emit("finished", {"outcome": "succeeded", "result": result})
    except AudioStopped as stopped:
        emitter.emit("finished", {
            "outcome": "stopped",
            "result": {"job_id": stopped.job_id, "state": "stopped", "reason": "user_requested"},
        })
    except AudioFailure as error:
        emitter.emit("error", {"code": error.code})
        emitter.emit("finished", {"outcome": "failed", "code": error.code})
    except Exception:
        emitter.emit("error", {"code": "analysis_audio_protocol_error"})
        emitter.emit("finished", {"outcome": "failed", "code": "analysis_audio_protocol_error"})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
