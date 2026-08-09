from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
import uuid
from pathlib import Path


SOURCE_ROOT = Path(__file__).resolve().parents[1] / "YoiSceneKirinuKu"
sys.path.insert(0, str(SOURCE_ROOT))
SCRIPT = SOURCE_ROOT / "analysis_audio.py"
SPEC = importlib.util.spec_from_file_location("analysis_audio", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

FFMPEG = Path("/opt/homebrew/bin/ffmpeg")
FFPROBE = Path("/opt/homebrew/bin/ffprobe")


class CapturingEmitter:
    def __init__(self) -> None:
        self.events: list[tuple[str, dict]] = []

    def emit(self, event_type: str, payload: dict) -> None:
        self.events.append((event_type, payload))


class AnalysisAudioTests(unittest.TestCase):
    def setUp(self) -> None:
        if not FFMPEG.is_file() or not FFPROBE.is_file():
            self.skipTest("開発時FFmpeg／ffprobeが存在しません")
        self.temporary = tempfile.TemporaryDirectory(dir="/private/tmp")
        self.root = Path(self.temporary.name)
        self.workspace = self.root / "workspace"
        self.source = self.root / "日本語 source audio.mp4"
        completed = subprocess.run([
            str(FFMPEG), "-nostdin", "-hide_banner", "-loglevel", "error", "-n",
            "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000:duration=1",
            "-c:a", "aac", str(self.source),
        ], shell=False, capture_output=True, check=False)
        self.assertEqual(completed.returncode, 0, completed.stderr.decode(errors="replace"))
        self.job = self.make_job()
        MODULE.jobs.prepare_workspace(str(self.workspace))
        MODULE.jobs.write_job(self.workspace, self.job, self.job["start_request_id"])

    def tearDown(self) -> None:
        if hasattr(self, "temporary"):
            self.temporary.cleanup()

    def make_job(self) -> dict:
        return {
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

    def request(self, *, ffmpeg: Path = FFMPEG) -> dict:
        return {
            "protocol_version": 1,
            "request_id": str(uuid.uuid4()),
            "workspace_root": str(self.workspace),
            "job_id": self.job["job_id"],
            "ffmpeg_path": str(ffmpeg),
            "ffprobe_path": str(FFPROBE),
        }

    def test_generates_valid_wav_then_reuses_verified_pair(self) -> None:
        emitter = CapturingEmitter()
        first = MODULE.generate(self.request(), emitter)
        self.assertFalse(first["reused"])
        self.assertGreater(first["frame_count"], 0)
        self.assertGreater(first["duration_ms"], 0)
        self.assertEqual(emitter.events, [
            ("progress", {"stage": "analysis_audio", "status": "running"}),
            ("progress", {"stage": "analysis_audio", "status": "completed"}),
        ])
        wav = self.workspace / "current_job" / "analysis.wav"
        metadata = self.workspace / "current_job" / "analysis_audio.json"
        self.assertTrue(wav.is_file())
        stored = json.loads(metadata.read_text(encoding="utf-8"))
        self.assertEqual(stored["source_fingerprint"], self.job["source"]["fingerprint"])
        self.assertEqual(stored["profile"], MODULE.PROFILE)

        second = MODULE.generate(self.request(), CapturingEmitter())
        self.assertTrue(second["reused"])
        self.assertEqual(second["frame_count"], first["frame_count"])

    def test_insufficient_space_does_not_start_ffmpeg_or_create_formal_output(self) -> None:
        with self.assertRaisesRegex(MODULE.AudioFailure, "analysis_audio_insufficient_space"):
            MODULE.generate(self.request(ffmpeg=Path("/usr/bin/false")), CapturingEmitter(), available_bytes=0)
        self.assertFalse((self.workspace / "current_job" / "analysis.wav").exists())
        self.assertFalse((self.workspace / "current_job" / "analysis_audio.json").exists())

    def test_ffmpeg_failure_does_not_create_formal_output(self) -> None:
        with self.assertRaisesRegex(MODULE.AudioFailure, "analysis_audio_ffmpeg_failed"):
            MODULE.generate(self.request(ffmpeg=Path("/usr/bin/false")), CapturingEmitter())
        self.assertFalse((self.workspace / "current_job" / "analysis.wav").exists())
        self.assertFalse((self.workspace / "current_job" / "analysis_audio.json").exists())

    def test_source_unavailable_is_rejected_before_conversion(self) -> None:
        self.source.unlink()
        with self.assertRaisesRegex(MODULE.AudioFailure, "analysis_audio_source_unavailable"):
            MODULE.generate(self.request(), CapturingEmitter())
        self.assertFalse((self.workspace / "current_job" / "analysis.wav").exists())

    def test_source_without_audio_stream_is_rejected(self) -> None:
        video_only = self.root / "video only.mp4"
        completed = subprocess.run([
            str(FFMPEG), "-nostdin", "-hide_banner", "-loglevel", "error", "-n",
            "-f", "lavfi", "-i", "color=c=black:s=160x90:r=10:d=1",
            "-an", "-c:v", "mpeg4", str(video_only),
        ], shell=False, capture_output=True, check=False)
        self.assertEqual(completed.returncode, 0, completed.stderr.decode(errors="replace"))
        self.source = video_only
        self.job["source"] = {
            "path": str(video_only),
            "fingerprint": MODULE.jobs.source_fingerprint(video_only),
        }
        (self.workspace / "current_job" / "job.json").unlink()
        MODULE.jobs.write_job(self.workspace, self.job, self.job["start_request_id"])
        with self.assertRaisesRegex(MODULE.AudioFailure, "analysis_audio_probe_failed"):
            MODULE.generate(self.request(), CapturingEmitter())
        self.assertFalse((self.workspace / "current_job" / "analysis.wav").exists())

    def test_changed_source_and_invalid_metadata_are_not_reused(self) -> None:
        MODULE.generate(self.request(), CapturingEmitter())
        self.source.write_bytes(b"changed")
        with self.assertRaisesRegex(MODULE.AudioFailure, "analysis_audio_source_changed"):
            MODULE.generate(self.request(), CapturingEmitter())

        self.source.write_bytes(b"different")
        metadata = self.workspace / "current_job" / "analysis_audio.json"
        value = json.loads(metadata.read_text(encoding="utf-8"))
        value["schema_version"] = 2
        metadata.write_text(json.dumps(value), encoding="utf-8")
        with self.assertRaisesRegex(MODULE.AudioFailure, "analysis_audio_reuse_invalid"):
            MODULE.generate(self.request(), CapturingEmitter())

    def test_orphan_formal_metadata_and_stale_partial_are_reconciled(self) -> None:
        current = self.workspace / "current_job"
        (current / "analysis_audio.json").write_text("{}", encoding="utf-8")
        stale = self.workspace / ".partial" / f"analysis_{uuid.uuid4()}.wav.partial"
        stale.write_bytes(b"stale")
        result = MODULE.generate(self.request(), CapturingEmitter())
        self.assertFalse(result["reused"])
        self.assertFalse(stale.exists())
        self.assertTrue((current / "analysis.wav").is_file())

    def test_dangling_formal_symlink_is_not_treated_as_absent(self) -> None:
        marker = self.workspace / "current_job" / "analysis.wav"
        marker.symlink_to(self.root / "missing.wav")
        with self.assertRaisesRegex(MODULE.AudioFailure, "analysis_audio_reuse_invalid"):
            MODULE.generate(self.request(), CapturingEmitter())
        self.assertTrue(marker.is_symlink())


if __name__ == "__main__":
    unittest.main()
