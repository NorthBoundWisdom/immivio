"""The master lock owns package versions; outputs cannot become competing authorities."""

from pathlib import Path
import json
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from configs import dependency_manifest as manifest
from freecm.dependency_lock import validate_dependency_lock_data


class MasterLock(unittest.TestCase):
    def fixture(self, root):
        data = manifest.template(ROOT)
        # Keep the real resolution graph but omit vendored files outside the fixture.
        data["immivio"]["vendored"] = {}
        (root / "source_roots.lock.jsonc.in").write_text(json.dumps(data))
        return data

    def test_fresh_checkout_generates_every_ecosystem_input_and_detects_manual_edits(
        self,
    ):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.fixture(root)
            manifest.generate(root)
            manifest.verify(root)
            self.assertTrue((root / "cloud/openlist/go.sum").is_file())
            self.assertTrue(
                (root / "android/gradle/verification-metadata.xml").is_file()
            )
            self.assertTrue(
                (
                    root / "build/dependency_manifests/python-media-tools.lock.txt"
                ).is_file()
            )
            (root / "android/gradle/libs.versions.toml").write_text(
                '[versions]\nmedia3="wrong"\n'
            )
            with self.assertRaisesRegex(RuntimeError, "differ"):
                manifest.verify(root)
            manifest.generate(root)
            manifest.verify(root)

    def test_version_update_has_one_authority(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            data = self.fixture(root)
            manifest.generate(root)
            data["immivio"]["gradle"]["catalog"]["versions"][
                "media3"
            ] = "fixture-new-version"
            (root / "source_roots.lock.jsonc.in").write_text(json.dumps(data))
            manifest.generate(root)
            self.assertIn(
                "fixture-new-version",
                (root / "android/gradle/libs.versions.toml").read_text(),
            )

    def test_generation_is_idempotent_and_preserves_existing_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.fixture(root)
            manifest.generate(root)
            path = root / "cloud/openlist/go.mod"
            before = path.stat().st_mtime_ns
            manifest.generate(root)
            self.assertEqual(path.stat().st_mtime_ns, before)

    def test_git_pins_and_host_extension_use_the_unmodified_freecm_schema(self):
        data = manifest.template(ROOT)
        validate_dependency_lock_data(data, path_label="source_roots.lock.jsonc.in")
        for name, record in data["dependencies"].items():
            self.assertRegex(record["commit"], "^[0-9a-f]{40}$", name)
        self.assertNotIn("MpvSources", data["assets"])
        self.assertNotIn("MpvBuilder", data["assets"])

    def test_invalid_checksum_and_output_escape_are_rejected(self):
        with self.assertRaisesRegex(ValueError, "checksum"):
            manifest.render_verification({"example:lib:1": {"lib.jar": ["bad"]}})
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaisesRegex(ValueError, "escapes"):
                manifest.safe_path(Path(tmp), "../outside")


if __name__ == "__main__":
    unittest.main()
