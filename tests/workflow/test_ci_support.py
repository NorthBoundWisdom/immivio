"""Offline checks for CI template caching and optional signing configuration."""

import base64
import json
from pathlib import Path
import tempfile
import unittest

import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from configs import ci_support as ci


class CiBoundaries(unittest.TestCase):
    def test_tag_ref_forces_release_even_when_debug_is_requested(self):
        self.assertEqual(
            ci.build_type_for_ref("Debug", {"GITHUB_REF": "refs/tags/v1"}), "Release"
        )

    def test_branch_and_pr_default_to_debug(self):
        for ref in ("refs/heads/main", "refs/pull/1/merge"):
            self.assertEqual(
                ci.build_type_for_ref(environment={"GITHUB_REF": ref}), "Debug"
            )

    def test_manual_release_and_invalid_build_type(self):
        self.assertEqual(ci.build_type_for_ref("Release", {}), "Release")
        self.assertEqual(
            ci.build_type_for_ref(environment={"CI_BUILD_TYPE": "Release"}), "Release"
        )
        with self.assertRaisesRegex(ValueError, "Debug or Release"):
            ci.build_type_for_ref("Invalid", {})

    def test_partial_signing_configuration_is_rejected(self):
        with self.assertRaisesRegex(RuntimeError, "all three"):
            ci.signing_env({"CI_ANDROID_KEY_ALIAS": "fixture"})

    def test_optional_signing_is_isolated_from_transport_variables(self):
        with tempfile.TemporaryDirectory() as directory:
            source = {
                "RUNNER_TEMP": directory,
                "CI_ANDROID_KEYSTORE_BASE64": base64.b64encode(b"fixture key").decode(),
                "CI_ANDROID_KEY_ALIAS": "fixture",
                "CI_ANDROID_KEY_PASSWORD": "fixture-password",
            }
            env, mode = ci.signing_env(source)
            self.assertEqual(mode, "repository-signing-key")
            self.assertFalse(any(name.startswith("CI_ANDROID_") for name in env))
            self.assertEqual(
                Path(env["GODOT_ANDROID_KEYSTORE_RELEASE_PATH"]).read_bytes(),
                b"fixture key",
            )
            self.assertEqual(
                env["GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD"], "fixture-password"
            )
            self.assertNotIn("GODOT_ANDROID_KEYSTORE_RELEASE_PATH", source)

    def test_missing_signing_secrets_uses_ephemeral_ci_mode(self):
        env, mode = ci.signing_env({})
        self.assertEqual(mode, "ephemeral-ci-key")
        self.assertEqual(env, {})


class HostTestReports(unittest.TestCase):
    script = Path("test_playback_control.gd")

    def report(self, **changes):
        data = {"script": "res://tests/" + self.script.name, "exit_code": 0}
        data.update(changes)
        return "IMMIVIO_TEST_RESULT " + json.dumps(data) + "\n"

    def test_explicit_completion_accepts_normal_engine_output(self):
        ci.validate_host_test_result(self.script, 0, "Godot Engine\n" + self.report())

    def test_zero_exit_without_completion_is_not_success(self):
        for output in ("", "Test started\n", "checks passed\n"):
            with self.subTest(output=output), self.assertRaisesRegex(
                RuntimeError, "completion"
            ):
                ci.validate_host_test_result(self.script, 0, output)

    def test_stale_duplicate_malformed_and_failed_reports_are_rejected(self):
        for output in (
            self.report(script="res://tests/test_other.gd"),
            self.report(exit_code=1),
            self.report(exit_code=False),
            self.report() * 2,
            "IMMIVIO_TEST_RESULT not-json\n",
            "IMMIVIO_TEST_RESULT []\n",
        ):
            with self.subTest(output=output), self.assertRaises(RuntimeError):
                ci.validate_host_test_result(self.script, 0, output)

    def test_engine_errors_and_process_failure_override_completion(self):
        for code, message in (
            (1, ""),
            (0, "SCRIPT ERROR: failed"),
            (0, "SHADER ERROR: failed"),
            (0, "ERROR: failed"),
        ):
            with self.subTest(code=code, message=message), self.assertRaises(
                RuntimeError
            ):
                ci.validate_host_test_result(self.script, code, self.report() + message)


if __name__ == "__main__":
    unittest.main()
