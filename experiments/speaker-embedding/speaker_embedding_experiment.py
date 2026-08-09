#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import math
import subprocess
import sys
import time
import wave
from pathlib import Path

import numpy as np
import torch
from speechbrain.inference.speaker import EncoderClassifier


ROOT = Path(__file__).resolve().parent
ARTIFACTS = ROOT / "artifacts"
MODEL_DIR = ARTIFACTS / "model"
MODEL_SOURCE = "speechbrain/spkrec-ecapa-voxceleb"
MODEL_REVISION = "0f99f2d0ebe89ac095bcc5903c4dd8f72b367286"
SAMPLE_RATE = 16_000


def run(arguments: list[str]) -> None:
    completed = subprocess.run(arguments, check=False, capture_output=True, text=True)
    if completed.returncode != 0:
        raise RuntimeError(f"command failed ({completed.returncode}): {arguments!r}\n{completed.stderr}")


def generate_voice(voice: str, text: str, output: Path) -> None:
    aiff = output.with_suffix(".aiff")
    run(["/usr/bin/say", "-v", voice, "-o", str(aiff), text])
    run([
        "/opt/homebrew/bin/ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error",
        "-n", "-i", str(aiff), "-ar", str(SAMPLE_RATE), "-ac", "1", "-c:a", "pcm_s16le", str(output),
    ])
    aiff.unlink()


def inspect_wav(path: Path) -> dict[str, float | int | str]:
    with wave.open(str(path), "rb") as wav:
        frames = wav.readframes(wav.getnframes())
        channels = wav.getnchannels()
        sample_width = wav.getsampwidth()
        sample_rate = wav.getframerate()
        frame_count = wav.getnframes()
    samples = np.frombuffer(frames, dtype="<i2").astype(np.float64) / 32768.0
    rms = float(np.sqrt(np.mean(np.square(samples)))) if samples.size else 0.0
    peak = float(np.max(np.abs(samples))) if samples.size else 0.0
    return {
        "channels": channels,
        "sample_width_bytes": sample_width,
        "sample_rate_hz": sample_rate,
        "frame_count": frame_count,
        "duration_ms": round(frame_count * 1000 / sample_rate),
        "rms_dbfs": 20 * math.log10(rms) if rms > 0 else float("-inf"),
        "peak_dbfs": 20 * math.log10(peak) if peak > 0 else float("-inf"),
        "sha256": hashlib.sha256(frames).hexdigest(),
    }


def cosine(left: np.ndarray, right: np.ndarray) -> float:
    return float(np.dot(left, right) / (np.linalg.norm(left) * np.linalg.norm(right)))


def normalized(vector: np.ndarray) -> np.ndarray:
    norm = np.linalg.norm(vector)
    if not np.isfinite(norm) or norm == 0:
        raise ValueError("invalid embedding norm")
    return vector / norm


def main() -> None:
    if ARTIFACTS.exists():
        raise RuntimeError("artifacts already exists; refuse to overwrite")
    ARTIFACTS.mkdir()

    fixtures = {
        "kyoko_a": ("Kyoko", "今日は静かな公園で、青い空を見上げながら散歩をしています。"),
        "kyoko_b": ("Kyoko", "明日の予定を確認してから、温かいお茶をゆっくり飲みます。"),
        "eddy_a": ("Eddy (日本語（日本）)", "今日は静かな公園で、青い空を見上げながら散歩をしています。"),
        "eddy_b": ("Eddy (日本語（日本）)", "明日の予定を確認してから、温かいお茶をゆっくり飲みます。"),
    }
    wav_paths: dict[str, Path] = {}
    for name, (voice, text) in fixtures.items():
        path = ARTIFACTS / f"{name}.wav"
        generate_voice(voice, text, path)
        wav_paths[name] = path

    started = time.perf_counter()
    classifier = EncoderClassifier.from_hparams(
        source=MODEL_SOURCE,
        savedir=str(MODEL_DIR),
        run_opts={"device": "cpu"},
        revision=MODEL_REVISION,
    )
    model_load_seconds = time.perf_counter() - started

    embeddings: dict[str, np.ndarray] = {}
    timings: dict[str, float] = {}
    for name, path in wav_paths.items():
        signal = classifier.load_audio(str(path)).unsqueeze(0)
        started = time.perf_counter()
        with torch.no_grad():
            value = classifier.encode_batch(signal).squeeze().cpu().numpy().astype(np.float32)
        timings[name] = time.perf_counter() - started
        embeddings[name] = normalized(value)

    repeat_signal = classifier.load_audio(str(wav_paths["kyoko_a"])).unsqueeze(0)
    with torch.no_grad():
        repeated = normalized(classifier.encode_batch(repeat_signal).squeeze().cpu().numpy().astype(np.float32))

    kyoko_centroid = normalized(embeddings["kyoko_a"] + embeddings["kyoko_b"])
    eddy_centroid = normalized(embeddings["eddy_a"] + embeddings["eddy_b"])
    report = {
        "candidate": {
            "model": MODEL_SOURCE,
            "revision_requested": MODEL_REVISION,
            "runtime": "SpeechBrain EncoderClassifier on CPU",
            "embedding_dtype": "float32",
            "normalization": "L2",
        },
        "environment": {
            "python": sys.executable,
            "torch": torch.__version__,
            "model_load_seconds": model_load_seconds,
        },
        "fixtures": {name: inspect_wav(path) for name, path in wav_paths.items()},
        "embedding": {
            "dimension": int(embeddings["kyoko_a"].shape[0]),
            "finite": all(bool(np.isfinite(value).all()) for value in embeddings.values()),
            "repeat_max_abs_delta": float(np.max(np.abs(embeddings["kyoko_a"] - repeated))),
            "inference_seconds": timings,
        },
        "cosine_similarity": {
            "same_kyoko": cosine(embeddings["kyoko_a"], embeddings["kyoko_b"]),
            "same_eddy": cosine(embeddings["eddy_a"], embeddings["eddy_b"]),
            "different_same_text": cosine(embeddings["kyoko_a"], embeddings["eddy_a"]),
            "different_other_text": cosine(embeddings["kyoko_b"], embeddings["eddy_b"]),
            "centroid_cross_speaker": cosine(kyoko_centroid, eddy_centroid),
            "kyoko_a_to_kyoko_centroid": cosine(embeddings["kyoko_a"], kyoko_centroid),
            "kyoko_b_to_kyoko_centroid": cosine(embeddings["kyoko_b"], kyoko_centroid),
        },
        "limitations": [
            "人工合成音声だけの限定検証であり、実人物音声の識別精度を示さない",
            "測定値から人物一致閾値を決定しない",
            "モデル配置・同梱方式を決定しない",
            "平均centroid以外の外れ値除去や重み付けは未検証",
        ],
    }
    (ARTIFACTS / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
