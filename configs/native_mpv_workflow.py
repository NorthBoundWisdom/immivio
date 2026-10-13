#!/usr/bin/env python3
# Usage: python3 configs/native_mpv_workflow.py configure|build|package
"""Isolated Linux recipe for the optional project mpv backend; always offline."""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from configs.dependencies import asset_file, digest, lock_data
from configs import player_build as player

WORK = ROOT / "build/native-mpv"


def extract_ndk(archive, destination):
    """Extract verified NDK bytes, allowing only contained links and restoring executable bits."""
    destination = Path(destination).resolve()
    with zipfile.ZipFile(archive) as source:
        members = source.infolist()
        links = {}
        paths = set()
        for entry in members:
            path = (destination / entry.filename).resolve()
            if not path.is_relative_to(destination) or path in paths:
                raise RuntimeError("Unsafe or duplicate NDK archive path")
            paths.add(path)
            if (entry.external_attr >> 16) & 0o170000 == 0o120000:
                target = source.read(entry).decode("utf-8")
                if Path(target).is_absolute() or not (
                    path.parent / target
                ).resolve().is_relative_to(destination):
                    raise RuntimeError("NDK archive link escapes destination")
                links[path] = target
        for path in paths:
            if any(parent in links for parent in path.parents):
                raise RuntimeError("NDK archive member is nested below a symbolic link")
        for entry in members:
            path = destination / entry.filename
            if path.resolve() in links:
                continue
            if entry.is_dir():
                path.mkdir(parents=True, exist_ok=True)
                continue
            path.parent.mkdir(parents=True, exist_ok=True)
            with source.open(entry) as data, path.open("wb") as output:
                shutil.copyfileobj(data, output)
            mode = (entry.external_attr >> 16) & 0o777
            if mode:
                path.chmod(mode)
        for path, target in links.items():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.symlink_to(target)


def environment():
    if not sys.platform.startswith("linux"):
        raise RuntimeError("The optional source backend requires a Linux build host")
    env = os.environ.copy()
    env.update(
        THRU3D_MPV_WORK=str(WORK),
        THRU3D_MPV_DOWNLOADS=str(ROOT / "build/dependency_seed_repos/MpvSources"),
        THRU3D_MPV_EXPORT=str(WORK / "output/arm64-v8a"),
        THRU3D_MPV_MANIFEST=str(WORK / "output/source-build.json"),
    )
    return env


def configure(env):
    for tool in (
        "meson",
        "ninja",
        "autoconf",
        "automake",
        "libtoolize",
        "pkg-config",
        "gperf",
        "nasm",
        "cmake",
        "bison",
        "flex",
        "gettext",
    ):
        if not shutil.which(tool):
            raise RuntimeError(f"Install Linux build prerequisite: {tool}")
    if subprocess.check_output(["meson", "--version"], text=True).strip() != "1.11.0":
        raise RuntimeError("Install Meson 1.11.0 before configuring native mpv")
    archive = asset_file("MpvBuilder")
    WORK.mkdir(parents=True, exist_ok=True)
    destination = WORK / "mpv-android"
    if not destination.exists():
        with tarfile.open(archive) as source:
            source.extractall(WORK / "builder-extract", filter="data")
        extracted = next((WORK / "builder-extract").iterdir())
        shutil.move(extracted, destination)
    if not (WORK / "android-ndk-r30/source.properties").exists():
        with tempfile.TemporaryDirectory(prefix="ndk-", dir=WORK) as pending:
            extract_ndk(asset_file("MpvLinuxNdk"), pending)
            shutil.move(Path(pending) / "android-ndk-r30", WORK / "android-ndk-r30")
    sdk = destination / "buildscripts/sdk"
    sdk.mkdir(exist_ok=True)
    link = sdk / "android-ndk-r30"
    if not link.exists():
        link.symlink_to(WORK / "android-ndk-r30", target_is_directory=True)
    # Locked sources are already fetched by FreeCM --init --native-mpv.
    records = json.loads((ROOT / "third_party/mpv/source-lock.json").read_text())[
        "sources"
    ]
    assets = {r["fileName"]: r for r in lock_data()["assets"]["MpvSources"]["files"]}
    for record in records:
        asset = assets[record["archive"]]
        if (asset["sha256"], asset["sizeBytes"]) != (record["sha256"], record["bytes"]):
            raise RuntimeError(
                "Native receipt provenance differs from the FreeCM source lock"
            )
        asset_file("MpvSources", record["archive"])
    player.run(
        [sys.executable, ROOT / "tools/environment/mpv-linux/prepare_sources.py"],
        env=env,
    )
    if shutil.which("dpkg-query"):
        (WORK / "host-packages.tsv").write_bytes(
            subprocess.check_output(["dpkg-query", "-W"])
        )
    else:
        (WORK / "host-packages.tsv").write_bytes(
            b"Host package inventory unavailable\n"
        )
    (WORK / "configured.json").write_text(
        json.dumps(
            {
                "lock": digest(ROOT / "source_roots.lock.jsonc"),
                "recipe": digest(Path(__file__)),
            },
            indent=2,
        )
        + "\n"
    )


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("configure", "build", "package"))
    args = parser.parse_args(argv)
    env = environment()
    with player.build_lock():
        if args.command == "configure":
            configure(env)
        else:
            marker = WORK / "configured.json"
            if not marker.is_file() or json.loads(marker.read_text()) != {
                "lock": digest(ROOT / "source_roots.lock.jsonc"),
                "recipe": digest(Path(__file__)),
            }:
                raise RuntimeError(
                    "Configure the native backend with current dependencies first"
                )
            if args.command == "build":
                player.run(
                    [
                        "unshare",
                        "--user",
                        "--map-root-user",
                        "--net",
                        "bash",
                        ROOT / "tools/environment/mpv-linux/build_source.sh",
                    ],
                    env=env,
                    timeout=7200,
                )
            else:
                player.run(
                    [
                        sys.executable,
                        ROOT / "tools/environment/mpv-linux/export_candidate.py",
                    ],
                    env=env,
                )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, OSError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
