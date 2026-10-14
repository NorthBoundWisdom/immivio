#!/usr/bin/env python3
# Usage: python3 configs/check_environment.py
"""Check available host tools and matching Android assets without version pins."""

import json
import os
from pathlib import Path
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
    if sys.version_info < (3, 11):
        raise RuntimeError(
            "Python 3.11+ is required for tomllib and hashlib.file_digest"
        )
    tools = host_tools()
    args = arguments_for("Quest", "Debug", tools)
    env, sdk = player.environment(args)
    versions = {"python": sys.version.split()[0]}
    for name, command in {
        "java": [
            str(
                Path(env["JAVA_HOME"])
                / "bin"
                / ("java.exe" if os.name == "nt" else "java")
            ),
            "-version",
        ],
        "go": ["go", "version"],
        "gradle": [tools["gradle"], "--version"],
    }.items():
        result = subprocess.run(
            command, env=env, capture_output=True, text=True, check=True, timeout=30
        )
        versions[name] = (result.stdout + result.stderr).strip()
    for name in ("gomobile", "gobind"):
        path = shutil.which(name, path=env["PATH"])
        if not path:
            raise RuntimeError(f"Preinstall {name} in PATH")
        versions[name] = subprocess.check_output(
            ["go", "version", "-m", path], env=env, text=True
        ).strip()
    for path in (
        sdk / f"platforms/android-{TOOLCHAIN['android']['platform']}/android.jar",
        sdk / "build-tools" / args.build_tools,
        sdk / "platform-tools" / ("adb.exe" if os.name == "nt" else "adb"),
    ):
        if not path.exists():
            raise RuntimeError(f"Preinstall Android SDK component: {path}")
    player.mpv_libraries()
    print(
        json.dumps(
            {
                **tools,
                "sdk": str(sdk),
                "android_components": player.sdk_tools(env),
                "mpv": str(player.mpv_directory()),
                "observed_versions": versions,
            },
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
