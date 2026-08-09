#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import subprocess
import time
from pathlib import Path

import numpy as np
import torch
from speechbrain.inference.speaker import EncoderClassifier


ROOT = Path(__file__).resolve().parent
ARTIFACTS = ROOT / "artifacts"
OUTPUT_ROOT = ARTIFACTS / "long-duration"
MODEL_DIR = ARTIFACTS / "model"


def run(arguments: list[str]) -> None:
    completed = subprocess.run(arguments, check=False, capture_output=True, text=True)
    if completed.returncode != 0:
        raise RuntimeError(f"command failed ({completed.returncode}): {arguments!r}\n{completed.stderr}")


def main() -> None:
    if OUTPUT_ROOT.exists():
        raise RuntimeError("long-duration artifacts already exist; refuse to overwrite")
    OUTPUT_ROOT.mkdir()
    source = ARTIFACTS / "kyoko_a.wav"
    cases: dict[int, Path] = {}
    for seconds in (10, 30, 60):
        output = OUTPUT_ROOT / f"duration_{seconds}s.wav"
        run([
            "/opt/homebrew/bin/ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-n",
            "-stream_loop", "-1", "-i", str(source), "-t", str(seconds), "-c:a", "pcm_s16le", str(output),
        ])
        cases[seconds] = output

    os.environ["HF_HUB_OFFLINE"] = "1"
    classifier = EncoderClassifier.from_hparams(
        source="speechbrain/spkrec-ecapa-voxceleb",
        savedir=str(MODEL_DIR),
        run_opts={"device": "cpu"},
        revision="0f99f2d0ebe89ac095bcc5903c4dd8f72b367286",
    )
    results: dict[str, dict[str, float | bool | int]] = {}
    for seconds, path in cases.items():
        signal = classifier.load_audio(str(path)).unsqueeze(0)
        started = time.perf_counter()
        with torch.no_grad():
            vector = classifier.encode_batch(signal).squeeze().cpu().numpy().astype(np.float32)
        results[str(seconds)] = {
            "file_bytes": path.stat().st_size,
            "inference_seconds": time.perf_counter() - started,
            "finite": bool(np.isfinite(vector).all()),
            "dimension": int(vector.shape[0]),
        }
    report = {
        "durations_seconds": results,
        "limitations": "繰返し人工音声による処理成立性・コスト確認であり、本番上限を単独で決定しない",
    }
    (OUTPUT_ROOT / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
