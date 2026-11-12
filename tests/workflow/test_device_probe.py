"""Host-side transport/correlation tests; these do not establish device behavior."""

import hashlib
import json
from pathlib import Path
import shlex
from subprocess import CompletedProcess
import tempfile
import unittest
from unittest.mock import patch

from tools import device_probe as probe
from tools.run_device_diagnostics import collect


class FakeDevice(probe.Device):
    def __init__(self, directory):
        super().__init__("adb", "serial", directory)
        self.calls = []
        self.overrides = {}
        self.reports = []
        self.native = None
        self.stale_receipt = False

    def _shell_text(self, *args, optional=False):
        self.calls.append(args)
        if args[0] == "am":
            self.key = args[args.index("request") + 1]
            self.receipt = {
                "request": self.key,
                "action": args[args.index("-a") + 1],
                "state": "accepted",
                "id": 1,
                "diagnostic_process": "process-1",
                **self.overrides,
            }
        return ""

    def read(self, filename, *, package=None):
        if filename.startswith("debug_request_"):
            if self.stale_receipt:
                self.stale_receipt = False
                return {**self.receipt, "request": "old-request"}
            return self.receipt
        if self.reports:
            return self.reports.pop(0)
        return self.native(self) if self.native else None


class DeviceProbe(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.device = FakeDevice(self.root)
        self.sleep = patch.object(probe.time, "sleep").start()
        self.addCleanup(patch.stopall)

    def test_typed_request_and_stale_receipt(self):
        self.device.stale_receipt = True
        receipt = self.device.request(
            "open",
            "open",
            enabled=True,
            position_ms=4,
            value=0.5,
            uri="https://example/a b?q=$x",
        )
        args = self.device.calls[0]
        for flag, name, value in [
            ("--ez", "enabled", "true"),
            ("--ei", "position_ms", "4"),
            ("--ef", "value", "0.5"),
            ("--es", "uri", "https://example/a b?q=$x"),
        ]:
            index = args.index(name)
            self.assertEqual(args[index - 1 : index + 2], (flag, name, value))
        self.assertEqual(self.device.process, "process-1")
        self.device.send_request(
            "restart", probe.PACKAGE + ".DEBUG_MPV_GPU", include_stopped=True
        )
        self.assertIn("--include-stopped-packages", self.device.calls[-1])
        self.assertTrue((self.root / (receipt["request"] + "-receipt.json")).is_file())

    def test_rejected_or_invalid_receipts_fail(self):
        for override in [
            {"state": "error"},
            {"id": 0},
            {"action": "wrong"},
            {"diagnostic_process": ""},
        ]:
            self.device.overrides = override
            with self.assertRaises(RuntimeError):
                self.device.request("invalid", "open")

    def test_process_changes_require_explicit_reset(self):
        self.device.request("first", "open")
        self.device.overrides = {"diagnostic_process": "process-2"}
        with self.assertRaisesRegex(RuntimeError, "process changed"):
            self.device.request("second", "open")
        self.device.process = None
        self.device.request("restart", "open")
        self.assertEqual(self.device.process, "process-2")

    def test_native_report_requires_request_process_and_id(self):
        receipt = self.device.request("native", "open")
        good = {
            "request_id": 1,
            "request_key": receipt["request"],
            "diagnostic_process": "process-1",
            "state": "passed",
        }
        self.device.reports = [
            {k: v for k, v in good.items() if k != "request_key"},
            {**good, "request_key": "stale"},
            {**good, "diagnostic_process": "old"},
            {**good, "request_id": 99},
            {k: v for k, v in good.items() if k != "diagnostic_process"},
            good,
        ]
        self.assertEqual(
            self.device.wait_report("native", receipt, "native.json"), good
        )
        self.assertFalse(self.device.reports)

    def test_player_report_rejects_duplicate_command_keys(self):
        receipt = self.device.request("open", "open")
        command = {"request_key": receipt["request"]}
        good = {"request_id": 1, "commands": [command], "media": {"state": "ready"}}
        self.device.reports = [{**good, "commands": [command, command]}, good]
        self.assertEqual(self.device.wait("ready", receipt, lambda r: True), good)

    def test_player_failure_preserves_evidence(self):
        receipt = self.device.request("open", "open")
        self.device.reports = [
            {
                "request_id": 1,
                "commands": [{"request_key": receipt["request"]}],
                "media": {"state": "failed"},
            }
        ]
        with self.assertRaisesRegex(RuntimeError, "Player failed"):
            self.device.wait("failed", receipt, lambda r: True)
        self.assertTrue((self.root / "failed-failed.json").is_file())

    def test_timeout_saves_the_stale_report(self):
        receipt = {"id": 1, "request": "new", "diagnostic_process": "new-process"}
        self.device.reports = [
            {"request_id": 1, "diagnostic_process": "old-process"},
            None,
        ]
        with patch.object(probe.time, "monotonic", side_effect=[0, 0, 0.1, 0.2, 2]):
            with self.assertRaises(TimeoutError):
                self.device.wait_report("timeout", receipt, "old.json", timeout=1)
        saved = json.loads((self.root / "timeout-timeout.json").read_text())
        self.assertEqual(saved["last_report"]["diagnostic_process"], "old-process")

    def test_shell_quoting_and_binary_transport(self):
        device = probe.Device("adb", "serial", self.root, port=5038)
        value = "a b; $(not-a-command)"
        with patch.object(device, "run", return_value="") as run:
            device.shell("echo", value)
            self.assertEqual(shlex.split(run.call_args.args[1]), ["echo", value])
        with patch.object(
            probe.subprocess,
            "run",
            return_value=CompletedProcess([], 0, b"\x89PNG\r\n", b""),
        ) as run:
            self.assertEqual(
                device.adb_bytes("exec-out", "screencap", "-p"), b"\x89PNG\r\n"
            )
            self.assertEqual(
                run.call_args.args[0][:5], ["adb", "-P", "5038", "-s", "serial"]
            )

    def test_apk_hash_is_checked(self):
        device = probe.Device("adb", "serial", self.root)
        apk = self.root / "debug.apk"
        apk.write_bytes(b"synthetic-apk")
        digest = hashlib.sha256(apk.read_bytes()).hexdigest()
        with patch.object(
            device,
            "_shell_text",
            side_effect=["package:/base.apk\n", digest + " /base.apk"],
        ):
            self.assertEqual(device.verify_apk(apk), digest)
        with patch.object(
            device,
            "_shell_text",
            side_effect=["package:/base.apk\n", "wrong /base.apk"],
        ):
            with self.assertRaisesRegex(RuntimeError, "hash differs"):
                device.verify_apk(apk)

    def test_output_and_evidence_paths_are_bounded(self):
        with patch.object(probe, "ROOT", self.root):
            first = probe.output_directory(None, "gpu")
            self.assertNotEqual(first, probe.output_directory(None, "gpu"))
            with self.assertRaises(ValueError):
                probe.output_directory(self.root / "outside", "gpu")
            with self.assertRaises(ValueError):
                probe.output_directory(None, "../../../outside")
        with self.assertRaises(ValueError):
            self.device.save_json("../outside", {})

    def test_three_native_diagnostic_routes(self):
        for kind in ["core", "gpu", "audio"]:
            self.device.native = lambda d: {
                "request_id": 1,
                "request_key": d.key,
                "diagnostic_process": "process-1",
                "state": "passed_native_checks" if kind == "audio" else "passed",
            }
            collect(self.device, kind)
            args = self.device.calls[-1]
            self.assertIn(probe.PACKAGE + ".DEBUG_MPV_" + kind.upper(), args)
            self.assertEqual("fixture" in args, kind != "audio")
            index = args.index("hardware")
            self.assertEqual(args[index + 1], "false" if kind == "core" else "true")

    def test_adb_timeouts_have_a_shared_catchable_type(self):
        device = probe.Device("adb", "serial", self.root)
        with patch.object(
            probe.subprocess,
            "run",
            side_effect=probe.subprocess.TimeoutExpired("adb", 1),
        ):
            with self.assertRaises(TimeoutError):
                device.adb_bytes("shell", "id", timeout=1)
            source = self.root / "media.mp4"
            source.write_bytes(b"synthetic")
            with self.assertRaises(TimeoutError):
                device.stream("exec-in", source=source, timeout=1)

    def test_broadcast_timeout_preserves_request_identity(self):
        device = probe.Device("adb", "serial", self.root)
        action = probe.PACKAGE + ".DEBUG_MPV_URI"
        with patch.object(
            device, "_shell_text", side_effect=TimeoutError("ADB timeout")
        ):
            with self.assertRaises(TimeoutError):
                device.send_request("request", action)
        attempts = list(self.root.glob("*-request.json"))
        self.assertEqual(len(attempts), 1)
        self.assertEqual(json.loads(attempts[0].read_text())["action"], action)
