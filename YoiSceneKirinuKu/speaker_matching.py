#!/usr/bin/env python3
from __future__ import annotations

import fcntl
import functools
import hashlib
import json
import math
import os
import stat
import sys
import wave
from pathlib import Path
from typing import Any, Callable

import numpy as np

import analysis_job_runner as jobs
import candidate_generation as candidate_generation
import character_registration as registration


MODEL = {
    "model_id": registration.MODEL_ID,
    "model_revision": registration.MODEL_REVISION,
    "dimension": registration.EMBEDDING_DIMENSION,
    "dtype": "float32",
    "normalization": "l2",
}
ERROR_CODES = {
    "speaker_matching_busy", "speaker_matching_job_invalid", "speaker_matching_input_unavailable",
    "speaker_matching_candidates_invalid", "speaker_matching_character_invalid",
    "speaker_matching_model_unavailable", "speaker_matching_embedding_failed",
    "speaker_matching_embedding_invalid", "speaker_matching_finalization_failed",
    "speaker_matching_reuse_invalid", "speaker_matching_protocol_error",
}


class MatchingFailure(Exception):
    def __init__(self, code: str) -> None:
        self.code = code if code in ERROR_CODES else "speaker_matching_protocol_error"
        super().__init__(self.code)


class Emitter:
    def __init__(self, request_id: str) -> None:
        self.request_id = request_id
        self.sequence = 0

    def emit(self, event_type: str, payload: dict[str, Any]) -> None:
        self.sequence += 1
        event = {
            "protocol_version": 1, "type": event_type, "request_id": self.request_id,
            "sequence": self.sequence, "payload": payload,
        }
        print(json.dumps(event, ensure_ascii=False, separators=(",", ":"), allow_nan=False), flush=True)


def exact(value: Any, keys: set[str], code: str) -> None:
    if not isinstance(value, dict) or set(value) != keys:
        raise MatchingFailure(code)


def fingerprint(path: Path, code: str) -> dict[str, Any]:
    try:
        metadata = path.lstat()
        if not stat.S_ISREG(metadata.st_mode) or path.is_symlink() or metadata.st_size <= 0:
            raise MatchingFailure(code)
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        after = path.lstat()
    except MatchingFailure:
        raise
    except OSError as error:
        raise MatchingFailure(code) from error
    if (metadata.st_dev, metadata.st_ino, metadata.st_size, metadata.st_mtime_ns) != (
        after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns
    ):
        raise MatchingFailure(code)
    return {"algorithm": "sha256", "byte_count": metadata.st_size, "digest": digest}


def normalize(vector: np.ndarray, code: str) -> np.ndarray:
    value = np.asarray(vector, dtype=np.float32).reshape(-1)
    if value.shape != (registration.EMBEDDING_DIMENSION,) or not np.isfinite(value).all():
        raise MatchingFailure(code)
    norm = float(np.linalg.norm(value))
    if not math.isfinite(norm) or norm <= 0:
        raise MatchingFailure(code)
    value = value / norm
    if not math.isclose(float(np.linalg.norm(value)), 1.0, rel_tol=0, abs_tol=1e-5):
        raise MatchingFailure(code)
    return value


@functools.lru_cache(maxsize=1)
def load_classifier(model_directory: Path):
    required = {"hyperparams.yaml", "embedding_model.ckpt", "mean_var_norm_emb.ckpt", "classifier.ckpt", "label_encoder.ckpt"}
    if not model_directory.is_dir() or model_directory.is_symlink():
        raise MatchingFailure("speaker_matching_model_unavailable")
    for name in required:
        try:
            registration.ensure_regular_file(model_directory / name, "registration_model_unavailable")
        except registration.RegistrationFailure as error:
            raise MatchingFailure("speaker_matching_model_unavailable") from error
    try:
        import torch
        from speechbrain.inference.speaker import EncoderClassifier

        return EncoderClassifier.from_hparams(
            source=str(model_directory), savedir=str(model_directory), run_opts={"device": "cpu"}
        )
    except MatchingFailure:
        raise
    except Exception as error:
        print(f"speaker matching model error: {type(error).__name__}: {error}", file=sys.stderr)
        raise MatchingFailure("speaker_matching_model_unavailable") from error


