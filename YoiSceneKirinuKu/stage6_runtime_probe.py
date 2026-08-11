import json
import socket
import sys
import uuid


PROTOCOL_VERSION = 1
EXPECTED_REQUEST_KEYS = {
    "protocol_version",
    "type",
    "request_id",
    "sequence",
    "payload",
}


def install_audit_hook():
    def audit(event, _arguments):
        if event.startswith("socket."):
            raise RuntimeError("network operation is prohibited")

    sys.addaudithook(audit)


def read_request(stream):
    line = stream.readline()
    if not line or stream.read(1):
        raise ValueError("request must be exactly one JSON line")
    request = json.loads(line)
    if not isinstance(request, dict) or set(request) != EXPECTED_REQUEST_KEYS:
        raise ValueError("invalid envelope")
    if request["protocol_version"] != PROTOCOL_VERSION:
        raise ValueError("invalid protocol version")
    if request["type"] != "request" or request["sequence"] != 0:
        raise ValueError("invalid request")
    request_id = request["request_id"]
    if not isinstance(request_id, str) or str(uuid.UUID(request_id)) != request_id:
        raise ValueError("invalid request id")
    payload = request["payload"]
    if not isinstance(payload, dict) or payload != {"operation": "runtime_probe"}:
        raise ValueError("invalid operation")
    return request_id


def emit(stream, message_type, request_id, sequence, payload):
    event = {
        "protocol_version": PROTOCOL_VERSION,
        "type": message_type,
        "request_id": request_id,
        "sequence": sequence,
        "payload": payload,
    }
    stream.write(json.dumps(event, ensure_ascii=False, separators=(",", ":")) + "\n")
    stream.flush()


def main():
    install_audit_hook()
    try:
        request_id = read_request(sys.stdin)
        emit(
            sys.stdout,
            "progress",
            request_id,
            1,
            {"stage": "runtime_probe", "completed": 0, "total": 1},
        )
        emit(
            sys.stdout,
            "finished",
            request_id,
            2,
            {"outcome": "succeeded", "python_version": "3.13.14"},
        )
        return 0
    except (json.JSONDecodeError, KeyError, TypeError, ValueError) as error:
        print(f"stage6_runtime_probe_failed: {type(error).__name__}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
