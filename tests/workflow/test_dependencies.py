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
from freecm.asset_seeds import prepare_asset_seeds, require_asset_seeds
from freecm.build_cleanup import clean_build


class DependencyLifecycle(unittest.TestCase):
    def test_source_workflow_does_not_install_host_tools_or_packages(self):
        for argv in (["--init"], ["--update"], ["--refreshpin"], ["--pinlatest"]):
            with (
                self.subTest(argv=argv),
                patch.object(source.script, "main", return_value=0) as script,
            ):
                with patch(
                    "subprocess.run",
                    side_effect=AssertionError("Unexpected host installer"),
                ):
                    self.assertEqual(source.main(argv), 0)
                script.assert_called_once_with(argv)

    def test_disabled_sources_need_no_seed_and_can_be_enabled_explicitly(self):
        from freecm.dependency_roots import DependencyRootConfig, DependencyRootSpec

        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            lock = {
                "schemaVersion": 5,
                "depsMode": "pinned",
                "depsManualPath": {"Optional": ""},
                "dependencies": {
                    "Optional": {
                        "remote": "https://example.invalid/never-clone.git",
                        "commit": "a" * 40,
                        "disabled": True,
                    }
                },
            }
            path = root / "source_roots.lock.jsonc"
            path.write_text(json.dumps(lock))
            (root / "source_roots.lock.jsonc.in").write_text(json.dumps(lock))
            manager = source.Workflow(
                DependencyRootConfig(
                    repo_root=root,
                    repo_display_name="Fixture",
                    dependency_root_specs=(
                        DependencyRootSpec("Optional", "Optional", "OPTIONAL_ROOT", ()),
                    ),
                    default_required_relative_paths=(),
                )
            )
            with patch(
                "urllib.request.urlopen",
                side_effect=AssertionError("Unexpected download"),
            ):
                manager.init_seed_repositories()
                roots = manager.materialize_source_roots(allow_network=False)
            self.assertEqual(roots.dependency_roots.resolved_commits, {})
            self.assertFalse((root / "build/dependency_seed_repos/Optional").exists())
            lock["dependencies"]["Optional"]["disabled"] = False
            path.write_text(json.dumps(lock))
            with self.assertRaises((RuntimeError, FileNotFoundError)):
                manager.materialize_source_roots(allow_network=False)

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
        with (
            tempfile.TemporaryDirectory() as tmp,
            patch.object(android, "ROOT", Path(tmp)),
            patch.object(android.player, "environment") as sdk,
            patch.object(android.player, "run"),
        ):
            self.assertEqual(android.main(["stop-gradle"]), 0)
            sdk.assert_not_called()

    def test_missing_and_stale_configuration_cannot_build(self):
        from types import SimpleNamespace

        with (
            tempfile.TemporaryDirectory() as tmp,
            patch.object(android, "ROOT", Path(tmp)),
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
        with (
            tempfile.TemporaryDirectory() as tmp,
            patch.object(android, "ROOT", Path(tmp)),
        ):
            with self.assertRaisesRegex(RuntimeError, "Run build"):
                android.require_build(args)


if __name__ == "__main__":
    unittest.main()
