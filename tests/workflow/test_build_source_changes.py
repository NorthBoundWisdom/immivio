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
    @contextmanager
    def workspace(self):
        with tempfile.TemporaryDirectory() as folder, ExitStack() as stack:
            root = Path(folder)
            stack.enter_context(patch.object(android, "ROOT", root))
            stack.enter_context(patch.object(android, "BUILD_INPUTS", ()))
            stack.enter_context(
                patch.object(
                    android.workflow,
                    "require_dependency_roots",
                    return_value=SimpleNamespace(
                        resolved_commits={"OpenList": "a" * 40}
                    ),
                )
            )
            stack.enter_context(
                patch.object(
                    android.subprocess, "check_output", return_value="b" * 40 + "\n"
                )
            )
            stack.enter_context(
                patch.object(android.player, "mpv_libraries", return_value={})
            )
            binaries = root / "app/godot/addons/quest_player/bin"
            binaries.mkdir(parents=True)
            for name in ("player-plugin-debug.aar", "cloudcore.aar"):
                (binaries / name).write_bytes(b"fixture-compiled-output")
            stack.enter_context(patch.object(android.player, "BIN", binaries))
            args = SimpleNamespace(vendor="Quest", build_type="Debug")
            marker = root / "build/configurations/Quest-Debug.built.json"
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
                    "openlist": android.digest(android.player.BIN / "cloudcore.aar"),
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
                "build/openlist/generated.go",
                "android/player-plugin/build/generated.kt",
                "app/godot/android/build/generated.gd",
                "app/godot/.godot/import.log",
                "artifacts/source-tests/report.xml",
            ):
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("generated output")
            android.require_build(args)


if __name__ == "__main__":
    unittest.main()
