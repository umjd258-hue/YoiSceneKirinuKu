from __future__ import annotations

import json
import math
import sys
import tempfile
import unittest
import uuid
import wave
from pathlib import Path


SOURCE_ROOT = Path(__file__).resolve().parents[1] / "YoiSceneKirinuKu"
sys.path.insert(0, str(SOURCE_ROOT))
import quality_features as module


class CapturingEmitter:
    def __init__(self) -> None:
        self.request_id = str(uuid.uuid4())
        self.events: list[tuple[str, dict]] = []

    def emit(self, event_type: str, payload: dict) -> None:
        self.events.append((event_type, payload))


class QualityFeatureTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(dir="/private/tmp")
        self.root = Path(self.temporary.name)
        self.workspace = self.root / "workspace"
        self.source = self.root / "source.mp4"
        self.source.write_bytes(b"source")
        self.job_id = str(uuid.uuid4())
        self.job = {
            "schema_version": 1, "job_id": self.job_id, "start_request_id": str(uuid.uuid4()),
            "state_revision": 0, "state": "preparing",
            "source": {"path": str(self.source), "fingerprint": module.jobs.source_fingerprint(self.source)},
            "selected_character_ids": ["char_" + str(uuid.uuid4())], "failure_code": None,
        }
        module.jobs.prepare_workspace(str(self.workspace))
        module.jobs.write_job(self.workspace, self.job, self.job["start_request_id"])
        self._write_inputs()

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def _write_wav(self, path: Path) -> None:
        values = []
        for index in range(64_000):
            amplitude = 8_000 if 8_000 <= index < 56_000 else 800
            values.append(round(amplitude * math.sin(2 * math.pi * 220 * index / 16_000)))
        with wave.open(str(path), "wb") as output:
            output.setnchannels(1)
            output.setsampwidth(2)
            output.setframerate(16_000)
            output.writeframes(b"".join(value.to_bytes(2, "little", signed=True) for value in values))

    def _write_inputs(self) -> None:
        current = self.workspace / "current_job"
        wav_path = current / "analysis.wav"
        self._write_wav(wav_path)
        wav = module.candidates.audio.validate_wav(wav_path)
        metadata = {
            "schema_version": 1, "job_id": self.job_id,
            "source_fingerprint": self.job["source"]["fingerprint"],
            "profile": module.candidates.audio.PROFILE, "selected_stream_index": 0, **wav,
        }
        (current / "analysis_audio.json").write_text(json.dumps(metadata), encoding="utf-8")
        analysis_fp = module.candidates.analysis_fingerprint(current)
        segments = [{"start_ms": 500, "end_ms": 3_500, "duration_ms": 3_000}]
        vad = {
            "schema_version": 1, "job_id": self.job_id, "analysis_audio_fingerprint": analysis_fp,
            "profile": module.candidates.VAD_PROFILE, "audio_duration_ms": 4_000, "segments": segments,
        }
        (current / "vad.json").write_text(json.dumps(vad), encoding="utf-8")
        vad_fp = module.candidates.file_fingerprint(current / "vad.json", "candidate_vad_invalid")
        generated = module.candidates.generate_candidates(segments, 4_000, self.job_id)
        candidates = {
            "schema_version": 1, "job_id": self.job_id, "vad_fingerprint": vad_fp,
            "generation_profile": module.candidates.GENERATION_PROFILE, "candidates": generated,
        }
        (current / "speaker_candidates.json").write_text(json.dumps(candidates), encoding="utf-8")

    def request(self) -> dict:
        return {"workspace_root": str(self.workspace), "job_id": self.job_id}

    def test_generates_objective_features_unknown_categories_and_reuses(self) -> None:
        first = module.run(self.request(), CapturingEmitter())
        self.assertEqual(first, {"reused": False, "candidate_count": 1})
        value = json.loads((self.workspace / "current_job" / "quality_features.json").read_text())
        item = value["candidates"][0]
        self.assertEqual(item["clarity"]["status"], "available")
        self.assertGreater(item["clarity"]["values"]["speech_coverage_ratio"], 0.8)
        self.assertEqual(item["noise"]["status"], "available")
        self.assertGreater(item["noise"]["values"]["speech_to_nonspeech_db"], 10)
        for name in ("other_speaker", "bgm", "sound_effect"):
            self.assertEqual(item[name], module.unavailable())
        self.assertEqual(module.run(self.request(), CapturingEmitter()), {"reused": True, "candidate_count": 1})

    def test_missing_input_fails_closed(self) -> None:
        (self.workspace / "current_job" / "vad.json").unlink()
        with self.assertRaisesRegex(module.QualityFeatureFailure, "quality_features_input_invalid"):
            module.run(self.request(), CapturingEmitter())

    def test_stale_output_is_rejected(self) -> None:
        module.run(self.request(), CapturingEmitter())
        output = self.workspace / "current_job" / "quality_features.json"
        value = json.loads(output.read_text())
        value["profile"]["processing_passes_per_candidate"] = 2
        output.write_text(json.dumps(value), encoding="utf-8")
        with self.assertRaisesRegex(module.QualityFeatureFailure, "quality_features_reuse_invalid"):
            module.run(self.request(), CapturingEmitter())

    def test_zero_nonspeech_frames_is_explicitly_unavailable(self) -> None:
        current = self.workspace / "current_job"
        (current / "speaker_candidates.json").unlink()
        (current / "vad.json").unlink()
        analysis_fp = module.candidates.analysis_fingerprint(current)
        segments = [{"start_ms": 0, "end_ms": 4_000, "duration_ms": 4_000}]
        vad = {"schema_version": 1, "job_id": self.job_id, "analysis_audio_fingerprint": analysis_fp, "profile": module.candidates.VAD_PROFILE, "audio_duration_ms": 4_000, "segments": segments}
        (current / "vad.json").write_text(json.dumps(vad), encoding="utf-8")
        vad_fp = module.candidates.file_fingerprint(current / "vad.json", "candidate_vad_invalid")
        generated = module.candidates.generate_candidates(segments, 4_000, self.job_id)
        (current / "speaker_candidates.json").write_text(json.dumps({"schema_version": 1, "job_id": self.job_id, "vad_fingerprint": vad_fp, "generation_profile": module.candidates.GENERATION_PROFILE, "candidates": generated}), encoding="utf-8")
        module.run(self.request(), CapturingEmitter())
        item = json.loads((current / "quality_features.json").read_text())["candidates"][0]
        self.assertEqual(item["noise"]["status"], "unavailable")
        self.assertEqual(item["noise"]["reason"], "insufficient_speech_or_nonspeech_frames")


if __name__ == "__main__":
    unittest.main()
