from __future__ import annotations

import json
import sys
import tempfile
import unittest
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "YoiSceneKirinuKu"
sys.path.insert(0, str(ROOT))
import speaker_decisions as module


class Emitter:
    def __init__(self): self.request_id = str(uuid.uuid4())
    def emit(self, *_): pass


class SpeakerDecisionTests(unittest.TestCase):
    def test_boundary_unknown_unique_match_and_multiple_unknown(self):
        identifier = "char_" + str(uuid.uuid4())
        other = "char_" + str(uuid.uuid4())
        self.assertEqual(module.decide([{"character_id": identifier, "cosine_similarity": module.MATCH_THRESHOLD - 1e-9}])["reason"], "below_threshold")
        self.assertEqual(module.decide([{"character_id": identifier, "cosine_similarity": module.MATCH_THRESHOLD}])["reason"], "boundary_uncertain")
        self.assertEqual(module.decide([{"character_id": identifier, "cosine_similarity": module.ACCEPTANCE_THRESHOLD - 1e-9}])["reason"], "boundary_uncertain")
        self.assertEqual(module.decide([{"character_id": identifier, "cosine_similarity": module.ACCEPTANCE_THRESHOLD}])["decision"], "matched")
        result = module.decide([
            {"character_id": identifier, "cosine_similarity": 0.95},
            {"character_id": other, "cosine_similarity": module.ACCEPTANCE_THRESHOLD},
        ])
        self.assertEqual((result["decision"], result["reason"]), ("unknown", "multiple_candidates"))

    def test_missing_invalid_and_deterministic(self):
        self.assertEqual(module.decide([])["reason"], "no_candidates")
        values = [{"character_id": "char_b", "cosine_similarity": 0.9}, {"character_id": "char_a", "cosine_similarity": 0.9}]
        first = module.decide(values)
        self.assertEqual(first, module.decide(list(reversed(values))))
        self.assertEqual(first["decision"], "unknown")
        with self.assertRaisesRegex(module.DecisionFailure, "speaker_decisions_input_invalid"):
            module.decide([{"character_id": "char_a", "cosine_similarity": float("nan")}])
        with self.assertRaisesRegex(module.DecisionFailure, "speaker_decisions_input_invalid"):
            module.decide([{"character_id": "char_a", "cosine_similarity": float("inf")}])

    def test_atomic_output_reuse_and_stale_rejection(self):
        with tempfile.TemporaryDirectory(dir="/private/tmp") as temporary:
            workspace = Path(temporary) / "workspace"
            source = Path(temporary) / "source.mp4"; source.write_bytes(b"source")
            job_id = str(uuid.uuid4()); request_id = str(uuid.uuid4())
            character_id = "char_" + str(uuid.uuid4())
            module.jobs.prepare_workspace(str(workspace))
            job = {"schema_version": 1, "job_id": job_id, "start_request_id": request_id, "state_revision": 0, "state": "preparing", "source": {"path": str(source), "fingerprint": module.jobs.source_fingerprint(source)}, "selected_character_ids": [character_id], "failure_code": None}
            module.jobs.write_job(workspace, job, request_id)
            current = workspace / "current_job"
            matches = {"schema_version": 1, "job_id": job_id, "speaker_candidates_fingerprint": {"algorithm": "sha256", "byte_count": 1, "digest": "0" * 64}, "model": dict(module.EXPECTED_MODEL), "selected_characters": [{"character_id": character_id}], "candidates": [{"candidate_id": "candidate_" + str(uuid.uuid4()), "comparisons": [{"character_id": character_id, "cosine_similarity": 0.4}]}]}
            path = current / "speaker_matches.json"; path.write_text(json.dumps(matches), encoding="utf-8")
            payload = {"workspace_root": str(workspace), "job_id": job_id}
            self.assertFalse(module.run(payload, Emitter())["reused"])
            self.assertTrue(module.run(payload, Emitter())["reused"])
            matches["candidates"][0]["comparisons"][0]["cosine_similarity"] = 0.5
            path.write_text(json.dumps(matches), encoding="utf-8")
            with self.assertRaisesRegex(module.DecisionFailure, "speaker_decisions_reuse_invalid"):
                module.run(payload, Emitter())

    def test_rejects_model_mismatch_before_writing_output(self):
        value = {
            "schema_version": 1,
            "job_id": str(uuid.uuid4()),
            "speaker_candidates_fingerprint": {"algorithm": "sha256", "byte_count": 1, "digest": "0" * 64},
            "model": {**module.EXPECTED_MODEL, "model_revision": "stale"},
            "selected_characters": [],
            "candidates": [],
        }
        with self.assertRaisesRegex(module.DecisionFailure, "speaker_decisions_input_invalid"):
            module.validate_input(value, value["job_id"])


if __name__ == "__main__": unittest.main()
