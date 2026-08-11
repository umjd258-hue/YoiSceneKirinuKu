import json
import os
import sys
import time


EXPECTED_KEYS = {"protocol_version", "type", "request_id", "sequence", "payload"}
network_audit_events = 0


def audit_hook(event: str, _arguments: tuple[object, ...]) -> None:
    global network_audit_events
    if event.startswith("socket."):
        network_audit_events += 1
        raise RuntimeError("network access is forbidden")


def emit(message_type: str, request_id: str, sequence: int, payload: dict[str, object]) -> None:
    message = {
        "protocol_version": 1,
        "type": message_type,
        "request_id": request_id,
        "sequence": sequence,
        "payload": payload,
    }
    print(json.dumps(message, ensure_ascii=True, separators=(",", ":")), flush=True)


def main() -> int:
    sys.addaudithook(audit_hook)
    raw_request = sys.stdin.buffer.readline()
    if not raw_request.endswith(b"\n") or sys.stdin.buffer.read(1) != b"":
        return 10
    request = json.loads(raw_request)
    if set(request) != EXPECTED_KEYS:
        return 11
    if request["protocol_version"] != 1 or request["type"] != "request" or request["sequence"] != 0:
        return 12
    if request["payload"] != {"operation": "stage6_gate"}:
        return 13

    request_id = request["request_id"]
    emit("progress", request_id, 1, {"stage": "stage6_gate", "status": "running"})
    time.sleep(3)
    site_paths = [path for path in sys.path if "site-packages" in path]
    payload = {
        "outcome": "succeeded",
        "python_version": ".".join(map(str, sys.version_info[:3])),
        "isolated": bool(sys.flags.isolated),
        "ignore_environment": bool(sys.flags.ignore_environment),
        "no_user_site": bool(sys.flags.no_user_site),
        "site_loaded": "site" in sys.modules,
        "site_packages_paths": len(site_paths),
        "network_audit_events": network_audit_events,
        "path": os.environ.get("PATH", ""),
    }
    print("stage6_gate_diagnostic", file=sys.stderr, flush=True)
    emit("finished", request_id, 2, payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
