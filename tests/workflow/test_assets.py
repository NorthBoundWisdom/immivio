"""The single OpenXR archive uses explicit acquisition and offline verification."""

import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from configs import dependencies
from test_hosted_ci import served


class OpenxrArchive(unittest.TestCase):
    def manifest(self, root, payload, url):
        path = root / "third_party/openxr-vendors/manifest.json"
        path.parent.mkdir(parents=True)
        path.write_text(
            json.dumps(
                {
                    "version": "test",
                    "url": url,
                    "fileName": "addon.zip",
                    "sizeBytes": len(payload),
                    "sha256": hashlib.sha256(payload).hexdigest(),
                }
            )
        )

    def test_explicit_download_verifies_bytes_and_reuses_cache_offline(self):
        payload = b"verified addon fixture"
        with tempfile.TemporaryDirectory() as temporary, served(payload) as origin:
            root = Path(temporary)
            self.manifest(root, payload, origin + "/tool")
            with patch.object(dependencies, "ROOT", root):
                archive = dependencies.prepare_vendor_archive()
                self.assertEqual(archive.read_bytes(), payload)
                with patch.object(
                    dependencies,
                    "urlopen",
                    side_effect=AssertionError("unexpected network"),
                ):
                    self.assertEqual(dependencies.prepare_vendor_archive(), archive)
                    self.assertEqual(dependencies.vendors_archive(), archive)
                    archive.write_bytes(b"corrupted")
                    with self.assertRaisesRegex(RuntimeError, "invalid OpenXR addon"):
                        dependencies.vendors_archive()

    def test_wrong_download_cannot_replace_existing_bytes(self):
        for observed in (b"tampered", b"larger than expected"):
            with self.subTest(
                observed=observed
            ), tempfile.TemporaryDirectory() as temporary, served(observed) as origin:
                root = Path(temporary)
                self.manifest(root, b"expected", origin + "/tool")
                archive = root / ".cache/openxr-vendors/addon.zip"
                archive.parent.mkdir(parents=True)
                archive.write_bytes(b"previous archive")
                with patch.object(dependencies, "ROOT", root):
                    with self.assertRaises(RuntimeError):
                        dependencies.prepare_vendor_archive()
                self.assertEqual(archive.read_bytes(), b"previous archive")

    def test_failed_response_cannot_become_a_verified_cache(self):
        with tempfile.TemporaryDirectory() as temporary, served(b"addon") as origin:
            root = Path(temporary)
            self.manifest(root, b"addon", origin + "/missing")
            with patch.object(dependencies, "ROOT", root):
                with self.assertRaises(OSError):
                    dependencies.prepare_vendor_archive()
            self.assertFalse((root / ".cache/openxr-vendors/addon.zip").exists())
