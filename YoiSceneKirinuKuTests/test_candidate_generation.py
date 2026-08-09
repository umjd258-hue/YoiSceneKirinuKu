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


SOURCE_ROOT = Path(__file__).resolve().parents[1] / "YoiSceneKirinuKu"
sys.path.insert(0, str(SOURCE_ROOT))
SCRIPT = SOURCE_ROOT / "candidate_generation.py"
SPEC = importlib.util.spec_from_file_location("candidate_generation", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class CapturingEmitter:
    def __init__(self) -> None:
        self.events: list[tuple[str, dict]] = []

    def emit(self, event_type: str, payload: dict) -> None:
        self.events.append((event_type, payload))


class CandidateGenerationTests(unittest.TestCase):
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

    @staticmethod
    def signal(parts: list[tuple[int, int]]) -> list[int]:
        samples: list[int] = []
        for duration_ms, peak in parts:
            for index in range(16_000 * duration_ms // 1000):
                samples.append(round(peak * math.sin(2 * math.pi * 220 * index / 16_000)) if peak else 0)
        return samples

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

    def test_persists_strict_vad_and_stable_candidates_then_reuses_pair(self) -> None:
        self.write_formal_pair(self.signal([
            (1_000, 0), (4_000, 6_000), (390, 0), (3_600, 6_000), (3_000, 0),
        ]))
        emitter = CapturingEmitter()
        first = MODULE.run(self.request(), emitter)
        self.assertEqual(first, {"reused": False, "vad_segment_count": 2, "candidate_count": 1})
        self.assertEqual(emitter.events, [
            ("progress", {"stage": "candidate_generation", "status": "running"}),
            ("progress", {"stage": "candidate_generation", "status": "vad_completed"}),
            ("progress", {"stage": "candidate_generation", "status": "completed"}),
        ])
        current = self.workspace / "current_job"
        vad_value = json.loads((current / "vad.json").read_text())
        candidates_value = json.loads((current / "speaker_candidates.json").read_text())
        self.assertEqual(vad_value["schema_version"], 1)
        self.assertEqual(vad_value["profile"], MODULE.VAD_PROFILE)
        self.assertEqual(candidates_value["generation_profile"], MODULE.GENERATION_PROFILE)
        identifier = candidates_value["candidates"][0]["candidate_id"]

        second = MODULE.run(self.request(), CapturingEmitter())
        self.assertEqual(second, {"reused": True, "vad_segment_count": 2, "candidate_count": 1})
        self.assertEqual(json.loads((current / "speaker_candidates.json").read_text())["candidates"][0]["candidate_id"], identifier)

    def test_zero_short_edge_and_long_candidates_stay_in_bounds(self) -> None:
        self.assertEqual(MODULE.generate_candidates([], 10_000, self.job["job_id"]), [])
        self.assertEqual(MODULE.generate_candidates([{"start_ms": 200, "end_ms": 1_800}], 2_000, self.job["job_id"]), [])
        edge = MODULE.generate_candidates([{"start_ms": 0, "end_ms": 300}], 10_000, self.job["job_id"])
        self.assertEqual((edge[0]["start_ms"], edge[0]["end_ms"]), (0, 3_000))
        long = MODULE.generate_candidates([{"start_ms": 2_000, "end_ms": 67_000}], 70_000, self.job["job_id"])
        self.assertEqual([item["duration_ms"] for item in long], [30_000, 30_000, 5_500])
        self.assertTrue(all(left["end_ms"] <= right["start_ms"] for left, right in zip(long, long[1:])))

    def test_vad_only_recovery_regenerates_candidates(self) -> None:
        self.write_formal_pair(self.signal([(500, 0), (3_000, 6_000), (500, 0)]))
        MODULE.run(self.request(), CapturingEmitter())
        current = self.workspace / "current_job"
        (current / "speaker_candidates.json").unlink()
        result = MODULE.run(self.request(), CapturingEmitter())
        self.assertFalse(result["reused"])
        self.assertTrue((current / "speaker_candidates.json").is_file())

    def test_candidate_without_vad_and_tampering_fail_closed(self) -> None:
        self.write_formal_pair(self.signal([(500, 0), (3_000, 6_000), (500, 0)]))
        MODULE.run(self.request(), CapturingEmitter())
        current = self.workspace / "current_job"
        (current / "vad.json").unlink()
        with self.assertRaisesRegex(MODULE.CandidateFailure, "candidate_reuse_invalid"):
            MODULE.run(self.request(), CapturingEmitter())

    def test_stale_known_partial_is_removed_but_unknown_item_is_rejected(self) -> None:
        self.write_formal_pair(self.signal([(500, 0), (3_000, 6_000), (500, 0)]))
        stale = self.workspace / ".partial" / f"vad_{uuid.uuid4()}.json.partial"
        stale.write_text("stale", encoding="utf-8")
        MODULE.run(self.request(), CapturingEmitter())
        self.assertFalse(stale.exists())
        (self.workspace / "current_job" / "unknown.bin").write_bytes(b"unknown")
        with self.assertRaisesRegex(MODULE.CandidateFailure, "candidate_job_invalid"):
            MODULE.run(self.request(), CapturingEmitter())

    def test_cli_emits_strict_progress_and_finished(self) -> None:
        self.write_formal_pair(self.signal([(500, 0), (3_000, 6_000), (500, 0)]))
        request = self.request()
        completed = subprocess.run(
            [sys.executable, str(SCRIPT)],
            input=(json.dumps(request) + "\n").encode(),
            capture_output=True,
            shell=False,
            check=False,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr.decode(errors="replace"))
        events = [json.loads(line) for line in completed.stdout.decode().splitlines()]
        self.assertEqual([event["type"] for event in events], ["progress", "progress", "progress", "finished"])
        self.assertEqual([event["sequence"] for event in events], [1, 2, 3, 4])
        self.assertEqual(events[-1]["payload"]["outcome"], "succeeded")


if __name__ == "__main__":
    unittest.main()
