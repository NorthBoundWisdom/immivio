import hashlib
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from configs.setup_hosted_ci import download, unpack


class HostedToolDownloads(unittest.TestCase):
    def test_download_rejects_corrupt_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "tool.zip"
            path.write_bytes(b"corrupt")
            with patch("configs.setup_hosted_ci.subprocess.run"):
                with self.assertRaisesRegex(RuntimeError, "Checksum mismatch"):
                    download("https://example.com/tool.zip", path, "0" * 64)
                download(
                    "https://example.com/tool.zip",
                    path,
                    hashlib.sha256(b"corrupt").hexdigest(),
                )

    def test_font_download_checks_git_blob_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "font.otf"
            path.write_bytes(b"font")
            with patch("configs.setup_hosted_ci.subprocess.run"):
                download(
                    "https://example.com/font.otf",
                    path,
                    hashlib.sha1(b"blob 4\0font").hexdigest(),
                    git_blob=True,
                )
                with self.assertRaisesRegex(RuntimeError, "Checksum mismatch"):
                    download(
                        "https://example.com/font.otf", path, "0" * 40, git_blob=True
                    )

    def test_templates_extract_only_selected_android_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive = root / "templates.zip"
            with zipfile.ZipFile(archive, "w") as output:
                output.writestr("templates/android_source.zip", b"android")
                output.writestr("templates/unneeded-desktop", b"desktop")
            unpack(archive, root / "out", ["templates/android_source.zip"])
            self.assertEqual(
                (root / "out/templates/android_source.zip").read_bytes(), b"android"
            )
            self.assertFalse((root / "out/templates/unneeded-desktop").exists())

    def test_archive_cannot_write_outside_destination(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive = root / "bad.zip"
            with zipfile.ZipFile(archive, "w") as output:
                output.writestr("../escaped", b"bad")
            with self.assertRaisesRegex(RuntimeError, "Unsafe archive"):
                unpack(archive, root / "out")
            self.assertFalse((root / "escaped").exists())
