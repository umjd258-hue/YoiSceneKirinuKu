#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import ctypes
import fcntl
import json
import math
import os
import re
import stat
import subprocess
import sys
import uuid
import wave
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Callable

import numpy as np


SCHEMA_VERSION = 1
MODEL_ID = "speechbrain/spkrec-ecapa-voxceleb"
MODEL_REVISION = "0f99f2d0ebe89ac095bcc5903c4dd8f72b367286"
EMBEDDING_DIMENSION = 192
CHARACTER_ID_PATTERN = re.compile(r"char_([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\Z")
SAMPLE_ID_PATTERN = re.compile(r"sample_([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\Z")


class RegistrationFailure(Exception):
    def __init__(self, code: str) -> None:
        super().__init__(code)
        self.code = code


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


def require_exact_keys(value: dict[str, Any], keys: set[str], code: str) -> None:
    if set(value) != keys:
        raise RegistrationFailure(code)


def canonical_request_id(value: Any) -> str:
    if not isinstance(value, str):
        raise RegistrationFailure("registration_invalid_request")
    try:
        parsed = uuid.UUID(value)
    except ValueError as error:
        raise RegistrationFailure("registration_invalid_request") from error
    if str(parsed) != value:
        raise RegistrationFailure("registration_invalid_request")
    return value


def ensure_path_without_symlinks(path: Path) -> None:
    current = Path(path.anchor)
    for part in path.parts[1:]:
        current = current / part
        if current.exists() and current.is_symlink():
            raise RegistrationFailure("registration_invalid_request")


def prepare_root(raw_path: Any) -> Path:
    if not isinstance(raw_path, str) or not raw_path.startswith("/"):
        raise RegistrationFailure("registration_invalid_request")
    root = Path(raw_path)
    ensure_path_without_symlinks(root)
    root.mkdir(parents=True, exist_ok=True)
    if not root.is_dir() or root.is_symlink():
        raise RegistrationFailure("registration_invalid_request")
    partial_root = root / ".partial"
    partial_root.mkdir(exist_ok=True)
    if not partial_root.is_dir() or partial_root.is_symlink():
        raise RegistrationFailure("registration_invalid_request")
    return root


def ensure_regular_file(path: Path, code: str) -> None:
    try:
        metadata = path.lstat()
    except OSError as error:
        raise RegistrationFailure(code) from error
    if not stat.S_ISREG(metadata.st_mode) or path.is_symlink() or metadata.st_size <= 0:
        raise RegistrationFailure(code)


def inspect_wav(path: Path) -> dict[str, Any]:
    ensure_regular_file(path, "registration_wav_missing")
    try:
        with wave.open(str(path), "rb") as wav:
            channels = wav.getnchannels()
            sample_width = wav.getsampwidth()
            sample_rate = wav.getframerate()
            frame_count = wav.getnframes()
            compression = wav.getcomptype()
            frames = wav.readframes(frame_count)
    except (OSError, EOFError, wave.Error) as error:
        raise RegistrationFailure("registration_wav_invalid_format") from error
    if channels != 1 or sample_width != 2 or sample_rate != 16_000 or compression != "NONE" or frame_count <= 0:
        raise RegistrationFailure("registration_wav_invalid_format")
    duration_ms = round(frame_count * 1000 / sample_rate)
    if duration_ms < 3_000:
        raise RegistrationFailure("registration_audio_too_short")
    if duration_ms > 30_000:
        raise RegistrationFailure("registration_audio_too_long")
    samples = np.frombuffer(frames, dtype="<i2").astype(np.float64) / 32768.0
    if samples.size == 0 or not np.any(samples):
        raise RegistrationFailure("registration_audio_silent")
    rms = float(np.sqrt(np.mean(np.square(samples))))
    peak = float(np.max(np.abs(samples)))
    rms_dbfs = 20 * math.log10(rms) if rms > 0 else float("-inf")
    peak_dbfs = 20 * math.log10(peak) if peak > 0 else float("-inf")
    if rms_dbfs <= -60 or peak_dbfs <= -40:
        raise RegistrationFailure("registration_audio_too_quiet")
    return {
        "file": "source.wav",
        "sample_rate_hz": sample_rate,
        "channels": channels,
        "sample_format": "pcm_s16le",
        "duration_ms": duration_ms,
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
    }


