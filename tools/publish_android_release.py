#!/usr/bin/env python3
"""Append only missing files to an existing GitHub Release."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
from urllib.parse import quote

from prepare_android_release import PLATFORMS, require_release_signer, sha256
from select_android_release import api

APK_PLATFORM = re.compile(r"Immivio-(PICO|QUEST|OpenXR)-.+\.apk", re.I)
NEW_PATCH = "Publish a new patch version. 请发新的补丁版本"


def release_assets(repository, tag):
    release = api(f"repos/{repository}/releases/tags/{quote(tag, safe='')}")
    pages = json.loads(
        subprocess.check_output(
            [
                "gh",
                "api",
                "--paginate",
                "--slurp",
                f"repos/{repository}/releases/{release['id']}/assets?per_page=100",
            ],
            text=True,
        )
    )
    return [asset for page in pages for asset in page]


def remote_digest(repository, asset):
    if re.fullmatch(r"sha256:[0-9a-f]{64}", asset.get("digest") or ""):
        return asset["digest"].removeprefix("sha256:")
    # Older assets may lack an API digest. Hash the binary without keeping a second copy.
    with subprocess.Popen(
        [
            "gh",
            "api",
            f"repos/{repository}/releases/assets/{asset['id']}",
            "-H",
            "Accept: application/octet-stream",
        ],
        stdout=subprocess.PIPE,
    ) as process:
        digest = hashlib.file_digest(process.stdout, "sha256").hexdigest()
        if process.wait() != 0:
            raise RuntimeError(
                f"Could not verify existing release asset {asset['name']}"
            )
    return digest


def missing_assets(bundle, existing, digest_for):
    """Validate every published APK and matching metadata before selecting uploads."""
    manifest = json.loads(
        (bundle / "release-manifest.json").read_text(encoding="utf-8")
    )
    records = manifest["packages"]
    if len(records) != len(PLATFORMS) or {r["vendor"] for r in records} != set(
        PLATFORMS
    ):
        raise ValueError("Expected one verified APK for each release platform")
    for record in records:
        require_release_signer(record)
    expected = {PLATFORMS[r["vendor"]].lower(): r["apk"] for r in records}
    files = {}
    for name in sorted(expected.values()):
        apk = bundle / name
        receipt = apk.with_suffix(".build.json")
        files.update({apk.name: apk, receipt.name: receipt})
    for name in ("SHA256SUMS.txt", "release-manifest.json"):
        files[name] = bundle / name

    seen_platforms = set()
    published = set()
    for asset in existing:
        name = asset["name"]
        if name.lower().endswith(".apk"):
            match = APK_PLATFORM.fullmatch(name)
            platform = match[1].lower() if match else ""
            if expected.get(platform) != name or platform in seen_platforms:
                raise ValueError(
                    f"Unexpected or duplicate APK on this tag: {name}. {NEW_PATCH}"
                )
            seen_platforms.add(platform)
        if name in files:
            if asset.get("state") != "uploaded" or digest_for(asset) != sha256(
                files[name]
            ):
                raise ValueError(f"Published asset differs: {name}. {NEW_PATCH}")
            published.add(name)
    return [path for name, path in files.items() if name not in published]


def publish_existing(bundle, repository, tag):
    def inspect():
        return missing_assets(
            bundle,
            release_assets(repository, tag),
            lambda asset: remote_digest(repository, asset),
        )

    pending = inspect()
    if not pending:
        print("All release assets already match")
        return
    subprocess.run(
        ["gh", "release", "upload", tag, *pending, "--repo", repository],
        check=True,
    )
    if inspect():
        raise RuntimeError("GitHub did not report all expected release assets")
    subprocess.run(
        [
            "gh",
            "release",
            "edit",
            tag,
            "--repo",
            repository,
            "--notes-file",
            bundle / "release-notes.md",
        ],
        check=True,
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle", type=Path, required=True)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--tag", required=True)
    args = parser.parse_args()
    try:
        publish_existing(args.bundle, args.repository, args.tag)
    except (ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"{error}\n")


if __name__ == "__main__":
    main()
