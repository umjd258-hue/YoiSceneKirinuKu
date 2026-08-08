import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
from typing import Any


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--ffmpeg", type=Path, required=True)
    parser.add_argument("--ffprobe", type=Path, required=True)
    parser.add_argument("--work-dir", type=Path, required=True)
    return parser.parse_args()


def run_command(arguments: list[str]) -> subprocess.CompletedProcess[bytes]:
    if not arguments or not all(isinstance(value, str) for value in arguments):
        raise ValueError("command arguments must be a non-empty list of strings")
    return subprocess.run(
        arguments,
        shell=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


def require_executable(path: Path, label: str) -> Path:
    resolved = path.expanduser().resolve(strict=True)
    if not resolved.is_file() or not os.access(resolved, os.X_OK):
        raise RuntimeError(f"{label} is not an executable file: {resolved}")
    return resolved


def require_success(result: subprocess.CompletedProcess[bytes], label: str) -> None:
    if result.returncode != 0:
        stderr = result.stderr.decode("utf-8", errors="replace")
        raise RuntimeError(f"{label} failed with exit={result.returncode}: {stderr[-1000:]}")


def main() -> int:
    arguments = parse_arguments()
    ffmpeg = require_executable(arguments.ffmpeg, "ffmpeg")
    ffprobe = require_executable(arguments.ffprobe, "ffprobe")
    work_dir = arguments.work_dir.resolve()
    experiment_root = Path(__file__).resolve().parent
    if work_dir != experiment_root and experiment_root not in work_dir.parents:
        raise RuntimeError("work directory must be inside the experiment directory")
    work_dir.mkdir(parents=True, exist_ok=True)

    media_path = work_dir / "人工 テスト動画.mp4"
    missing_input = work_dir / "存在しない 入力動画.mp4"
    missing_executable = work_dir / "存在しない ffmpeg"
    if media_path.exists():
        raise RuntimeError(f"refusing to overwrite existing artifact: {media_path}")

    command_arguments: dict[str, list[str]] = {}

    command_arguments["ffmpeg_version"] = [str(ffmpeg), "-version"]
    ffmpeg_version = run_command(command_arguments["ffmpeg_version"])
    require_success(ffmpeg_version, "ffmpeg version")
    if not ffmpeg_version.stdout or ffmpeg_version.stderr is ffmpeg_version.stdout:
        raise RuntimeError("ffmpeg version stdout/stderr separation was not observed")

    command_arguments["ffprobe_version"] = [str(ffprobe), "-version"]
    ffprobe_version = run_command(command_arguments["ffprobe_version"])
    require_success(ffprobe_version, "ffprobe version")

    command_arguments["generate_media"] = [
        str(ffmpeg),
        "-hide_banner",
        "-nostdin",
        "-f",
        "lavfi",
        "-i",
        "color=c=black:s=160x90:r=10:d=2",
        "-f",
        "lavfi",
        "-i",
        "sine=frequency=440:sample_rate=48000:duration=2",
        "-c:v",
        "mpeg4",
        "-c:a",
        "aac",
        "-shortest",
        "-n",
        str(media_path),
    ]
    generated = run_command(command_arguments["generate_media"])
    require_success(generated, "artificial media generation")
    if generated.stderr is generated.stdout:
        raise RuntimeError("generation stdout/stderr were not captured separately")
    if not media_path.is_file() or media_path.stat().st_size <= 0:
        raise RuntimeError("generated media is missing or empty")

    command_arguments["read_japanese_path"] = [
        str(ffmpeg),
        "-hide_banner",
        "-nostdin",
        "-i",
        str(media_path),
        "-f",
        "null",
        "-",
    ]
    read_result = run_command(command_arguments["read_japanese_path"])
    require_success(read_result, "Japanese and space path read")

    spawn_failure_classification = ""
    try:
        run_command([str(missing_executable), "-version"])
    except FileNotFoundError:
        spawn_failure_classification = "not_started_file_not_found"
    if spawn_failure_classification != "not_started_file_not_found":
        raise RuntimeError("missing FFmpeg executable was not classified as a spawn failure")

    command_arguments["ffmpeg_post_launch_error"] = [
        str(ffmpeg),
        "-hide_banner",
        "-nostdin",
        "-i",
        str(missing_input),
        "-f",
        "null",
        "-",
    ]
    post_launch_error = run_command(command_arguments["ffmpeg_post_launch_error"])
    if post_launch_error.returncode == 0 or not post_launch_error.stderr:
        raise RuntimeError("post-launch FFmpeg error was not observed")

    command_arguments["ffprobe_media"] = [
        str(ffprobe),
        "-v",
        "error",
        "-show_entries",
        "format=duration:stream=index,codec_type,codec_name",
        "-of",
        "json",
        str(media_path),
    ]
    probe_result = run_command(command_arguments["ffprobe_media"])
    require_success(probe_result, "ffprobe media inspection")
    try:
        probe_payload: dict[str, Any] = json.loads(probe_result.stdout)
    except (json.JSONDecodeError, UnicodeDecodeError) as error:
        raise RuntimeError(f"ffprobe did not return valid JSON: {error}") from error

    streams = probe_payload.get("streams")
    if not isinstance(streams, list):
        raise RuntimeError("ffprobe streams is not a list")
    stream_types = {stream.get("codec_type") for stream in streams if isinstance(stream, dict)}
    if "video" not in stream_types or "audio" not in stream_types:
        raise RuntimeError(f"expected video and audio streams, got: {stream_types}")
    try:
        duration = float(probe_payload["format"]["duration"])
    except (KeyError, TypeError, ValueError) as error:
        raise RuntimeError(f"ffprobe duration is invalid: {error}") from error
    if duration <= 0:
        raise RuntimeError(f"duration must be positive: {duration}")

    report = {
        "experiment_result": "passed",
        "shell": False,
        "ffmpeg_path": str(ffmpeg),
        "ffprobe_path": str(ffprobe),
        "commands": command_arguments,
        "normal_case": {
            "generation_exit": generated.returncode,
            "read_exit": read_result.returncode,
            "stdout_stderr_separate": generated.stdout is not generated.stderr,
        },
        "path_case": {
            "path": str(media_path),
            "exists": media_path.is_file(),
            "size_bytes": media_path.stat().st_size,
        },
        "spawn_failure": spawn_failure_classification,
        "post_launch_error": {
            "classification": "started_nonzero_exit",
            "exit": post_launch_error.returncode,
            "stderr_bytes": len(post_launch_error.stderr),
        },
        "ffprobe": {
            "exit": probe_result.returncode,
            "json_parsed": True,
            "video_stream": "video" in stream_types,
            "audio_stream": "audio" in stream_types,
            "duration": duration,
        },
    }
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"experiment_result=failed {error}", file=sys.stderr)
        raise SystemExit(1)
