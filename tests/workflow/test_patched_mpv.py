"""Patch provenance and byte-integrity boundaries for the source-built playback runtime."""

import json
from pathlib import Path
import tempfile
import unittest
from tools.build_patched_mpv import digest, recipe_inputs, verify_output


class PatchedMpv(unittest.TestCase):
    def test_recipe_and_library_bytes_must_both_match(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for name in [
                "tools/build_patched_mpv.py",
                "native/fix.patch",
                "native/clock.h",
                "third_party/mpv/manifest.json",
            ]:
                target = root / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text("reviewed input")
            lock = {
                "patch": "native/fix.patch",
                "clock_header": "native/clock.h",
                "ndk": "reviewed-ndk",
                "tools": {"meson": "reviewed-version"},
            }
            (root / "third_party/mpv/source-build.json").write_text(json.dumps(lock))
            library = root / "prepared/libmpv.so"
            library.parent.mkdir()
            library.write_bytes(b"compiled reviewed runtime")
            receipt = {
                "schema_version": 1,
                "inputs": recipe_inputs(root),
                "ndk": lock["ndk"],
                "tools": lock["tools"],
                "sha256": digest(library),
                "bytes": library.stat().st_size,
            }
            (library.parent / "mpv-build-receipt.json").write_text(json.dumps(receipt))
            verify_output(library, root)
            library.write_bytes(b"modified runtime")
            with self.assertRaisesRegex(RuntimeError, "library bytes changed"):
                verify_output(library, root)
            library.write_bytes(b"compiled reviewed runtime")
            (root / "native/fix.patch").write_text("different patch")
            with self.assertRaisesRegex(RuntimeError, "source recipe changed"):
                verify_output(library, root)

    def test_missing_receipt_does_not_accept_a_stock_or_unreviewed_library(self):
        with tempfile.TemporaryDirectory() as temporary:
            library = Path(temporary) / "libmpv.so"
            library.write_bytes(b"arbitrary")
            with self.assertRaisesRegex(RuntimeError, "incompatible patched libmpv"):
                verify_output(library)

    def test_full_source_receipt_covers_each_ffmpeg_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            files = [
                "tools/build_patched_mpv.py",
                "native/fix.patch",
                "native/clock.h",
                "native/codec.patch",
                "native/cadence.patch",
                "third_party/mpv/manifest.json",
            ]
            for name in files:
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("locked")
            lock = {
                "patch": "native/fix.patch",
                "clock_header": "native/clock.h",
                "ffmpeg_patch": "native/codec.patch",
                "extra_patches": ["native/cadence.patch"],
                "build_ffmpeg": True,
                "ndk": "reviewed",
                "tools": {},
            }
            (root / "third_party/mpv/source-build.json").write_text(json.dumps(lock))
            library = root / "prepared/libavcodec.so"
            library.parent.mkdir()
            library.write_bytes(b"patched codec")
            receipt = {
                "schema_version": 1,
                "inputs": recipe_inputs(root),
                "ndk": lock["ndk"],
                "tools": {},
                "libraries": {
                    library.name: {
                        "sha256": digest(library),
                        "bytes": library.stat().st_size,
                    }
                },
            }
            (library.parent / "mpv-build-receipt.json").write_text(json.dumps(receipt))
            verify_output(library, root)
            library.write_bytes(b"stock codec")
            with self.assertRaisesRegex(RuntimeError, "library bytes changed"):
                verify_output(library, root)
            library.write_bytes(b"patched codec")
            (root / "native/codec.patch").write_text("changed decoder policy")
            with self.assertRaisesRegex(RuntimeError, "source recipe changed"):
                verify_output(library, root)