def default_embedding(model_directory: Path, samples: np.ndarray) -> np.ndarray:
    try:
        import torch

        classifier = load_classifier(model_directory)
        signal = torch.from_numpy(samples.astype(np.float32, copy=False)).unsqueeze(0)
        with torch.no_grad():
            return classifier.encode_batch(signal).squeeze().cpu().numpy().astype(np.float32)
    except MatchingFailure:
        raise
    except Exception as error:
        print(f"speaker matching embedding error: {type(error).__name__}: {error}", file=sys.stderr)
        raise MatchingFailure("speaker_matching_embedding_failed") from error


def load_candidates(current: Path, job_id: str) -> tuple[dict[str, Any], dict[str, Any]]:
    try:
        input_fingerprint = candidate_generation.analysis_fingerprint(current)
        vad_path = current / "vad.json"
        vad_value = candidate_generation.validate_vad(
            jobs.read_json(vad_path, "candidate_vad_invalid"), job_id, input_fingerprint
        )
        vad_fingerprint = candidate_generation.file_fingerprint(vad_path, "candidate_vad_invalid")
        candidate_path = current / "speaker_candidates.json"
        value = candidate_generation.validate_candidates(
            jobs.read_json(candidate_path, "candidate_reuse_invalid"), job_id,
            vad_fingerprint, vad_value["audio_duration_ms"],
        )
        return value, fingerprint(candidate_path, "speaker_matching_candidates_invalid")
    except (jobs.JobFailure, candidate_generation.CandidateFailure, OSError) as error:
        raise MatchingFailure("speaker_matching_candidates_invalid") from error


def load_characters(characters_root: Path, identifiers: list[str]) -> tuple[list[dict[str, Any]], list[np.ndarray]]:
    if not characters_root.is_dir() or characters_root.is_symlink():
        raise MatchingFailure("speaker_matching_character_invalid")
    metadata: list[dict[str, Any]] = []
    centroids: list[np.ndarray] = []
    for identifier in identifiers:
        directory = characters_root / identifier
        try:
            registration.validate_character_directory(directory)
            character = registration.read_json(directory / "character.json")
            samples_meta = []
            vectors = []
            for sample_id in character["sample_ids"]:
                embedding_path = directory / "samples" / sample_id / "embedding.npy"
                vector = normalize(np.load(embedding_path, allow_pickle=False), "speaker_matching_character_invalid")
                vectors.append(vector)
                samples_meta.append({
                    "sample_id": sample_id,
                    "embedding_sha256": hashlib.sha256(embedding_path.read_bytes()).hexdigest(),
                })
        except (OSError, ValueError, registration.RegistrationFailure, MatchingFailure) as error:
            raise MatchingFailure("speaker_matching_character_invalid") from error
        centroid = normalize(np.mean(np.stack(vectors), axis=0), "speaker_matching_character_invalid")
        metadata.append({"character_id": identifier, "samples": samples_meta})
        centroids.append(centroid)
    return metadata, centroids


def read_candidate_samples(path: Path, start_ms: int, end_ms: int) -> np.ndarray:
    try:
        with wave.open(str(path), "rb") as source:
            if source.getnchannels() != 1 or source.getsampwidth() != 2 or source.getframerate() != 16_000 or source.getcomptype() != "NONE":
                raise MatchingFailure("speaker_matching_input_unavailable")
            source.setpos(start_ms * 16)
            frames = source.readframes((end_ms - start_ms) * 16)
    except (OSError, EOFError, wave.Error) as error:
        raise MatchingFailure("speaker_matching_input_unavailable") from error
    samples = np.frombuffer(frames, dtype="<i2").astype(np.float32) / 32768.0
    if samples.size != (end_ms - start_ms) * 16 or not np.isfinite(samples).all():
        raise MatchingFailure("speaker_matching_input_unavailable")
    return samples


