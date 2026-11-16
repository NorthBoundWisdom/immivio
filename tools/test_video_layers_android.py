#!/usr/bin/env python3
"""Run disposable Surface-decoder and GLES layer checks on an explicit emulator."""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from configs.dependencies import find_gradle
from configs.player_build import prepare_mpv
from tools.build_patched_mpv import verify_output

PACKAGE = "com.northboundwisdom.immivio.performancefixture"
ACTIVITY = PACKAGE + "/org.vrpassthroughplayer.plugin.PerformanceFixtureActivity"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serial", required=True)
    parser.add_argument("--port", type=int, default=5037)
    args = parser.parse_args()
    if not args.serial.startswith("emulator-"):
        parser.error(
            "Synthetic muted checks are restricted to an explicitly selected emulator"
        )
    libraries = Path(
        os.environ.get("IMMIVIO_MPV_LIB_DIR", ROOT / ".cache/verified-mpv/arm64-v8a")
    )
    verify_output(libraries / "libmpv.so")
    sdk = Path(os.environ["ANDROID_HOME"])
    ndk = Path(os.environ["ANDROID_NDK_HOME"])
    compiler = (
        ndk
        / "toolchains/llvm/prebuilt"
        / ("darwin-x86_64" if sys.platform == "darwin" else "linux-x86_64")
        / "bin/aarch64-linux-android29-clang++"
    )
    adb = [sdk / "platform-tools/adb", "-P", str(args.port), "-s", args.serial]
    output = ROOT / "artifacts/tests/video-layers"
    output.mkdir(parents=True, exist_ok=True)
    transcript = []

    def run(command, timeout=60, check=True):
        result = subprocess.run(
            list(map(str, command)),
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        transcript.append(result.stdout + result.stderr)
        if check:
            result.check_returncode()
        return result.stdout.strip()

    run([*adb, "wait-for-device"], timeout=15)
    if run([*adb, "shell", "getprop", "ro.kernel.qemu"]) != "1":
        parser.error("Target must report ro.kernel.qemu=1")
    # Never replace a preexisting fixture belonging to another run.
    if run([*adb, "shell", "pm", "path", PACKAGE], check=False).startswith("package:"):
        parser.error(
            "Disposable fixture is already installed; remove it before this isolated run"
        )
    folder = ROOT / "build/tests/performance-fixture"
    folder.mkdir(parents=True, exist_ok=True)
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
            "-preset",
            "ultrafast",
            "-tune",
            "zerolatency",
            "-bf",
            "0",
            "-g",
            "30",
            "-pix_fmt",
            "yuv420p",
            "-c:a",
            "aac",
            "-y",
            folder / "sample.mp4",
        ]
    )
    runtime = ROOT / "build/tests/performance-fixture-libs/arm64-v8a"
    runtime.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(
        compiler.parent.parent
        / "sysroot/usr/lib/aarch64-linux-android/libc++_shared.so",
        runtime / "libc++_shared.so",
    )
    prepare_mpv()
    run(
        [
            find_gradle(),
            "-p",
            ROOT / "android",
            "--offline",
            "-PincludePerformanceFixture=true",
            ":performance-fixture:assembleDebug",
        ],
        timeout=600,
    )
    probe = ROOT / "build/tests/video-layer-probe"
    run(
        [
            compiler,
            ROOT / "tests/native/android_video_layer_probe.cpp",
            "-I" + str(ROOT / "third_party/openxr/include"),
            "-std=c++17",
            "-static-libstdc++",
            "-lEGL",
            "-lGLESv3",
            "-llog",
            "-landroid",
            "-o",
            probe,
        ]
    )
    run([*adb, "wait-for-device"], timeout=15)
    remote = "/data/local/tmp/immivio-layers-" + uuid.uuid4().hex
    installed = False
    try:
        run([*adb, "push", probe, remote])
        result = run([*adb, "shell", remote], timeout=30)
        (output / "gles.log").write_text(result + "\n")
        if "checks passed" not in result:
            raise RuntimeError("Native GLES probe did not report completion")
        run(
            [
                *adb,
                "install",
                "-r",
                ROOT
                / "android/performance-fixture/build/outputs/apk/debug/performance-fixture-debug.apk",
            ]
        )
        installed = True
        for reject in (False, True):
            run([*adb, "shell", "am", "force-stop", PACKAGE])
            run([*adb, "shell", "run-as", PACKAGE, "rm", "-f", "files/result.json"])
            run(
                [
                    *adb,
                    "shell",
                    "am",
                    "start",
                    "-n",
                    ACTIVITY,
                    "--ez",
                    "reject_hints",
                    str(reject).lower(),
                ]
            )
            deadline = time.monotonic() + 35
            report = None
            while time.monotonic() < deadline:
                data = run(
                    [*adb, "shell", "run-as", PACKAGE, "cat", "files/result.json"],
                    check=False,
                )
                if data.startswith("{"):
                    report = json.loads(data)
                    break
                time.sleep(0.2)
            (output / ("surface-retry.json" if reject else "surface.json")).write_text(
                json.dumps(report, indent=2) + "\n"
            )
            if not report or not report.get("passed") or not report.get("closed"):
                raise RuntimeError("Surface decoder fixture failed: " + str(report))
            pid = run([*adb, "shell", "pidof", PACKAGE])
            logs = run(
                [
                    *adb,
                    "logcat",
                    "-d",
                    "-v",
                    "brief",
                    "--pid=" + pid,
                    "-s",
                    "ImmivioMpvSource:I",
                ]
            )
            (output / ("surface-retry.log" if reject else "surface.log")).write_text(
                logs + "\n"
            )
            retries = logs.count("MediaCodec hints rejected; retrying without hints")
            if retries != int(reject):
                raise RuntimeError(
                    "Expected exactly one no-hint retry only in the rejection case: "
                    + str(retries)
                )
            print(json.dumps(report))
        print(result)
    finally:
        if installed:
            run([*adb, "shell", "am", "force-stop", PACKAGE], check=False)
            run([*adb, "uninstall", PACKAGE], check=False)
        run([*adb, "shell", "rm", "-f", remote], check=False)
        (output / "commands.log").write_text("\n".join(transcript))


if __name__ == "__main__":
    main()
