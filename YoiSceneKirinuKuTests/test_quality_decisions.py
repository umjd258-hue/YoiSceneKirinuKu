from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path


SOURCE_ROOT = Path(__file__).resolve().parents[1] / "YoiSceneKirinuKu"
sys.path.insert(0, str(SOURCE_ROOT))
sys.path.insert(0, str(Path(__file__).resolve().parent))
import quality_decisions as module
import test_quality_features as feature_test_support


class QualityDecisionTests(unittest.TestCase):
    def setUp(self) -> None:
        feature_test_support.QualityFeatureTests.setUp(self)
        module.features.run(self.request(), feature_test_support.CapturingEmitter())

    def tearDown(self) -> None:
        feature_test_support.QualityFeatureTests.tearDown(self)

    def _write_inputs(self) -> None:
        feature_test_support.QualityFeatureTests._write_inputs(self)

    def _write_wav(self, path: Path) -> None:
        feature_test_support.QualityFeatureTests._write_wav(self, path)

    def request(self) -> dict:
        return {"workspace_root": str(self.workspace), "job_id": self.job_id}

    def _candidate_ids(self) -> list[str]:
        value = json.loads((self.workspace / "current_job" / "speaker_candidates.json").read_text())
        return [item["candidate_id"] for item in value["candidates"]]

    def _write_assessments(self, items: list[dict]) -> None:
        current = self.workspace / "current_job"
        candidate_fp = module.candidates.file_fingerprint(current / "speaker_candidates.json", "candidate_reuse_invalid")
        value = {
            "schema_version": 1,
            "job_id": self.job_id,
            "speaker_candidates_fingerprint": candidate_fp,
            "contract_version": module.CONTRACT_VERSION,
            "candidates": items,
        }
        (current / "quality_human_assessments.json").write_text(json.dumps(value), encoding="utf-8")

    def test_generates_separate_atomic_output_and_reuses(self) -> None:
        identifier = self._candidate_ids()[0]
        self._write_assessments([{"candidate_id": identifier, "label": "excellent", "reason_codes": ["human_clear"]}])
        self.assertEqual(module.run(self.request(), feature_test_support.CapturingEmitter()), {"reused": False, "candidate_count": 1})
        output = json.loads((self.workspace / "current_job" / "quality_decisions.json").read_text())
        self.assertEqual(output["candidates"][0]["label"], "excellent")
        self.assertTrue((self.workspace / "current_job" / "quality_features.json").is_file())
        self.assertEqual(module.run(self.request(), feature_test_support.CapturingEmitter()), {"reused": True, "candidate_count": 1})

    def test_missing_invalid_and_uncertain_fail_closed(self) -> None:
        identifier = self._candidate_ids()[0]
        missing, status = module.combine([identifier], None)
        self.assertEqual((missing[0]["label"], status), ("needs_review", "missing"))
        invalid, status = module.combine([identifier], {
            "schema_version": 1, "job_id": self.job_id,
            "speaker_candidates_fingerprint": {}, "contract_version": module.CONTRACT_VERSION,
            "candidates": [{"candidate_id": identifier, "label": "excellent", "reason_codes": ["bgm"]}],
        })
        self.assertEqual((invalid[0]["label"], invalid[0]["human_input_status"]), ("needs_review", "invalid"))
        uncertain, _ = module.combine([identifier], {
            "schema_version": 1, "job_id": self.job_id,
            "speaker_candidates_fingerprint": {}, "contract_version": module.CONTRACT_VERSION,
            "candidates": [{"candidate_id": identifier, "label": "needs_review", "reason_codes": ["uncertain"]}],
        })
        self.assertEqual((uncertain[0]["label"], uncertain[0]["human_input_status"]), ("needs_review", "available"))

    def test_stale_assessment_rejects_existing_output(self) -> None:
        identifier = self._candidate_ids()[0]
        self._write_assessments([{"candidate_id": identifier, "label": "excellent", "reason_codes": ["human_clear"]}])
        module.run(self.request(), feature_test_support.CapturingEmitter())
        self._write_assessments([{"candidate_id": identifier, "label": "good", "reason_codes": ["human_usable_with_issue"]}])
        with self.assertRaisesRegex(module.QualityDecisionFailure, "quality_decisions_reuse_invalid"):
            module.run(self.request(), feature_test_support.CapturingEmitter())

    def test_fixed_validation_contract(self) -> None:
        labels = [
            "excellent", "good", "needs_review", "good", "needs_review", "good",
            "excellent", "excellent", "excellent", "excellent", "excellent", "good",
            "excellent", "good", "excellent", "needs_review", "needs_review", "needs_review",
            "needs_review", "excellent", "needs_review", "good", "good", "excellent",
            "good", "good", "good", "good", "needs_review", "needs_review", "good", "good",
            "good", "needs_review", "needs_review", "excellent",
        ]
        identifiers = [f"candidate_{index:03d}" for index in range(36)]
        reasons = {"excellent": ["human_clear"], "good": ["human_usable_with_issue"], "needs_review": ["uncertain"]}
        value = {
            "schema_version": 1, "job_id": self.job_id,
            "speaker_candidates_fingerprint": {}, "contract_version": module.CONTRACT_VERSION,
            "candidates": [
                {"candidate_id": identifier, "label": label, "reason_codes": reasons[label]}
                for identifier, label in zip(identifiers, labels)
            ],
        }
        decisions, status = module.combine(identifiers, value)
        validation = [0, 3, 6, 9, 12, 15, 18, 21, 24, 27, 30, 33]
        predicted = [decisions[index]["label"] for index in validation]
        expected = [labels[index] for index in validation]
        self.assertEqual(status, "available")
        self.assertEqual(predicted, expected)
        self.assertEqual(sum(left == right for left, right in zip(predicted, expected)), 12)


if __name__ == "__main__":
    unittest.main()
