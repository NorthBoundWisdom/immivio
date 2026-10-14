"""Behavioral checks for acquisition boundaries, configuration fences and cleanup."""

import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from configs import android_workflow as android
from freecm.build_cleanup import clean_build


class DependencyLifecycle(unittest.TestCase):
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
