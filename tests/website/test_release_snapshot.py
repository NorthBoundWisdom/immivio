"""Website downloads stay usable before a complete branded release exists."""

from pathlib import Path
import sys
import unittest
from unittest.mock import patch
from urllib.error import HTTPError

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
import refresh_website_release as releases


class ReleaseSnapshot(unittest.TestCase):
    def release(self):
        return {
            "tag_name": "v0.6.0-fork.1",
            "html_url": releases.RELEASES_URL + "/tag/v0.6.0-fork.1",
            "assets": [
                {
                    "name": f"Immivio-{platform}-0.6.0-release-20261013.apk",
                    "size": 100,
                    "browser_download_url": releases.RELEASES_URL
                    + f"/download/v0.6.0-fork.1/{platform}.apk",
                }
                for platform in ("QUEST", "PICO", "OpenXR")
            ],
        }

    def test_no_release_uses_development_downloads(self):
        result = releases.snapshot(None)
        self.assertIsNone(result["tag_name"])
        self.assertEqual(result["assets"], [])

    def test_complete_release_keeps_the_three_apks(self):
        data = self.release()
        data["assets"].append({"name": "SHA256SUMS.txt"})
        result = releases.snapshot(data)
        self.assertEqual(result["tag_name"], data["tag_name"])
        self.assertEqual(len(result["assets"]), 3)

    def test_partial_duplicate_or_untrusted_assets_use_fallback(self):
        for case in ("partial", "duplicate", "url", "zero", "draft", "prerelease"):
            with self.subTest(case=case):
                data = self.release()
                if case == "partial":
                    data["assets"].pop()
                elif case == "duplicate":
                    data["assets"].append(data["assets"][0])
                elif case == "url":
                    data["assets"][0][
                        "browser_download_url"
                    ] = "https://example.invalid/download.apk"
                elif case == "zero":
                    data["assets"][0]["size"] = 0
                else:
                    data[case] = True
                self.assertEqual(releases.snapshot(data)["assets"], [])

    def test_404_is_the_only_api_error_treated_as_no_release(self):
        for status in (404, 403, 500):
            error = HTTPError("https://api.github.com/", status, "fixture", {}, None)
            with (
                self.subTest(status=status),
                patch.object(releases, "urlopen", side_effect=error),
            ):
                if status == 404:
                    self.assertIsNone(releases.latest_release())
                else:
                    with self.assertRaises(HTTPError):
                        releases.latest_release()


if __name__ == "__main__":
    unittest.main()
