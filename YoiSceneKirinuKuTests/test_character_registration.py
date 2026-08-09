from __future__ import annotations

import importlib.util
import subprocess
import tempfile
import unittest
import uuid
from pathlib import Path

import numpy as np


SCRIPT = Path(__file__).resolve().parents[1] / "YoiSceneKirinuKu" / "character_registration.py"
SPEC = importlib.util.spec_from_file_location("character_registration", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)
FFMPEG = Path("/opt/homebrew/bin/ffmpeg")


class SilentEmitter:
    def emit(self, event_type: str, payload: dict) -> None:
        pass


def fake_embedding(model_directory: Path, wav_path: Path, output: Path) -> None:
    vector = np.arange(1, MODULE.EMBEDDING_DIMENSION + 1, dtype=np.float32)
    vector /= np.linalg.norm(vector)
    with output.open("xb") as file:
        np.save(file, vector, allow_pickle=False)


def failing_embedding(model_directory: Path, wav_path: Path, output: Path) -> None:
    raise MODULE.RegistrationFailure("registration_embedding_failed")


class CharacterRegistrationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(dir="/private/tmp")
        self.root = Path(self.temporary.name)
        self.characters = self.root / "characters"
        self.model = self.root / "model"
        self.model.mkdir()
        self.source = self.root / "source.mp4"
        self.silent_source = self.root / "silent.mp4"
        self._make_media(self.source, silent=False)
        self._make_media(self.silent_source, silent=True)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def _make_media(self, output: Path, silent: bool) -> None:
        audio = "anullsrc=r=16000:cl=mono" if silent else "sine=frequency=440:sample_rate=16000"
        completed = subprocess.run([
            str(FFMPEG), "-nostdin", "-hide_banner", "-loglevel", "error", "-n",
            "-f", "lavfi", "-i", "color=c=black:s=160x90:r=10",
            "-f", "lavfi", "-i", audio, "-t", "5",
            "-c:v", "mpeg4", "-c:a", "aac", "-shortest", str(output),
        ], shell=False, capture_output=True, check=False)
        self.assertEqual(completed.returncode, 0, completed.stderr.decode(errors="replace"))

    def request(self, source: Path | None = None) -> dict:
        return {
            "protocol_version": 1,
            "request_id": str(uuid.uuid4()),
            "operation": "register_character",
            "display_name": "テスト人物",
            "source_path": str(source or self.source),
            "start_ms": 1_000,
            "end_ms": 4_000,
            "characters_root": str(self.characters),
        }

    def test_normal_registration_and_reload(self) -> None:
        summary = MODULE.register_character(
            self.request(), FFMPEG, self.model, SilentEmitter(), embedding_generator=fake_embedding
        )
        final = self.characters / summary["character_id"]
        self.assertTrue(final.is_dir())
        self.assertFalse((self.characters / ".partial" / summary["character_id"]).exists())
        sample_id = summary["samples"][0]["sample_id"]
        source_wav = final / "samples" / sample_id / "source.wav"
        sample = MODULE.read_json(final / "samples" / sample_id / "sample.json")
        self.assertEqual(sample["source_wav"]["sha256"], MODULE.hashlib.sha256(source_wav.read_bytes()).hexdigest())
        self.assertEqual(MODULE.list_characters({
            "protocol_version": 1,
            "request_id": str(uuid.uuid4()),
            "operation": "list_characters",
            "characters_root": str(self.characters),
        }), [summary])

    def test_missing_source_does_not_create_formal_character(self) -> None:
        with self.assertRaisesRegex(MODULE.RegistrationFailure, "registration_source_unavailable"):
            MODULE.register_character(
                self.request(self.root / "missing.mp4"), FFMPEG, self.model, SilentEmitter(),
                embedding_generator=fake_embedding,
            )
        self.assertEqual(self._formal_directories(), [])

    def test_silent_audio_is_rejected_before_embedding(self) -> None:
        with self.assertRaisesRegex(MODULE.RegistrationFailure, "registration_audio_silent"):
            MODULE.register_character(
                self.request(self.silent_source), FFMPEG, self.model, SilentEmitter(),
                embedding_generator=fake_embedding,
            )
        self.assertEqual(self._formal_directories(), [])

    def test_embedding_failure_does_not_create_formal_character(self) -> None:
        with self.assertRaisesRegex(MODULE.RegistrationFailure, "registration_embedding_failed"):
            MODULE.register_character(
                self.request(), FFMPEG, self.model, SilentEmitter(), embedding_generator=failing_embedding
            )
        self.assertEqual(self._formal_directories(), [])

    def test_failure_before_finalization_leaves_only_ignored_partial(self) -> None:
        with self.assertRaisesRegex(MODULE.RegistrationFailure, "registration_finalization_failed"):
            MODULE.register_character(
                self.request(), FFMPEG, self.model, SilentEmitter(), embedding_generator=fake_embedding,
                fail_before_finalization=True,
            )
        self.assertEqual(self._formal_directories(), [])
        partial_items = list((self.characters / ".partial").iterdir())
        self.assertEqual(len(partial_items), 1)
        self.assertEqual(MODULE.list_characters({
            "protocol_version": 1,
            "request_id": str(uuid.uuid4()),
            "operation": "list_characters",
            "characters_root": str(self.characters),
        }), [])

    def _formal_directories(self) -> list[Path]:
        if not self.characters.exists():
            return []
        return [path for path in self.characters.iterdir() if path.name != ".partial"]


if __name__ == "__main__":
    unittest.main()
