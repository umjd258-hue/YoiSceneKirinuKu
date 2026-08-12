from __future__ import annotations

import importlib.util
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
import uuid
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = REPOSITORY_ROOT / "YoiSceneKirinuKu"
sys.path.insert(0, str(SOURCE_ROOT))
SCRIPT = SOURCE_ROOT / "analysis_audio.py"
SPEC = importlib.util.spec_from_file_location("analysis_audio", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

VENDOR_BIN = REPOSITORY_ROOT / "vendor" / "ffmpeg" / "8.1.2" / "universal2" / "bin"
FIXTURE_FFMPEG = Path("/opt/homebrew/bin/ffmpeg")


class CapturingEmitter:
    def __init__(self) -> None:
        self.events: list[tuple[str, dict]] = []

    def emit(self, event_type: str, payload: dict) -> None:
        self.events.append((event_type, payload))


class AnalysisAudioTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.bundle_temporary = tempfile.TemporaryDirectory(dir="/private/tmp")
        cls.bundle = Path(cls.bundle_temporary.name) / "YoiSceneKirinuKu.app"
        bundle_bin = cls.bundle / "Contents" / "MacOS"
        bundle_bin.mkdir(parents=True)
        shutil.copy2(VENDOR_BIN / "ffmpeg", bundle_bin / "ffmpeg")
        shutil.copy2(VENDOR_BIN / "ffprobe", bundle_bin / "ffprobe")
        cls.ffmpeg = bundle_bin / "ffmpeg"
        cls.ffprobe = bundle_bin / "ffprobe"

    @classmethod
    def tearDownClass(cls) -> None:
        cls.bundle_temporary.cleanup()

    def setUp(self) -> None:
        if not FIXTURE_FFMPEG.is_file():
            self.skipTest("テストfixture生成用FFmpegが存在しません")
        self.temporary = tempfile.TemporaryDirectory(dir="/private/tmp")
        self.root = Path(self.temporary.name)
        self.workspace = self.root / "workspace"
        self.source = self.root / "日本語 source audio.mp4"
        completed = subprocess.run([
            str(FIXTURE_FFMPEG), "-nostdin", "-hide_banner", "-loglevel", "error", "-n",
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

    def request(self, *, bundle: Path | None = None, ffmpeg: Path | None = None) -> dict:
        selected_bundle = bundle or self.bundle
        return {
            "protocol_version": 1,
            "request_id": str(uuid.uuid4()),
            "workspace_root": str(self.workspace),
            "job_id": self.job["job_id"],
            "bundle_root": str(selected_bundle),
            "ffmpeg_path": str(ffmpeg or self.ffmpeg),
            "ffprobe_path": str(selected_bundle / "Contents" / "MacOS" / "ffprobe"),
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
            MODULE.generate(self.request(), CapturingEmitter(), available_bytes=0)
        self.assertFalse((self.workspace / "current_job" / "analysis.wav").exists())
        self.assertFalse((self.workspace / "current_job" / "analysis_audio.json").exists())

    def test_ffmpeg_failure_does_not_create_formal_output(self) -> None:
        failing_bundle = self.root / "Failing.app"
        failing_bin = failing_bundle / "Contents" / "MacOS"
        failing_bin.mkdir(parents=True)
        failing_ffmpeg = failing_bin / "ffmpeg"
        shutil.copyfile("/usr/bin/false", failing_ffmpeg)
        failing_ffmpeg.chmod(0o755)
        shutil.copy2(self.ffprobe, failing_bin / "ffprobe")
        with self.assertRaisesRegex(MODULE.AudioFailure, "analysis_audio_ffmpeg_failed"):
            MODULE.generate(self.request(bundle=failing_bundle, ffmpeg=failing_bin / "ffmpeg"), CapturingEmitter())
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
            str(FIXTURE_FFMPEG), "-nostdin", "-hide_banner", "-loglevel", "error", "-n",
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

    def test_rejects_executable_outside_bundle(self) -> None:
        with self.assertRaisesRegex(MODULE.AudioFailure, "analysis_audio_job_invalid"):
            MODULE.generate(self.request(ffmpeg=Path("/usr/bin/false")), CapturingEmitter())


if __name__ == "__main__":
    unittest.main()
