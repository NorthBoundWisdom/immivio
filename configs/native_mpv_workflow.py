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

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from configs.dependencies import digest
from configs.source_roots import workflow
from configs import player_build as player

WORK = ROOT / "build/native-mpv"


def environment():
    if not sys.platform.startswith("linux"):
        raise RuntimeError("The optional source backend requires a Linux build host")
    env = os.environ.copy()
    if env.get("ANDROID_NDK_HOME"):
        env["THRU3D_MPV_TOOLCHAIN_BIN"] = str(
            Path(env["ANDROID_NDK_HOME"]) / "toolchains/llvm/prebuilt/linux-x86_64/bin"
        )
    env.update(
        THRU3D_MPV_WORK=str(WORK),
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
        if not shutil.which(tool, path=env["PATH"]):
            raise RuntimeError(f"Install Linux build prerequisite: {tool}")
    roots = workflow.require_dependency_roots()
    WORK.mkdir(parents=True, exist_ok=True)
    destination = WORK / "mpv-android"
    identity = WORK / "builder-commit.txt"
    if "MpvAndroidSource" not in roots.resolved_commits:
        raise RuntimeError(
            "Native source dependencies are disabled; enable them explicitly in source_roots.lock.jsonc"
        )
    commit = roots.resolved_commits["MpvAndroidSource"]
    if not identity.exists() or identity.read_text() != commit:
        shutil.rmtree(destination, ignore_errors=True)
        destination.mkdir()
        shutil.copytree(
            roots.dependency_root_for("MpvAndroidSource") / "buildscripts",
            destination / "buildscripts",
        )
        identity.write_text(commit)
    ndk = Path(env.get("ANDROID_NDK_HOME", ""))
    if not (ndk / "source.properties").is_file():
        raise RuntimeError("Preinstall Linux Android NDK and set ANDROID_NDK_HOME")
    ndk = ndk.resolve()
    sdk = destination / "buildscripts/sdk"
    sdk.mkdir(exist_ok=True)
    link = sdk / "android-ndk-r30"
    if link.is_symlink():
        link.unlink()
    if link.exists():
        raise RuntimeError(f"Expected an SDK link, found a directory: {link}")
    link.symlink_to(ndk, target_is_directory=True)
    # The FreeCM materialized roots are copied into disposable build trees below.
    player.run(
        [sys.executable, ROOT / "tools/environment/mpv-linux/prepare_sources.py"],
        env=env,
    )
    # Git checkouts omit distribution-generated Autotools files; bootstrap in build copies.
    for dependency in ("unibreak", "curl"):
        directory = destination / "buildscripts/deps" / dependency
        if not (directory / "configure").is_file():
            player.run(["autoreconf", "-fi"], cwd=directory, env=env)
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
