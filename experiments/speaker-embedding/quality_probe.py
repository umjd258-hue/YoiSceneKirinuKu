#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import subprocess
import time
import wave
from pathlib import Path

import numpy as np
import torch
from speechbrain.inference.speaker import EncoderClassifier


ROOT = Path(__file__).resolve().parent
ARTIFACTS = ROOT / "artifacts"
QUALITY_ROOT = ARTIFACTS / "quality"
MODEL_DIR = ARTIFACTS / "model"
MODEL_SOURCE = "speechbrain/spkrec-ecapa-voxceleb"
MODEL_REVISION = "0f99f2d0ebe89ac095bcc5903c4dd8f72b367286"


def run(arguments: list[str]) -> None:
    completed = subprocess.run(arguments, check=False, capture_output=True, text=True)
    if completed.returncode != 0:
        raise RuntimeError(f"command failed ({completed.returncode}): {arguments!r}\n{completed.stderr}")


def normalized(vector: np.ndarray) -> np.ndarray:
    return vector / np.linalg.norm(vector)


def cosine(left: np.ndarray, right: np.ndarray) -> float:
    return float(np.dot(left, right) / (np.linalg.norm(left) * np.linalg.norm(right)))


def metrics(path: Path) -> dict[str, float | int]:
    with wave.open(str(path), "rb") as wav:
        frames = wav.readframes(wav.getnframes())
        sample_rate = wav.getframerate()
        frame_count = wav.getnframes()
    samples = np.frombuffer(frames, dtype="<i2").astype(np.float64) / 32768.0
    rms = float(np.sqrt(np.mean(np.square(samples)))) if samples.size else 0.0
    peak = float(np.max(np.abs(samples))) if samples.size else 0.0
    return {
        "duration_ms": round(frame_count * 1000 / sample_rate),
        "rms_dbfs": float(20 * np.log10(rms)) if rms else float("-inf"),
        "peak_dbfs": float(20 * np.log10(peak)) if peak else float("-inf"),
    }


def main() -> None:
    if QUALITY_ROOT.exists():
        raise RuntimeError("quality artifacts already exist; refuse to overwrite")
    QUALITY_ROOT.mkdir()
    source = ARTIFACTS / "kyoko_a.wav"
    cases: dict[str, Path] = {"full": source}
    for milliseconds in (500, 1000, 2000, 3000, 4000):
        output = QUALITY_ROOT / f"duration_{milliseconds}.wav"
        run([
            "/opt/homebrew/bin/ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-n",
            "-i", str(source), "-t", f"{milliseconds / 1000:.3f}", "-c:a", "pcm_s16le", str(output),
        ])
        cases[f"duration_{milliseconds}"] = output
    for attenuation in (20, 30, 40):
        output = QUALITY_ROOT / f"attenuated_{attenuation}db.wav"
        run([
            "/opt/homebrew/bin/ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-n",
            "-i", str(source), "-af", f"volume=-{attenuation}dB", "-c:a", "pcm_s16le", str(output),
        ])
        cases[f"attenuated_{attenuation}db"] = output
    silence = QUALITY_ROOT / "silence.wav"
    run([
        "/opt/homebrew/bin/ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-n",
        "-f", "lavfi", "-i", "anullsrc=r=16000:cl=mono", "-t", "5", "-c:a", "pcm_s16le", str(silence),
    ])
    cases["silence"] = silence

    os.environ["HF_HUB_OFFLINE"] = "1"
    classifier = EncoderClassifier.from_hparams(
        source=MODEL_SOURCE,
        savedir=str(MODEL_DIR),
        run_opts={"device": "cpu"},
        revision=MODEL_REVISION,
    )
    embeddings: dict[str, np.ndarray] = {}
    timings: dict[str, float] = {}
    errors: dict[str, str] = {}
    for name, path in cases.items():
        try:
            signal = classifier.load_audio(str(path)).unsqueeze(0)
            started = time.perf_counter()
            with torch.no_grad():
                vector = classifier.encode_batch(signal).squeeze().cpu().numpy().astype(np.float32)
            timings[name] = time.perf_counter() - started
            if np.isfinite(vector).all() and np.linalg.norm(vector) > 0:
                embeddings[name] = normalized(vector)
            else:
                errors[name] = "non-finite or zero-norm embedding"
        except Exception as error:
            errors[name] = f"{type(error).__name__}: {error}"

    baseline = embeddings["full"]
    report = {
        "input_metrics": {name: metrics(path) for name, path in cases.items()},
        "cosine_to_full": {name: cosine(baseline, vector) for name, vector in embeddings.items()},
        "inference_seconds": timings,
        "errors": errors,
        "limitations": [
            "人工合成音声1話者だけの入力安定性確認である",
            "数値は人物一致判定閾値に使用しない",
            "品質条件は明白な不正入力を拒否する最低条件としてのみ検討する",
        ],
    }
    (QUALITY_ROOT / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
