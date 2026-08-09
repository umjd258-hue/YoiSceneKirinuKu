from __future__ import annotations

import importlib.util
import json
import math
import subprocess
import sys
import tempfile
import unittest
import uuid
import wave
from pathlib import Path
from unittest import mock


SOURCE_ROOT = Path(__file__).resolve().parents[1] / "YoiSceneKirinuKu"
sys.path.insert(0, str(SOURCE_ROOT))
SCRIPT = SOURCE_ROOT / "vad.py"
SPEC = importlib.util.spec_from_file_location("vad", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class CapturingEmitter:
    def __init__(self) -> None:
        self.events: list[tuple[str, dict]] = []

    def emit(self, event_type: str, payload: dict) -> None:
        self.events.append((event_type, payload))


class VADTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(dir="/private/tmp")
        self.root = Path(self.temporary.name)
        self.workspace = self.root / "workspace"
        self.source = self.root / "source.mp4"
        self.source.write_bytes(b"source")
        self.job = {
            "schema_version": 1,
            "job_id": str(uuid.uuid4()),
            "start_request_id": str(uuid.uuid4()),
            "state_revision": 0,
            "state": "start_requested",
            "source": {
                "path": str(self.source),
                "fingerprint": MODULE.jobs.source_fingerprint(self.source),
            },
            "selected_character_ids": ["char_" + str(uuid.uuid4())],
            "failure_code": None,
        }
        MODULE.jobs.prepare_workspace(str(self.workspace))
        MODULE.jobs.write_job(self.workspace, self.job, self.job["start_request_id"])

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def request(self) -> dict:
        return {
            "protocol_version": 1,
            "request_id": str(uuid.uuid4()),
            "workspace_root": str(self.workspace),
            "job_id": self.job["job_id"],
        }

    def write_formal_pair(self, samples: list[int]) -> None:
        current = self.workspace / "current_job"
        wav_path = current / "analysis.wav"
        with wave.open(str(wav_path), "wb") as output:
            output.setnchannels(1)
            output.setsampwidth(2)
            output.setframerate(16_000)
            output.writeframes(b"".join(sample.to_bytes(2, "little", signed=True) for sample in samples))
        wav = MODULE.audio.validate_wav(wav_path)
        metadata = {
            "schema_version": 1,
            "job_id": self.job["job_id"],
            "source_fingerprint": self.job["source"]["fingerprint"],
            "profile": MODULE.audio.PROFILE,
            "selected_stream_index": 0,
            **wav,
        }
        (current / "analysis_audio.json").write_text(json.dumps(metadata), encoding="utf-8")

    @staticmethod
    def signal(parts: list[tuple[int, int]]) -> list[int]:
        samples: list[int] = []
        for duration_ms, peak in parts:
            for index in range(16_000 * duration_ms // 1000):
                samples.append(round(peak * math.sin(2 * math.pi * 220 * index / 16_000)) if peak else 0)
        return samples

    def test_detects_activity_regions_from_formal_pair(self) -> None:
        self.write_formal_pair(self.signal([(300, 0), (510, 6000), (210, 0), (600, 5000), (390, 0)]))
        emitter = CapturingEmitter()
        result = MODULE.process(self.request(), emitter)
        self.assertEqual(result, {
            "frame_ms": 30,
            "segment_count": 2,
            "segments": [{"start_ms": 300, "end_ms": 810}, {"start_ms": 1020, "end_ms": 1620}],
        })
        self.assertEqual(emitter.events, [
            ("progress", {"stage": "vad", "status": "running"}),
            ("progress", {"stage": "vad", "status": "completed"}),
        ])
        self.assertFalse((self.workspace / "current_job" / "vad.json").exists())

    def test_silence_and_short_activity_are_successful_empty_results(self) -> None:
        self.write_formal_pair(self.signal([(300, 0), (30, 12_000), (300, 0)]))
        result = MODULE.process(self.request(), CapturingEmitter())
        self.assertEqual(result["segment_count"], 0)
        self.assertEqual(result["segments"], [])

    def test_missing_or_invalid_formal_pair_is_rejected(self) -> None:
        with self.assertRaisesRegex(MODULE.VADFailure, "vad_input_unavailable"):
            MODULE.process(self.request(), CapturingEmitter())
        self.write_formal_pair(self.signal([(300, 0), (300, 6000)]))
        metadata = self.workspace / "current_job" / "analysis_audio.json"
        value = json.loads(metadata.read_text(encoding="utf-8"))
        value["schema_version"] = 2
        metadata.write_text(json.dumps(value), encoding="utf-8")
        with self.assertRaisesRegex(MODULE.VADFailure, "vad_input_invalid"):
            MODULE.process(self.request(), CapturingEmitter())

    def test_dangling_formal_symlink_is_invalid(self) -> None:
        current = self.workspace / "current_job"
        (current / "analysis.wav").symlink_to(self.root / "missing.wav")
        (current / "analysis_audio.json").write_text("{}", encoding="utf-8")
        with self.assertRaisesRegex(MODULE.VADFailure, "vad_input_invalid"):
            MODULE.process(self.request(), CapturingEmitter())

    def test_partial_is_not_consumed_or_persisted(self) -> None:
        self.write_formal_pair(self.signal([(300, 0), (300, 6000)]))
        partial = self.workspace / ".partial" / f"analysis_{uuid.uuid4()}.wav.partial"
        partial.write_bytes(b"partial")
        MODULE.process(self.request(), CapturingEmitter())
        self.assertEqual(partial.read_bytes(), b"partial")
        self.assertFalse((self.workspace / "current_job" / "vad.json").exists())

    def test_unexpected_detector_failure_uses_stable_error(self) -> None:
        self.write_formal_pair(self.signal([(300, 0), (300, 6000)]))
        with mock.patch.object(MODULE, "detect_segments", side_effect=RuntimeError("test")):
            with self.assertRaisesRegex(MODULE.VADFailure, "vad_processing_failed"):
                MODULE.process(self.request(), CapturingEmitter())

    def test_cli_emits_strict_progress_and_finished_events(self) -> None:
        self.write_formal_pair(self.signal([(300, 0), (300, 6000)]))
        completed = subprocess.run(
            [sys.executable, str(SCRIPT)],
            input=(json.dumps(self.request()) + "\n").encode(),
            capture_output=True,
            shell=False,
            check=False,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr.decode(errors="replace"))
        events = [json.loads(line) for line in completed.stdout.decode().splitlines()]
        self.assertEqual([event["type"] for event in events], ["progress", "progress", "finished"])
        self.assertEqual([event["sequence"] for event in events], [1, 2, 3])
        self.assertEqual(events[-1]["payload"]["outcome"], "succeeded")
        self.assertEqual(events[-1]["payload"]["result"]["segment_count"], 1)


if __name__ == "__main__":
    unittest.main()
