"""The public source copy must work without an upstream FreeCM installation."""

import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class VendoredFreecm(unittest.TestCase):
    def test_standalone_source_runs_workflows_and_rejects_corrupt_assets(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            for folder in ("configs", "third_party/freecm"):
                shutil.copytree(
                    ROOT / folder,
                    root / folder,
                    ignore=shutil.ignore_patterns("__pycache__", "*.pyc"),
                )
            for name in (
                "android/gradle/libs.versions.toml",
                "android/gradle/verification-metadata.xml",
                "android/gradle.lockfile",
                "third_party/mpv/manifest.json",
                "tools/validate_repo_commands.py",
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
                ["tools/validate_repo_commands.py"],
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
from pathlib import Path
import sys
sys.path.insert(0, sys.argv[1])
from configs import android_workflow as android
from configs.freecm_vendor import provenance
import freecm
import repomgrandroid
vendor = Path(sys.argv[1]) / 'third_party/freecm'
assert Path(freecm.__file__).is_relative_to(vendor)
assert Path(repomgrandroid.__file__).is_relative_to(vendor)
receipt = android.dependency_receipt()
assert receipt['freecm_commit'] == provenance()['commit']
assert receipt['freecm_vendor_sha256'] == provenance()['sha256']
assert receipt['schema_version'] == 4
assert 'third_party/freecm/UPSTREAM.json' in receipt['dependency_manifests']
assert 'third_party/openxr-vendors/manifest.json' in receipt['dependency_manifests']
assert 'dependency_mode' not in receipt
assert 'dependency_commits' not in receipt
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
            self.assertFalse((root / "FreeCM").exists())
            self.assertFalse((root / "source_roots.lock.jsonc").exists())
            self.assertFalse((root / "source_roots.lock.jsonc.in").exists())
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
