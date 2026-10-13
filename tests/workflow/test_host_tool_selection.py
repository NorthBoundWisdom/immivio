"""Host tools are selected from prepared installations, not exact version pins."""

from pathlib import Path
import tempfile
import unittest

from configs import player_build as player


class HostTools(unittest.TestCase):
    def test_latest_complete_stable_sdk_component_is_selected(self):
        with tempfile.TemporaryDirectory() as folder:
            sdk = Path(folder)
            for version in ("27.2.0", "30.0.1", "31.0.0-rc1"):
                marker = sdk / "ndk" / version / "build/cmake/android.toolchain.cmake"
                marker.parent.mkdir(parents=True)
                marker.touch()
            (sdk / "ndk/32.0.0").mkdir()
            self.assertEqual(
                player.installed_sdk_component(
                    sdk, "ndk", "build/cmake/android.toolchain.cmake"
                ),
                "30.0.1",
            )
            self.assertEqual(
                player.installed_sdk_component(
                    sdk,
                    "ndk",
                    "build/cmake/android.toolchain.cmake",
                    preferred="27.2.0",
                ),
                "27.2.0",
            )

    def test_missing_explicit_component_does_not_silently_fall_back(self):
        with tempfile.TemporaryDirectory() as folder:
            sdk = Path(folder)
            with self.assertRaisesRegex(
                RuntimeError, "Configured Android component is missing"
            ):
                player.installed_sdk_component(sdk, "cmake", "bin", preferred="9.0.0")
            with self.assertRaisesRegex(RuntimeError, "Preinstall"):
                player.installed_sdk_component(sdk, "cmake", "bin")


if __name__ == "__main__":
    unittest.main()
