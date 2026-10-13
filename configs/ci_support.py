# Internal: CI signing, host tests and package receipt summaries.
"""Provision and verify Immivio Android builds on hosted CI."""

import base64
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
from urllib.parse import quote
import xml.etree.ElementTree as ET
import zipfile

from configs import player_build as player


def install_macos_fonts(executable):
    # Hosted macOS images can advertise unavailable on-demand Apple CJK fonts.
    # Supply the application's preferred Noto families without changing app UI code.
    directory = Path.home() / "Library/Fonts"
    directory.mkdir(parents=True, exist_ok=True)
    records = player.TOOLCHAIN["fonts"]
    for record in records:
        source = player.asset_file(record["family"].replace(" ", ""))
        shutil.copy2(source, directory / record["filename"])
    license_file = player.asset_file("NotoLicense")
    shutil.copy2(license_file, directory / license_file.name)
    probe = player.ROOT / "build/ci_font_probe.gd"
    probe.parent.mkdir(parents=True, exist_ok=True)
    families = json.dumps([record["family"] for record in records])
    probe.write_text(
        "extends SceneTree\nfunc _initialize():\n\tvar available = OS.get_system_fonts()\n"
        + "\tfor family in "
        + families
        + ":\n\t\tif not family in available:\n"
        + '\t\t\tprinterr("Missing CI font: " + family)\n\t\t\tquit(1)\n\t\t\treturn\n'
        + '\tprint("CI_CJK_FONTS_READY")\n\tquit()\n',
        encoding="utf-8",
    )
    player.LOGS.mkdir(parents=True, exist_ok=True)
    for attempt in range(10):
        try:
            result = subprocess.run(
                [
                    str(executable),
                    "--headless",
                    "--xr-mode",
                    "off",
                    "--path",
                    str(player.PROJECT),
                    "--quit-after",
                    "120",
                    "--script",
                    str(probe),
                ],
                capture_output=True,
                text=True,
                encoding="utf-8",
                timeout=30,
            )
        except subprocess.TimeoutExpired as error:
            output = (error.stdout or b"") + (error.stderr or b"")
            (player.LOGS / "ci-macos-fonts.log").write_bytes(output)
            raise RuntimeError(
                "macOS font probe timed out; see artifacts/logs/ci-macos-fonts.log"
            ) from error
        (player.LOGS / "ci-macos-fonts.log").write_text(
            result.stdout + result.stderr, encoding="utf-8"
        )
        if result.returncode == 0 and "CI_CJK_FONTS_READY" in result.stdout:
            print("Registered pinned Noto CJK fonts for macOS host tests", flush=True)
            return
        if attempt < 9:
            time.sleep(1)
    raise RuntimeError(
        "macOS did not register CI fonts; see artifacts/logs/ci-macos-fonts.log"
    )


def host_tests(godot):
    logs = player.ROOT / "artifacts/source-tests"
    logs.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    # Windows Godot honors these directories. Hosted macOS has fresh user state.
    userdata = player.ROOT / "artifacts/source-test-userdata"
    userdata.mkdir(parents=True, exist_ok=True)
    env.update(APPDATA=str(userdata), LOCALAPPDATA=str(userdata))
    player.run(
        [
            godot,
            "--headless",
            "--xr-mode",
            "off",
            "--path",
            player.PROJECT,
            "--editor",
            "--quit-after",
            "600",
        ],
        env=env,
        log="ci-host-import.log",
    )
    if re.search(
        r"(?m)^(SCRIPT ERROR:|SHADER ERROR:|ERROR:)",
        (player.LOGS / "ci-host-import.log").read_text(encoding="utf-8"),
    ):
        raise RuntimeError("Godot host import reported errors")
    suite = ET.Element("testsuite", name="Godot source tests")
    failures = []
    for script in sorted((player.PROJECT / "tests").glob("test_*.gd")):
        case = ET.SubElement(suite, "testcase", name=script.stem)
        try:
            result = subprocess.run(
                [
                    godot,
                    "--headless",
                    "--xr-mode",
                    "off",
                    "--path",
                    str(player.PROJECT),
                    "--quit-after",
                    "1800",
                    "--script",
                    "res://tests/" + script.name,
                ],
                env=env,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                timeout=90,
            )
            output = result.stdout + result.stderr
            (logs / (script.stem + ".log")).write_text(output, encoding="utf-8")
            if result.returncode or re.search(
                r"(?m)^(SCRIPT ERROR:|SHADER ERROR:|ERROR:)", output
            ):
                raise RuntimeError(f"exit={result.returncode}; see {script.stem}.log")
            print("Passed: " + script.name, flush=True)
        except (RuntimeError, subprocess.TimeoutExpired) as error:
            failures.append(script.name)
            ET.SubElement(case, "failure", message=str(error))
            print("Failed: " + script.name + ": " + str(error), flush=True)
    suite.set("tests", str(len(suite)))
    suite.set("failures", str(len(failures)))
    ET.ElementTree(suite).write(
        logs / "junit.xml", encoding="utf-8", xml_declaration=True
    )
    if failures:
        raise RuntimeError(f"Godot source tests failed: {failures}")


