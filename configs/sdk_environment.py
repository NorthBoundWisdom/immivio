#!/usr/bin/env python3
# Usage: python3 configs/sdk_environment.py --install
"""Provision host SDK requirements declared by the master lock on Windows/macOS/Linux."""

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from configs.dependency_manifest import catalog


def sdkmanager_command(env):
    sdk = env.get("ANDROID_HOME") or env.get("ANDROID_SDK_ROOT")
    if not sdk:
        raise RuntimeError(
            "Provide ANDROID_HOME after installing Android command-line tools"
        )
    executable = shutil.which("sdkmanager", path=env.get("PATH")) or shutil.which(
        "sdkmanager.bat", path=env.get("PATH")
    )
    if not executable:
        suffix = "sdkmanager.bat" if os.name == "nt" else "sdkmanager"
        candidates = sorted((Path(sdk) / "cmdline-tools").glob("*/bin/" + suffix))
        if not candidates:
            raise RuntimeError("Android command-line tools are missing")
        executable = str(candidates[-1])
    return [executable, "--sdk_root=" + sdk]


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--install", action="store_true", required=True)
    parser.parse_args(argv)
    android = catalog()["toolchain"]["android"]
    command = sdkmanager_command(os.environ)
    subprocess.run(
        [
            *command,
            "platform-tools",
            "platforms;android-" + str(android["platform"]),
            "build-tools;" + android["build_tools"],
            "ndk;" + android["ndk"],
            "cmake;" + android["cmake"],
        ],
        check=True,
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, OSError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
