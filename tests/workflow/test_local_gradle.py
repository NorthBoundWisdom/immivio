"""Resolve preinstalled Gradle without downloading or selecting an older cache."""

import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from configs import dependencies
from configs import android_workflow


class LocalGradle(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        config = self.root / "configs/ci_toolchain.json"
        config.parent.mkdir()
        config.write_text(
            json.dumps({"assets": {"Gradle": {"fileName": "gradle-9.8.2-bin.zip"}}})
        )
        self.addCleanup(patch.stopall)
        patch.object(dependencies, "ROOT", self.root).start()
        patch.dict(dependencies.os.environ, {}, clear=True).start()
        self.which = patch.object(
            dependencies.shutil, "which", return_value=None
        ).start()

    def cache(self, version="9.8.2", command=None):
        if command is None:
            command = "gradle.bat" if dependencies.os.name == "nt" else "gradle"
        path = (
            self.root
            / f".cache/gradle/wrapper/dists/gradle-{version}-bin/prepared/gradle-{version}/bin/{command}"
        )
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("prepared")
        return path

    def test_explicit_override_precedes_path_and_cache(self):
        self.cache()
        self.which.return_value = "/system/gradle"
        with patch.dict(dependencies.os.environ, GRADLE_EXE="/explicit/gradle"):
            self.assertEqual(dependencies.find_gradle(), "/explicit/gradle")

    def test_path_precedes_cache(self):
        self.cache()
        self.which.return_value = "/system/gradle"
        self.assertEqual(dependencies.find_gradle(), "/system/gradle")

    def test_selects_only_the_ci_version(self):
        self.cache("9.8.1")
        self.assertIsNone(dependencies.find_gradle())
        expected = self.cache()
        self.assertEqual(dependencies.find_gradle(), str(expected))

    def test_windows_uses_batch_entry(self):
        with patch.object(dependencies, "os", SimpleNamespace(name="nt", environ={})):
            expected = self.cache()
            self.assertEqual(dependencies.find_gradle(), str(expected))

    def test_invalid_manifest_name_is_rejected(self):
        path = self.root / "configs/ci_toolchain.json"
        path.write_text(
            json.dumps({"assets": {"Gradle": {"fileName": "../other.zip"}}})
        )
        with self.assertRaisesRegex(RuntimeError, "Invalid Gradle"):
            dependencies.find_gradle()

    def test_stop_gradle_uses_the_cache_without_probing_android(self):
        for platform in ("posix", "nt"):
            with (
                self.subTest(platform=platform),
                patch.object(
                    dependencies, "os", SimpleNamespace(name=platform, environ={})
                ),
                patch.object(android_workflow.player, "run") as run,
                patch.object(android_workflow, "host_tools") as tools,
            ):
                expected = self.cache()
                self.assertEqual(android_workflow.main(["stop-gradle"]), 0)
                run.assert_called_once_with(
                    [str(expected), "--stop"], env={}, timeout=60
                )
                tools.assert_not_called()

    def test_stop_gradle_is_a_noop_without_a_prepared_tool(self):
        with patch.object(android_workflow.player, "run") as run:
            self.assertEqual(android_workflow.main(["stop-gradle"]), 0)
            run.assert_not_called()
