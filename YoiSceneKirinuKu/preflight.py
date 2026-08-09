#!/usr/bin/env python3
import json
import math
import os
from pathlib import Path
import subprocess
import sys

PROTOCOL_VERSION = 1
ERROR_CODES = {
    "invalid_request",
    "unsupported_file_type",
    "input_not_found",
    "input_not_readable",
    "probe_not_started",
    "probe_timed_out",
    "probe_failed",
    "invalid_probe_output",
    "video_stream_missing",
    "audio_stream_missing",
    "invalid_duration",
    "internal_error",
}


class EventWriter:
    def __init__(self, request_id):
        self.request_id = request_id
        self.sequence = 0

    def write(self, event_type, payload):
        self.sequence += 1
        event = {
            "protocol_version": PROTOCOL_VERSION,
            "type": event_type,
            "request_id": self.request_id,
            "sequence": self.sequence,
            "payload": payload,
        }
        sys.stdout.write(json.dumps(event, ensure_ascii=False, separators=(",", ":")) + "\n")
        sys.stdout.flush()

    def fail(self, code):
        if code not in ERROR_CODES:
            code = "internal_error"
        self.write("error", {"code": code})
        self.write("finished", {"outcome": "failed", "code": code})


def valid_request(value):
    return (
        isinstance(value, dict)
        and set(value) == {"protocol_version", "request_id", "operation", "source_path"}
        and value.get("protocol_version") == PROTOCOL_VERSION
        and value.get("operation") == "preflight"
        and isinstance(value.get("request_id"), str)
        and isinstance(value.get("source_path"), str)
        and os.path.isabs(value["source_path"])
    )


def main():
    raw = sys.stdin.buffer.readline()
    try:
        request = json.loads(raw)
    except (json.JSONDecodeError, UnicodeDecodeError):
        return 2

    if not valid_request(request) or sys.stdin.buffer.read(1):
        return 2

    writer = EventWriter(request["request_id"])
    source = Path(request["source_path"])
    if source.suffix.lower() != ".mp4":
        writer.fail("unsupported_file_type")
        return 0
    if not source.exists() or not source.is_file():
        writer.fail("input_not_found")
        return 0
    if not os.access(source, os.R_OK):
        writer.fail("input_not_readable")
        return 0

    ffprobe = Path(sys.argv[1]) if len(sys.argv) == 2 else None
    if ffprobe is None or not ffprobe.is_absolute() or not ffprobe.is_file() or not os.access(ffprobe, os.X_OK):
        writer.fail("probe_not_started")
        return 0

    writer.write("progress", {"stage": "preflight", "status": "running"})
    arguments = [
        str(ffprobe), "-v", "error", "-print_format", "json",
        "-show_format", "-show_streams", "--", str(source),
    ]
    try:
        completed = subprocess.run(arguments, shell=False, capture_output=True, timeout=20, check=False)
    except subprocess.TimeoutExpired:
        writer.fail("probe_timed_out")
        return 0
    except OSError:
        writer.fail("probe_not_started")
        return 0

    if completed.returncode != 0:
        writer.fail("probe_failed")
        return 0
    try:
        probe = json.loads(completed.stdout)
    except (json.JSONDecodeError, UnicodeDecodeError):
        writer.fail("invalid_probe_output")
        return 0

    streams = probe.get("streams")
    media_format = probe.get("format")
    if not isinstance(streams, list) or not isinstance(media_format, dict):
        writer.fail("invalid_probe_output")
        return 0
    format_name = media_format.get("format_name")
    if not isinstance(format_name, str) or "mp4" not in format_name.split(","):
        writer.fail("invalid_probe_output")
        return 0
    video_count = sum(stream.get("codec_type") == "video" for stream in streams if isinstance(stream, dict))
    audio_count = sum(stream.get("codec_type") == "audio" for stream in streams if isinstance(stream, dict))
    if video_count == 0:
        writer.fail("video_stream_missing")
        return 0
    if audio_count == 0:
        writer.fail("audio_stream_missing")
        return 0
    try:
        duration_seconds = float(media_format["duration"])
    except (KeyError, TypeError, ValueError):
        writer.fail("invalid_duration")
        return 0
    if not math.isfinite(duration_seconds) or duration_seconds <= 0:
        writer.fail("invalid_duration")
        return 0

    duration_ms = math.ceil(duration_seconds * 1000)
    writer.write("progress", {"stage": "preflight", "status": "completed"})
    writer.write("finished", {
        "outcome": "succeeded",
        "result": {
            "file_name": source.name,
            "duration_ms": duration_ms,
            "container_format": format_name,
            "video_stream_count": video_count,
            "audio_stream_count": audio_count,
        },
    })
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
