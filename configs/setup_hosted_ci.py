#!/usr/bin/env python3
"""Provision disposable GitHub Windows/macOS runners; never called by builds."""

import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def download(url, destination, expected, *, git_blob=False):
    subprocess.run(
        [
            "curl",
            "--fail",
            "--location",
            "--retry",
            "3",
            "--output",
            str(destination),
            url,
        ],
        check=True,
    )
    with destination.open("rb") as source:
        if git_blob:
            digest = hashlib.sha1(f"blob {destination.stat().st_size}\0".encode())
            while chunk := source.read(1024 * 1024):
                digest.update(chunk)
            actual = digest.hexdigest()
        else:
            actual = hashlib.file_digest(source, "sha256").hexdigest()
    if actual != expected:
        raise RuntimeError(f"Checksum mismatch for {destination.name}")


def unpack(archive, destination, members=None):
    with zipfile.ZipFile(archive) as source:
        for name in members or source.namelist():
            info = source.getinfo(name)
            target = (destination / name).resolve()
            if not target.is_relative_to(destination.resolve()):
                raise RuntimeError(f"Unsafe archive member: {name}")
            source.extract(info, destination)
            mode = info.external_attr >> 16
            if mode and os.name != "nt":
                target.chmod(mode & 0o777)


def main():
    if os.environ.get("GITHUB_ACTIONS") != "true":
        raise RuntimeError("This installer is only for GitHub Actions")
    windows = sys.platform == "win32"
    if sys.platform not in ("win32", "darwin"):
        raise RuntimeError("Only Windows and macOS CI hosts are supported")
    config = json.loads((ROOT / "configs/ci_toolchain.json").read_text())
    base = Path(os.environ["RUNNER_TEMP"]) / "immivio-tools"
    base.mkdir(parents=True, exist_ok=True)
    environment = {}
    for name in (
        "Gradle",
        "GodotWindows" if windows else "GodotMacOS",
        "GodotTemplates",
    ):
        record = config["assets"][name]
        archive = base / record["fileName"]
        download(record["url"], archive, record["sha256"])
        members = None
        if name == "GodotTemplates":
            members = [
                "templates/" + item
                for item in (
                    "android_source.zip",
                    "android_debug.apk",
                    "android_release.apk",
                    "version.txt",
                )
            ]
        unpack(archive, base, members)
        archive.unlink()
    environment["GRADLE_EXE"] = str(
        next(base.glob("gradle-*/bin/gradle.bat" if windows else "gradle-*/bin/gradle"))
    )
    environment["GODOT_EXE"] = str(
        next(base.glob("Godot*_console.exe"))
        if windows
        else base / "Godot.app/Contents/MacOS/Godot"
    )
    environment["GODOT_TEMPLATES_DIR"] = str(base / "templates")

    manifest = json.loads((ROOT / "third_party/mpv/manifest.json").read_text())
    apk = base / "mpv.apk"
    download(manifest["source_url"], apk, manifest["apk_sha256"])
    with zipfile.ZipFile(apk) as source:
        directory = base / "mpv"
        directory.mkdir(exist_ok=True)
        for library in manifest["libraries"]:
            content = source.read(library["path"])
            if hashlib.sha256(content).hexdigest() != library["sha256"]:
                raise RuntimeError(f"Invalid mpv library: {library['name']}")
            (directory / library["name"]).write_bytes(content)
    apk.unlink()
    environment["IMMIVIO_MPV_LIB_DIR"] = str(directory)

    # A short SDK path prevents gomobile's C compiler command breaking on spaces.
    sdk = Path(os.environ["ANDROID_HOME"])
    if windows and " " in str(sdk):
        alias = Path(os.environ["RUNNER_TEMP"]).anchor + "immivio-android-sdk"
        subprocess.run(["cmd", "/c", "mklink", "/J", alias, str(sdk)], check=True)
        sdk = Path(alias)
    environment.update(ANDROID_HOME=str(sdk), ANDROID_SDK_ROOT=str(sdk))
    command = shutil.which("sdkmanager") or shutil.which("sdkmanager.bat")
    if not command:
        raise RuntimeError("Android command-line tools are missing")
    android = config["android"]
    platform = json.loads((ROOT / "configs/toolchain.json").read_text())["android"][
        "platform"
    ]
    subprocess.run(
        [
            command,
            "--sdk_root=" + str(sdk),
            "platform-tools",
            f"platforms;android-{platform}",
            "build-tools;" + android["build_tools"],
            "ndk;" + android["ndk"],
            "cmake;" + android["cmake"],
        ],
        check=True,
    )
    for name, key in [
        ("NDK", "ndk"),
        ("CMAKE", "cmake"),
        ("BUILD_TOOLS", "build_tools"),
    ]:
        environment[f"IMMIVIO_{name}_VERSION"] = android[key]

    fonts = (
        Path(os.environ["WINDIR"]) / "Fonts"
        if windows
        else Path.home() / "Library/Fonts"
    )
    fonts.mkdir(parents=True, exist_ok=True)
    for font in config["fonts"]:
        target = fonts / font["fileName"]
        download(font["url"], target, font["git_blob_sha1"], git_blob=True)
        if windows:
            env = dict(
                os.environ,
                IMMIVIO_FONT_PATH=str(target),
                IMMIVIO_FONT_NAME=font["family"],
            )
            subprocess.run(
                [
                    "pwsh",
                    "-NoProfile",
                    "-Command",
                    r"New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts' "
                    "-Name ($env:IMMIVIO_FONT_NAME + ' (OpenType)') -Value $env:IMMIVIO_FONT_PATH "
                    "-PropertyType String -Force | Out-Null",
                ],
                env=env,
                check=True,
            )

    module = (ROOT / "cloud/openlist/go.mod").read_text()
    revision = re.search(r"^\s*golang.org/x/mobile\s+(\S+)", module, re.M).group(1)
    bin_dir = base / "bin"
    bin_dir.mkdir(exist_ok=True)
    env = dict(os.environ, GOBIN=str(bin_dir), GOTOOLCHAIN="local")
    for tool in ("gomobile", "gobind"):
        subprocess.run(
            ["go", "install", f"golang.org/x/mobile/cmd/{tool}@{revision}"],
            env=env,
            check=True,
        )
    with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as output:
        for name, value in environment.items():
            output.write(f"{name}={value}\n")
    with open(os.environ["GITHUB_PATH"], "a", encoding="utf-8") as output:
        output.write(str(bin_dir) + "\n")


if __name__ == "__main__":
    main()
