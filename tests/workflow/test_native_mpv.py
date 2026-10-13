"""NDK extraction retains required executable bits without permitting link traversal."""

from pathlib import Path
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from configs.native_mpv_workflow import extract_ndk


class NdkExtraction(unittest.TestCase):
    def test_contained_symlink_and_executable_are_preserved(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            archive = root / "ndk.zip"
            with zipfile.ZipFile(archive, "w") as source:
                executable = zipfile.ZipInfo("ndk/bin/compiler")
                executable.create_system = 3
                executable.external_attr = 0o100755 << 16
                source.writestr(executable, b"compiler fixture")
                link = zipfile.ZipInfo("ndk/bin/alias")
                link.create_system = 3
                link.external_attr = 0o120777 << 16
                source.writestr(link, "compiler")
            extract_ndk(archive, root / "output")
            self.assertEqual(
                (root / "output/ndk/bin/alias").read_bytes(), b"compiler fixture"
            )
            self.assertTrue((root / "output/ndk/bin/compiler").stat().st_mode & 0o111)

    def test_escaping_link_is_rejected_before_any_file_is_written(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            archive = root / "ndk.zip"
            with zipfile.ZipFile(archive, "w") as source:
                source.writestr("ndk/good", "fixture")
                link = zipfile.ZipInfo("ndk/link")
                link.create_system = 3
                link.external_attr = 0o120777 << 16
                source.writestr(link, "../../outside")
            with self.assertRaisesRegex(RuntimeError, "escapes"):
                extract_ndk(archive, root / "output")
            self.assertFalse((root / "output/ndk/good").exists())


if __name__ == "__main__":
    unittest.main()
