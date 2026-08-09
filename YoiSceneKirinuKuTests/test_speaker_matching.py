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

import numpy as np


SOURCE_ROOT = Path(__file__).resolve().parents[1] / "YoiSceneKirinuKu"
sys.path.insert(0, str(SOURCE_ROOT))
SCRIPT = SOURCE_ROOT / "speaker_matching.py"
SPEC = importlib.util.spec_from_file_location("speaker_matching", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class CapturingEmitter:
    def __init__(self) -> None:
        self.events: list[tuple[str, dict]] = []

    def emit(self, event_type: str, payload: dict) -> None:
        self.events.append((event_type, payload))


def fake_embedding(model_directory: Path, samples: np.ndarray) -> np.ndarray:
    vector = np.zeros(MODULE.registration.EMBEDDING_DIMENSION, dtype=np.float32)
    vector[0] = 1
    return vector


class SpeakerMatchingTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(dir="/private/tmp")
        self.root = Path(self.temporary.name)
        self.workspace = self.root / "workspace"
        self.characters = self.root / "characters"
        self.characters.mkdir()
        self.model = self.root / "model"
        self.model.mkdir()
        self.source = self.root / "source.mp4"
        self.source.write_bytes(b"source")
        self.character_ids = ["char_" + str(uuid.uuid4()), "char_" + str(uuid.uuid4())]
        self._write_character(self.character_ids[0], axis=0)
        self._write_character(self.character_ids[1], axis=1)
        self.job = {
            "schema_version": 1,
            "job_id": str(uuid.uuid4()),
            "start_request_id": str(uuid.uuid4()),
            "state_revision": 0,
            "state": "start_requested",
            "source": {"path": str(self.source), "fingerprint": MODULE.jobs.source_fingerprint(self.source)},
            "selected_character_ids": self.character_ids,
            "failure_code": None,
        }
        MODULE.jobs.prepare_workspace(str(self.workspace))
        MODULE.jobs.write_job(self.workspace, self.job, self.job["start_request_id"])
        self._write_analysis_and_candidates(with_candidate=True)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def request(self) -> dict:
        return {
            "protocol_version": 1,
            "request_id": str(uuid.uuid4()),
            "workspace_root": str(self.workspace),
            "characters_root": str(self.characters),
            "job_id": self.job["job_id"],
        }

    def _write_wav(self, path: Path, duration_ms: int = 4_000) -> None:
        samples = [round(6000 * math.sin(2 * math.pi * 220 * index / 16_000)) for index in range(duration_ms * 16)]
        with wave.open(str(path), "wb") as output:
            output.setnchannels(1)
            output.setsampwidth(2)
            output.setframerate(16_000)
            output.writeframes(b"".join(value.to_bytes(2, "little", signed=True) for value in samples))

    def _write_character(self, character_id: str, axis: int) -> None:
        sample_id = "sample_" + str(uuid.uuid4())
        sample_root = self.characters / character_id / "samples" / sample_id
        sample_root.mkdir(parents=True)
        wav = sample_root / "source.wav"
        self._write_wav(wav, 3_000)
        vector = np.zeros(MODULE.registration.EMBEDDING_DIMENSION, dtype=np.float32)
        vector[axis] = 1
        with (sample_root / "embedding.npy").open("xb") as output:
            np.save(output, vector, allow_pickle=False)
        wav_metadata = MODULE.registration.inspect_wav(wav)
        sample = {
            "schema_version": 1,
            "sample_id": sample_id,
            "character_id": character_id,
            "source_interval": {"start_ms": 0, "end_ms": 3_000},
            "source_wav": wav_metadata,
            "embedding": {
                "file": "embedding.npy", "model_id": MODULE.registration.MODEL_ID,
                "model_revision": MODULE.registration.MODEL_REVISION,
                "dimension": MODULE.registration.EMBEDDING_DIMENSION, "dtype": "float32",
                "normalization": "l2", "source_wav_sha256": wav_metadata["sha256"],
            },
        }
        (sample_root / "sample.json").write_text(json.dumps(sample), encoding="utf-8")
        character = {"schema_version": 1, "character_id": character_id, "display_name": character_id, "sample_ids": [sample_id]}
        (self.characters / character_id / "character.json").write_text(json.dumps(character), encoding="utf-8")

    def _write_analysis_and_candidates(self, with_candidate: bool) -> None:
        current = self.workspace / "current_job"
        wav_path = current / "analysis.wav"
        self._write_wav(wav_path)
        wav = MODULE.candidate_generation.audio.validate_wav(wav_path)
        metadata = {
            "schema_version": 1, "job_id": self.job["job_id"],
            "source_fingerprint": self.job["source"]["fingerprint"],
            "profile": MODULE.candidate_generation.audio.PROFILE, "selected_stream_index": 0, **wav,
        }
        (current / "analysis_audio.json").write_text(json.dumps(metadata), encoding="utf-8")
        analysis_fp = MODULE.candidate_generation.analysis_fingerprint(current)
        segments = [{"start_ms": 0, "end_ms": 4_000, "duration_ms": 4_000}] if with_candidate else []
        vad = {
            "schema_version": 1, "job_id": self.job["job_id"], "analysis_audio_fingerprint": analysis_fp,
            "profile": MODULE.candidate_generation.VAD_PROFILE, "audio_duration_ms": 4_000, "segments": segments,
        }
        (current / "vad.json").write_text(json.dumps(vad), encoding="utf-8")
        vad_fp = MODULE.candidate_generation.file_fingerprint(current / "vad.json", "candidate_vad_invalid")
        candidates = MODULE.candidate_generation.generate_candidates(segments, 4_000, self.job["job_id"])
        value = {
            "schema_version": 1, "job_id": self.job["job_id"], "vad_fingerprint": vad_fp,
            "generation_profile": MODULE.candidate_generation.GENERATION_PROFILE, "candidates": candidates,
        }
        (current / "speaker_candidates.json").write_text(json.dumps(value), encoding="utf-8")

    def test_persists_selected_character_comparisons_and_reuses(self) -> None:
        emitter = CapturingEmitter()
        first = MODULE.run(self.request(), self.model, emitter, embedding_generator=fake_embedding)
        self.assertEqual(first, {"reused": False, "candidate_count": 1, "selected_character_count": 2})
        self.assertEqual([payload["status"] for event, payload in emitter.events if event == "progress"], ["running", "processing", "completed"])
        self.assertTrue(all("cosine_similarity" not in payload for _, payload in emitter.events))
        value = json.loads((self.workspace / "current_job" / "speaker_matches.json").read_text())
        self.assertEqual([item["character_id"] for item in value["candidates"][0]["comparisons"]], self.character_ids)
        self.assertAlmostEqual(value["candidates"][0]["comparisons"][0]["cosine_similarity"], 1.0)
        self.assertAlmostEqual(value["candidates"][0]["comparisons"][1]["cosine_similarity"], 0.0)
        second = MODULE.run(self.request(), self.model, CapturingEmitter(), embedding_generator=fake_embedding)
        self.assertTrue(second["reused"])

    def test_zero_candidates_is_normal_and_emits_no_processing(self) -> None:
        current = self.workspace / "current_job"
        (current / "speaker_candidates.json").unlink()
        (current / "vad.json").unlink()
        self._write_analysis_and_candidates(with_candidate=False)
        emitter = CapturingEmitter()
        result = MODULE.run(self.request(), self.model, emitter, embedding_generator=fake_embedding)
        self.assertEqual(result["candidate_count"], 0)
        self.assertEqual([payload["status"] for event, payload in emitter.events if event == "progress"], ["running", "completed"])

    def test_unselected_broken_character_is_not_read(self) -> None:
        unrelated = self.characters / ("char_" + str(uuid.uuid4()))
        unrelated.mkdir()
        (unrelated / "broken").write_text("broken")
        result = MODULE.run(self.request(), self.model, CapturingEmitter(), embedding_generator=fake_embedding)
        self.assertEqual(result["selected_character_count"], 2)

    def test_selected_embedding_change_rejects_stale_result(self) -> None:
        MODULE.run(self.request(), self.model, CapturingEmitter(), embedding_generator=fake_embedding)
        first_character = self.characters / self.character_ids[0]
        sample_id = json.loads((first_character / "character.json").read_text())["sample_ids"][0]
        embedding = first_character / "samples" / sample_id / "embedding.npy"
        vector = np.zeros(MODULE.registration.EMBEDDING_DIMENSION, dtype=np.float32)
        vector[1] = 1
        with embedding.open("wb") as output:
            np.save(output, vector, allow_pickle=False)
        with self.assertRaisesRegex(MODULE.MatchingFailure, "speaker_matching_reuse_invalid|speaker_matching_character_invalid"):
            MODULE.run(self.request(), self.model, CapturingEmitter(), embedding_generator=fake_embedding)

    def test_cli_reports_missing_model_without_promoting_partial(self) -> None:
        completed = subprocess.run(
            [sys.executable, str(SCRIPT), str(self.root / "missing-model")],
            input=(json.dumps(self.request()) + "\n").encode(), capture_output=True, shell=False, check=False,
        )
        self.assertEqual(completed.returncode, 0)
        events = [json.loads(line) for line in completed.stdout.decode().splitlines()]
        self.assertEqual(events[-2]["payload"]["code"], "speaker_matching_model_unavailable")
        self.assertFalse((self.workspace / "current_job" / "speaker_matches.json").exists())


if __name__ == "__main__":
    unittest.main()
