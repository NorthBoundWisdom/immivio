"""Changing production code must invalidate a previously built Android package."""

from contextlib import ExitStack, contextmanager
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from configs import android_workflow as android


class BuildSourceChanges(unittest.TestCase):
    def test_channel_change_rejects_a_copied_build_receipt(self):
        with self.workspace() as (root, args, marker):
            self.mark_built(args, marker)
            args.channel = "web"
            web_marker = android.configuration_path(
                "Quest", "Debug", "web"
            ).with_suffix(".built.json")
            web_marker.write_bytes(marker.read_bytes())
            with self.assertRaisesRegex(RuntimeError, "Build inputs changed"):
                android.require_build(args)

    @contextmanager
    def workspace(self):
        with tempfile.TemporaryDirectory() as folder, ExitStack() as stack:
            root = Path(folder)
            stack.enter_context(patch.object(android, "ROOT", root))
            stack.enter_context(patch.object(android, "BUILD_INPUTS", ()))
            stack.enter_context(
                patch.object(android.player, "mpv_libraries", return_value={})
            )
            binaries = root / "app/godot/addons/quest_player/bin"
            binaries.mkdir(parents=True)
            for name in ("player-plugin-debug.aar",):
                (binaries / name).write_bytes(b"fixture-compiled-output")
            stack.enter_context(patch.object(android.player, "BIN", binaries))
            args = SimpleNamespace(
                vendor="Quest",
                build_type="Debug",
                ndk="ndk",
                cmake="cmake",
                build_tools="build",
            )
            marker = root / "build/android/state/Quest-Debug.built.json"
            marker.parent.mkdir(parents=True)
            yield root, args, marker

    def mark_built(self, args, marker):
        marker.write_text(
            json.dumps(
                {
                    "inputs": android.input_signature(args),
                    "aar": android.digest(
                        android.player.BIN / "player-plugin-debug.aar"
                    ),
                }
            )
        )

    def test_production_source_add_edit_and_delete_reject_the_old_build(self):
        for language in (
            "android/player-plugin/src/main/java/example/Bridge.kt",
            "native/render-bridge/src/render_bridge.cpp",
            "native/render-bridge/CMakeLists.txt",
            "native/mpv/include/immivio/mpv/json_quote.h",
            "app/godot/scripts/player.gd",
            "app/godot/shaders/video.gdshader",
            "app/godot/shaders/video.gdshaderinc",
            "app/godot/scenes/main.tscn",
            "app/godot/i18n/translations.json",
            "app/godot/models/hands/model.bin",
            "android/player-plugin/src/debug/java/example/Probe.kt",
            "app/godot/media/fixture.mp4",
            "configs/android_workflow.py",
            "configs/workspace_lock.py",
        ):
            for action in ("add", "edit", "delete"):
                with (
                    self.subTest(language=language, action=action),
                    self.workspace() as (root, args, marker),
                ):
                    source = root / language
                    source.parent.mkdir(parents=True, exist_ok=True)
                    if action != "add":
                        source.write_text("original production code")
                    self.mark_built(args, marker)
                    android.require_build(args)
                    if action == "delete":
                        source.unlink()
                    else:
                        source.write_text("changed production code")
                    with self.assertRaisesRegex(RuntimeError, "Build inputs changed"):
                        android.require_build(args)

    def test_generated_outputs_and_test_reports_do_not_invalidate_source_inputs(self):
        with self.workspace() as (root, args, marker):
            self.mark_built(args, marker)
            for name in (
                "build/generated/source.kt",
                "android/player-plugin/build/generated.kt",
                "app/godot/android/build/generated.gd",
                "app/godot/.godot/import.log",
                "artifacts/tests/godot/report.xml",
            ):
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("generated output")
            android.require_build(args)

    def test_selected_sdk_component_change_requires_rebuild(self):
        with self.workspace() as (_, args, marker):
            self.mark_built(args, marker)
            args.ndk = "other"
            with self.assertRaisesRegex(RuntimeError, "Build inputs changed"):
                android.require_build(args)

    def test_run_checks_that_the_package_came_from_the_current_build(self):
        with self.workspace() as (root, args, marker):
            self.mark_built(args, marker)
            current_build = android.require_build(args)
            apk = root / "Immivio-QUEST-1.0.0-appstore-debug-20261121.apk"
            apk.write_bytes(b"fixture APK")
            receipt = apk.with_suffix(".build.json")
            record = {"apk": apk.name, "sha256": android.digest(apk)}
            with patch("configs.ci_support.latest_receipt_file", return_value=receipt):
                receipt.write_text(json.dumps(record))
                with self.assertRaisesRegex(RuntimeError, "run package again"):
                    android.require_packaged_build(args, current_build)
                record["build_sha256"] = current_build
                receipt.write_text(json.dumps(record))
                self.assertEqual(
                    android.require_packaged_build(args, current_build), apk
                )
                apk.write_bytes(b"changed bytes")
                with self.assertRaisesRegex(RuntimeError, "differs from its receipt"):
                    android.require_packaged_build(args, current_build)

    def test_addon_manifest_changes_require_a_new_build(self):
        with self.workspace() as (root, args, marker):
            name = "third_party/openxr-vendors/manifest.json"
            manifest = root / name
            manifest.parent.mkdir(parents=True)
            manifest.write_text(json.dumps({"version": "original", "sha256": "a" * 64}))
            with patch.object(android, "BUILD_INPUTS", (name,)):
                self.mark_built(args, marker)
                android.require_build(args)
                manifest.write_text(
                    json.dumps({"version": "updated", "sha256": "b" * 64})
                )
                with self.assertRaisesRegex(RuntimeError, "Build inputs changed"):
                    android.require_build(args)


if __name__ == "__main__":
    unittest.main()
