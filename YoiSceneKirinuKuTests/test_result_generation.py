from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "YoiSceneKirinuKu"
sys.path.insert(0, str(ROOT))
import result_generation as module


class ResultGenerationTests(unittest.TestCase):
    def test_generates_deterministic_strict_result(self):
        candidates = [
            {"candidate_id": "candidate_b", "start_ms": 4000, "end_ms": 7000, "duration_ms": 3000},
            {"candidate_id": "candidate_a", "start_ms": 0, "end_ms": 3000, "duration_ms": 3000},
        ]
        speakers = [
            {"candidate_id": "candidate_b", "decision": "unknown", "character_id": None, "top_similarity": 0.4, "reason": "below_threshold"},
            {"candidate_id": "candidate_a", "decision": "matched", "character_id": "char_a", "top_similarity": 0.9, "reason": "unique_match"},
        ]
        quality = [
            {"candidate_id": "candidate_b", "label": "needs_review", "automatic_reason_codes": ["noise"], "human_reason_codes": ["uncertain"], "human_input_status": "available"},
            {"candidate_id": "candidate_a", "label": "excellent", "automatic_reason_codes": [], "human_reason_codes": ["human_clear"], "human_input_status": "available"},
        ]
        result = module.generate(candidates, speakers, quality)
        self.assertEqual([item["candidate_id"] for item in result], ["candidate_a", "candidate_b"])
        self.assertEqual((result[0]["match"], result[0]["character_id"], result[0]["quality"]), ("matched", "char_a", "excellent"))
        self.assertEqual((result[1]["match"], result[1]["character_id"], result[1]["quality_reasons"]), ("unknown", None, ["noise", "uncertain"]))
        value = {"schema_version": 1, "job_id": "job", "contract_version": module.CONTRACT_VERSION, "sources": {}, "candidates": result}
        self.assertEqual(module.validate_output(value, "job", {}), value)

    def test_rejects_missing_or_invalid_contract(self):
        with self.assertRaisesRegex(module.ResultFailure, "result_input_invalid"):
            module.generate([{"candidate_id": "candidate_a", "start_ms": 0, "end_ms": 3000, "duration_ms": 3000}], [], [])
        value = {"schema_version": 1, "job_id": "job", "contract_version": "stale", "sources": {}, "candidates": []}
        with self.assertRaisesRegex(module.ResultFailure, "result_reuse_invalid"):
            module.validate_output(value, "job", {})


if __name__ == "__main__": unittest.main()
