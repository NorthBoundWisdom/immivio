#!/usr/bin/env python3
# Usage: python3 configs/check_environment.py
"""Check the prepared Android development environment without installing anything."""

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "FreeCM"))
from configs.dependencies import TOOLCHAIN, host_tools
from configs.android_workflow import arguments_for
from configs import player_build as player


def check():
    expected = tuple(map(int, TOOLCHAIN["python"].split(".")))
    if sys.version_info[:2] != expected:
        raise RuntimeError(f"Preinstall Python {TOOLCHAIN['python']}")
    tools = host_tools()
    env, sdk = player.environment(arguments_for("Quest", "Debug", tools))
    versions = {
        "java": (
            [
                str(
                    Path(env["JAVA_HOME"])
                    / "bin"
                    / ("java.exe" if os.name == "nt" else "java")
                ),
                "-version",
            ],
            r'version "(\d+)',
            TOOLCHAIN["java"],
        ),
        "go": (["go", "version"], r"go version go([^\s]+)", TOOLCHAIN["go"]),
        "gradle": (
            [tools["gradle"], "--version"],
            r"(?m)^Gradle ([^\s]+)",
            TOOLCHAIN["gradle"],
        ),
    }
    for name, (command, pattern, version) in versions.items():
        result = subprocess.run(
            command, env=env, capture_output=True, text=True, check=True, timeout=30
        )
        match = re.search(pattern, result.stdout + result.stderr)
        if not match or match[1] != version:
            raise RuntimeError(
                f"Preinstall {name} {version}; see configs/toolchain.json"
            )
    for name in ("gomobile", "gobind"):
        path = shutil.which(name, path=env["PATH"])
        if not path:
            raise RuntimeError(f"Preinstall {name} in PATH")
        info = subprocess.check_output(
            ["go", "version", "-m", path], env=env, text=True
        )
        if not re.search(
            r"(?m)^\s*mod\s+golang.org/x/mobile\s+"
            + re.escape(TOOLCHAIN["gomobile"])
            + r"(?:\s|$)",
            info,
        ):
            raise RuntimeError(
                f"Preinstall {name} from golang.org/x/mobile@{TOOLCHAIN['gomobile']}"
            )
    for path in (
        sdk / f"platforms/android-{TOOLCHAIN['android']['platform']}/android.jar",
        sdk / "build-tools" / TOOLCHAIN["android"]["build_tools"],
        sdk / "platform-tools" / ("adb.exe" if os.name == "nt" else "adb"),
    ):
        if not path.exists():
            raise RuntimeError(f"Preinstall Android SDK component: {path}")
    player.standard_mpv_libraries()
    print(
        json.dumps(
            {**tools, "sdk": str(sdk), "mpv": str(player.standard_mpv_directory())},
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(check())
    except (RuntimeError, OSError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
