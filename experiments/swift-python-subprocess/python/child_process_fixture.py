import argparse
import json
import sys


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=("success", "failure"), required=True)
    parser.add_argument("--message", required=True)
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
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

