"""Validate driver decisions and cleanup with fake reports, not Android permissions."""

import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from tools import run_external_uri_probe as driver
from tools.device_probe import PACKAGE


class FakeDevice:
    package = PACKAGE

    def __init__(self, root, expected):
        self.root, self.expected = root, expected
        self.calls = []
        self.granted = False
        self.process = None
        self.process_number = 0
        self.restart_works = True
        self.revoke_error = "permission_denied"
        self.granted_decode_fails = False
        self.same_uid = False
        self.cleanup_fails = False
        self.last_label = None
        self.counter = 0

    def run(self, *args, optional=False):
        self.calls.append(("run", args))
        if args[:3] == ("shell", "am", "force-stop"):
            if self.restart_works or self.process_number == 0:
                self.process_number += 1
        return "Success"

    def verify_apk(self, apk, *, package=None):
        self.calls.append(("verified", package))
        return "verified"

    def save_json(self, label, value):
        (self.root / (label + ".json")).write_text(json.dumps(value))

    def send_request(self, label, action, extras=None, **kwargs):
        self.counter += 1
        key = "request-" + str(self.counter)
        self.last_label = label
        if action.endswith(".CONTROL"):
            operation = extras["operation"]
            self.calls.append(("control", operation, label))
            if label == "cleanup-revoke" and self.cleanup_fails:
                raise TimeoutError("Provider cleanup timed out")
            if operation in ("grant", "revoke"):
                self.granted = operation == "grant"
            return {
                "request": key,
                "state": "applied",
                "operation": operation,
                "uri": driver.URI,
                "client_uid": 10001,
                "provider_uid": 10001 if self.same_uid else 10002,
                "provider_process": "fixture-process",
                "clip_sha256": self.expected,
            }
        self.process = f"client-process-{self.process_number}"
        return {"request": key, "id": self.counter, "diagnostic_process": self.process}

    def wait_report(self, label, receipt, filename, **kwargs):
        self.calls.append(("decode", label, self.granted))
        passed = self.granted and not self.granted_decode_fails
        return {
            "state": "passed" if passed else "failed",
            "permission_granted": self.granted,
            "descriptor_opened": self.granted,
            "descriptor_closed": True,
            "error_type": (
                "native_decode_failed"
                if self.granted_decode_fails and self.granted
                else self.revoke_error
            ),
            "uri": driver.URI,
            "client_uid": 10001,
            "fixture": "mp03_frame_identity",
            "probe_kind": "external_uri",
        }


class ExternalUriProbe(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.apk = self.root / "fixture.apk"
        self.media = b"project-owned synthetic clip"
        self.sha = hashlib.sha256(self.media).hexdigest()
        with zipfile.ZipFile(self.apk, "w") as archive:
            archive.writestr("assets/mp03_frame_identity.mp4", self.media)
        self.device = FakeDevice(self.root, self.sha)

    def test_grant_decode_revoke_restart_and_cleanup(self):
        result = driver.run_probe(self.device, self.apk, self.sha)
        self.assertEqual(result["state"], "passed")
        self.assertEqual(
            [c[1:] for c in self.device.calls if c[0] == "decode"],
            [
                ("before-grant", False),
                ("granted", True),
                ("revoked", False),
                ("after-restart", False),
            ],
        )
        self.assertTrue(result["cleanup_revoked"] and result["fixture_uninstalled"])
        self.assertNotEqual(result["client_uid"], result["provider_uid"])
        self.assertNotIn(("run", ("uninstall", PACKAGE)), self.device.calls)
        self.assertFalse(
            any("clear" in c[1] for c in self.device.calls if c[0] == "run")
        )

    def test_same_uid_cannot_count_as_cross_app_evidence(self):
        self.device.same_uid = True
        with self.assertRaisesRegex(RuntimeError, "distinct UIDs"):
            driver.run_probe(self.device, self.apk, self.sha)
        self.assertEqual(
            json.loads((self.root / "result.json").read_text())["state"], "failed"
        )

    def test_decoder_failure_is_not_a_permission_denial(self):
        self.device.revoke_error = "native_decode_failed"
        with self.assertRaisesRegex(RuntimeError, "permission denial"):
            driver.run_probe(self.device, self.apk, self.sha)

    def test_decoder_failure_after_grant_still_revokes(self):
        self.device.granted_decode_fails = True
        with self.assertRaisesRegex(RuntimeError, "native FD decode"):
            driver.run_probe(self.device, self.apk, self.sha)
        self.assertFalse(self.device.granted)
        self.assertIn(("control", "revoke", "cleanup-revoke"), self.device.calls)

    def test_restart_must_create_a_new_client_process(self):
        self.device.restart_works = False
        with self.assertRaisesRegex(RuntimeError, "did not restart"):
            driver.run_probe(self.device, self.apk, self.sha)

    def test_wrong_fixture_bytes_fail_before_adb(self):
        with self.assertRaisesRegex(ValueError, "different MP03"):
            driver.run_probe(self.device, self.apk, "0" * 64)
        self.assertFalse(self.device.calls)

    def test_cleanup_failure_cannot_leave_a_passing_result(self):
        self.device.cleanup_fails = True
        with self.assertRaises(TimeoutError):
            driver.run_probe(self.device, self.apk, self.sha)
        result = json.loads((self.root / "result.json").read_text())
        self.assertEqual(result["state"], "failed")
        self.assertFalse(result["cleanup_revoked"])
        self.assertTrue(result["fixture_uninstalled"])

    def test_keep_fixture_still_revokes(self):
        result = driver.run_probe(self.device, self.apk, self.sha, keep_fixture=True)
        self.assertTrue(result["cleanup_revoked"])
        self.assertFalse(
            any(c[0] == "run" and c[1][0] == "uninstall" for c in self.device.calls)
        )

    def test_uninstall_timeout_preserves_failed_evidence(self):
        original = self.device.run

        def run(*args, optional=False):
            if args[0] == "uninstall":
                raise TimeoutError("ADB uninstall timed out")
            return original(*args, optional=optional)

        self.device.run = run
        with self.assertRaises(TimeoutError):
            driver.run_probe(self.device, self.apk, self.sha)
        result = json.loads((self.root / "result.json").read_text())
        self.assertEqual(result["state"], "failed")
        self.assertTrue(result["cleanup_revoked"])
        self.assertFalse(result["fixture_uninstalled"])


class ExternalUriCli(unittest.TestCase):
    def test_selected_adb_port_reaches_the_device(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            with (
                patch.object(
                    driver.sys,
                    "argv",
                    [
                        "probe",
                        "--serial",
                        "pico",
                        "--port",
                        "5042",
                        "--apk",
                        "player.apk",
                        "--fixture-apk",
                        "fixture.apk",
                    ],
                ),
                patch.object(driver, "output_directory", return_value=output),
                patch.object(driver, "Device") as device,
                patch.object(driver, "run_probe"),
            ):
                self.assertEqual(driver.main(), 0)
                device.assert_called_once_with("adb", "pico", output, port=5042)
