"""Behavioral checks for acquisition boundaries, configuration fences and cleanup."""

import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from configs import source_root_workflow as source, android_workflow as android
from configs import dependencies as deps
from freecm.asset_seeds import prepare_asset_seeds, require_asset_seeds
from freecm.build_cleanup import clean_build


class DependencyLifecycle(unittest.TestCase):
    def test_update_refresh_latest_and_diagnostics_never_initialize_packages(self):
        for argv in (
            ["--update"],
            ["--refreshpin"],
            ["--pinlatest"],
            ["--cleanbuild", "--dry-run"],
        ):
            with self.subTest(argv=argv), patch.object(
                source.script, "main", return_value=0
            ) as script, patch.object(
                source, "initialize_packages"
            ) as network, patch.object(
                source, "select_assets"
            ) as assets:
                self.assertEqual(source.main(argv), 0)
                script.assert_called_once_with(argv)
                network.assert_not_called()
                if argv[0] in ("--update", "--refreshpin"):
                    assets.assert_called_once_with(native=False)
                else:
                    assets.assert_not_called()

    def test_host_asset_selection_keeps_native_downloads_opt_in(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(
            deps, "ROOT", Path(tmp)
        ):
            root = Path(tmp)
            template = {
                "schemaVersion": 5,
                "depsMode": "pinned",
                "depsManualPath": {},
                "dependencies": {},
                "assets": {
                    name: {
                        "seedPath": "build/dependency_seed_repos/" + name,
                        "files": [],
                    }
                    for name in (
                        "Gradle",
                        "GodotTemplates",
                        "OpenXRVendors",
                        "MpvAndroid",
                        "GodotMacOS",
                        "NotoLicense",
                        "NotoSansCJKSC",
                        "NotoSansCJKTC",
                        "NotoSansCJKJP",
                        "MpvSources",
                        "MpvBuilder",
                        "MpvLinuxNdk",
                    )
                },
            }
            (root / "source_roots.lock.jsonc.in").write_text(json.dumps(template))
            (root / "source_roots.lock.jsonc").write_text(json.dumps(template))
            with patch(
                "configs.source_roots.workflow.ensure_active_lock_file"
            ), patch.object(deps.sys, "platform", "darwin"):
                deps.select_assets()
                self.assertNotIn("MpvLinuxNdk", deps.lock_data(root)["assets"])
                deps.select_assets(native=True)
                self.assertIn("MpvLinuxNdk", deps.lock_data(root)["assets"])
                self.assertTrue((root / ".cache/native-mpv-enabled").exists())

    def test_python_package_download_requires_explicit_init(self):
        with self.assertRaisesRegex(ValueError, "requires --init"):
            source.main(["--update", "--python-tools"])

    def test_package_refresh_requires_explicit_init(self):
        with self.assertRaisesRegex(ValueError, "requires --init"):
            source.main(["--update", "--refresh-packages"])

    def test_native_download_request_requires_explicit_init(self):
        with self.assertRaisesRegex(ValueError, "requires --init"):
            source.main(["--update", "--native-mpv"])

    def test_verified_asset_lifecycle_and_corruption_do_not_download_during_verify(
        self,
    ):
        import hashlib

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            fixture = root / "fixture"
            fixture.write_bytes(b"locked payload")
            lock = {
                "schemaVersion": 5,
                "depsMode": "pinned",
                "depsManualPath": {},
                "dependencies": {},
                "assets": {
                    "Fixture": {
                        "seedPath": "build/dependency_seed_repos/Fixture",
                        "files": [
                            {
                                "id": "fixture",
                                "type": "file",
                                "url": fixture.as_uri(),
                                "fileName": "fixture",
                                "sizeBytes": fixture.stat().st_size,
                                "sha256": hashlib.sha256(
                                    fixture.read_bytes()
                                ).hexdigest(),
                            }
                        ],
                    }
                },
            }
            (root / "source_roots.lock.jsonc").write_text(json.dumps(lock))
            prepare_asset_seeds(root)
            with patch("urllib.request.urlopen", side_effect=AssertionError("offline")):
                require_asset_seeds(root)
                (root / "build/dependency_seed_repos/Fixture/fixture").write_bytes(
                    b"corrupt"
                )
                with self.assertRaisesRegex(FileNotFoundError, "missing or invalid"):
                    require_asset_seeds(root)

    def test_cleanup_preserves_dependency_roots_and_signing_material(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for relative in (
                "build/dependency_seed_repos/A",
                "build/dependency_source_roots/A",
                "build/generated",
                "artifacts/signing",
            ):
                path = root / relative
                path.mkdir(parents=True)
                (path / "marker").touch()
            clean_build(root, dry_run=True)
            self.assertTrue((root / "build/generated").exists())
            clean_build(root, dry_run=False)
            self.assertFalse((root / "build/generated").exists())
            for relative in (
                "build/dependency_seed_repos/A",
                "build/dependency_source_roots/A",
                "artifacts/signing",
            ):
                self.assertTrue((root / relative / "marker").exists())

    def test_cleanup_can_stop_gradle_after_incomplete_setup(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(
            android, "ROOT", Path(tmp)
        ), patch.object(android.player, "environment") as sdk:
            self.assertEqual(android.main(["stop-gradle"]), 0)
            sdk.assert_not_called()

    def test_missing_and_stale_configuration_cannot_build(self):
        from types import SimpleNamespace

        with tempfile.TemporaryDirectory() as tmp, patch.object(
            android, "ROOT", Path(tmp)
        ):
            args = SimpleNamespace(vendor="Quest", build_type="Debug")
            with self.assertRaisesRegex(RuntimeError, "Configure"):
                android.require_configuration(args, {}, Path(tmp) / "sdk")
            marker = android.configuration_path("Quest", "Debug")
            marker.parent.mkdir(parents=True)
            marker.write_text(
                json.dumps(
                    {
                        "inputs": {"old": "hash"},
                        "host": sys.platform,
                        "sdk": "sdk",
                        "java_home": "jdk",
                    }
                )
            )
            with patch.object(android, "input_signature", return_value={"new": "hash"}):
                with self.assertRaisesRegex(RuntimeError, "stale"):
                    android.require_configuration(
                        args, {"JAVA_HOME": "jdk"}, Path("sdk")
                    )

    def test_build_and_package_are_separate_stages(self):
        from types import SimpleNamespace

        args = SimpleNamespace(vendor="Quest", build_type="Debug")
        with tempfile.TemporaryDirectory() as tmp, patch.object(
            android, "ROOT", Path(tmp)
        ):
            with self.assertRaisesRegex(RuntimeError, "Run build"):
                android.require_build(args)


if __name__ == "__main__":
    unittest.main()
