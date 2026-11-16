#!/usr/bin/env python3
"""Check the patched runtime on an explicitly selected Android emulator, without installing an app."""

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import uuid

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.build_patched_mpv import verify_output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serial", required=True)
    parser.add_argument("--port", type=int, default=5037)
    parser.add_argument(
        "--libraries", type=Path, default=ROOT / ".cache/verified-mpv/arm64-v8a"
    )
    args = parser.parse_args()
    if not args.serial.startswith("emulator-"):
        parser.error("This muted synthetic test is restricted to an emulator")
    verify_output(args.libraries / "libmpv.so")
    sdk = Path(os.environ["ANDROID_HOME"])
    ndk = Path(os.environ["ANDROID_NDK_HOME"])
    binary = (
        ndk
        / "toolchains/llvm/prebuilt"
        / ("darwin-x86_64" if sys.platform == "darwin" else "linux-x86_64")
        / "bin"
    )
    folder = ROOT / "build/tests/upstream-runtime"
    folder.mkdir(parents=True, exist_ok=True)
    output = ROOT / "artifacts/tests/native/android-runtime.log"
    output.parent.mkdir(parents=True, exist_ok=True)
    adb = [sdk / "platform-tools/adb", "-P", str(args.port), "-s", args.serial]

    def run(command, timeout=30):
        result = subprocess.run(
            list(map(str, command)),
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        if result.returncode:
            output.write_text(result.stdout + result.stderr)
            print(result.stdout + result.stderr, file=sys.stderr)
            result.check_returncode()
        return result.stdout

    run(
        [
            shutil.which("ffmpeg") or "ffmpeg",
            "-hide_banner",
            "-loglevel",
            "error",
            "-f",
            "lavfi",
            "-i",
            "testsrc2=size=320x180:rate=30",
            "-f",
            "lavfi",
            "-i",
            "sine=frequency=440:sample_rate=48000",
            "-t",
            "2",
            "-c:v",
            "libx264",
            "-pix_fmt",
            "yuv420p",
            "-c:a",
            "aac",
            "-y",
            folder / "sample.mp4",
        ]
    )
    run(
        [
            binary / "aarch64-linux-android29-clang",
            ROOT / "tests/native/android_runtime_probe.c",
            "-I" + str(ROOT / "native/mpv/include"),
            "-L" + str(args.libraries),
            "-lmpv",
            "-Wl,-rpath-link," + str(args.libraries),
            "-o",
            folder / "probe",
        ]
    )
    remote = "/data/local/tmp/immivio-upstream-" + uuid.uuid4().hex
    try:
        run([*adb, "shell", "mkdir", "-p", remote + "/libs"])
        libraries = [
            args.libraries / name
            for name in [
                "libmpv.so",
                "libavcodec.so",
                "libavfilter.so",
                "libavformat.so",
                "libavutil.so",
                "libavdevice.so",
                "libswresample.so",
                "libswscale.so",
            ]
        ]
        run([*adb, "push", *libraries, remote + "/libs/"])
        run([*adb, "push", folder / "probe", folder / "sample.mp4", remote + "/"])
        result = run(
            [
                *adb,
                "shell",
                "env",
                "LD_LIBRARY_PATH=" + remote + "/libs",
                remote + "/probe",
                remote + "/sample.mp4",
            ],
            timeout=25,
        )
        output.write_text(result)
        print(result, end="")
    finally:
        run([*adb, "shell", "rm", "-rf", remote])


if __name__ == "__main__":
    main()
