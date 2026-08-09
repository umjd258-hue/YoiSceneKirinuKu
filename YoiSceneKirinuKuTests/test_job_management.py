from __future__ import annotations

import fcntl
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest
import uuid
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "YoiSceneKirinuKu" / "analysis_job_runner.py"
SPEC = importlib.util.spec_from_file_location("analysis_job_runner", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class CapturingEmitter:
    def __init__(self) -> None:
        self.events: list[tuple[str, dict]] = []

    def emit(self, event_type: str, payload: dict) -> None:
        self.events.append((event_type, payload))


class JobManagementTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(dir="/private/tmp")
        self.root = Path(self.temporary.name)
        self.workspace = self.root / "workspace"
        self.source = self.root / "日本語 source video.mp4"
        self.source.write_bytes((b"stage-9-source" * 1024) + b"end")

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def job(self, request_id: str | None = None) -> dict:
        return {
            "schema_version": 1,
            "job_id": str(uuid.uuid4()),
            "start_request_id": request_id or str(uuid.uuid4()),
            "state_revision": 0,
            "state": "start_requested",
            "source": {
                "path": str(self.source),
                "fingerprint": MODULE.source_fingerprint(self.source),
            },
            "selected_character_ids": ["char_" + str(uuid.uuid4())],
            "failure_code": None,
        }

    def request(self, operation: str, job: dict, request_id: str | None = None) -> dict:
        return {
            "protocol_version": 1,
            "request_id": request_id or job["start_request_id"],
            "operation": operation,
            "workspace_root": str(self.workspace),
            "job": job,
        }

    def create(self) -> tuple[dict, CapturingEmitter]:
        job = self.job()
        emitter = CapturingEmitter()
        result = MODULE.run(self.request("create_job", job), emitter)
        self.assertEqual(result, {"job_id": job["job_id"], "state": "start_requested"})
        return job, emitter

    def test_create_job_writes_valid_document_and_protocol_order(self) -> None:
        job, emitter = self.create()
        stored = MODULE.validate_job(MODULE.read_json(
            self.workspace / "current_job" / "job.json", "job_invalid"
        ))
        self.assertEqual(stored, job)
        self.assertEqual(emitter.events, [
            ("progress", {"stage": "job_lock", "status": "completed"}),
            ("progress", {"stage": "job_ready", "status": "completed"}),
        ])

    def test_second_job_is_rejected_without_replacing_first(self) -> None:
        first, _ = self.create()
        before = (self.workspace / "current_job" / "job.json").read_bytes()
        second = self.job()
        with self.assertRaisesRegex(MODULE.JobFailure, "job_already_exists"):
            MODULE.run(self.request("create_job", second), CapturingEmitter())
        self.assertEqual((self.workspace / "current_job" / "job.json").read_bytes(), before)
        self.assertEqual(MODULE.read_json(
            self.workspace / "current_job" / "job.json", "job_invalid"
        )["job_id"], first["job_id"])

    def test_lock_contention_rejects_before_job_creation(self) -> None:
        job = self.job()
        workspace = MODULE.prepare_workspace(str(self.workspace))
        descriptor = os.open(workspace / "analysis.lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with self.assertRaisesRegex(MODULE.JobFailure, "analysis_busy"):
                MODULE.run(self.request("create_job", job), CapturingEmitter())
        finally:
            os.close(descriptor)
        self.assertFalse((self.workspace / "current_job" / "job.json").exists())

    def test_recovery_marks_active_job_and_removes_valid_stale_stop(self) -> None:
        job, _ = self.create()
        marker = self.workspace / "current_job" / "stop.requested"
        marker.write_text(json.dumps({
            "schema_version": 1,
            "job_id": job["job_id"],
            "request_id": str(uuid.uuid4()),
        }), encoding="utf-8")
        request_id = str(uuid.uuid4())
        result = MODULE.run(self.request("recover_job", job, request_id), CapturingEmitter())
        self.assertEqual(result["state"], "recovery_required")
        recovered = MODULE.read_json(self.workspace / "current_job" / "job.json", "job_invalid")
        self.assertEqual(recovered["state_revision"], 1)
        self.assertFalse(marker.exists())

    def test_source_change_prevents_reuse(self) -> None:
        job, _ = self.create()
        self.source.write_bytes(b"changed")
        result = MODULE.run(
            self.request("recover_job", job, str(uuid.uuid4())), CapturingEmitter()
        )
        self.assertEqual(result["state"], "failed")
        failed = MODULE.read_json(self.workspace / "current_job" / "job.json", "job_invalid")
        self.assertEqual(failed["failure_code"], "source_changed")

    def test_malformed_stop_and_unknown_workspace_item_fail_closed(self) -> None:
        current = self.workspace / "current_job"
        current.mkdir(parents=True)
        (current / "stop.requested").write_text("{}", encoding="utf-8")
        with self.assertRaisesRegex(MODULE.JobFailure, "job_workspace_invalid"):
            MODULE.run(self.request("create_job", self.job()), CapturingEmitter())

        (current / "stop.requested").unlink()
        (current / "unknown.bin").write_bytes(b"unknown")
        with self.assertRaisesRegex(MODULE.JobFailure, "job_workspace_invalid"):
            MODULE.run(self.request("create_job", self.job()), CapturingEmitter())

    def test_subprocess_emits_only_json_lines_and_terminal_finished(self) -> None:
        job = self.job()
        request = self.request("create_job", job)
        completed = subprocess.run(
            [sys.executable, str(SCRIPT)],
            input=(json.dumps(request) + "\n").encode(),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        self.assertEqual(completed.returncode, 0)
        events = [json.loads(line) for line in completed.stdout.decode().splitlines()]
        self.assertEqual([event["type"] for event in events], ["progress", "progress", "finished"])
        self.assertEqual(events[-1]["payload"]["outcome"], "succeeded")
        self.assertEqual(completed.stderr, b"")


if __name__ == "__main__":
    unittest.main()