def extract_wav(ffmpeg_path: Path, source: Path, start_ms: int, end_ms: int, output: Path) -> None:
    ensure_regular_file(source, "registration_source_unavailable")
    arguments = [
        str(ffmpeg_path), "-nostdin", "-hide_banner", "-loglevel", "error", "-n",
        "-ss", f"{start_ms / 1000:.3f}", "-i", str(source),
        "-t", f"{(end_ms - start_ms) / 1000:.3f}",
        "-vn", "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le", str(output),
    ]
    try:
        completed = subprocess.run(arguments, shell=False, capture_output=True, check=False)
    except OSError as error:
        raise RegistrationFailure("registration_ffmpeg_launch_failed") from error
    if completed.returncode != 0:
        raise RegistrationFailure("registration_ffmpeg_failed")


def generate_embedding(model_directory: Path, wav_path: Path, output: Path) -> None:
    if not model_directory.is_dir() or model_directory.is_symlink():
        raise RegistrationFailure("registration_model_unavailable")
    required = {"hyperparams.yaml", "embedding_model.ckpt", "mean_var_norm_emb.ckpt", "classifier.ckpt", "label_encoder.ckpt"}
    for name in required:
        ensure_regular_file(model_directory / name, "registration_model_unavailable")
    try:
        import torch
        from speechbrain.inference.speaker import EncoderClassifier

        classifier = EncoderClassifier.from_hparams(
            source=str(model_directory),
            savedir=str(model_directory),
            run_opts={"device": "cpu"},
        )
        signal = classifier.load_audio(str(wav_path)).unsqueeze(0)
        with torch.no_grad():
            vector = classifier.encode_batch(signal).squeeze().cpu().numpy().astype(np.float32)
        if vector.shape != (EMBEDDING_DIMENSION,) or not np.isfinite(vector).all():
            raise RegistrationFailure("registration_embedding_invalid")
        norm = float(np.linalg.norm(vector))
        if not math.isfinite(norm) or norm <= 0:
            raise RegistrationFailure("registration_embedding_invalid")
        vector /= norm
        with output.open("xb") as file:
            np.save(file, vector, allow_pickle=False)
    except RegistrationFailure:
        raise
    except Exception as error:
        print(f"character registration embedding error: {type(error).__name__}: {error}", file=sys.stderr)
        raise RegistrationFailure("registration_embedding_failed") from error


def validate_embedding(path: Path) -> None:
    ensure_regular_file(path, "registration_embedding_invalid")
    try:
        vector = np.load(path, allow_pickle=False)
    except Exception as error:
        raise RegistrationFailure("registration_embedding_invalid") from error
    if vector.dtype != np.float32 or vector.shape != (EMBEDDING_DIMENSION,) or not np.isfinite(vector).all():
        raise RegistrationFailure("registration_embedding_invalid")
    if not math.isclose(float(np.linalg.norm(vector)), 1.0, rel_tol=0, abs_tol=1e-5):
        raise RegistrationFailure("registration_embedding_invalid")


