"""The public source copy runs with Python's standard library alone."""

import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class StandaloneWorkflow(unittest.TestCase):
    def test_standalone_source_runs_workflows_and_rejects_corrupt_assets(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            shutil.copytree(
                ROOT / "configs",
                root / "configs",
                ignore=shutil.ignore_patterns("__pycache__", "*.pyc", "*.jsonc"),
            )
            for name in (
                "android/gradle/libs.versions.toml",
                "android/gradle/verification-metadata.xml",
                "android/gradle.lockfile",
                "third_party/mpv/manifest.json",
            ):
                target = root / name
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(ROOT / name, target)
            content = b"verified local addon fixture"
            seed = root / ".cache/openxr-vendors/addon.zip"
            seed.parent.mkdir(parents=True)
            seed.write_bytes(content)
            addon = {
                "version": "test",
                "url": "https://example.invalid/addon.zip",
                "fileName": "addon.zip",
                "sizeBytes": len(content),
                "sha256": hashlib.sha256(content).hexdigest(),
            }
            manifest = root / "third_party/openxr-vendors/manifest.json"
            manifest.parent.mkdir(parents=True)
            manifest.write_text(json.dumps(addon))
            for command in (
                ["configs/prepare_assets.py"],
                ["configs/android_workflow.py", "--help"],
            ):
                with self.subTest(command=command):
                    result = subprocess.run(
                        [sys.executable, "-I", "-S", *command],
                        cwd=root,
                        capture_output=True,
                        text=True,
                        timeout=30,
                    )
                    self.assertEqual(
                        result.returncode, 0, result.stdout + result.stderr
                    )
            result = subprocess.run(
                [
                    sys.executable,
                    "-I",
                    "-S",
                    "-c",
                    """
import json
import sys
sys.path.insert(0, sys.argv[1])
from configs import android_workflow as android
receipt = android.dependency_receipt()
assert receipt['schema_version'] == 5
assert 'third_party/openxr-vendors/manifest.json' in receipt['dependency_manifests']
print(json.dumps(receipt))
""",
                    str(root),
                ],
                cwd=root,
                capture_output=True,
                text=True,
                timeout=30,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertFalse((root / ".git").exists())
            seed.write_bytes(b"corrupted addon")
            result = subprocess.run(
                [
                    sys.executable,
                    "-I",
                    "-S",
                    "configs/prepare_assets.py",
                ],
                cwd=root,
                capture_output=True,
                text=True,
                timeout=30,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("OpenXR addon", result.stdout + result.stderr)