def validate_output(value: Any, job_id: str, candidates_fingerprint: dict[str, Any], selected: list[dict[str, Any]], candidate_ids: list[str]) -> dict[str, Any]:
    code = "speaker_matching_reuse_invalid"
    exact(value, {"schema_version", "job_id", "speaker_candidates_fingerprint", "model", "selected_characters", "candidates"}, code)
    if value["schema_version"] != 1 or value["job_id"] != job_id or value["speaker_candidates_fingerprint"] != candidates_fingerprint or value["model"] != MODEL or value["selected_characters"] != selected:
        raise MatchingFailure(code)
    items = value["candidates"]
    if not isinstance(items, list) or [item.get("candidate_id") if isinstance(item, dict) else None for item in items] != candidate_ids:
        raise MatchingFailure(code)
    selected_ids = [item["character_id"] for item in selected]
    for item in items:
        exact(item, {"candidate_id", "comparisons"}, code)
        comparisons = item["comparisons"]
        if not isinstance(comparisons, list) or [comparison.get("character_id") if isinstance(comparison, dict) else None for comparison in comparisons] != selected_ids:
            raise MatchingFailure(code)
        for comparison in comparisons:
            exact(comparison, {"character_id", "cosine_similarity"}, code)
            score = comparison["cosine_similarity"]
            if not isinstance(score, (int, float)) or isinstance(score, bool) or not math.isfinite(score) or not -1 <= score <= 1:
                raise MatchingFailure(code)
    return value


def write_partial(path: Path, value: dict[str, Any]) -> None:
    try:
        with path.open("x", encoding="utf-8") as output:
            json.dump(value, output, ensure_ascii=False, separators=(",", ":"), sort_keys=True, allow_nan=False)
            output.write("\n")
            output.flush()
            os.fsync(output.fileno())
    except (OSError, ValueError) as error:
        raise MatchingFailure("speaker_matching_finalization_failed") from error