def write_json(path: Path, value: dict[str, Any]) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    try:
        with temporary.open("x", encoding="utf-8") as file:
            json.dump(value, file, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
            file.write("\n")
            file.flush()
            os.fsync(file.fileno())
        os.rename(temporary, path)
    except OSError as error:
        raise RegistrationFailure("registration_metadata_write_failed") from error


@contextmanager
def character_update_lock(partial_root: Path, character_id: str):
    lock_path = partial_root / f"{character_id}.lock"
    try:
        descriptor = os.open(lock_path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    except OSError as error:
        raise RegistrationFailure("registration_character_busy") from error
    try:
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode):
            raise RegistrationFailure("registration_character_busy")
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise RegistrationFailure("registration_character_busy") from error
        yield
    finally:
        os.close(descriptor)


@contextmanager
def global_character_lock(partial_root: Path, exclusive: bool):
    lock_path = partial_root / "global.lock"
    try:
        descriptor = os.open(lock_path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    except OSError as error:
        raise RegistrationFailure("registration_character_busy") from error
    try:
        if not stat.S_ISREG(os.fstat(descriptor).st_mode):
            raise RegistrationFailure("registration_character_busy")
        operation = fcntl.LOCK_EX if exclusive else fcntl.LOCK_SH
        try:
            fcntl.flock(descriptor, operation | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise RegistrationFailure("registration_character_busy") from error
        yield
    finally:
        os.close(descriptor)


def copy_character_directory(source: Path, destination: Path) -> None:
    validate_character_directory(source)
    character = read_json(source / "character.json")
    try:
        (destination / "samples").mkdir(parents=True)
        for sample_id in character["sample_ids"]:
            source_sample = source / "samples" / sample_id
            destination_sample = destination / "samples" / sample_id
            destination_sample.mkdir()
            for name in ("source.wav", "embedding.npy", "sample.json"):
                source_file = source_sample / name
                destination_file = destination_sample / name
                ensure_regular_file(source_file, "registration_protocol_error")
                with source_file.open("rb") as reader, destination_file.open("xb") as writer:
                    while chunk := reader.read(1024 * 1024):
                        writer.write(chunk)
                    writer.flush()
                    os.fsync(writer.fileno())
        with (source / "character.json").open("rb") as reader, (destination / "character.json").open("xb") as writer:
            writer.write(reader.read())
            writer.flush()
            os.fsync(writer.fileno())
    except OSError as error:
        raise RegistrationFailure("registration_metadata_write_failed") from error


def atomic_swap(first: Path, second: Path) -> None:
    rename = ctypes.CDLL(None, use_errno=True).renameatx_np
    rename.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
    rename.restype = ctypes.c_int
    if rename(-2, os.fsencode(first), -2, os.fsencode(second), 0x00000002) != 0:
        raise RegistrationFailure("registration_finalization_failed")


def cleanup_swapped_character(update_root: Path, character_directory: Path) -> None:
    try:
        character = read_json(character_directory / "character.json")
        validate_character_directory(character_directory)
        for sample_id in character["sample_ids"]:
            sample_directory = character_directory / "samples" / sample_id
            for name in ("source.wav", "embedding.npy", "sample.json"):
                (sample_directory / name).unlink()
            sample_directory.rmdir()
        (character_directory / "samples").rmdir()
        (character_directory / "character.json").unlink()
        character_directory.rmdir()
        update_root.rmdir()
    except (OSError, RegistrationFailure):
        pass


def read_json(path: Path) -> dict[str, Any]:
    ensure_regular_file(path, "registration_protocol_error")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise RegistrationFailure("registration_protocol_error") from error
    if not isinstance(value, dict):
        raise RegistrationFailure("registration_protocol_error")
    return value


def validate_character_directory(directory: Path) -> dict[str, Any]:
    if not directory.is_dir() or directory.is_symlink() or CHARACTER_ID_PATTERN.fullmatch(directory.name) is None:
        raise RegistrationFailure("registration_protocol_error")
    character = read_json(directory / "character.json")
    require_exact_keys(character, {"schema_version", "character_id", "display_name", "sample_ids"}, "registration_protocol_error")
    if character["schema_version"] != SCHEMA_VERSION or character["character_id"] != directory.name:
        raise RegistrationFailure("registration_protocol_error")
    if not isinstance(character["display_name"], str) or not character["display_name"].strip():
        raise RegistrationFailure("registration_protocol_error")
    sample_ids = character["sample_ids"]
    if not isinstance(sample_ids, list) or not sample_ids or len(sample_ids) != len(set(sample_ids)):
        raise RegistrationFailure("registration_protocol_error")
    if set(item.name for item in directory.iterdir()) != {"character.json", "samples"}:
        raise RegistrationFailure("registration_protocol_error")
    samples_root = directory / "samples"
    if not samples_root.is_dir() or samples_root.is_symlink():
        raise RegistrationFailure("registration_protocol_error")
    if set(item.name for item in samples_root.iterdir()) != set(sample_ids):
        raise RegistrationFailure("registration_protocol_error")

    summaries = []
    for sample_id in sample_ids:
        if not isinstance(sample_id, str) or SAMPLE_ID_PATTERN.fullmatch(sample_id) is None:
            raise RegistrationFailure("registration_protocol_error")
        sample_directory = samples_root / sample_id
        if not sample_directory.is_dir() or sample_directory.is_symlink():
            raise RegistrationFailure("registration_protocol_error")
        if set(item.name for item in sample_directory.iterdir()) != {"source.wav", "embedding.npy", "sample.json"}:
            raise RegistrationFailure("registration_protocol_error")
        wav_metadata = inspect_wav(sample_directory / "source.wav")
        validate_embedding(sample_directory / "embedding.npy")
        sample = read_json(sample_directory / "sample.json")
        require_exact_keys(sample, {"schema_version", "sample_id", "character_id", "source_interval", "source_wav", "embedding"}, "registration_protocol_error")
        if sample["schema_version"] != SCHEMA_VERSION or sample["sample_id"] != sample_id or sample["character_id"] != directory.name:
            raise RegistrationFailure("registration_protocol_error")
        interval = sample["source_interval"]
        if not isinstance(interval, dict) or set(interval) != {"start_ms", "end_ms"}:
            raise RegistrationFailure("registration_protocol_error")
        if not isinstance(interval["start_ms"], int) or isinstance(interval["start_ms"], bool) or not isinstance(interval["end_ms"], int) or isinstance(interval["end_ms"], bool):
            raise RegistrationFailure("registration_protocol_error")
        if interval["start_ms"] < 0 or interval["start_ms"] >= interval["end_ms"]:
            raise RegistrationFailure("registration_protocol_error")
        source_wav = sample["source_wav"]
        if not isinstance(source_wav, dict) or source_wav != wav_metadata:
            raise RegistrationFailure("registration_protocol_error")
        embedding = sample["embedding"]
        expected_embedding = {
            "file": "embedding.npy",
            "model_id": MODEL_ID,
            "model_revision": MODEL_REVISION,
            "dimension": EMBEDDING_DIMENSION,
            "dtype": "float32",
            "normalization": "l2",
            "source_wav_sha256": wav_metadata["sha256"],
        }
        if embedding != expected_embedding:
            raise RegistrationFailure("registration_protocol_error")
        summaries.append({"sample_id": sample_id, "duration_ms": wav_metadata["duration_ms"]})
    return {
        "character_id": directory.name,
        "display_name": character["display_name"],
        "samples": summaries,
    }


def build_sample(
    sample_directory: Path,
    sample_id: str,
    character_id: str,
    source: Path,
    start_ms: int,
    end_ms: int,
    ffmpeg_path: Path,
    model_directory: Path,
    emitter: Emitter,
    embedding_generator: Callable[[Path, Path, Path], None],
) -> None:
    sample_directory.mkdir(parents=True)
    emitter.emit("progress", {"stage": "source_wav", "status": "running"})
    wav_path = sample_directory / "source.wav"
    extract_wav(ffmpeg_path, source, start_ms, end_ms, wav_path)
    wav_metadata = inspect_wav(wav_path)
    emitter.emit("progress", {"stage": "source_wav", "status": "completed"})

    emitter.emit("progress", {"stage": "embedding", "status": "running"})
    embedding_path = sample_directory / "embedding.npy"
    embedding_generator(model_directory, wav_path, embedding_path)
    validate_embedding(embedding_path)
    emitter.emit("progress", {"stage": "embedding", "status": "completed"})

    write_json(sample_directory / "sample.json", {
        "schema_version": SCHEMA_VERSION,
        "sample_id": sample_id,
        "character_id": character_id,
        "source_interval": {"start_ms": start_ms, "end_ms": end_ms},
        "source_wav": wav_metadata,
        "embedding": {
            "file": "embedding.npy",
            "model_id": MODEL_ID,
            "model_revision": MODEL_REVISION,
            "dimension": EMBEDDING_DIMENSION,
            "dtype": "float32",
            "normalization": "l2",
            "source_wav_sha256": wav_metadata["sha256"],
        },
    })


def register_character(
    request: dict[str, Any],
    ffmpeg_path: Path,
    model_directory: Path,
    emitter: Emitter,
    embedding_generator: Callable[[Path, Path, Path], None] = generate_embedding,
    fail_before_finalization: bool = False,
) -> dict[str, Any]:
    require_exact_keys(request, {"protocol_version", "request_id", "operation", "display_name", "source_path", "start_ms", "end_ms", "characters_root"}, "registration_invalid_request")
    name = request["display_name"]
    start_ms = request["start_ms"]
    end_ms = request["end_ms"]
    if not isinstance(name, str) or not name.strip() or len(name.strip()) > 100:
        raise RegistrationFailure("registration_invalid_request")
    if not isinstance(start_ms, int) or isinstance(start_ms, bool) or not isinstance(end_ms, int) or isinstance(end_ms, bool):
        raise RegistrationFailure("registration_invalid_interval")
    if start_ms < 0 or end_ms <= start_ms or end_ms - start_ms < 3_000 or end_ms - start_ms > 30_000:
        raise RegistrationFailure("registration_invalid_interval")
    source = Path(request["source_path"]) if isinstance(request["source_path"], str) else Path()
    root = prepare_root(request["characters_root"])
    with global_character_lock(root / ".partial", exclusive=False):
        return _register_character_locked(
            name.strip(), source, start_ms, end_ms, root, ffmpeg_path, model_directory,
            emitter, embedding_generator, fail_before_finalization,
        )


def _register_character_locked(
    name: str,
    source: Path,
    start_ms: int,
    end_ms: int,
    root: Path,
    ffmpeg_path: Path,
    model_directory: Path,
    emitter: Emitter,
    embedding_generator: Callable[[Path, Path, Path], None],
    fail_before_finalization: bool,
) -> dict[str, Any]:
    character_id = "char_" + str(uuid.uuid4())
    sample_id = "sample_" + str(uuid.uuid4())
    staging = root / ".partial" / character_id
    final = root / character_id
    if staging.exists() or final.exists():
        raise RegistrationFailure("registration_finalization_failed")
    build_sample(
        staging / "samples" / sample_id, sample_id, character_id, source, start_ms, end_ms,
        ffmpeg_path, model_directory, emitter, embedding_generator,
    )
    write_json(staging / "character.json", {
        "schema_version": SCHEMA_VERSION,
        "character_id": character_id,
        "display_name": name,
        "sample_ids": [sample_id],
    })
    summary = validate_character_directory(staging)
    if fail_before_finalization:
        raise RegistrationFailure("registration_finalization_failed")
    try:
        os.rename(staging, final)
    except OSError as error:
        raise RegistrationFailure("registration_finalization_failed") from error
    summary = validate_character_directory(final)
    emitter.emit("progress", {"stage": "finalization", "status": "completed"})
    return summary


def add_sample(
    request: dict[str, Any],
    ffmpeg_path: Path,
    model_directory: Path,
    emitter: Emitter,
    embedding_generator: Callable[[Path, Path, Path], None] = generate_embedding,
    fail_before_swap: bool = False,
) -> dict[str, Any]:
    require_exact_keys(request, {"protocol_version", "request_id", "operation", "character_id", "source_path", "start_ms", "end_ms", "characters_root"}, "registration_invalid_request")
    character_id = request["character_id"]
    start_ms = request["start_ms"]
    end_ms = request["end_ms"]
    if not isinstance(character_id, str) or CHARACTER_ID_PATTERN.fullmatch(character_id) is None:
        raise RegistrationFailure("registration_invalid_request")
    if not isinstance(start_ms, int) or isinstance(start_ms, bool) or not isinstance(end_ms, int) or isinstance(end_ms, bool):
        raise RegistrationFailure("registration_invalid_interval")
    if start_ms < 0 or end_ms <= start_ms or end_ms - start_ms < 3_000 or end_ms - start_ms > 30_000:
        raise RegistrationFailure("registration_invalid_interval")
    source = Path(request["source_path"]) if isinstance(request["source_path"], str) else Path()
    root = prepare_root(request["characters_root"])
    partial_root = root / ".partial"
    formal = root / character_id
    if not formal.exists():
        raise RegistrationFailure("registration_character_not_found")

    with global_character_lock(partial_root, exclusive=False), character_update_lock(partial_root, character_id):
        validate_character_directory(formal)
        update_root = partial_root / ("update_" + str(uuid.uuid4()))
        staging = update_root / character_id
        try:
            update_root.mkdir()
        except OSError as error:
            raise RegistrationFailure("registration_metadata_write_failed") from error
        copy_character_directory(formal, staging)
        character = read_json(staging / "character.json")
        sample_id = "sample_" + str(uuid.uuid4())
        build_sample(
            staging / "samples" / sample_id, sample_id, character_id, source, start_ms, end_ms,
            ffmpeg_path, model_directory, emitter, embedding_generator,
        )
        write_json(staging / "character.json", {
            "schema_version": SCHEMA_VERSION,
            "character_id": character_id,
            "display_name": character["display_name"],
            "sample_ids": [*character["sample_ids"], sample_id],
        })
        expected = validate_character_directory(staging)
        if fail_before_swap:
            raise RegistrationFailure("registration_finalization_failed")
        atomic_swap(formal, staging)
        try:
            actual = validate_character_directory(formal)
            if actual != expected:
                raise RegistrationFailure("registration_protocol_error")
        except RegistrationFailure:
            try:
                atomic_swap(formal, staging)
            except RegistrationFailure:
                pass
            raise
        emitter.emit("progress", {"stage": "finalization", "status": "completed"})
        cleanup_swapped_character(update_root, staging)
        return actual


def delete_character(
    request: dict[str, Any],
    emitter: Emitter,
    fail_before_rename: bool = False,
    keep_tombstone: bool = False,
) -> str:
    require_exact_keys(
        request,
        {"protocol_version", "request_id", "operation", "character_id", "characters_root"},
        "registration_invalid_request",
    )
    character_id = request["character_id"]
    if not isinstance(character_id, str) or CHARACTER_ID_PATTERN.fullmatch(character_id) is None:
        raise RegistrationFailure("registration_invalid_request")
    root = prepare_root(request["characters_root"])
    partial_root = root / ".partial"
    formal = root / character_id
    with global_character_lock(partial_root, exclusive=True):
        if not formal.exists():
            raise RegistrationFailure("registration_character_not_found")
        try:
            validate_character_directory(formal)
        except RegistrationFailure as error:
            raise RegistrationFailure("registration_character_delete_failed") from error
        tombstone_root = partial_root / ("delete_" + str(uuid.uuid4()))
        tombstone = tombstone_root / character_id
        if tombstone_root.exists():
            raise RegistrationFailure("registration_character_delete_failed")
        try:
            tombstone_root.mkdir()
        except OSError as error:
            raise RegistrationFailure("registration_character_delete_failed") from error
        if fail_before_rename:
            raise RegistrationFailure("registration_character_delete_failed")
        try:
            os.rename(formal, tombstone)
        except OSError as error:
            raise RegistrationFailure("registration_character_delete_failed") from error
        if formal.exists():
            raise RegistrationFailure("registration_character_delete_failed")
        try:
            validate_character_directory(tombstone)
        except RegistrationFailure as error:
            raise RegistrationFailure("registration_character_delete_failed") from error
        emitter.emit("progress", {"stage": "finalization", "status": "completed"})
        if not keep_tombstone:
            cleanup_swapped_character(tombstone_root, tombstone)
        return character_id


def list_characters(request: dict[str, Any]) -> list[dict[str, Any]]:
    require_exact_keys(request, {"protocol_version", "request_id", "operation", "characters_root"}, "registration_invalid_request")
    root = prepare_root(request["characters_root"])
    characters = []
    for child in sorted(root.iterdir(), key=lambda path: path.name):
        if child.name == ".partial":
            continue
        characters.append(validate_character_directory(child))
    return characters


def main() -> int:
    if len(sys.argv) != 3:
        return 2
    ffmpeg_path = Path(sys.argv[1])
    model_directory = Path(sys.argv[2])
    try:
        raw_line = sys.stdin.buffer.readline()
        if not raw_line or sys.stdin.buffer.read(1):
            return 2
        request = json.loads(raw_line)
        if not isinstance(request, dict) or request.get("protocol_version") != 1:
            return 2
        request_id = canonical_request_id(request.get("request_id"))
    except (UnicodeError, json.JSONDecodeError, RegistrationFailure):
        return 2

    emitter = Emitter(request_id)
    try:
        operation = request.get("operation")
        if operation == "register_character":
            character = register_character(request, ffmpeg_path, model_directory, emitter)
            result = {"character": character}
        elif operation == "add_sample":
            character = add_sample(request, ffmpeg_path, model_directory, emitter)
            result = {"character": character}
        elif operation == "list_characters":
            result = {"characters": list_characters(request)}
        elif operation == "delete_character":
            result = {"deleted_character_id": delete_character(request, emitter)}
        else:
            raise RegistrationFailure("registration_invalid_request")
        emitter.emit("finished", {"outcome": "succeeded", "result": result})
    except RegistrationFailure as error:
        emitter.emit("error", {"code": error.code})
        emitter.emit("finished", {"outcome": "failed", "code": error.code})
    except Exception:
        emitter.emit("error", {"code": "registration_protocol_error"})
        emitter.emit("finished", {"outcome": "failed", "code": "registration_protocol_error"})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
