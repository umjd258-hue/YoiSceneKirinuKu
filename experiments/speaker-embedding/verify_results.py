#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parent
ARTIFACTS = ROOT / "artifacts"


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def main() -> None:
    embedding = read_json(ARTIFACTS / "report.json")
    quality = read_json(ARTIFACTS / "quality" / "report.json")
    duration = read_json(ARTIFACTS / "long-duration" / "report.json")

    assert embedding["embedding"]["dimension"] == 192
    assert embedding["embedding"]["finite"] is True
    assert embedding["embedding"]["repeat_max_abs_delta"] == 0.0
    similarities = embedding["cosine_similarity"]
    assert similarities["same_kyoko"] > similarities["different_same_text"]
    assert similarities["same_eddy"] > similarities["different_other_text"]
    assert similarities["kyoko_a_to_kyoko_centroid"] > similarities["same_kyoko"]
    assert similarities["kyoko_b_to_kyoko_centroid"] > similarities["same_kyoko"]

    cosine_to_full = quality["cosine_to_full"]
    assert cosine_to_full["duration_3000"] > cosine_to_full["duration_1000"]
    assert quality["input_metrics"]["silence"]["rms_dbfs"] == float("-inf")
    assert "silence" in cosine_to_full

    for seconds in ("10", "30", "60"):
        result = duration["durations_seconds"][seconds]
        assert result["finite"] is True
        assert result["dimension"] == 192

    print("speaker embedding result verification: PASS")


if __name__ == "__main__":
    main()
