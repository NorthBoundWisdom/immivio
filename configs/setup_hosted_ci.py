#!/usr/bin/env python3
"""Provision disposable GitHub Windows/macOS runners; never called by builds."""

import hashlib
import json
import os
from pathlib import Path
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


def register_macos_font(path):
    """Register checked CI fonts for this login session, not just copy their files."""
    import ctypes
    from ctypes.util import find_library

    cf = ctypes.CDLL(find_library("CoreFoundation"))
    ct = ctypes.CDLL(find_library("CoreText"))
    cf.CFURLCreateFromFileSystemRepresentation.argtypes = [
        ctypes.c_void_p,
        ctypes.c_char_p,
        ctypes.c_long,
        ctypes.c_bool,
    ]
    cf.CFURLCreateFromFileSystemRepresentation.restype = ctypes.c_void_p
    cf.CFErrorGetCode.argtypes = [ctypes.c_void_p]
    cf.CFErrorGetCode.restype = ctypes.c_long
    cf.CFRelease.argtypes = [ctypes.c_void_p]
    cf.CFRelease.restype = None
    ct.CTFontManagerRegisterFontsForURL.argtypes = [
        ctypes.c_void_p,
        ctypes.c_uint32,
        ctypes.POINTER(ctypes.c_void_p),
    ]
    ct.CTFontManagerRegisterFontsForURL.restype = ctypes.c_bool
    encoded = os.fsencode(path.resolve())
    url = cf.CFURLCreateFromFileSystemRepresentation(None, encoded, len(encoded), False)
    if not url:
        raise RuntimeError(f"Cannot create font URL: {path.name}")
    error = ctypes.c_void_p()
    try:
        # kCTFontManagerScopeSession: visible to subsequent Godot processes.
        registered = ct.CTFontManagerRegisterFontsForURL(url, 3, ctypes.byref(error))
        code = cf.CFErrorGetCode(error) if error.value else 0
        # Font discovery may already have registered it after the copy.
        if not registered and code != 105:  # kCTFontManagerErrorAlreadyRegistered
            raise RuntimeError(f"Cannot register {path.name}: CoreText error {code}")
    finally:
        if error.value:
            cf.CFRelease(error)
        cf.CFRelease(url)


def check_host_fonts(godot, fonts, folder):
    """Fail before a long native build if Godot cannot load the prepared fonts."""
    result = subprocess.run(
        [
            godot,
            "--headless",
            "--xr-mode",
            "off",
            "--script",
            ROOT / "tools/check_host_fonts.gd",
            "--",
            json.dumps(
                [
                    {"family": f["family"], "path": str(folder / f["fileName"])}
                    for f in fonts
                ]
            ),
        ],
        capture_output=True,
        text=True,
        timeout=60,
    )
    print(result.stdout, end="", flush=True)
    print(result.stderr, end="", file=sys.stderr, flush=True)
    import re

    if result.returncode or re.search(
        r"(?m)^(SCRIPT ERROR:|ERROR:)", result.stdout + result.stderr
    ):
        raise RuntimeError("Godot could not load the prepared CI fonts")
    if "IMMIVIO_HOST_FONTS_OK" not in result.stdout:
        raise RuntimeError("Godot font probe did not complete")


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

    # A short SDK path prevents native compiler commands breaking on spaces.
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

        else:
            register_macos_font(target)

    check_host_fonts(environment["GODOT_EXE"], config["fonts"], fonts)

    if manifest.get("source_build"):
        subprocess.run(
            [
                sys.executable,
                ROOT / "tools/build_patched_mpv.py",
                "--base",
                directory,
                "--output",
                directory,
                "--ndk",
                sdk / "ndk" / android["ndk"],
                "--download",
                "--prepare-tools",
            ],
            check=True,
        )

    with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as output:
        for name, value in environment.items():
            output.write(f"{name}={value}\n")


if __name__ == "__main__":
    main()