def signing_env(environ):
    env = environ.copy()
    transport = "CI_ANDROID_"
    names = tuple(
        transport + key for key in ("KEYSTORE_BASE64", "KEY_ALIAS", "KEY_PASSWORD")
    )
    values = [env.get(name, "") for name in names]
    env = {
        key: value for key, value in env.items() if not key.startswith("CI_ANDROID_")
    }
    if not any(values):
        return env, "ephemeral-ci-key"
    if not all(values):
        raise RuntimeError("Configure all three Android signing secrets, or none")
    key = (
        Path(env.get("RUNNER_TEMP", player.ROOT / "artifacts/signing"))
        / "immivio-ci-release.keystore"
    )
    key.parent.mkdir(parents=True, exist_ok=True)
    key.write_bytes(base64.b64decode(values[0], validate=True))
    if os.name != "nt":
        key.chmod(0o600)
    prefix = "GODOT_ANDROID_KEYSTORE_RELEASE"
    env.update(
        {
            prefix + "_PATH": str(key),
            prefix + "_USER": values[1],
            prefix + "_PASSWORD": values[2],
        }
    )
    return env, "repository-signing-key"


def check_export_path(templates, gradle, env):
    """Exercise the real template closure with Gradle, including Windows drive URIs."""
    directory = player.ROOT / "build/ci-export-path"
    directory.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(Path(templates) / "android_source.zip") as source:
        config = source.read("config.gradle").decode("utf-8")
    (directory / "config.gradle").write_text(
        player.patch_export_path(config), encoding="utf-8"
    )
    (directory / "settings.gradle").write_text(
        "rootProject.name = 'export-path-check'\n", encoding="utf-8"
    )
    (directory / "marker.txt").write_bytes(b"export-path-check")
    (directory / "build.gradle").write_text(
        "apply from: 'config.gradle'\n"
        + "tasks.register('checkExportPath', Copy) { from 'marker.txt'; into getExportPath() }\n",
        encoding="utf-8",
    )
    destination = directory / "output with spaces+plus"
    shutil.rmtree(destination, ignore_errors=True)
    # Matches Godot's file:D:/... representation on Windows, retaining URI escaping.
    uri = "file:" + quote(destination.absolute().as_posix(), safe="/:+")
    player.run(
        [
            gradle,
            "-p",
            directory,
            "--console=plain",
            "--offline",
            "-Pexport_path=" + uri,
            "checkExportPath",
        ],
        env=env,
        log="ci-export-path-check.log",
        timeout=120,
    )
    if (destination / "marker.txt").read_bytes() != b"export-path-check":
        raise RuntimeError("Gradle copied the export to an unexpected destination")
    print("Verified Godot/Gradle export path with spaces and a literal +", flush=True)


def build_type_for_ref(requested=None, environment=None):
    environment = os.environ if environment is None else environment
    # A tag is a release boundary even if a caller accidentally requests Debug.
    if environment.get("GITHUB_REF", "").startswith("refs/tags/"):
        return "Release"
    selected = requested or environment.get("CI_BUILD_TYPE", "Debug")
    if selected not in ("Debug", "Release"):
        raise ValueError("Build type must be Debug or Release")
    return selected


def latest_receipt(vendor, build_type):
    platform = {"Pico": "PICO", "Quest": "QUEST", "OpenXR": "OpenXR"}[vendor]
    paths = list(
        (player.ROOT / "artifacts").glob(
            f"Immivio-{platform}-*-{build_type.lower()}-*.build.json"
        )
    )
    if not paths:
        raise RuntimeError("No packaged APK for this target")
    path = max(paths, key=lambda p: p.stat().st_mtime)
    return json.loads(path.read_text())


def ci_package_metadata(vendor, build_type):
    receipt = latest_receipt(vendor, build_type)
    receipt.update(
        ci_ref=os.environ.get("GITHUB_REF", ""),
        ci_host=os.environ.get("RUNNER_OS", sys.platform),
        ci_signing=(
            "repository-signing-key"
            if os.environ.get("CI_ANDROID_KEYSTORE_BASE64")
            else "ephemeral-ci-key"
        ),
    )
    path = player.ROOT / "artifacts" / Path(receipt["apk"]).with_suffix(".build.json")
    path.write_text(json.dumps(receipt, indent=2) + "\n")
    receipts = []
    for v in ("Pico", "Quest", "OpenXR"):
        try:
            receipts.append(latest_receipt(v, build_type))
        except RuntimeError:
            pass
    (player.ROOT / "artifacts/SHA256SUMS.txt").write_text(
        "".join(f'{r["sha256"]}  {r["apk"]}\n' for r in receipts)
    )
    (player.ROOT / "artifacts/ci-summary.json").write_text(
        json.dumps(receipts, indent=2) + "\n"
    )
