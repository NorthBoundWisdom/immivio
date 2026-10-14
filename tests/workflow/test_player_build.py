"""Offline boundary tests for dependency cache and archive handling."""

from pathlib import Path
import argparse
import hashlib
import json
import os
import sys
import tempfile
import time
import unittest
from unittest.mock import patch
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from configs import player_build as builder


class DependencyBoundaries(unittest.TestCase):
    def test_preinstalled_mpv_libraries_are_verified_before_staging(self):
        with (
            tempfile.TemporaryDirectory() as directory,
            patch.object(builder, "ROOT", Path(directory)),
        ):
            root = Path(directory)
            native = root / "prepared"
            native.mkdir()
            records = []
            for name in ("libmpv.so", "libavcodec.so"):
                path = native / name
                path.write_bytes(b"original")
                records.append(
                    {
                        "name": name,
                        "bytes": path.stat().st_size,
                        "sha256": builder.digest(path),
                    }
                )
            manifest = root / "third_party/mpv/manifest.json"
            manifest.parent.mkdir(parents=True)
            manifest.write_text(
                json.dumps(
                    {
                        "packaged_libraries": [item["name"] for item in records],
                        "libraries": records,
                    }
                )
            )
            (native / "libavcodec.so").write_bytes(b"modified")
            with patch.dict(os.environ, {"IMMIVIO_MPV_LIB_DIR": str(native)}):
                with self.assertRaisesRegex(RuntimeError, "incompatible"):
                    builder.prepare_mpv()
            self.assertFalse((root / "android").exists())

    def test_engine_failure_terminates_a_hung_export_and_keeps_its_log(self):
        with (
            tempfile.TemporaryDirectory() as directory,
            patch.object(builder, "LOGS", Path(directory)),
        ):
            started = time.monotonic()
            with self.assertRaisesRegex(RuntimeError, "Godot reported an error"):
                builder.run(
                    [
                        sys.executable,
                        "-u",
                        "-c",
                        'import time; print("ERROR: Export failed"); time.sleep(60)',
                    ],
                    log="export.log",
                    timeout=10,
                    fail_on_engine_error=True,
                )
            self.assertLess(time.monotonic() - started, 8)
            self.assertIn(
                "ERROR: Export failed", (Path(directory) / "export.log").read_text()
            )

    def test_silent_hung_command_is_bounded(self):
        with (
            tempfile.TemporaryDirectory() as directory,
            patch.object(builder, "LOGS", Path(directory)),
        ):
            started = time.monotonic()
            with self.assertRaisesRegex(RuntimeError, "timed out"):
                builder.run(
                    [sys.executable, "-c", "import time; time.sleep(60)"],
                    log="silent.log",
                    timeout=0.5,
                )
            self.assertLess(time.monotonic() - started, 8)

    def test_host_sdk_alias_is_preserved_when_real_path_contains_spaces(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            actual = root / "Android SDK real"
            ndk, cmake = "30.0.16248370", "4.1.2"
            (actual / f"ndk/{ndk}/build/cmake").mkdir(parents=True)
            (actual / f"ndk/{ndk}/build/cmake/android.toolchain.cmake").touch()
            (actual / f"cmake/{cmake}").mkdir(parents=True)
            alias = root / "sdk"
            try:
                alias.symlink_to(actual, target_is_directory=True)
            except OSError:
                self.skipTest("Host does not permit directory symlinks")
            jdk = root / "jdk"
            (jdk / "bin").mkdir(parents=True)
            (jdk / "bin" / ("java.exe" if os.name == "nt" else "java")).touch()
            args = argparse.Namespace(
                sdk=str(alias),
                java_home=str(jdk),
                ndk=ndk,
                cmake=cmake,
                gradle="gradle",
            )
            env, observed = builder.environment(args)
            self.assertEqual(observed, alias.absolute())
            self.assertEqual(
                env["ANDROID_NDK_HOME"], str(alias.absolute() / f"ndk/{ndk}")
            )
            self.assertTrue(
                (observed / f"ndk/{ndk}/build/cmake/android.toolchain.cmake").is_file()
            )

    def test_java_proxy_bypass_preserves_host_no_proxy(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "sdk/ndk/ndk/build/cmake").mkdir(parents=True)
            (root / "sdk/ndk/ndk/build/cmake/android.toolchain.cmake").touch()
            (root / "sdk/cmake/cmake").mkdir(parents=True)
            (root / "jdk/bin").mkdir(parents=True)
            (root / "jdk/bin" / ("java.exe" if os.name == "nt" else "java")).touch()
            args = argparse.Namespace(
                sdk=str(root / "sdk"),
                java_home=str(root / "jdk"),
                ndk="ndk",
                cmake="cmake",
                gradle="gradle",
            )
            env, _ = builder.environment(
                args,
                {
                    "PATH": "",
                    "HTTPS_PROXY": "http://proxy.example:8080",
                    "NO_PROXY": "repo.maven.apache.org,.example.org",
                },
            )
            self.assertIn(
                "-Dhttp.nonProxyHosts=repo.maven.apache.org|*.example.org",
                env["JAVA_TOOL_OPTIONS"],
            )

    def test_zip_traversal_is_rejected_before_extracting_any_entry(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive = root / "unsafe.zip"
            with zipfile.ZipFile(archive, "w") as stream:
                stream.writestr("valid", "valid")
                stream.writestr("../outside", "escape")
            with self.assertRaisesRegex(RuntimeError, "Unsafe dependency archive path"):
                builder.extract(archive, root / "output")
            self.assertFalse((root / "outside").exists())
            self.assertFalse((root / "output/valid").exists())

    def test_zip_symlink_cannot_redirect_a_later_file(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive = root / "unsafe.zip"
            with zipfile.ZipFile(archive, "w") as stream:
                link = zipfile.ZipInfo("link")
                link.create_system = 3
                link.external_attr = 0o120777 << 16
                stream.writestr(link, "../outside")
                stream.writestr("link/file", "escape")
            with self.assertRaisesRegex(RuntimeError, "symbolic link"):
                builder.extract(archive, root / "output")
            self.assertFalse((root / "outside").exists())


class VariantIdentityBoundaries(unittest.TestCase):
    def test_package_and_label_are_separate_and_presets_restore_after_failure(self):
        with (
            tempfile.TemporaryDirectory() as directory,
            patch.object(builder, "PROJECT", Path(directory)),
        ):
            path = Path(directory) / "export_presets.cfg"
            original = b"\r\n".join(
                [b'package/unique_name="com.wapok.thru3d"\r\npackage/name="Original"']
                * 3
            )
            path.write_bytes(original)
            with self.assertRaisesRegex(RuntimeError, "simulated"):
                with builder.variant_export_presets() as identity:
                    self.assertEqual(identity["application_id"], "com.wapok.thru3d")
                    self.assertEqual(
                        path.read_text().count('package/name="Immivio"'), 3
                    )
                    raise RuntimeError("simulated export failure")
            self.assertEqual(path.read_bytes(), original)
            with builder.variant_export_presets() as identity:
                self.assertEqual(identity["application_id"], "com.wapok.thru3d")
                self.assertEqual(identity, builder.android_identity())
            self.assertEqual(path.read_bytes(), original)

    def test_existing_signing_override_is_used_without_generating_another_key(self):
        env = {
            "GODOT_ANDROID_KEYSTORE_RELEASE_PATH": "base.key",
            "GODOT_ANDROID_KEYSTORE_RELEASE_USER": "base",
            "GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD": "fixture",
        }
        with patch.object(builder, "run") as run:
            self.assertEqual(builder.signing_environment(env), env)
            run.assert_not_called()

    def test_partial_signing_override_is_rejected(self):
        with self.assertRaisesRegex(RuntimeError, "all GODOT_ANDROID"):
            builder.signing_environment(
                {"GODOT_ANDROID_KEYSTORE_RELEASE_USER": "only-alias"}
            )

    def test_relocated_legacy_workspace_reuses_the_same_named_key(self):
        with (
            tempfile.TemporaryDirectory() as directory,
            patch.object(builder, "ROOT", Path(directory)),
            patch.object(builder, "run") as run,
        ):
            signing = Path(directory) / "artifacts/signing"
            signing.mkdir(parents=True)
            key = signing / "thru3d-release.keystore"
            key.write_bytes(b"original fixture key")
            record = {
                "keystore": "D:\\old-workspace\\artifacts\\signing\\thru3d-release.keystore",
                "alias": "legacy",
                "password": "fixture",
            }
            (signing / "thru3d-signing.json").write_text(json.dumps(record))
            env = builder.signing_environment({})
            self.assertEqual(env["GODOT_ANDROID_KEYSTORE_RELEASE_PATH"], str(key))
            self.assertEqual(
                json.loads((signing / "thru3d-signing.json").read_text()), record
            )
            run.assert_not_called()

    def test_missing_legacy_key_cannot_silently_create_a_new_identity(self):
        with (
            tempfile.TemporaryDirectory() as directory,
            patch.object(builder, "ROOT", Path(directory)),
            patch.object(builder, "run") as run,
        ):
            signing = Path(directory) / "artifacts/signing"
            signing.mkdir(parents=True)
            (signing / "thru3d-signing.json").write_text(
                json.dumps(
                    {
                        "keystore": str(signing / "missing.key"),
                        "alias": "legacy",
                        "password": "fixture",
                    }
                )
            )
            with self.assertRaisesRegex(RuntimeError, "Saved signing key is missing"):
                builder.signing_environment({})
            run.assert_not_called()


if __name__ == "__main__":
    unittest.main()
