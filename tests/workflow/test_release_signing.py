"""Exercise release APK signer verification and persistent signing keys."""

import json
import shutil
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile
from contextlib import nullcontext
from types import SimpleNamespace

from configs import player_build as builder


class ReleaseSigning(unittest.TestCase):
    certificate = "a" * 64

    def package_signer(self, prefix, *, vendor="Pico", mismatch=False):
        root = Path(self.directory.name) / "package-test"
        project = root / "project"
        logs = root / "logs"
        project.mkdir(parents=True, exist_ok=True)
        logs.mkdir(exist_ok=True)
        (project / "project.godot").write_text('config/version="0.9.6"\n')
        expected = self.certificate
        apk = root / "fixture.apk"
        with zipfile.ZipFile(apk, "w") as archive:
            archive.writestr("assets/project.binary", b"pico,immivio_web")
        actual = "b" * 64 if mismatch else expected
        outputs = []

        def export(command, *, log, **kwargs):
            output = Path(command[-1])
            shutil.copy2(apk, output)
            outputs.append(output)
            (logs / log).write_text("Export completed\n")

        def inspect(output, env, sdk):
            (logs / "base-apk-signature.log").write_text(
                f"Verifies\n{prefix} certificate SHA-256 digest: {actual}\n"
            )
            return builder.digest(output)

        def command_output(command, **kwargs):
            return "f" * 40 if command[1] == "rev-parse" else ""

        env = {
            "JAVA_HOME": str(root / "jdk"),
            "GODOT_ANDROID_KEYSTORE_RELEASE_PATH": str(root / "unused.keystore"),
            "GODOT_ANDROID_KEYSTORE_RELEASE_USER": "fixture",
            "GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD": "fixture",
        }
        args = SimpleNamespace(
            vendor=vendor,
            build_type="Release",
            godot="godot",
            ndk="fixture",
            cmake="fixture",
        )
        with (
            patch.object(builder, "ROOT", root),
            patch.object(builder, "PROJECT", project),
            patch.object(builder, "LOGS", logs),
            patch.object(
                builder, "template_directory", return_value=(root, "4.7.2.stable")
            ),
            patch.object(
                builder, "signing_environment", side_effect=lambda env, **kw: env.copy()
            ),
            patch.object(builder, "variant_export_presets", return_value=nullcontext()),
            patch.object(builder, "export_executable", return_value="godot"),
            patch.object(builder, "run", side_effect=export),
            patch.object(builder, "inspect_package", side_effect=inspect),
            patch.object(
                builder.subprocess, "check_output", side_effect=command_output
            ),
            patch.object(builder, "CERTIFICATE_SHA256", expected),
            patch(
                "configs.android_workflow.dependency_receipt",
                return_value={"schema_version": 5},
            ),
            patch.dict("os.environ", {"IMMIVIO_DEVELOPMENT_PACKAGE": "0"}),
        ):
            if mismatch:
                with self.assertRaisesRegex(RuntimeError, "APK signer differs"):
                    builder.package(args, env, root / "sdk", build_sha256="b" * 64)
                self.assertFalse(outputs[0].exists())
                self.assertFalse(outputs[0].with_suffix(".build.json").exists())
            else:
                builder.package(args, env, root / "sdk", build_sha256="b" * 64)
                receipt = json.loads(outputs[0].with_suffix(".build.json").read_text())
                self.assertEqual(receipt["signing_certificate_sha256"], expected)
                self.assertEqual(receipt["build_sha256"], "b" * 64)

    def test_package_reads_legacy_and_v2_signer_output(self):
        for prefix in ("Signer #1", "V2 Signer:"):
            with self.subTest(prefix=prefix):
                self.package_signer(prefix)

    def test_package_rejects_wrong_certificate_in_both_signer_formats(self):
        for prefix in ("Signer #1", "V2 Signer:"):
            with self.subTest(prefix=prefix):
                self.package_signer(prefix, mismatch=True)

    def test_every_vendor_rejects_a_different_release_certificate(self):
        for vendor in ("Pico", "Quest", "OpenXR"):
            with self.subTest(vendor=vendor):
                self.package_signer("Signer #1", vendor=vendor, mismatch=True)

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)

    def test_persistent_key_survives_disposable_artifact_cleanup(self):
        root = Path(self.directory.name)
        persistent = root / "private-config/signing"
        persistent.mkdir(parents=True)
        key = persistent / "immivio-release.keystore"
        key.write_bytes(b"fixed project key")
        (persistent / "immivio-signing.json").write_text(
            json.dumps(
                {"keystore": str(key), "alias": "immivio", "password": "fixture"}
            )
        )
        artifacts = root / "artifacts"
        artifacts.mkdir()
        (artifacts / "unrelated.bin").write_bytes(b"disposable")
        shutil.rmtree(artifacts)
        with patch.object(builder, "ROOT", root), patch.object(builder, "run") as run:
            env = builder.signing_environment(
                {"IMMIVIO_SIGNING_DIR": str(persistent)}, require_existing=True
            )
            self.assertEqual(env["GODOT_ANDROID_KEYSTORE_RELEASE_PATH"], str(key))
            self.assertEqual(key.read_bytes(), b"fixed project key")
            run.assert_not_called()

    def test_legacy_migration_cannot_overwrite_a_different_persistent_key(self):
        root = Path(self.directory.name)
        legacy = root / "artifacts/signing"
        legacy.mkdir(parents=True)
        source = legacy / "immivio-release.keystore"
        source.write_bytes(b"legacy key")
        (legacy / "immivio-signing.json").write_text(
            json.dumps(
                {"keystore": str(source), "alias": "immivio", "password": "fixture"}
            )
        )
        target = root / "private-config/signing"
        target.mkdir(parents=True)
        existing = target / "immivio-release.keystore"
        existing.write_bytes(b"different key")
        with patch.object(builder, "ROOT", root):
            with self.assertRaisesRegex(RuntimeError, "refusing to overwrite"):
                builder.signing_environment(
                    {"IMMIVIO_SIGNING_DIR": str(target)}, require_existing=True
                )
        self.assertEqual(existing.read_bytes(), b"different key")

    def test_formal_releases_never_generate_an_ephemeral_key(self):
        with (
            patch.object(builder, "ROOT", Path(self.directory.name)),
            patch.object(builder, "run") as run,
        ):
            with self.assertRaisesRegex(RuntimeError, "existing project release key"):
                builder.signing_environment(
                    {
                        "IMMIVIO_SIGNING_DIR": str(
                            Path(self.directory.name) / "persistent"
                        )
                    },
                    require_existing=True,
                )
            run.assert_not_called()


if __name__ == "__main__":
    unittest.main()
