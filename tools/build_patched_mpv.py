#!/usr/bin/env python3
"""Build the locked Android mpv/FFmpeg runtime; network/tool setup is explicit."""

from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
LOCK = ROOT / "third_party/mpv/source-build.json"


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def recipe_inputs(root=ROOT):
    lock = json.loads((root / "third_party/mpv/source-build.json").read_text())
    return {
        name: digest(root / name)
        for name in [
            "third_party/mpv/source-build.json",
            "tools/build_patched_mpv.py",
            lock["patch"],
            *lock.get("extra_patches", []),
            *([lock["ffmpeg_patch"]] if lock.get("ffmpeg_patch") else []),
            lock["clock_header"],
            "third_party/mpv/manifest.json",
        ]
    }


def verify_output(path, root=ROOT):
    path = Path(path)
    try:
        receipt = json.loads((path.parent / "mpv-build-receipt.json").read_text())
        lock = json.loads((root / "third_party/mpv/source-build.json").read_text())
        if receipt.get("schema_version") != 1 or receipt.get("inputs") != recipe_inputs(
            root
        ):
            raise ValueError("source recipe changed")
        if receipt.get("ndk") != lock["ndk"] or receipt.get("tools") != lock["tools"]:
            raise ValueError("toolchain differs")
        metadata = (
            receipt.get("libraries", {}).get(path.name, {})
            if lock.get("build_ffmpeg")
            else receipt
        )
        if (
            metadata.get("sha256") != digest(path)
            or metadata.get("bytes") != path.stat().st_size
        ):
            raise ValueError("library bytes changed")
    except (OSError, ValueError, KeyError) as error:
        raise RuntimeError(
            f"Missing or incompatible patched libmpv: {path}; rebuild with tools/build_patched_mpv.py ({error})"
        ) from error


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--base", type=Path, default=ROOT / ".cache/verified-mpv/arm64-v8a"
    )
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--archives", type=Path, default=ROOT / ".cache/downloads")
    parser.add_argument("--download", action="store_true")
    parser.add_argument("--prepare-tools", action="store_true")
    parser.add_argument("--ndk", type=Path)
    args = parser.parse_args()
    if sys.platform not in ("darwin", "linux"):
        parser.error("This source build supports macOS and Linux Android NDK hosts")
    lock = json.loads(LOCK.read_text())
    sdk = Path(os.environ.get("ANDROID_HOME", str(Path.home() / "Library/Android/sdk")))
    ndk = args.ndk or Path(
        os.environ.get("ANDROID_NDK_HOME", str(sdk / "ndk" / lock["ndk"]))
    )
    if f"Pkg.Revision = {lock['ndk']}" not in (ndk / "source.properties").read_text():
        parser.error("Use the reviewed NDK version from source-build.json")
    tools = ROOT / ".cache/native-build-tools"
    python = tools / "bin/python"
    if args.prepare_tools:
        if not python.is_file():
            subprocess.run([sys.executable, "-m", "venv", tools], check=True)
        subprocess.run(
            [
                python,
                "-m",
                "pip",
                "install",
                *[f"{k}=={v}" for k, v in lock["tools"].items()],
            ],
            check=True,
        )
    if not python.is_file():
        parser.error("Prepare local tools with --prepare-tools")
    versions = json.loads(
        subprocess.check_output(
            [
                python,
                "-c",
                "import importlib.metadata,json; print(json.dumps({k:importlib.metadata.version(k) for k in ['meson','Jinja2','MarkupSafe']}))",
            ],
            text=True,
        )
    )
    if versions != lock["tools"]:
        parser.error("Local tool versions differ; run --prepare-tools")
    manifest = json.loads((ROOT / "third_party/mpv/manifest.json").read_text())
    base = args.base.resolve()
    for library in manifest["libraries"]:
        if lock.get("build_ffmpeg"):
            break
        if (
            library["name"] in manifest["packaged_libraries"]
            and library["name"] != "libmpv.so"
        ):
            if digest(base / library["name"]) != library["sha256"]:
                parser.error(f"Base FFmpeg differs: {library['name']}")
    work = ROOT / "build/dependencies/patched-mpv"
    prefix = work / "prefix"
    prefix.mkdir(parents=True, exist_ok=True)
    # Recreate owned source trees from checked archives on every build.
    for source in lock["sources"]:
        archive = args.archives / source["archive"]
        if not archive.is_file() and args.download:
            archive.parent.mkdir(parents=True, exist_ok=True)
            temporary = archive.with_suffix(archive.suffix + ".download")
            urllib.request.urlretrieve(source["url"], temporary)
            if digest(temporary) != source["sha256"]:
                temporary.unlink()
                raise RuntimeError(f"Source checksum failed: {source['name']}")
            temporary.replace(archive)
        if not archive.is_file() or digest(archive) != source["sha256"]:
            parser.error(
                f"Missing/changed source archive {archive}; --download explicitly fetches missing inputs"
            )
        destination = work / source["name"]
        if destination.is_symlink():
            raise RuntimeError("Source directory must not be a symlink")
        if destination.exists():
            shutil.rmtree(destination)
        destination.mkdir()
        with tarfile.open(archive) as tar:
            for member in tar.getmembers():
                if "/" not in member.name:
                    continue
                member.name = member.name.split("/", 1)[1]
                if member.name:
                    tar.extract(member, destination, filter="data")
    subprocess.run(
        ["patch", "-p1", "--batch", "-i", ROOT / lock["patch"]],
        cwd=work / "mpv",
        check=True,
    )
    for patch in lock.get("extra_patches", []):
        subprocess.run(
            ["patch", "-p1", "--batch", "-i", ROOT / patch],
            cwd=work / "mpv",
            check=True,
        )
    if lock.get("ffmpeg_patch"):
        subprocess.run(
            ["patch", "-p1", "--batch", "-i", ROOT / lock["ffmpeg_patch"]],
            cwd=work / "ffmpeg",
            check=True,
        )
    if digest(work / "mpv/audio/out/immivio_aaudio_clock.h") != digest(
        ROOT / lock["clock_header"]
    ):
        raise RuntimeError("Tested AAudio header differs from source patch")
    binary = (
        ndk
        / "toolchains/llvm/prebuilt"
        / ("darwin-x86_64" if sys.platform == "darwin" else "linux-x86_64")
        / "bin"
    )
    cross = work / "android.ini"
    cross.write_text(f"""[binaries]
c = '{binary}/aarch64-linux-android29-clang'
cpp = '{binary}/aarch64-linux-android29-clang++'
ar = '{binary}/llvm-ar'
strip = '{binary}/llvm-strip'
pkg-config = '{shutil.which("pkg-config")}'
[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'armv8'
endian = 'little'
[built-in options]
c_args = ['-fPIC']
cpp_args = ['-fPIC']
c_link_args = ['-Wl,-z,max-page-size=16384']
cpp_link_args = ['-Wl,-z,max-page-size=16384']
[properties]
needs_exe_wrapper = true
""")
    env = os.environ.copy()
    env.update(
        PATH=str(tools / "bin") + os.pathsep + env["PATH"],
        PKG_CONFIG_LIBDIR=str(prefix / "lib/pkgconfig"),
        PKG_CONFIG_PATH="",
    )
    meson = tools / "bin/meson"

    def run(command, cwd=None):
        print("+", *map(str, command), flush=True)
        subprocess.run(list(map(str, command)), cwd=cwd, env=env, check=True)

    def build(name, options=()):
        destination = work / (name + "-build")
        setup = (
            "--reconfigure"
            if (destination / "build.ninja").is_file()
            else "--wipe"
            if (destination / "meson-private/coredata.dat").is_file()
            else None
        )
        run(
            [
                meson,
                "setup",
                *([setup] if setup else []),
                destination,
                work / name,
                "--cross-file",
                cross,
                "--prefix",
                prefix,
                "--libdir",
                "lib",
                "--buildtype",
                "release",
                "--default-library",
                "static",
                "--auto-features",
                "disabled",
                "--wrap-mode",
                "nodownload",
                *options,
            ]
        )
        run([meson, "compile", "-C", destination, "-j", "6"])
        run([meson, "install", "-C", destination])

    build("freetype", ["-Dharfbuzz=disabled", "-Dzlib=internal"])
    build("fribidi", ["-Ddocs=false", "-Dbin=false", "-Dtests=false"])
    build(
        "harfbuzz",
        [
            "-Dfreetype=enabled",
            "-Dtests=disabled",
            "-Dutilities=disabled",
            "-Dsubset=disabled",
            "-Draster=disabled",
            "-Dvector=disabled",
            "-Dgpu=disabled",
        ],
    )
    build("libass", ["-Drequire-system-font-provider=false"])
    for name in ["glad", "fast_float"]:
        shutil.copytree(
            work / name, work / "libplacebo/3rdparty" / name, dirs_exist_ok=True
        )
    build(
        "libplacebo",
        [
            "-Ddemos=false",
            "-Dopengl=enabled",
            "-Dgl-proc-addr=enabled",
            "-Ddovi=enabled",
        ],
    )
    ffmpeg = work / "ffmpeg"
    for name, options in [
        (
            "mbedtls",
            [
                "-DENABLE_PROGRAMS=OFF",
                "-DENABLE_TESTING=OFF",
                "-DUSE_SHARED_MBEDTLS_LIBRARY=OFF",
                "-DUSE_STATIC_MBEDTLS_LIBRARY=ON",
            ],
        ),
        (
            "libxml2",
            [
                "-DBUILD_SHARED_LIBS=OFF",
                "-DLIBXML2_WITH_PYTHON=OFF",
                "-DLIBXML2_WITH_ICONV=OFF",
                "-DLIBXML2_WITH_TESTS=OFF",
                "-DLIBXML2_WITH_PROGRAMS=OFF",
                "-DLIBXML2_WITH_LZMA=OFF",
            ],
        ),
    ]:
        destination = work / (name + "-build")
        run(
            [
                "cmake",
                "-S",
                work / name,
                "-B",
                destination,
                "-G",
                "Ninja",
                f"-DCMAKE_TOOLCHAIN_FILE={ndk}/build/cmake/android.toolchain.cmake",
                "-DANDROID_ABI=arm64-v8a",
                "-DANDROID_PLATFORM=android-29",
                f"-DCMAKE_INSTALL_PREFIX={prefix}",
                "-DCMAKE_BUILD_TYPE=Release",
                "-DCMAKE_POSITION_INDEPENDENT_CODE=ON",
                *options,
            ]
        )
        run(["cmake", "--build", destination, "--parallel", "6"])
        run(["cmake", "--install", destination])
    build("dav1d", ["-Denable_tools=false", "-Denable_tests=false"])
    # Prevent the release helper from discovering the application's parent Git history.
    env["revision"] = lock["ffmpeg_version"]
    run(
        [
            ffmpeg / "configure",
            f"--prefix={prefix}",
            "--target-os=android",
            "--arch=aarch64",
            "--cpu=armv8-a",
            "--enable-cross-compile",
            f"--cc={binary}/aarch64-linux-android29-clang",
            f"--cxx={binary}/aarch64-linux-android29-clang++",
            f"--ar={binary}/llvm-ar",
            f"--ranlib={binary}/llvm-ranlib",
            f"--strip={binary}/llvm-strip",
            f"--nm={binary}/llvm-nm",
            "--pkg-config=pkg-config",
            "--pkg-config-flags=--static",
            f"--extra-cflags=-I{prefix}/include -fPIC",
            f"--extra-ldflags=-L{prefix}/lib -Wl,-z,max-page-size=16384",
            "--enable-jni",
            "--enable-mediacodec",
            "--enable-mbedtls",
            "--enable-libdav1d",
            "--enable-libxml2",
            "--disable-vulkan",
            "--disable-static",
            "--enable-shared",
            "--enable-gpl",
            "--enable-version3",
            "--disable-stripping",
            "--disable-doc",
            "--disable-programs",
            "--disable-muxers",
            "--disable-encoders",
            "--disable-devices",
            "--enable-encoder=mjpeg,png",
            "--enable-muxer=mov,matroska,mpegts",
        ],
        cwd=ffmpeg,
    )
    run(["make", "-j6"], cwd=ffmpeg)
    run(["make", "install"], cwd=ffmpeg)
    env.pop("revision", None)
    # Meson's static C++ dependencies advertise -lc++ (the shared NDK runtime).
    # The patched mpv target explicitly links its static runtime; do not bind to Godot's
    # potentially older libc++_shared.so or export duplicate STL symbols.
    for pc in (prefix / "lib/pkgconfig").glob("*.pc"):
        pc.write_text(pc.read_text().replace(" -lc++", ""))
    mpv_build = work / "mpv-build"
    if mpv_build.exists():
        shutil.rmtree(mpv_build)
    build(
        "mpv",
        [
            "--default-library=shared",
            "-Dcplayer=false",
            "-Dbuild-date=false",
            "-Dlibmpv=true",
            "-Db_lundef=true",
            "-Daaudio=enabled",
            "-Dgl=enabled",
            "-Degl-android=enabled",
            "-Dplain-gl=enabled",
            "-Dlibavdevice=enabled",
            "-Dandroid-media-ndk=enabled",
        ],
    )
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    library = output / "libmpv.so"
    temporary = output / "libmpv.so.building"
    shutil.copy2(prefix / "lib/libmpv.so", temporary)
    run([binary / "llvm-strip", "--strip-unneeded", temporary])
    dynamic = subprocess.check_output(
        [binary / "llvm-readelf", "-d", temporary], text=True
    )
    if "libc++_shared.so" in dynamic or "RUNPATH" in dynamic or "RPATH" in dynamic:
        raise RuntimeError(
            "Patched libmpv must have a private static C++ runtime and no host search paths"
        )
    exports = subprocess.check_output(
        [binary / "llvm-nm", "-D", "--defined-only", temporary], text=True
    )
    for symbol in [
        "mpv_create",
        "mpv_initialize",
        "mpv_terminate_destroy",
        "mpv_render_context_create",
        "mpv_render_context_render",
        "mpv_quest_vsync_api_version",
        "mpv_quest_vsync_update",
        "mpv_immivio_surface_released",
    ]:
        if not re.search(r"\b" + symbol + r"$", exports, re.M):
            raise RuntimeError(f"Required public libmpv API missing: {symbol}")
    temporary.replace(library)
    for name in manifest["packaged_libraries"]:
        if name != "libmpv.so":
            shutil.copy2(prefix / "lib" / name, output / name)
            run([binary / "llvm-strip", "--strip-unneeded", output / name])
    receipt = {
        "schema_version": 1,
        "libraries": {
            name: {
                "sha256": digest(output / name),
                "bytes": (output / name).stat().st_size,
            }
            for name in manifest["packaged_libraries"]
        },
        "inputs": recipe_inputs(),
        "ndk": lock["ndk"],
        "tools": versions,
        "sha256": digest(library),
        "bytes": library.stat().st_size,
    }
    (output / "mpv-build-receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    verify_output(library)
    print(f"Verified patched libmpv: {library}")


if __name__ == "__main__":
    main()
