import importlib.util
import io
import json
import socket
import subprocess
import sys
import unittest
import uuid
from pathlib import Path


SCRIPT = Path(__file__).parents[1] / "YoiSceneKirinuKu" / "stage6_runtime_probe.py"


class Stage6RuntimeProbeTests(unittest.TestCase):
    def test_success_emits_only_strict_progress_and_finished(self):
        request_id = str(uuid.uuid4())
        completed = self.run_probe(self.request(request_id))

        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertEqual(completed.stderr, "")
        events = [json.loads(line) for line in completed.stdout.splitlines()]
        self.assertEqual([event["type"] for event in events], ["progress", "finished"])
        self.assertEqual([event["sequence"] for event in events], [1, 2])
        for event in events:
            self.assertEqual(
                set(event),
                {"protocol_version", "type", "request_id", "sequence", "payload"},
            )
            self.assertEqual(event["protocol_version"], 1)
            self.assertEqual(event["request_id"], request_id)
        self.assertEqual(events[-1]["payload"]["outcome"], "succeeded")
        self.assertEqual(events[-1]["payload"]["python_version"], "3.13.14")

    def test_unknown_operation_fails_without_protocol_output(self):
        request = self.request(str(uuid.uuid4()))
        request["payload"]["operation"] = "future_operation"
        completed = self.run_probe(request)

        self.assertEqual(completed.returncode, 1)
        self.assertEqual(completed.stdout, "")
        self.assertIn("stage6_runtime_probe_failed: ValueError", completed.stderr)

    def test_extra_envelope_key_fails_without_protocol_output(self):
        request = self.request(str(uuid.uuid4()))
        request["extra"] = True
        completed = self.run_probe(request)

        self.assertEqual(completed.returncode, 1)
        self.assertEqual(completed.stdout, "")

    def test_audit_hook_blocks_socket_operation(self):
        specification = importlib.util.spec_from_file_location("stage6_runtime_probe", SCRIPT)
        module = importlib.util.module_from_spec(specification)
        specification.loader.exec_module(module)
        module.install_audit_hook()

        with self.assertRaisesRegex(RuntimeError, "network operation is prohibited"):
            socket.socket()

    @staticmethod
    def request(request_id):
        return {
            "protocol_version": 1,
            "type": "request",
            "request_id": request_id,
            "sequence": 0,
            "payload": {"operation": "runtime_probe"},
        }

    @staticmethod
    def run_probe(request):
        return subprocess.run(
            [sys.executable, "-I", "-S", str(SCRIPT)],
            input=json.dumps(request, separators=(",", ":")) + "\n",
            text=True,
            capture_output=True,
            check=False,
            env={"LANG": "C.UTF-8", "PATH": "/nonexistent", "PYTHONNOUSERSITE": "1"},
        )


if __name__ == "__main__":
    unittest.main()