def run(request: dict[str, Any], model_directory: Path, emitter: Emitter, embedding_generator: Callable[[Path, np.ndarray], np.ndarray] = default_embedding) -> dict[str, Any]:
    exact(request, {"protocol_version", "request_id", "workspace_root", "characters_root", "job_id"}, "speaker_matching_job_invalid")
    if request["protocol_version"] != 1:
        raise MatchingFailure("speaker_matching_job_invalid")
    try:
        request_id = jobs.canonical_uuid(request["request_id"], "speaker_matching_job_invalid")
        job_id = jobs.canonical_uuid(request["job_id"], "speaker_matching_job_invalid")
        workspace = jobs.prepare_workspace(request["workspace_root"])
    except jobs.JobFailure as error:
        raise MatchingFailure("speaker_matching_job_invalid") from error
    characters_root = Path(request["characters_root"])
    descriptor = os.open(workspace / "analysis.lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise MatchingFailure("speaker_matching_busy") from error
        emitter.emit("progress", {"stage": "speaker_matching", "status": "running"})
        current = workspace / "current_job"
        if not current.is_dir() or current.is_symlink():
            raise MatchingFailure("speaker_matching_job_invalid")
        allowed = {"job.json", "stop.requested", "analysis.wav", "analysis_audio.json", "vad.json", "speaker_candidates.json", "speaker_matches.json"}
        if {item.name for item in current.iterdir()} - allowed:
            raise MatchingFailure("speaker_matching_job_invalid")
        try:
            job = jobs.validate_job(jobs.read_json(current / "job.json", "job_invalid"))
        except jobs.JobFailure as error:
            raise MatchingFailure("speaker_matching_job_invalid") from error
        if job["job_id"] != job_id or job["state"] not in {"start_requested", "preparing", "recovery_required"}:
            raise MatchingFailure("speaker_matching_job_invalid")
        candidates, candidates_fp = load_candidates(current, job_id)
        selected, centroids = load_characters(characters_root, job["selected_character_ids"])
        output_path = current / "speaker_matches.json"
        candidate_ids = [item["candidate_id"] for item in candidates["candidates"]]
        if output_path.exists() or output_path.is_symlink():
            try:
                reused = validate_output(jobs.read_json(output_path, "speaker_matching_reuse_invalid"), job_id, candidates_fp, selected, candidate_ids)
            except (jobs.JobFailure, MatchingFailure) as error:
                raise MatchingFailure("speaker_matching_reuse_invalid") from error
            emitter.emit("progress", {"stage": "speaker_matching", "status": "completed"})
            return {"reused": True, "candidate_count": len(reused["candidates"]), "selected_character_count": len(selected)}
        results = []
        wav_path = current / "analysis.wav"
        total = len(candidates["candidates"])
        for index, candidate in enumerate(candidates["candidates"]):
            try:
                vector = normalize(embedding_generator(model_directory, read_candidate_samples(wav_path, candidate["start_ms"], candidate["end_ms"])), "speaker_matching_embedding_invalid")
            except MatchingFailure:
                raise
            except Exception as error:
                raise MatchingFailure("speaker_matching_embedding_failed") from error
            comparisons = [
                {"character_id": item["character_id"], "cosine_similarity": float(np.clip(np.dot(vector, centroid), -1.0, 1.0))}
                for item, centroid in zip(selected, centroids)
            ]
            results.append({"candidate_id": candidate["candidate_id"], "comparisons": comparisons})
            emitter.emit("progress", {"stage": "speaker_matching", "status": "processing", "completed_count": index + 1, "total_count": total})
        value = {
            "schema_version": 1, "job_id": job_id, "speaker_candidates_fingerprint": candidates_fp,
            "model": MODEL, "selected_characters": selected, "candidates": results,
        }
        validate_output(value, job_id, candidates_fp, selected, candidate_ids)
        partial = workspace / ".partial" / f"speaker_matches_{request_id}.json.partial"
        write_partial(partial, value)
        try:
            validate_output(jobs.read_json(partial, "speaker_matching_reuse_invalid"), job_id, candidates_fp, selected, candidate_ids)
            os.rename(partial, output_path)
            directory = os.open(current, os.O_RDONLY | os.O_DIRECTORY)
            try:
                os.fsync(directory)
            finally:
                os.close(directory)
            final = validate_output(jobs.read_json(output_path, "speaker_matching_reuse_invalid"), job_id, candidates_fp, selected, candidate_ids)
        except (OSError, jobs.JobFailure, MatchingFailure) as error:
            raise MatchingFailure("speaker_matching_finalization_failed") from error
        emitter.emit("progress", {"stage": "speaker_matching", "status": "completed"})
        return {"reused": False, "candidate_count": len(final["candidates"]), "selected_character_count": len(selected)}
    finally:
        os.close(descriptor)


def main() -> int:
    if len(sys.argv) != 2:
        return 2
    try:
        line = sys.stdin.buffer.readline()
        if not line or sys.stdin.buffer.read(1):
            return 2
        request = json.loads(line)
        if not isinstance(request, dict):
            return 2
        request_id = jobs.canonical_uuid(request.get("request_id"), "speaker_matching_job_invalid")
    except (UnicodeError, json.JSONDecodeError, jobs.JobFailure):
        return 2
    emitter = Emitter(request_id)
    try:
        result = run(request, Path(sys.argv[1]), emitter)
        emitter.emit("finished", {"outcome": "succeeded", "result": result})
    except MatchingFailure as error:
        emitter.emit("error", {"code": error.code})
        emitter.emit("finished", {"outcome": "failed", "code": error.code})
    except Exception:
        emitter.emit("error", {"code": "speaker_matching_protocol_error"})
        emitter.emit("finished", {"outcome": "failed", "code": "speaker_matching_protocol_error"})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
