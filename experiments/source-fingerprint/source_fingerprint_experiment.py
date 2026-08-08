#!/usr/bin/env python3
"""人工ファイルによるSource fingerprint候補の限定比較実験。"""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import statistics
import time
from pathlib import Path
from typing import Callable


ROOT = Path(__file__).resolve().parent
ARTIFACTS = ROOT / "artifacts"
REPORT = ARTIFACTS / "report.json"
SIZES = {"small": 1 << 20, "medium": 64 << 20, "large": 256 << 20}
SAMPLE_BYTES = 64 << 10
REPETITIONS = 5
CHUNK_BYTES = 1 << 20


def ensure_inside(path: Path) -> None:
    resolved = path.resolve(strict=False)
    root = ARTIFACTS.resolve(strict=False)
    if resolved != root and root not in resolved.parents:
        raise RuntimeError(f"artifact path escaped experiment root: {resolved}")


def write_artificial(path: Path, size: int, seed: int) -> None:
    ensure_inside(path)
    block = bytes(((index + seed) % 251 for index in range(CHUNK_BYTES)))
    remaining = size
    with path.open("xb") as handle:
        while remaining:
            data = block[: min(remaining, len(block))]
            handle.write(data)
            remaining -= len(data)


def sampled_offsets(size: int) -> list[int]:
    width = min(SAMPLE_BYTES, size)
    return sorted({0, max(0, (size - width) // 2), max(0, size - width)})


def partial_digest(path: Path) -> tuple[str, int]:
    size = path.stat().st_size
    digest = hashlib.sha256()
    read_bytes = 0
    with path.open("rb") as handle:
        for offset in sampled_offsets(size):
            handle.seek(offset)
            data = handle.read(min(SAMPLE_BYTES, size - offset))
            digest.update(offset.to_bytes(8, "big"))
            digest.update(data)
            read_bytes += len(data)
    return digest.hexdigest(), read_bytes


def full_digest(path: Path) -> tuple[str, int]:
    digest = hashlib.sha256()
    read_bytes = 0
    with path.open("rb") as handle:
        while data := handle.read(CHUNK_BYTES):
            digest.update(data)
            read_bytes += len(data)
    return digest.hexdigest(), read_bytes


def fingerprint(path: Path, method: str) -> tuple[dict[str, object], int]:
    stat = path.stat()
    if method == "size":
        return {"size": stat.st_size}, 0
    if method == "size_mtime":
        return {"size": stat.st_size, "mtime_ns": stat.st_mtime_ns}, 0
    if method in {"size_mtime_partial", "size_partial"}:
        digest, read_bytes = partial_digest(path)
        value: dict[str, object] = {"size": stat.st_size, "partial_sha256": digest}
        if method == "size_mtime_partial":
            value["mtime_ns"] = stat.st_mtime_ns
        return value, read_bytes
    if method == "size_full":
        digest, read_bytes = full_digest(path)
        return {"size": stat.st_size, "full_sha256": digest}, read_bytes
    raise ValueError(method)


METHODS = ["size", "size_mtime", "size_mtime_partial", "size_partial", "size_full"]


def flip_byte(path: Path, offset: int) -> None:
    with path.open("r+b") as handle:
        handle.seek(offset)
        original = handle.read(1)
        if not original:
            raise RuntimeError("mutation offset is outside file")
        handle.seek(offset)
        handle.write(bytes([original[0] ^ 0xFF]))


def mutation_matrix(base: Path) -> dict[str, object]:
    original_stat = base.stat()
    original = {method: fingerprint(base, method)[0] for method in METHODS}
    size = original_stat.st_size
    cases: list[tuple[str, Callable[[Path], None], bool]] = [
        ("unchanged", lambda path: None, False),
        ("mtime_only", lambda path: os.utime(path, ns=(original_stat.st_atime_ns, original_stat.st_mtime_ns + 2_000_000_000)), False),
        ("append", lambda path: path.open("ab").write(b"APPEND"), True),
        ("truncate", lambda path: path.open("r+b").truncate(size - 1), True),
        ("same_size_head", lambda path: flip_byte(path, 1), True),
        ("same_size_middle", lambda path: flip_byte(path, size // 2), True),
        ("same_size_tail", lambda path: flip_byte(path, size - 2), True),
        ("same_size_unsampled", lambda path: flip_byte(path, size // 4), True),
        ("changed_mtime_restored", lambda path: (flip_byte(path, size // 4), os.utime(path, ns=(original_stat.st_atime_ns, original_stat.st_mtime_ns))), True),
        ("replacement_same_size_mtime", lambda path: replace_same_metadata(path, size, original_stat), True),
    ]
    results: dict[str, object] = {}
    work = ARTIFACTS / "mutation-work.bin"
    for name, mutate, content_changed in cases:
        ensure_inside(work)
        shutil.copy2(base, work)
        mutate(work)
        detected = {method: fingerprint(work, method)[0] != original[method] for method in METHODS}
        results[name] = {"content_changed": content_changed, "detected": detected}
        work.unlink()
    return results


def replace_same_metadata(path: Path, size: int, original_stat: os.stat_result) -> None:
    replacement = ARTIFACTS / "replacement.bin"
    write_artificial(replacement, size, seed=97)
    os.utime(replacement, ns=(original_stat.st_atime_ns, original_stat.st_mtime_ns))
    os.replace(replacement, path)


def benchmark(files: dict[str, Path]) -> dict[str, object]:
    results: dict[str, object] = {}
    for label, path in files.items():
        per_method: dict[str, object] = {}
        for method in METHODS:
            durations: list[int] = []
            reads: list[int] = []
            for _ in range(REPETITIONS):
                started = time.perf_counter_ns()
                _, read_bytes = fingerprint(path, method)
                durations.append(time.perf_counter_ns() - started)
                reads.append(read_bytes)
            per_method[method] = {
                "first_ns": durations[0],
                "repeat_median_ns": int(statistics.median(durations[1:])),
                "min_ns": min(durations),
                "max_ns": max(durations),
                "read_bytes": reads[0],
                "runs": REPETITIONS,
            }
        results[label] = {"file_size": path.stat().st_size, "methods": per_method}
    return results


def validate(report: dict[str, object]) -> None:
    matrix = report["detection_matrix"]
    assert isinstance(matrix, dict)
    assert all(not value["detected"][method] for method in METHODS for value in [matrix["unchanged"]])
    assert matrix["mtime_only"]["detected"]["size_mtime"] is True
    assert matrix["mtime_only"]["detected"]["size_full"] is False
    for case in ("append", "truncate", "same_size_head", "same_size_middle", "same_size_tail", "same_size_unsampled", "changed_mtime_restored", "replacement_same_size_mtime"):
        assert matrix[case]["detected"]["size_full"] is True
    assert matrix["same_size_unsampled"]["detected"]["size_partial"] is False
    assert matrix["changed_mtime_restored"]["detected"]["size_mtime"] is False


def main() -> int:
    ARTIFACTS.mkdir(exist_ok=True)
    files: dict[str, Path] = {}
    for index, (label, size) in enumerate(SIZES.items(), start=1):
        path = ARTIFACTS / f"artificial-{label}.bin"
        ensure_inside(path)
        if path.exists():
            path.unlink()
        write_artificial(path, size, seed=index)
        files[label] = path

    report: dict[str, object] = {
        "conditions": {
            "sizes": SIZES,
            "sample_bytes_per_region": SAMPLE_BYTES,
            "sample_regions": 3,
            "repetitions": REPETITIONS,
            "cache_note": "first and repeated runs may both be affected by OS cache",
        },
        "detection_matrix": mutation_matrix(files["small"]),
        "benchmarks": benchmark(files),
    }
    validate(report)
    REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"status": "PASS", "report": str(REPORT), "methods": METHODS}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
