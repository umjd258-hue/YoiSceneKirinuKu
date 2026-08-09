#!/usr/bin/env python3
from __future__ import annotations

import array
import json
import math
import random
import re
import statistics
import subprocess
import time
import wave
from pathlib import Path


ROOT = Path(__file__).resolve().parent
ARTIFACTS = ROOT / "artifacts"
RATE = 16_000
FRAME_MS = 30
THRESHOLD_DBFS = -45.0
MIN_ACTIVE_MS = 90
FFMPEG = Path("/opt/homebrew/bin/ffmpeg")


def amplitude(dbfs: float) -> int:
    return round(32767 * (10 ** (dbfs / 20)))


def tone(duration_ms: int, dbfs: float, frequency: float = 220.0) -> list[int]:
    peak = amplitude(dbfs)
    return [round(peak * math.sin(2 * math.pi * frequency * index / RATE))
            for index in range(RATE * duration_ms // 1000)]


def silence(duration_ms: int) -> list[int]:
    return [0] * (RATE * duration_ms // 1000)


def noise(duration_ms: int, dbfs: float) -> list[int]:
    generator = random.Random(20260809)
    peak = amplitude(dbfs)
    return [generator.randint(-peak, peak) for _ in range(RATE * duration_ms // 1000)]


def write_wav(path: Path, samples: list[int], rate: int = RATE) -> None:
    values = array.array("h", samples)
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(rate)
        output.writeframes(values.tobytes())


def validate_input(path: Path) -> tuple[list[int], int]:
    try:
        with wave.open(str(path), "rb") as source:
            if (source.getnchannels(), source.getsampwidth(), source.getframerate(), source.getcomptype()) != (1, 2, RATE, "NONE"):
                raise ValueError("vad_input_invalid")
            frames = source.getnframes()
            if frames <= 0:
                raise ValueError("vad_input_invalid")
            values = array.array("h")
            values.frombytes(source.readframes(frames))
    except (EOFError, OSError, wave.Error) as error:
        raise ValueError("vad_input_invalid") from error
    return values.tolist(), frames


def rms_segments(path: Path) -> list[list[int]]:
    samples, frame_count = validate_input(path)
    frame_size = RATE * FRAME_MS // 1000
    active: list[tuple[int, int]] = []
    for start in range(0, frame_count, frame_size):
        frame = samples[start:min(start + frame_size, frame_count)]
        rms = math.sqrt(sum(sample * sample for sample in frame) / len(frame))
        dbfs = -math.inf if rms == 0 else 20 * math.log10(rms / 32767)
        if dbfs >= THRESHOLD_DBFS:
            active.append((start, min(start + frame_size, frame_count)))
    grouped: list[list[int]] = []
    for start, end in active:
        start_ms = start * 1000 // RATE
        end_ms = math.ceil(end * 1000 / RATE)
        if grouped and start_ms == grouped[-1][1]:
            grouped[-1][1] = end_ms
        else:
            grouped.append([start_ms, end_ms])
    return [segment for segment in grouped if segment[1] - segment[0] >= MIN_ACTIVE_MS]


def ffmpeg_segments(path: Path) -> list[list[int]]:
    validate_input(path)
    command = [
        str(FFMPEG), "-nostdin", "-hide_banner", "-i", str(path),
        "-af", f"silencedetect=noise={THRESHOLD_DBFS}dB:d={MIN_ACTIVE_MS / 1000}",
        "-f", "null", "-",
    ]
    completed = subprocess.run(command, shell=False, capture_output=True, text=True, check=False)
    if completed.returncode != 0:
        raise ValueError("vad_processing_failed")
    duration_ms = round(len(validate_input(path)[0]) * 1000 / RATE)
    silence_starts = [float(value) for value in re.findall(r"silence_start: ([0-9.]+)", completed.stderr)]
    silence_ends = [float(value) for value in re.findall(r"silence_end: ([0-9.]+)", completed.stderr)]
    silent: list[tuple[int, int]] = []
    end_index = 0
    for start in silence_starts:
        while end_index < len(silence_ends) and silence_ends[end_index] < start:
            end_index += 1
        end = silence_ends[end_index] if end_index < len(silence_ends) else duration_ms / 1000
        silent.append((round(start * 1000), round(end * 1000)))
        end_index += 1
    cursor = 0
    active: list[list[int]] = []
    for start, end in silent:
        if start > cursor:
            active.append([cursor, start])
        cursor = max(cursor, end)
    if cursor < duration_ms:
        active.append([cursor, duration_ms])
    return [segment for segment in active if segment[1] - segment[0] >= MIN_ACTIVE_MS]


def close_to(actual: list[list[int]], expected: list[list[int]], tolerance_ms: int = 40) -> bool:
    return len(actual) == len(expected) and all(
        abs(a_start - e_start) <= tolerance_ms and abs(a_end - e_end) <= tolerance_ms
        for (a_start, a_end), (e_start, e_end) in zip(actual, expected)
    )


def timed(function, path: Path) -> dict[str, float]:
    durations = []
    for _ in range(7):
        started = time.perf_counter_ns()
        function(path)
        durations.append((time.perf_counter_ns() - started) / 1_000_000)
    return {
        "median_ms": round(statistics.median(durations), 3),
        "min_ms": round(min(durations), 3),
        "max_ms": round(max(durations), 3),
    }


def main() -> int:
    ARTIFACTS.mkdir(exist_ok=True)
    fixtures = {
        "silence": (silence(2000), []),
        "two_regions": (
            silence(300) + tone(510, -18) + silence(210) + tone(600, -20, 330) + silence(390),
            [[300, 810], [1020, 1620]],
        ),
        "quiet_region": (silence(300) + tone(510, -40) + silence(300), [[300, 810]]),
        "low_noise": (noise(2000, -55), []),
        "short_burst": (silence(300) + tone(30, -10) + silence(300), []),
    }
    paths: dict[str, Path] = {}
    for name, (samples, _) in fixtures.items():
        path = ARTIFACTS / f"{name}.wav"
        write_wav(path, samples)
        paths[name] = path
    invalid = ARTIFACTS / "corrupt.wav"
    invalid.write_bytes(b"not a wav")
    wrong_rate = ARTIFACTS / "wrong_rate.wav"
    write_wav(wrong_rate, tone(500, -18), rate=8000)

    candidates = {"python_frame_rms": rms_segments, "ffmpeg_silencedetect": ffmpeg_segments}
    results: dict[str, object] = {}
    for candidate, function in candidates.items():
        cases = {}
        for name, (_, expected) in fixtures.items():
            actual = function(paths[name])
            cases[name] = {"expected": expected, "actual": actual, "passed": close_to(actual, expected)}
        invalid_codes = []
        for path in (invalid, wrong_rate):
            try:
                function(path)
                invalid_codes.append("accepted")
            except ValueError as error:
                invalid_codes.append(str(error))
        results[candidate] = {
            "cases": cases,
            "invalid_input_codes": invalid_codes,
            "timing_two_seconds": timed(function, paths["low_noise"]),
        }

    import torch
    import torchaudio
    waveform = torch.tensor(fixtures["two_regions"][0], dtype=torch.float32).unsqueeze(0) / 32768
    trimmed = torchaudio.functional.vad(waveform, RATE)
    torchaudio_result = {
        "available": True,
        "torch_version": torch.__version__,
        "torchaudio_version": torchaudio.__version__,
        "input_samples": waveform.shape[-1],
        "output_samples": trimmed.shape[-1],
        "supports_all_intervals": False,
        "reason": "API returns waveform trimmed before one trigger and does not return every activity interval",
    }
    all_passed = all(
        case["passed"]
        for candidate in results.values()
        for case in candidate["cases"].values()
    ) and all(
        code == "vad_input_invalid"
        for candidate in results.values()
        for code in candidate["invalid_input_codes"]
    )
    report = {
        "conditions": {
            "sample_rate_hz": RATE,
            "channels": 1,
            "sample_format": "pcm_s16le",
            "frame_ms": FRAME_MS,
            "activity_threshold_dbfs": THRESHOLD_DBFS,
            "minimum_activity_ms": MIN_ACTIVE_MS,
            "repetitions": 7,
        },
        "candidates": results,
        "torchaudio_functional_vad": torchaudio_result,
        "all_expected_checks_passed": all_passed,
    }
    (ARTIFACTS / "report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))
    return 0 if all_passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
