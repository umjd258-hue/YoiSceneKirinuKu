from __future__ import annotations

import importlib.util
import fcntl
import os
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

    def addition_request(self, character_id: str, source: Path | None = None) -> dict:
        return {
            "protocol_version": 1,
            "request_id": str(uuid.uuid4()),
            "operation": "add_sample",
            "character_id": character_id,
            "source_path": str(source or self.source),
            "start_ms": 1_000,
            "end_ms": 4_000,
            "characters_root": str(self.characters),
        }

    def deletion_request(self, character_id: str) -> dict:
        return {
            "protocol_version": 1,
            "request_id": str(uuid.uuid4()),
            "operation": "delete_character",
            "character_id": character_id,
            "characters_root": str(self.characters),
        }

    def register_initial_character(self) -> dict:
        return MODULE.register_character(
            self.request(), FFMPEG, self.model, SilentEmitter(), embedding_generator=fake_embedding
        )

    def formal_snapshot(self, character_id: str) -> dict[str, bytes]:
        root = self.characters / character_id
        return {
            str(path.relative_to(root)): path.read_bytes()
            for path in root.rglob("*") if path.is_file()
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
        partial_items = [
            item for item in (self.characters / ".partial").iterdir()
            if item.name != "global.lock"
        ]
        self.assertEqual(len(partial_items), 1)
        self.assertEqual(MODULE.list_characters({
            "protocol_version": 1,
            "request_id": str(uuid.uuid4()),
            "operation": "list_characters",
            "characters_root": str(self.characters),
        }), [])

    def test_sample_addition_atomically_extends_formal_character(self) -> None:
        initial = self.register_initial_character()
        old_sample_id = initial["samples"][0]["sample_id"]
        old_sample = self.formal_snapshot(initial["character_id"])

        updated = MODULE.add_sample(
            self.addition_request(initial["character_id"]), FFMPEG, self.model, SilentEmitter(),
            embedding_generator=fake_embedding,
        )

        self.assertEqual(len(updated["samples"]), 2)
        self.assertEqual(updated["samples"][0]["sample_id"], old_sample_id)
        current = self.formal_snapshot(initial["character_id"])
        for path, contents in old_sample.items():
            if path != "character.json":
                self.assertEqual(current[path], contents)
        self.assertEqual(list((self.characters / ".partial").glob("update_*")), [])

    def test_sample_addition_embedding_failure_preserves_formal_character(self) -> None:
        initial = self.register_initial_character()
        before = self.formal_snapshot(initial["character_id"])
        with self.assertRaisesRegex(MODULE.RegistrationFailure, "registration_embedding_failed"):
            MODULE.add_sample(
                self.addition_request(initial["character_id"]), FFMPEG, self.model, SilentEmitter(),
                embedding_generator=failing_embedding,
            )
        self.assertEqual(self.formal_snapshot(initial["character_id"]), before)

    def test_failure_before_sample_swap_preserves_formal_character(self) -> None:
        initial = self.register_initial_character()
        before = self.formal_snapshot(initial["character_id"])
        with self.assertRaisesRegex(MODULE.RegistrationFailure, "registration_finalization_failed"):
            MODULE.add_sample(
                self.addition_request(initial["character_id"]), FFMPEG, self.model, SilentEmitter(),
                embedding_generator=fake_embedding, fail_before_swap=True,
            )
        self.assertEqual(self.formal_snapshot(initial["character_id"]), before)

    def test_competing_sample_addition_is_rejected(self) -> None:
        initial = self.register_initial_character()
        lock_path = self.characters / ".partial" / f"{initial['character_id']}.lock"
        descriptor = os.open(lock_path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with self.assertRaisesRegex(MODULE.RegistrationFailure, "registration_character_busy"):
                MODULE.add_sample(
                    self.addition_request(initial["character_id"]), FFMPEG, self.model, SilentEmitter(),
                    embedding_generator=fake_embedding,
                )
        finally:
            os.close(descriptor)

    def test_character_deletion_removes_only_selected_character(self) -> None:
        selected = self.register_initial_character()
        remaining = self.register_initial_character()
        deleted_id = MODULE.delete_character(
            self.deletion_request(selected["character_id"]), SilentEmitter()
        )
        self.assertEqual(deleted_id, selected["character_id"])
        self.assertFalse((self.characters / selected["character_id"]).exists())
        self.assertTrue((self.characters / remaining["character_id"]).is_dir())
        self.assertEqual(
            [item["character_id"] for item in MODULE.list_characters(self._list_request())],
            [remaining["character_id"]],
        )

    def test_failure_before_delete_rename_preserves_formal_character(self) -> None:
        selected = self.register_initial_character()
        before = self.formal_snapshot(selected["character_id"])
        with self.assertRaisesRegex(MODULE.RegistrationFailure, "registration_character_delete_failed"):
            MODULE.delete_character(
                self.deletion_request(selected["character_id"]), SilentEmitter(), fail_before_rename=True
            )
        self.assertEqual(self.formal_snapshot(selected["character_id"]), before)

    def test_delete_cleanup_failure_leaves_ignored_tombstone(self) -> None:
        selected = self.register_initial_character()
        MODULE.delete_character(
            self.deletion_request(selected["character_id"]), SilentEmitter(), keep_tombstone=True
        )
        self.assertFalse((self.characters / selected["character_id"]).exists())
        self.assertEqual(MODULE.list_characters(self._list_request()), [])
        tombstones = list((self.characters / ".partial").glob("delete_*"))
        self.assertEqual(len(tombstones), 1)

    def test_delete_rejects_invalid_id_symlink_and_global_lock_contention(self) -> None:
        selected = self.register_initial_character()
        invalid = self.deletion_request("../character")
        with self.assertRaisesRegex(MODULE.RegistrationFailure, "registration_invalid_request"):
            MODULE.delete_character(invalid, SilentEmitter())

        lock_path = self.characters / ".partial" / "global.lock"
        descriptor = os.open(lock_path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
        try:
            fcntl.flock(descriptor, fcntl.LOCK_SH | fcntl.LOCK_NB)
            with self.assertRaisesRegex(MODULE.RegistrationFailure, "registration_character_busy"):
                MODULE.delete_character(self.deletion_request(selected["character_id"]), SilentEmitter())
        finally:
            os.close(descriptor)

        formal = self.characters / selected["character_id"]
        moved = self.characters / (selected["character_id"] + "_moved")
        formal.rename(moved)
        formal.symlink_to(moved, target_is_directory=True)
        with self.assertRaisesRegex(MODULE.RegistrationFailure, "registration_character_delete_failed"):
            MODULE.delete_character(self.deletion_request(selected["character_id"]), SilentEmitter())

    def _list_request(self) -> dict:
        return {
            "protocol_version": 1,
            "request_id": str(uuid.uuid4()),
            "operation": "list_characters",
            "characters_root": str(self.characters),
        }

    def _formal_directories(self) -> list[Path]:
        if not self.characters.exists():
            return []
        return [path for path in self.characters.iterdir() if path.name != ".partial"]


if __name__ == "__main__":
    unittest.main()
