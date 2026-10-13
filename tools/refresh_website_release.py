#!/usr/bin/env python3
"""Refresh the website APK selector; no published release keeps the CI fallback."""

import argparse
import json
import os
from pathlib import Path
import re
from urllib.error import HTTPError
from urllib.request import Request, urlopen

REPOSITORY = "NorthBoundWisdom/immivio"
RELEASES_URL = f"https://github.com/{REPOSITORY}/releases"
APK = re.compile(
    r"Immivio-(QUEST|PICO|OpenXR)-[0-9][A-Za-z0-9._-]*-release-\d{8}\.apk", re.I
)


def snapshot(release):
    empty = {"tag_name": None, "html_url": RELEASES_URL, "assets": []}
    if not release or release.get("draft") or release.get("prerelease"):
        return empty
    assets = [
        {key: asset[key] for key in ("name", "size", "browser_download_url")}
        for asset in release.get("assets", [])
        if APK.fullmatch(asset.get("name", ""))
        and asset.get("size", 0) > 0
        and asset.get("browser_download_url", "").startswith(
            RELEASES_URL + "/download/"
        )
    ]
    platforms = [APK.fullmatch(asset["name"])[1].lower() for asset in assets]
    if sorted(platforms) != ["openxr", "pico", "quest"]:
        return empty
    if not release.get("tag_name") or not release.get("html_url", "").startswith(
        RELEASES_URL + "/tag/"
    ):
        raise ValueError("Invalid public release metadata")
    return {
        "tag_name": release["tag_name"],
        "html_url": release["html_url"],
        "assets": assets,
    }


def latest_release():
    headers = {"Accept": "application/vnd.github+json", "User-Agent": "immivio-website"}
    if token := os.environ.get("GH_TOKEN"):
        headers["Authorization"] = "Bearer " + token
    request = Request(
        f"https://api.github.com/repos/{REPOSITORY}/releases/latest", headers=headers
    )
    try:
        with urlopen(request, timeout=30) as response:
            return json.load(response)
    except HTTPError as error:
        if error.code == 404:
            return None
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        type=Path,
        default=Path(__file__).resolve().parents[1] / "website/assets/releases.json",
    )
    args = parser.parse_args()
    data = snapshot(latest_release())
    args.output.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    print("Website downloads: " + (data["tag_name"] or "development build fallback"))


if __name__ == "__main__":
    main()
