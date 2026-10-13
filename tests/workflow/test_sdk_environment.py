"""SDK command selection includes Windows batch entrypoints without Bash aliases."""

from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from configs import sdk_environment as sdk


class SdkEnvironment(unittest.TestCase):
    def test_batch_entrypoint_is_selected(self):
        with patch.object(
            sdk.shutil, "which", side_effect=[None, "C:/Android/bin/sdkmanager.bat"]
        ):
            self.assertEqual(
                sdk.sdkmanager_command(
                    {"ANDROID_HOME": "C:/Android", "PATH": "fixture"}
                ),
                ["C:/Android/bin/sdkmanager.bat", "--sdk_root=C:/Android"],
            )

    def test_missing_sdk_is_explicit(self):
        with self.assertRaisesRegex(RuntimeError, "ANDROID_HOME"):
            sdk.sdkmanager_command({})


if __name__ == "__main__":
    unittest.main()
