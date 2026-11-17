"""Dependency caches reuse only matching inputs and unchanged verified files."""

import json
import os
from pathlib import Path
import tempfile
import unittest

from configs.ci_playback_cache import cache_key, reuse_or_build, verify_runtime
from configs.setup_hosted_ci import reuse_host_tools, install_font
from tools.build_patched_mpv import digest, recipe_inputs


class PlaybackCache(unittest.TestCase):
    def fixture(self, root):
        for name in [
            "tools/build_patched_mpv.py",
            "native/fix.patch",
            "native/clock.h",
        ]:
            path = root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("reviewed source")
        names = [
            "libmpv.so",
            "libavcodec.so",
            "libavdevice.so",
            "libavfilter.so",
            "libavformat.so",
            "libavutil.so",
            "libswresample.so",
            "libswscale.so",
        ]
        folder = root / "third_party/mpv"
        folder.mkdir(parents=True)
        (folder / "source-build.json").write_text(
            json.dumps(
                {
                    "ndk": "ndk",
                    "tools": {},
                    "patch": "native/fix.patch",
                    "clock_header": "native/clock.h",
                    "build_ffmpeg": True,
                }
            )
        )
        (folder / "manifest.json").write_text(
            json.dumps(
                {
                    "source_build": "third_party/mpv/source-build.json",
                    "packaged_libraries": names,
                    "libraries": [{"name": name} for name in names],
                }
            )
        )
        (root / "configs").mkdir()
        (root / "configs/ci_toolchain.json").write_text(
            json.dumps({"python": "3.13", "android": {"ndk": "ndk", "cmake": "cmake"}})
        )
        output = root / "prepared"
        calls = []

        def build():
            calls.append(True)
            output.mkdir(exist_ok=True)
            for name in names:
                (output / name).write_bytes(b"compiled " + name.encode())
            (output / "mpv-build-receipt.json").write_text(
                json.dumps(
                    {
                        "schema_version": 1,
                        "ndk": "ndk",
                        "tools": {},
                        "inputs": recipe_inputs(root),
                        "libraries": {
                            name: {
                                "sha256": digest(output / name),
                                "bytes": (output / name).stat().st_size,
                            }
                            for name in names
                        },
                    }
                )
            )

        return output, calls, build

    def test_hit_skips_build_but_one_changed_ffmpeg_library_rebuilds(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            output, calls, build = self.fixture(root)
            self.assertTrue(reuse_or_build(output, build, root))
            self.assertFalse(reuse_or_build(output, build, root))
            self.assertEqual(len(calls), 1)
            (output / "libswscale.so").write_bytes(b"changed")
            self.assertTrue(reuse_or_build(output, build, root))
            self.assertEqual(len(calls), 2)
            verify_runtime(output, root)

    def test_app_edits_keep_key_but_patch_toolchain_and_host_changes_invalidate_it(
        self,
    ):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            output, _, build = self.fixture(root)
            build()
            key = cache_key(root, {"image": "same"})
            (root / "player.gd").write_text("application-only edit")
            self.assertEqual(key, cache_key(root, {"image": "same"}))
            self.assertFalse(reuse_or_build(output, build, root))
            self.assertNotEqual(key, cache_key(root, {"image": "updated"}))
            (root / "native/fix.patch").write_text("new patch")
            self.assertNotEqual(key, cache_key(root, {"image": "same"}))
            self.assertTrue(reuse_or_build(output, build, root))
            key = cache_key(root, {"image": "same"})
            path = root / "configs/ci_toolchain.json"
            ci = json.loads(path.read_text())
            ci["android"]["cmake"] = "new-cmake"
            path.write_text(json.dumps(ci))
            self.assertNotEqual(key, cache_key(root, {"image": "same"}))

    def test_missing_receipt_or_invalid_fresh_build_cannot_be_reused(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            output, _, build = self.fixture(root)
            build()
            (output / "mpv-build-receipt.json").write_text('{"libraries":null}')
            with self.assertRaises(RuntimeError):
                reuse_or_build(output, lambda: None, root)
            self.assertTrue(reuse_or_build(output, build, root))
            (output / "libavcodec.so").unlink()
            self.assertTrue(reuse_or_build(output, build, root))


class HostToolsCache(unittest.TestCase):
    def test_input_byte_permission_and_file_set_changes_force_reinstall(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp) / "tools"
            calls = []

            def build():
                calls.append(True)
                (base / "godot").write_bytes(b"checked executable")
                (base / "godot").chmod(0o755)
                (base / "template.zip").write_bytes(b"checked template")

            self.assertTrue(reuse_host_tools(base, {"version": 1}, build))
            self.assertFalse(reuse_host_tools(base, {"version": 1}, build))
            self.assertEqual(len(calls), 1)
            (base / "tools-receipt.json").write_text("[]")
            self.assertTrue(reuse_host_tools(base, {"version": 1}, build))
            (base / "godot").write_bytes(b"changed")
            self.assertTrue(reuse_host_tools(base, {"version": 1}, build))
            (base / "template.zip").unlink()
            self.assertTrue(reuse_host_tools(base, {"version": 1}, build))
            (base / "extra").write_text("unexpected")
            self.assertTrue(reuse_host_tools(base, {"version": 1}, build))
            self.assertFalse((base / "extra").exists())
            self.assertTrue(reuse_host_tools(base, {"version": 2}, build))
            if os.name != "nt":
                (base / "godot").chmod(0o644)
                self.assertTrue(reuse_host_tools(base, {"version": 2}, build))

    def test_font_is_published_complete_and_unchanged_file_is_not_replaced(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source, target = root / "cached.otf", root / "installed.otf"
            source.write_bytes(b"checked font")
            target.write_bytes(b"old font")
            install_font(source, target)
            self.assertEqual(target.read_bytes(), source.read_bytes())
            stamp = target.stat().st_mtime_ns
            install_font(source, target)
            self.assertEqual(target.stat().st_mtime_ns, stamp)
            self.assertEqual(set(root.iterdir()), {source, target})
