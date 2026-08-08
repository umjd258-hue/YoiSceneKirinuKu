import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import stat
import subprocess
import sys
import uuid


DISKUTIL = "/usr/sbin/diskutil"
PARTIAL_NAME = "日本語 空白 読み書きテスト.partial"
FINAL_NAME = "日本語 空白 読み書きテスト.txt"


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--volume-mount-point", type=Path, required=True)
    parser.add_argument("--expected-device-identifier", required=True)
    parser.add_argument("--expected-device-node", required=True)
    parser.add_argument("--expected-volume-uuid", required=True)
    parser.add_argument("--experiment-directory-name", required=True)
    return parser.parse_args()


def disk_info(identifier: str) -> dict[str, object]:
    completed = subprocess.run(
        [DISKUTIL, "info", "-plist", identifier],
        shell=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if completed.returncode != 0:
        raise RuntimeError(f"diskutil info failed with exit={completed.returncode}")
    return plistlib.loads(completed.stdout)


def require_not_symlink(path: Path, label: str) -> None:
    if path.is_symlink():
        raise RuntimeError(f"{label} must not be a symlink: {path}")


def require_directory_without_symlink(path: Path, label: str) -> None:
    require_not_symlink(path, label)
    mode = path.lstat().st_mode
    if not stat.S_ISDIR(mode):
        raise RuntimeError(f"{label} must be a directory: {path}")


def require_regular_file_without_symlink(path: Path, label: str) -> None:
    require_not_symlink(path, label)
    mode = path.lstat().st_mode
    if not stat.S_ISREG(mode):
        raise RuntimeError(f"{label} must be a regular file: {path}")


def require_identity(arguments: argparse.Namespace) -> dict[str, object]:
    info = disk_info(arguments.expected_device_identifier)
    expected = {
        "DeviceIdentifier": arguments.expected_device_identifier,
        "DeviceNode": arguments.expected_device_node,
        "VolumeUUID": arguments.expected_volume_uuid,
        "MountPoint": str(arguments.volume_mount_point),
    }
    for key, expected_value in expected.items():
        if info.get(key) != expected_value:
            raise RuntimeError(f"disk identity mismatch for {key}")
    if info.get("Internal") is not False:
        raise RuntimeError("disk must be external")
    if info.get("Removable") is not True or info.get("RemovableMedia") is not True:
        raise RuntimeError("disk must be removable")
    if info.get("Writable") is not True or info.get("WritableVolume") is not True:
        raise RuntimeError("disk must be writable")
    mount_point = arguments.volume_mount_point
    require_directory_without_symlink(mount_point, "mount point")
    return info


def require_direct_child(path: Path, parent: Path, expected_name: str) -> None:
    if path.parent != parent or path.name != expected_name:
        raise RuntimeError(f"path is outside the approved experiment root: {path}")
    if ".." in path.parts:
        raise RuntimeError(f"path traversal is not allowed: {path}")


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def main() -> int:
    arguments = parse_arguments()
    mount_point = arguments.volume_mount_point
    if not mount_point.is_absolute() or mount_point != Path("/Volumes/Untitled"):
        raise RuntimeError("mount point is not the explicitly approved absolute path")
    if arguments.experiment_directory_name != "YoiSceneKirinuKu_Experiment_20260808":
        raise RuntimeError("experiment directory name is not the approved name")

    start_info = require_identity(arguments)
    experiment_root = mount_point / arguments.experiment_directory_name
    partial_path = experiment_root / PARTIAL_NAME
    final_path = experiment_root / FINAL_NAME
    if experiment_root.exists() or experiment_root.is_symlink():
        raise RuntimeError("experiment root already exists; refusing to reuse or delete it")

    audit = {
        "created": [],
        "renamed": [],
        "deleted": [],
    }
    experiment_root.mkdir(mode=0o700, parents=False, exist_ok=False)
    audit["created"].append(str(experiment_root))
    require_directory_without_symlink(experiment_root, "experiment root")
    if experiment_root.parent != mount_point:
        raise RuntimeError("experiment root escaped the approved mount point")

    require_direct_child(partial_path, experiment_root, PARTIAL_NAME)
    require_direct_child(final_path, experiment_root, FINAL_NAME)
    if partial_path.exists() or final_path.exists():
        raise RuntimeError("test file already exists")

    payload_object = {
        "experiment": "YoiSceneKirinuKu external storage IO",
        "nonce": str(uuid.uuid4()),
        "content": "日本語 と spaces",
    }
    expected_bytes = (json.dumps(payload_object, ensure_ascii=False, sort_keys=True) + "\n").encode("utf-8")
    expected_hash = sha256(expected_bytes)

    with partial_path.open("xb") as file_handle:
        written = file_handle.write(expected_bytes)
        if written != len(expected_bytes):
            raise RuntimeError("partial write length mismatch")
        file_handle.flush()
        os.fsync(file_handle.fileno())
    audit["created"].append(str(partial_path))
    require_regular_file_without_symlink(partial_path, "partial file")
    partial_bytes = partial_path.read_bytes()
    partial_hash = sha256(partial_bytes)
    if partial_bytes != expected_bytes or partial_hash != expected_hash:
        raise RuntimeError("partial bytes or SHA-256 mismatch")

    require_identity(arguments)
    require_directory_without_symlink(experiment_root, "experiment root before rename")
    require_regular_file_without_symlink(partial_path, "partial file before rename")
    if final_path.exists() or final_path.is_symlink():
        raise RuntimeError("final path already exists; refusing to overwrite")
    os.rename(partial_path, final_path)
    audit["renamed"].append({"from": str(partial_path), "to": str(final_path)})
    if partial_path.exists() or partial_path.is_symlink():
        raise RuntimeError("partial path remained after rename")
    require_regular_file_without_symlink(final_path, "final file")
    final_bytes = final_path.read_bytes()
    final_hash = sha256(final_bytes)
    if final_bytes != expected_bytes or final_hash != expected_hash:
        raise RuntimeError("renamed file bytes or SHA-256 mismatch")

    require_identity(arguments)
    require_directory_without_symlink(experiment_root, "experiment root before deletion")
    require_regular_file_without_symlink(final_path, "final file before deletion")
    entries = list(experiment_root.iterdir())
    if entries != [final_path]:
        raise RuntimeError("unexpected experiment-root entry; refusing to delete")
    if final_path.read_bytes() != expected_bytes or sha256(final_path.read_bytes()) != expected_hash:
        raise RuntimeError("final validation before deletion failed")
    final_path.unlink()
    audit["deleted"].append(str(final_path))
    if list(experiment_root.iterdir()):
        raise RuntimeError("experiment root is not empty; refusing to remove it")
    experiment_root.rmdir()
    audit["deleted"].append(str(experiment_root))
    if experiment_root.exists() or experiment_root.is_symlink():
        raise RuntimeError("experiment root remained after rmdir")

    report = {
        "experiment_result": "passed",
        "device": {
            "identifier": start_info.get("DeviceIdentifier"),
            "node": start_info.get("DeviceNode"),
            "volume_uuid": start_info.get("VolumeUUID"),
            "mount_point": start_info.get("MountPoint"),
            "filesystem": start_info.get("FilesystemType"),
            "removable": start_info.get("Removable"),
            "internal": start_info.get("Internal"),
            "writable": start_info.get("WritableVolume"),
        },
        "paths": {
            "experiment_root": str(experiment_root),
            "partial": str(partial_path),
            "final": str(final_path),
        },
        "verification": {
            "expected_bytes": len(expected_bytes),
            "partial_bytes_match": partial_bytes == expected_bytes,
            "partial_sha256": partial_hash,
            "partial_sha256_match": partial_hash == expected_hash,
            "final_bytes_match": final_bytes == expected_bytes,
            "final_sha256": final_hash,
            "final_sha256_match": final_hash == expected_hash,
            "japanese_and_space_path": True,
        },
        "cleanup": {
            "final_file_removed": not final_path.exists(),
            "experiment_root_removed": not experiment_root.exists(),
        },
        "audit": audit,
    }
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"experiment_result=failed {error}", file=sys.stderr)
        raise SystemExit(1)
