#!/usr/bin/env python3
"""Prepare GitHub Release assets from verified, tag-matched macOS CI packages."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import tempfile

PLATFORMS = {"Pico": "PICO", "Quest": "QUEST", "OpenXR": "OpenXR"}


def sha256(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def prepare(packages, output, tag, commit):
    if not tag or tag.startswith("-") or any(c in tag for c in "\r\n"):
        raise ValueError("Invalid release tag")
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise ValueError("Release commit must be a full Git SHA")
    assets = []
    records = []
    directory = Path(packages)
    seen = set()
    receipts = sorted(directory.glob("*.build.json"))
    if len(receipts) != len(PLATFORMS):
        raise ValueError("Expected three Immivio build receipts")
    for receipt in receipts:
        record = json.loads(receipt.read_text(encoding="utf-8"))
        vendor = record.get("vendor")
        if vendor not in PLATFORMS or vendor in seen:
            raise ValueError(f"Unexpected/duplicate release platform: {vendor}")
        seen.add(vendor)
        if record.get("product") != "Immivio" or record.get("build_type") != "Release":
            raise ValueError("Only Immivio Release packages can be published")
        if (
            record.get("source_commit") != commit
            or record.get("ci_ref") != "refs/tags/" + tag
        ):
            raise ValueError("Release receipt belongs to a different tag or commit")
        if record.get("ci_host") != "macOS":
            raise ValueError("Release assets must come from the canonical macOS builds")
        if (
            record.get("schema_version") not in (2, 3)
            or record.get("dependency_mode") != "pinned"
        ):
            raise ValueError("Release requires a pinned dependency receipt")
        if record.get("schema_version") == 3 and not re.fullmatch(
            r"[0-9a-f]{64}", record.get("dependency_catalog_sha256", "")
        ):
            raise ValueError("Release is missing its master dependency lock digest")
        if not re.fullmatch(r"[0-9a-f]{40}", record.get("freecm_commit", "")):
            raise ValueError("Release receipt is missing the FreeCM commit")
        if (
            not record.get("dependency_commits")
            or not record.get("dependency_assets")
            or not record.get("gradle_locks")
        ):
            raise ValueError("Release receipt is missing dependency provenance")
        for digest in record.get("dependency_manifests", {}).values():
            if not re.fullmatch(r"[0-9a-f]{64}", digest):
                raise ValueError("Invalid dependency manifest digest")
        required_manifests = {
            "source_roots.lock.jsonc.in",
            "configs/toolchain.json",
            "android/gradle/libs.versions.toml",
            "android/gradle/verification-metadata.xml",
            "cloud/openlist/go.mod",
            "cloud/openlist/go.sum",
        }
        if not required_manifests <= record.get("dependency_manifests", {}).keys():
            raise ValueError("Release receipt is missing dependency manifest digests")
        name = record.get("apk", "")
        pattern = rf"Immivio-{PLATFORMS[vendor]}-[A-Za-z0-9._-]+-release-\d{{8}}\.apk"
        if (
            not re.fullmatch(pattern, name)
            or receipt.name != Path(name).with_suffix(".build.json").name
        ):
            raise ValueError("Unsafe or mismatched release APK filename")
        apk = directory / name
        if apk.is_symlink() or not apk.is_file() or sha256(apk) != record.get("sha256"):
            raise ValueError(
                "Release APK is missing or differs from its verified receipt"
            )
        certificate = record.get("signing_certificate_sha256")
        # Earlier tag builders verified signatures but did not record the
        # certificate fingerprint. Preserve those original receipts.
        if certificate is not None and not re.fullmatch(r"[0-9a-f]{64}", certificate):
            raise ValueError("Release receipt has an invalid signing certificate")
        records.append(record)
        assets.extend([apk, receipt])
    if {p.name for p in directory.glob("*.apk")} != {r["apk"] for r in records}:
        raise ValueError("Unexpected APKs in the release input directory")
    # Validate the entire set before copying any publishable package.
    output = Path(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(
        prefix="release-stage-", dir=output.parent
    ) as temporary:
        stage = Path(temporary)
        for asset in assets:
            shutil.copy2(asset, stage / asset.name)
        records.sort(key=lambda r: r["vendor"])
        (stage / "SHA256SUMS.txt").write_text(
            "".join(f'{r["sha256"]}  {r["apk"]}\n' for r in records), encoding="utf-8"
        )
        manifest = {
            "tag": tag,
            "source_commit": commit,
            "host": "macOS",
            "packages": records,
        }
        (stage / "release-manifest.json").write_text(
            json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
        )
        notes = [
            f"Android APKs for `{tag}` (`{commit[:7]}`).",
            "",
            "Choose the PICO, QUEST or OpenXR APK matching your headset. Immivio has one playback edition.",
            "",
            "APK hashes and build receipts are included. Both Windows and macOS CI builds passed; release assets use the macOS packages.",
            "",
        ]
        changelog = Path(__file__).resolve().parents[1] / "CHANGELOG.md"
        section = re.search(
            r"^## " + re.escape(tag.removeprefix("v")) + r"[^\n]*\n(.*?)(?=^## |\Z)",
            changelog.read_text(encoding="utf-8"),
            re.M | re.S,
        )
        if section:
            notes += [section.group(1).strip(), ""]
        notes += [
            "[English release notes](https://northboundwisdom.github.io/immivio/updates/) · [中文更新说明](https://northboundwisdom.github.io/immivio/zh/updates/)",
            "",
        ]
        if any(r.get("ci_signing") == "ephemeral-ci-key" for r in records):
            notes += [
                "These packages use CI-generated signing keys. An existing installation signed with a different key cannot be updated with these APKs.",
                "",
            ]
        notes += [
            "CI build/package verification does not establish physical headset playback validation.",
            "",
        ]
        (stage / "release-notes.md").write_text("\n".join(notes), encoding="utf-8")
        output.mkdir(parents=True, exist_ok=True)
        expected = {p.name for p in stage.iterdir()}
        if any(p.name not in expected for p in output.iterdir()):
            raise ValueError("Release output contains unrelated files")
        for asset in stage.iterdir():
            asset.replace(output / asset.name)
    print(f"Prepared {len(records)} verified Release APKs for {tag} at {commit[:7]}")
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--packages", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--commit", required=True)
    args = parser.parse_args()
    prepare(args.packages, args.output, args.tag, args.commit)


if __name__ == "__main__":
    main()
