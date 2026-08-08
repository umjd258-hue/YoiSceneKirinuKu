import argparse
import json
import sys
import time


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=("success", "failure", "streaming"), required=True)
    parser.add_argument("--message", default="")
    parser.add_argument("--profile", choices=("burst", "paced", "trailing"))
    parser.add_argument("--records", type=int)
    parser.add_argument("--payload-bytes", type=int)
    parser.add_argument("--delay-microseconds", type=int, default=0)
    return parser.parse_args()


def encoded_record(stream: str, sequence: int | None, payload: str | None, sentinel: bool) -> bytes:
    value = {
        "stream": stream,
        "sequence": sequence,
        "payload": payload,
        "sentinel": sentinel,
    }
    return (json.dumps(value, ensure_ascii=True, separators=(",", ":")) + "\n").encode("utf-8")


def run_streaming(arguments: argparse.Namespace) -> int:
    if arguments.profile is None or arguments.records is None or arguments.payload_bytes is None:
        raise ValueError("streaming arguments are required")
    if arguments.records < 0 or arguments.payload_bytes < 0 or arguments.delay_microseconds < 0:
        raise ValueError("streaming arguments must be non-negative")

    stdout_payload = "O" * arguments.payload_bytes
    stderr_payload = "E" * arguments.payload_bytes
    for sequence in range(arguments.records):
        sys.stdout.buffer.write(encoded_record("stdout", sequence, stdout_payload, False))
        sys.stderr.buffer.write(encoded_record("stderr", sequence, stderr_payload, False))
        sys.stdout.buffer.flush()
        sys.stderr.buffer.flush()
        if arguments.delay_microseconds:
            time.sleep(arguments.delay_microseconds / 1_000_000)

    sys.stdout.buffer.write(encoded_record("stdout", None, None, True))
    sys.stderr.buffer.write(encoded_record("stderr", None, None, True))
    if arguments.profile != "trailing":
        sys.stdout.buffer.flush()
        sys.stderr.buffer.flush()
    return 0


def main() -> int:
    arguments = parse_arguments()
    if arguments.mode == "streaming":
        return run_streaming(arguments)

    payload = {
        "fixture": arguments.mode,
        "message": arguments.message,
    }
    print(json.dumps(payload, ensure_ascii=False), flush=True)
    print(f"fixture_log mode={arguments.mode}", file=sys.stderr, flush=True)
    if arguments.mode == "failure":
        return 7
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
