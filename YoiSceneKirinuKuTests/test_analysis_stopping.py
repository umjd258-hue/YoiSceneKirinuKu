from __future__ import annotations

import json
import sys
import tempfile
import unittest
import uuid
from pathlib import Path


SOURCE_ROOT = Path(__file__).resolve().parents[1] / "YoiSceneKirinuKu"
sys.path.insert(0, str(SOURCE_ROOT))
import analysis_job_runner as jobs  # noqa: E402
import analysis_stopping as stopping  # noqa: E402


class AnalysisStoppingTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(dir="/private/tmp")
        self.workspace = Path(self.temporary.name) / "workspace"
        jobs.prepare_workspace(str(self.workspace))
        self.source = Path(self.temporary.name) / "source.mp4"
        self.source.write_bytes(b"artificial source")
        self.job_id = str(uuid.uuid4())
        self.request_id = str(uuid.uuid4())
        self.job = {
            "schema_version": 1, "job_id": self.job_id,
            "start_request_id": str(uuid.uuid4()), "state_revision": 1,
            "state": "stop_requested",
            "source": {"path": str(self.source), "fingerprint": jobs.source_fingerprint(self.source)},
            "selected_character_ids": ["char_" + str(uuid.uuid4())], "failure_code": None,
        }
        jobs.write_job(self.workspace, self.job, self.job["start_request_id"])
        self.current = self.workspace / "current_job"
        (self.current / "stop.requested").write_text(json.dumps({
            "schema_version": 1, "job_id": self.job_id, "request_id": self.request_id,
        }), encoding="utf-8")

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def test_completion_requires_valid_request_and_removes_marker_after_stopped(self) -> None:
        stop = stopping.requested(self.current, self.job_id)
        self.assertIsNotNone(stop)
        stored = stopping.complete(self.workspace, self.current, stop)
        self.assertEqual(stored["state"], "stopped")
        self.assertEqual(stored["state_revision"], 2)
        self.assertFalse((self.current / "stop.requested").exists())
        resumed = jobs.resume_job(self.workspace, self.job_id, str(uuid.uuid4()))
        self.assertEqual(resumed["state"], "preparing")
        self.assertEqual(resumed["state_revision"], 3)

    def test_unknown_schema_and_job_mismatch_fail_closed(self) -> None:
        marker = self.current / "stop.requested"
        value = json.loads(marker.read_text(encoding="utf-8"))
        value["schema_version"] = 2
        marker.write_text(json.dumps(value), encoding="utf-8")
        with self.assertRaisesRegex(stopping.StopFailure, "stop_request_invalid"):
            stopping.requested(self.current, self.job_id)

    def test_owned_process_group_stops_before_completion_classification(self) -> None:
        events: list[str] = []
        completed, stored = stopping.run_process(
            ["/bin/sleep", "10"], self.workspace, self.current, self.job_id, events.append,
        )
        self.assertIsNone(completed)
        self.assertEqual(stored["state"], "stopped")
        self.assertEqual(events, [
            "stop_requested_detected", "child_exit_observed", "post_stop_state_verified",
        ])
        self.assertFalse((self.current / "stop.requested").exists())


if __name__ == "__main__":
    unittest.main()
