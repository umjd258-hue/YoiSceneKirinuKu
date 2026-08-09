#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import math
import time
import uuid
from pathlib import Path


ROOT = Path(__file__).resolve().parent
ARTIFACTS = ROOT / "artifacts"
JOB_ID = "8c6a5777-0475-43c9-8502-9d64cb790589"
PROFILES = {
    "compact": {"merge_gap_ms": 250, "padding_ms": 150, "minimum_ms": 3000, "maximum_ms": 30000},
    "balanced": {"merge_gap_ms": 500, "padding_ms": 250, "minimum_ms": 3000, "maximum_ms": 30000},
    "broad": {"merge_gap_ms": 1000, "padding_ms": 500, "minimum_ms": 3000, "maximum_ms": 30000},
}


def expand(start: int, end: int, minimum: int, duration: int) -> tuple[int, int]:
    missing = minimum - (end - start)
    if missing <= 0 or duration <= end - start:
        return start, end
    before = missing // 2
    after = missing - before
    start = max(0, start - before)
    end = min(duration, end + after)
    if end - start < minimum:
        if start == 0:
            end = min(duration, minimum)
        elif end == duration:
            start = max(0, duration - minimum)
    return start, end


def split_interval(start: int, end: int, minimum: int, maximum: int) -> list[tuple[int, int]]:
    result = []
    cursor = start
    while end - cursor > maximum:
        length = maximum
        if end - (cursor + length) < minimum:
            length = end - cursor - minimum
        result.append((cursor, cursor + length))
        cursor += length
    result.append((cursor, end))
    return result


def generate(intervals: list[tuple[int, int]], duration: int, profile: dict[str, int]) -> list[dict[str, object]]:
    if duration <= 0:
        raise ValueError("duration_invalid")
    prior_end = 0
    for start, end in intervals:
        if start < prior_end or start < 0 or end <= start or end > duration:
            raise ValueError("vad_invalid")
        prior_end = end
    if duration < profile["minimum_ms"]:
        return []
    merged: list[list[int]] = []
    for start, end in intervals:
        if merged and start - merged[-1][1] <= profile["merge_gap_ms"]:
            merged[-1][1] = end
        else:
            merged.append([start, end])
    padded = [
        list(expand(
            max(0, start - profile["padding_ms"]),
            min(duration, end + profile["padding_ms"]),
            profile["minimum_ms"], duration,
        ))
        for start, end in merged
    ]
    united: list[list[int]] = []
    for start, end in padded:
        if united and start <= united[-1][1]:
            united[-1][1] = max(united[-1][1], end)
        else:
            united.append([start, end])
    namespace = uuid.UUID(JOB_ID)
    candidates = []
    for start, end in united:
        for split_start, split_end in split_interval(
            start, end, profile["minimum_ms"], profile["maximum_ms"],
        ):
            identifier = uuid.uuid5(namespace, f"candidate:v1:{split_start}:{split_end}")
            candidates.append({
                "candidate_id": f"candidate_{identifier}",
                "start_ms": split_start,
                "end_ms": split_end,
                "duration_ms": split_end - split_start,
            })
    return candidates


def no_overlap(candidates: list[dict[str, object]], duration: int) -> bool:
    prior_end = 0
    identifiers = set()
    for candidate in candidates:
        start = candidate["start_ms"]
        end = candidate["end_ms"]
        identifier = candidate["candidate_id"]
        if not (isinstance(start, int) and isinstance(end, int) and 0 <= prior_end <= start < end <= duration):
            return False
        if candidate["duration_ms"] != end - start or identifier in identifiers:
            return False
        identifiers.add(identifier)
        prior_end = end
    return True


def canonical_fingerprint(value: object) -> dict[str, object]:
    encoded = (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode()
    return {"algorithm": "sha256", "byte_count": len(encoded), "digest": hashlib.sha256(encoded).hexdigest()}


def main() -> int:
    ARTIFACTS.mkdir(exist_ok=True)
    cases = {
        "zero": {"duration": 10000, "intervals": []},
        "micro_pause_400": {"duration": 12000, "intervals": [(1000, 5000), (5400, 9000)]},
        "separate_pause_800": {"duration": 12000, "intervals": [(1000, 5000), (5800, 9000)]},
        "short_at_start": {"duration": 10000, "intervals": [(0, 300)]},
        "short_at_end": {"duration": 10000, "intervals": [(9700, 10000)]},
        "short_video": {"duration": 2000, "intervals": [(200, 1800)]},
        "long_65000": {"duration": 70000, "intervals": [(2000, 67000)]},
    }
    expected_counts = {
        "compact": {"micro_pause_400": 2, "separate_pause_800": 2},
        "balanced": {"micro_pause_400": 1, "separate_pause_800": 2},
        "broad": {"micro_pause_400": 1, "separate_pause_800": 1},
    }
    report: dict[str, object] = {"profiles": {}, "selected": "balanced"}
    all_passed = True
    for name, profile in PROFILES.items():
        profile_cases = {}
        started = time.perf_counter_ns()
        for case_name, case in cases.items():
            first = generate(case["intervals"], case["duration"], profile)
            second = generate(case["intervals"], case["duration"], profile)
            valid = no_overlap(first, case["duration"]) and first == second
            if case_name in expected_counts[name]:
                valid = valid and len(first) == expected_counts[name][case_name]
            if case_name == "zero":
                valid = valid and first == []
            if case_name == "short_video":
                valid = valid and first == []
            if case_name in {"short_at_start", "short_at_end"}:
                valid = valid and len(first) == 1 and first[0]["duration_ms"] == 3000
            if case_name == "long_65000":
                valid = valid and all(3000 <= item["duration_ms"] <= 30000 for item in first)
            profile_cases[case_name] = {"candidates": first, "passed": valid}
            all_passed = all_passed and valid
        elapsed_ms = (time.perf_counter_ns() - started) / 1_000_000
        report["profiles"][name] = {
            "parameters": profile,
            "cases": profile_cases,
            "elapsed_ms": round(elapsed_ms, 3),
        }
    invalid_rejected = False
    try:
        generate([(1000, 3000), (2500, 4000)], 10000, PROFILES["balanced"])
    except ValueError as error:
        invalid_rejected = str(error) == "vad_invalid"
    report["invalid_overlap_rejected"] = invalid_rejected
    report["canonical_vad_fingerprint_example"] = canonical_fingerprint({
        "schema_version": 1,
        "job_id": JOB_ID,
        "segments": [{"start_ms": 1000, "end_ms": 5000}],
    })
    report["all_expected_checks_passed"] = all_passed and invalid_rejected
    (ARTIFACTS / "report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))
    return 0 if report["all_expected_checks_passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
