#!/usr/bin/env python3
"""Provision disposable GitHub Windows/macOS runners; never called by builds."""

import hashlib
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import zipfile
import time

ROOT = Path(__file__).resolve().parents[1]


def download(url, destination, expected, *, git_blob=False):
    # fontd can inspect ~/Library/Fonts while curl is still writing. Publish only
    # complete checked bytes, using a hidden file and a same-filesystem rename.
    with tempfile.NamedTemporaryFile(
        dir=destination.parent,
        prefix="." + destination.name + ".",
        suffix=".download",
        delete=False,
    ) as pending:
        temporary = Path(pending.name)
    try:
        subprocess.run(
            [
                "curl",
                "--fail",
                "--location",
                "--retry",
                "3",
                "--output",
                str(temporary),
                url,
            ],
            check=True,
        )
        with temporary.open("rb") as source:
            if git_blob:
                digest = hashlib.sha1(f"blob {temporary.stat().st_size}\0".encode())
                while chunk := source.read(1024 * 1024):
                    digest.update(chunk)
                actual = digest.hexdigest()
            else:
                actual = hashlib.file_digest(source, "sha256").hexdigest()
        if actual != expected:
            raise RuntimeError(f"Checksum mismatch for {destination.name}")
        temporary.chmod(0o644)
        temporary.replace(destination)
    finally:
        temporary.unlink(missing_ok=True)


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
    if result.returncode or re.search(
        r"(?m)^(SCRIPT ERROR:|ERROR:)", result.stdout + result.stderr
    ):
        raise RuntimeError("Godot could not load the prepared CI fonts")
    if "IMMIVIO_HOST_FONTS_OK" not in result.stdout:
        raise RuntimeError("Godot font probe did not complete")


def file_sha256(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def tool_tree(base):
    files = {}
    for path in sorted(base.rglob("*")):
        if path.is_symlink():
            raise ValueError("Unexpected host tool cache symlink")
        if path.is_file() and path != base / "tools-receipt.json":
            files[path.relative_to(base).as_posix()] = {
                "sha256": file_sha256(path),
                "executable": bool(path.stat().st_mode & 0o111)
                if os.name != "nt"
                else False,
            }
    return files


def reuse_host_tools(base, inputs, build):
    try:
        if base.is_symlink():
            raise ValueError("Unexpected tool directory symlink")
        receipt = json.loads((base / "tools-receipt.json").read_text())
        if not isinstance(receipt, dict):
            raise ValueError("Invalid tool cache receipt")
        if (
            receipt.get("inputs") != inputs
            or not receipt.get("files")
            or receipt["files"] != tool_tree(base)
        ):
            raise ValueError("Tool inputs, bytes or permissions changed")
    except (OSError, ValueError, KeyError, TypeError):
        if base.is_symlink() or base.is_file():
            base.unlink()
        elif base.exists():
            shutil.rmtree(base)
        base.mkdir(parents=True)
        build()
        (base / "tools-receipt.json").write_text(
            json.dumps({"inputs": inputs, "files": tool_tree(base)}, sort_keys=True)
            + "\n"
        )
        print("Installed and recorded checked CI tools", flush=True)
        return True
    print(
        "Reusing verified Godot, Gradle, Android templates and CJK font files",
        flush=True,
    )
    return False


def install_font(source, target):
    if target.is_file() and file_sha256(source) == file_sha256(target):
        return
    # Keep fontd from seeing partial bytes even when restoring an extracted tool cache.
    with tempfile.NamedTemporaryFile(
        dir=target.parent, prefix="." + target.name, delete=False
    ) as pending:
        temporary = Path(pending.name)
    try:
        shutil.copyfile(source, temporary)
        if file_sha256(temporary) != file_sha256(source):
            raise RuntimeError("Font copy differs from the checked tool cache")
        temporary.chmod(0o644)
        temporary.replace(target)
    finally:
        temporary.unlink(missing_ok=True)


def main():
    if os.environ.get("GITHUB_ACTIONS") != "true":
        raise RuntimeError("This installer is only for GitHub Actions")
    windows = sys.platform == "win32"
    if sys.platform not in ("win32", "darwin"):
        raise RuntimeError("Only Windows and macOS CI hosts are supported")
    config = json.loads((ROOT / "configs/ci_toolchain.json").read_text())
    started = time.monotonic()
    base = ROOT / ".cache/ci-tools"
    environment = {}
    selected = ["Gradle", "GodotWindows" if windows else "GodotMacOS", "GodotTemplates"]
    inputs = {
        "schema": 1,
        "installer": file_sha256(Path(__file__)),
        "assets": {name: config["assets"][name] for name in selected},
        "fonts": config["fonts"],
    }

    def install_tools():
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
        folder = base / "fonts"
        folder.mkdir()
        for font in config["fonts"]:
            download(
                font["url"],
                folder / font["fileName"],
                font["git_blob_sha1"],
                git_blob=True,
            )

    tools_built = reuse_host_tools(base, inputs, install_tools)
    environment["GRADLE_EXE"] = str(
        next(base.glob("gradle-*/bin/gradle.bat" if windows else "gradle-*/bin/gradle"))
    )
    environment["GODOT_EXE"] = str(
        next(base.glob("Godot*_console.exe"))
        if windows
        else base / "Godot.app/Contents/MacOS/Godot"
    )
    environment["GODOT_TEMPLATES_DIR"] = str(base / "templates")

    environment["IMMIVIO_MPV_LIB_DIR"] = str(ROOT / ".cache/ci-playback/arm64-v8a")

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
        install_font(base / "fonts" / font["fileName"], target)
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

    with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as output:
        for name, value in environment.items():
            output.write(f"{name}={value}\n")
    elapsed = time.monotonic() - started
    print(
        f"Toolchain preparation: {'installed' if tools_built else 'reused'} in {elapsed:.1f}s",
        flush=True,
    )
    with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
        output.write(f"tools-built={str(tools_built).lower()}\n")
    with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as output:
        output.write(
            f"Host tools: **{'installed' if tools_built else 'reused'}**, {elapsed:.1f}s including SDK checks and font validation.\n\n"
        )


if __name__ == "__main__":
    main()
