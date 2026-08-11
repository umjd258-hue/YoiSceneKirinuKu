import json
import sys
import time
import uuid


def emit(message_type, request_id, sequence, payload):
    message = {
        "protocol_version": 1,
        "type": message_type,
        "request_id": request_id,
        "sequence": sequence,
        "payload": payload,
    }
    sys.stdout.write(json.dumps(message, separators=(",", ":")) + "\n")
    sys.stdout.flush()


request = json.loads(sys.stdin.buffer.readline())
if sys.stdin.buffer.read(1):
    raise SystemExit(2)
if set(request) != {"protocol_version", "type", "request_id", "sequence", "payload"}:
    raise SystemExit(2)
if request["protocol_version"] != 1 or request["type"] != "request" or request["sequence"] != 0:
    raise SystemExit(2)

request_id = request["request_id"]
operation = request["payload"]["operation"]

if operation == "success":
    print("stage6 fixture diagnostic", file=sys.stderr, flush=True)
    emit("progress", request_id, 1, {"stage": "stage6", "completed": 0, "total": 1})
    emit("finished", request_id, 2, {"outcome": "succeeded"})
elif operation == "malformed":
    print("not-json", flush=True)
elif operation == "unknown_type":
    emit("future", request_id, 1, {})
elif operation == "request_id_mismatch":
    emit("finished", str(uuid.uuid4()), 1, {"outcome": "succeeded"})
elif operation == "sequence_violation":
    emit("finished", request_id, 2, {"outcome": "succeeded"})
elif operation == "terminal_violation":
    emit("progress", request_id, 1, {"stage": "stage6"})
elif operation == "nonzero":
    print("stage6 fixture nonzero", file=sys.stderr, flush=True)
    raise SystemExit(7)
elif operation == "wait":
    time.sleep(30)
else:
    raise SystemExit(2)
