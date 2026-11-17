"""Fingerprint and verify the dependency-only Android playback cache."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import time

from tools.build_patched_mpv import digest, recipe_inputs, verify_output

ROOT = Path(__file__).resolve().parents[1]


def cache_key(root=ROOT, host=None):
    manifest = json.loads((root / "third_party/mpv/manifest.json").read_text())
    ci = json.loads((root / "configs/ci_toolchain.json").read_text())
    inputs = (
        recipe_inputs(root)
        if manifest.get("source_build")
        else {
            "third_party/mpv/manifest.json": digest(
                root / "third_party/mpv/manifest.json"
            )
        }
    )
    context = (
        host
        if host is not None
        else {
            "os": platform.system(),
            "arch": platform.machine(),
            "python": list(sys.version_info[:3]),
            "image": os.environ.get("ImageVersion", ""),
        }
    )
    record = {
        "schema": 1,
        "inputs": inputs,
        "host": context,
        "python": ci["python"],
        "ndk": ci["android"]["ndk"],
        "cmake": ci["android"]["cmake"],
    }
    return hashlib.sha256(json.dumps(record, sort_keys=True).encode()).hexdigest()


def verify_runtime(directory, root=ROOT):
    if directory.is_symlink():
        raise RuntimeError("Unexpected playback directory symlink")
    manifest = json.loads((root / "third_party/mpv/manifest.json").read_text())
    lock = (
        json.loads((root / manifest["source_build"]).read_text())
        if manifest.get("source_build")
        else {}
    )
    originals = {item["name"]: item for item in manifest["libraries"]}
    if not directory.is_dir() or not manifest["packaged_libraries"]:
        raise RuntimeError("Playback cache is incomplete")
    for name in manifest["packaged_libraries"]:
        path = directory / name
        if path.is_symlink():
            raise RuntimeError(f"Unexpected playback cache symlink: {name}")
        if lock and (name == "libmpv.so" or lock.get("build_ffmpeg")):
            verify_output(path, root)
        else:
            expected = originals[name]
            if (
                path.stat().st_size != expected["bytes"]
                or digest(path) != expected["sha256"]
            ):
                raise RuntimeError(f"Playback cache differs: {name}")


def reuse_or_build(directory, build, root=ROOT):
    try:
        verify_runtime(directory, root)
    except (
        OSError,
        RuntimeError,
        ValueError,
        KeyError,
        TypeError,
        AttributeError,
    ) as error:
        print(f"Playback cache unavailable or invalid: {error}", flush=True)
    else:
        print(
            "Reusing verified playback runtime; source compilation skipped", flush=True
        )
        return False
    build()
    verify_runtime(
        directory, root
    )  # A bad fresh build must fail, never enter the cache.
    print("Built and verified playback runtime", flush=True)
    return True


def prepare():
    if os.environ.get("GITHUB_ACTIONS") != "true":
        raise RuntimeError("Playback cache preparation is restricted to hosted CI")
    from configs.setup_hosted_ci import download

    started = time.monotonic()
    directory = Path(os.environ["IMMIVIO_MPV_LIB_DIR"])
    if directory != ROOT / ".cache/ci-playback/arm64-v8a":
        raise RuntimeError("CI preparation may rebuild only its owned playback cache")
    sdk = Path(os.environ["ANDROID_HOME"])
    ci = json.loads((ROOT / "configs/ci_toolchain.json").read_text())
    manifest = json.loads((ROOT / "third_party/mpv/manifest.json").read_text())
    lock = (
        json.loads((ROOT / manifest["source_build"]).read_text())
        if manifest.get("source_build")
        else {}
    )
    ndk = sdk / "ndk" / ci["android"]["ndk"]
    if lock and (
        lock["ndk"] != ci["android"]["ndk"]
        or f"Pkg.Revision = {lock['ndk']}"
        not in (ndk / "source.properties").read_text()
    ):
        raise RuntimeError("Installed NDK does not match the playback source lock")

    def build():
        if directory.is_symlink() or directory.is_file():
            directory.unlink()
        elif directory.exists():
            shutil.rmtree(directory)
        directory.mkdir(parents=True)
        # A full source build needs none of the original APK's binary inputs.
        if not lock.get("build_ffmpeg"):
            import zipfile

            archive = directory / "original.apk"
            download(manifest["source_url"], archive, manifest["apk_sha256"])
            with zipfile.ZipFile(archive) as source:
                for item in manifest["libraries"]:
                    if item["name"] not in manifest["packaged_libraries"]:
                        continue
                    data = source.read(item["path"])
                    if (
                        len(data) != item["bytes"]
                        or hashlib.sha256(data).hexdigest() != item["sha256"]
                    ):
                        raise RuntimeError(
                            f"Invalid original playback library: {item['name']}"
                        )
                    (directory / item["name"]).write_bytes(data)
            archive.unlink()
        if lock:
            subprocess.run(
                [
                    sys.executable,
                    ROOT / "tools/build_patched_mpv.py",
                    "--base",
                    directory,
                    "--output",
                    directory,
                    "--ndk",
                    ndk,
                    "--download",
                    "--prepare-tools",
                ],
                check=True,
            )

    built = reuse_or_build(directory, build)
    elapsed = time.monotonic() - started
    print(
        f"Playback preparation: {'built' if built else 'reused'} in {elapsed:.1f}s",
        flush=True,
    )
    with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
        output.write(f"runtime-built={str(built).lower()}\n")
    with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as output:
        output.write(
            f"Playback runtime: **{'built' if built else 'reused'}**, {elapsed:.1f}s; all packaged libraries verified.\n\n"
        )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--key", action="store_true")
    args = parser.parse_args()
    print(cache_key()) if args.key else prepare()
