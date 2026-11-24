#!/usr/bin/env python3
# Usage: python3 configs/android_workflow.py configure --vendor Quest --build-type Debug
# Usage: python3 configs/android_workflow.py prepare-packages|build|test|package|run --vendor Quest --build-type Debug
"""Explicit, offline Android build workflow shared by local use and CI."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from configs import player_build as player
from configs.dependencies import (
    TOOLCHAIN,
    digest,
    find_gradle,
    stage_vendors,
    host_tools,
    vendors_archive,
    vendors_manifest,
)

VENDORS = ("Quest", "Pico", "OpenXR")
BUILD_INPUTS = (
    "third_party/openxr-vendors/manifest.json",
    "configs/toolchain.json",
    "android/build.gradle",
    "android/gradle.properties",
    "android/gradlew",
    "android/gradlew.bat",
    "android/player-plugin/build.gradle",
    "android/player-plugin/consumer-rules.pro",
    "android/settings.gradle",
    "android/gradle/libs.versions.toml",
    "android/gradle/dependency-cache.gradle",
    "third_party/mpv/manifest.json",
    "third_party/mpv/source-build.json",
    "tools/build_patched_mpv.py",
    "native/mpv/patches/0001-aaudio-clock-and-image-fence.patch",
    "native/mpv/patches/0002-ffmpeg-mediacodec-hints.patch",
    "native/mpv/patches/0003-surface-cadence.patch",
    "android/gradle/verification-metadata.xml",
    "app/godot/export_presets.cfg",
    "app/godot/project.godot",
    "app/godot/openxr_action_map.tres",
    "app/godot/icon.svg",
    "app/godot/icon.svg.import",
    "app/godot/addons/quest_player/plugin.cfg",
    "tools/prepare_branding.gd",
)


def arguments_for(vendor, build_type, tools):
    components = player.sdk_tools()
    return SimpleNamespace(
        vendor=vendor,
        build_type=build_type,
        godot=tools["godot"],
        templates=Path(tools["templates"]),
        gradle=tools["gradle"],
        sdk=None,
        java_home=None,
        ndk=components["ndk"],
        cmake=components["cmake"],
        build_tools=components["build_tools"],
        plugin_only=False,
    )


def configuration_path(vendor, build_type):
    return ROOT / f"build/android/state/{vendor}-{build_type}-web.json"


def input_signature(args):
    inputs = {name: digest(ROOT / name) for name in BUILD_INPUTS}
    source_paths = [
        ("configs", "*.py"),
        ("app/godot/branding", "*"),
        ("branding/source", "*.png"),
        ("app/godot/backgrounds", "*"),
        ("app/godot/i18n", "*.json"),
        ("app/godot/models", "**/*"),
        ("android/player-plugin/src/main", "**/*.kt"),
        ("android/player-plugin/src/main", "**/*.java"),
        ("android/player-plugin/src/main", "**/*.xml"),
        ("native", "**/*.cpp"),
        ("native", "**/*.h"),
        ("native", "**/*.hpp"),
        ("native", "**/CMakeLists.txt"),
        ("app/godot/scripts", "**/*.gd"),
        ("app/godot/scripts", "**/*.uid"),
        ("app/godot/shaders", "**/*.gdshader"),
        ("app/godot/shaders", "**/*.gdshaderinc"),
        ("app/godot/shaders", "**/*.uid"),
        ("app/godot/scenes", "**/*.tscn"),
        ("app/godot/addons/quest_player", "*.gd"),
        ("app/godot/addons/quest_player", "*.uid"),
        ("android", "**/*gradle.lockfile"),
        ("third_party", "**/*"),
    ]
    if args.build_type == "Debug":
        source_paths.extend(
            [
                ("android/player-plugin/src/debug", "**/*"),
                ("app/godot/media", "*.mp4"),
            ]
        )
    for directory, pattern in source_paths:
        inputs.update(
            {
                str(p.relative_to(ROOT)): digest(p)
                for p in (ROOT / directory).glob(pattern)
                if not p.name.startswith(".") and p.is_file()
            }
        )
    inputs["android_identity"] = player.android_identity(args.build_type)
    inputs["distribution_channel"] = player.DISTRIBUTION_CHANNEL
    inputs["sdk_components"] = {
        "ndk": args.ndk,
        "cmake": args.cmake,
        "build_tools": args.build_tools,
    }
    inputs["mpv_libraries"] = {
        name: digest(path) for name, path in player.mpv_libraries().items()
    }

    return inputs


def dependency_receipt():
    vendors_archive()
    addon = vendors_manifest()
    return {
        "schema_version": 5,
        "dependency_assets": {
            "OpenXRVendors": [
                {
                    "id": "OpenXRVendors",
                    "version": addon["version"],
                    "sha256": addon["sha256"],
                    "sizeBytes": addon["sizeBytes"],
                }
            ],
        },
        "dependency_manifests": {
            name: digest(ROOT / name)
            for name in (
                "third_party/openxr-vendors/manifest.json",
                "configs/toolchain.json",
                "android/gradle/libs.versions.toml",
                "android/gradle/verification-metadata.xml",
            )
        },
        "gradle_locks": {
            str(p.relative_to(ROOT)): digest(p)
            for p in (ROOT / "android").glob("**/*gradle.lockfile")
        },
        "toolchain": TOOLCHAIN,
        "native_manifest_sha256": digest(ROOT / "third_party/mpv/manifest.json"),
    }


def configure(args, env, sdk):
    vendors_archive()
    player.prepare_mpv()
    # Stage the OpenXR vendor addon before configuring the Android project.
    stage_vendors()
    from configs.output_paths import guides

    guides(ROOT)
    player.configure_project(args, env, sdk)
    marker = configuration_path(args.vendor, args.build_type)
    marker.parent.mkdir(parents=True, exist_ok=True)
    marker.write_text(
        json.dumps(
            {
                "inputs": input_signature(args),
                "host": sys.platform,
                "tool_paths": {
                    "godot": args.godot,
                    "templates": str(args.templates),
                    "gradle": str(args.gradle),
                },
                "sdk": str(sdk),
                "java_home": env["JAVA_HOME"],
                "generated_properties": digest(
                    ROOT / "build/android/android.properties"
                ),
                "staged_mpv": {
                    p.name: digest(p)
                    for p in (
                        ROOT / "android/player-plugin/src/main/jniLibs/arm64-v8a"
                    ).glob("*.so")
                },
            },
            indent=2,
        )
        + "\n"
    )


def require_configuration(args, env, sdk):
    marker = configuration_path(args.vendor, args.build_type)
    if not marker.is_file():
        raise RuntimeError("Configure this target and build type first")
    data = json.loads(marker.read_text())
    if (
        data["inputs"] != input_signature(args)
        or data["host"] != sys.platform
        or data["sdk"] != str(sdk)
        or data["java_home"] != env["JAVA_HOME"]
    ):
        raise RuntimeError("Configuration is stale; run configure again")
    if data["tool_paths"] != {
        "godot": args.godot,
        "templates": str(args.templates),
        "gradle": str(args.gradle),
    }:
        raise RuntimeError("Tool paths changed; run configure again")
    if (
        not (player.PROJECT / "android/build/build.gradle").is_file()
        or not (ROOT / "build/android/godot-api/godot-lib.template_debug.aar").is_file()
    ):
        raise RuntimeError("Generated configuration is missing; run configure again")
    if data.get("generated_properties") != digest(
        ROOT / "build/android/android.properties"
    ) or data.get("staged_mpv") != {
        p.name: digest(p)
        for p in (ROOT / "android/player-plugin/src/main/jniLibs/arm64-v8a").glob(
            "*.so"
        )
    }:
        raise RuntimeError(
            "Generated backend configuration changed; run configure again"
        )
    vendors_archive()


def prepare_packages(args, env):
    """Resolve application packages with Gradle; host tools remain untouched."""
    online = dict(env, IMMIVIO_OFFLINE_BUILD="0")
    for directory in (ROOT / "android", player.PROJECT / "android/build"):
        player.run(
            [args.gradle, "-p", directory, "--console=plain", "prepareDependencyCache"],
            env=online,
            log="gradle-dependencies-" + directory.parent.name + ".log",
        )


def build(args, env, sdk):
    player.build_plugin(args, env, sdk)
    path = configuration_path(args.vendor, args.build_type).with_suffix(".built.json")
    path.write_text(
        json.dumps(
            {
                "inputs": input_signature(args),
                "aar": digest(
                    player.BIN / f"player-plugin-{args.build_type.lower()}.aar"
                ),
            },
            indent=2,
        )
        + "\n"
    )


def require_build(args):
    path = configuration_path(args.vendor, args.build_type).with_suffix(".built.json")
    if not path.exists():
        raise RuntimeError("Run build before package or run")
    serialized = path.read_bytes()
    data = json.loads(serialized)
    if data != {
        "inputs": input_signature(args),
        "aar": digest(player.BIN / f"player-plugin-{args.build_type.lower()}.aar"),
    }:
        raise RuntimeError("Build inputs changed; run build again")
    return hashlib.sha256(serialized).hexdigest()


def require_packaged_build(args, build_sha256):
    from configs.ci_support import latest_receipt_file
    from configs.output_paths import apk_for_receipt

    path = latest_receipt_file(args.vendor, args.build_type)
    receipt = json.loads(path.read_text())
    if receipt.get("build_sha256") != build_sha256:
        raise RuntimeError("APK does not match the current build; run package again")
    apk = apk_for_receipt(path, receipt)
    if digest(apk) != receipt.get("sha256"):
        raise RuntimeError("APK differs from its receipt")
    return apk


def test(args, env, sdk, level):
    if level in ("l0", "all"):
        player.run(
            [
                sys.executable,
                "-m",
                "py_compile",
                *sorted((ROOT / "configs").glob("*.py")),
            ],
            env=env,
        )
        player.run(["git", "diff", "--check"], env=env)
        player.run([sys.executable, ROOT / "tools/Check-PublicSource.py"], env=env)
        player.run(
            [
                sys.executable,
                "-m",
                "unittest",
                "discover",
                "-s",
                "tests/workflow",
                "-v",
            ],
            env=env,
            log=ROOT / "artifacts/tests/workflow/unittest.log",
        )
        player.run(
            [sys.executable, ROOT / "tools/test_prepare_android_release.py"],
            env=env,
            log=ROOT / "artifacts/tests/workflow/release-publisher.log",
        )
        from configs.ci_support import check_export_path

        check_export_path(args.templates, args.gradle, env)
    if level in ("l1", "all"):
        import shutil

        try:
            player.run(
                [
                    args.gradle,
                    "-p",
                    ROOT / "android",
                    "--offline",
                    ":player-plugin:testDebugUnitTest",
                ],
                env=env,
                log="jvm-tests.log",
            )
        finally:
            source = ROOT / "android/player-plugin/build/test-results/testDebugUnitTest"
            if source.is_dir():
                shutil.copytree(
                    source, ROOT / "artifacts/tests/jvm", dirs_exist_ok=True
                )

    if level in ("l2", "all"):
        from configs.ci_support import host_tests

        host_tests(args.godot)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "command",
        choices=(
            "configure",
            "prepare-packages",
            "build",
            "test",
            "package",
            "run",
            "stop-gradle",
            "clean",
            "organize",
            "outputs",
            "locate",
        ),
    )
    parser.add_argument("--vendor", choices=VENDORS, default="Quest")
    parser.add_argument(
        "--channel",
        choices=(player.DISTRIBUTION_CHANNEL,),
        help="Optional compatibility flag for the web distribution channel",
    )
    parser.add_argument(
        "--build-type",
        choices=("Debug", "Release"),
        help="Defaults to Debug. GitHub tags always use Release.",
    )
    parser.add_argument("--level", choices=("l0", "l1", "l2", "all"), default="all")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview clean or organize without changing files",
    )
    parser.add_argument(
        "--scope",
        choices=("build", "intermediates", "logs", "tests", "captures", "archive"),
        help="Cleanup category; default build; packages and signing are never included",
    )
    opts = parser.parse_args(argv)
    if opts.dry_run and opts.command not in ("clean", "organize"):
        parser.error("--dry-run requires clean or organize")
    if opts.scope and opts.command != "clean":
        parser.error("--scope requires clean")
    if opts.command in ("clean", "organize", "outputs"):
        from configs import output_paths

        if opts.command == "clean":
            output_paths.clean(ROOT, opts.scope or "build", opts.dry_run)
        elif opts.command == "organize":
            output_paths.organize(ROOT, opts.dry_run)
        else:
            print(json.dumps(output_paths.describe(ROOT), ensure_ascii=False, indent=2))
        return 0
    from configs.ci_support import build_type_for_ref

    opts.build_type = build_type_for_ref(opts.build_type)
    if opts.command == "locate":
        from configs.ci_support import latest_receipt_file
        from configs.output_paths import apk_for_receipt

        path = latest_receipt_file(opts.vendor, opts.build_type)
        record = json.loads(path.read_text())
        apk = apk_for_receipt(path, record)
        if digest(apk) != record.get("sha256"):
            raise RuntimeError("APK differs from its receipt")
        print(apk)
        return 0
    if opts.command == "stop-gradle":
        gradle = find_gradle()
        if gradle and Path(gradle).is_file():
            player.run([gradle, "--stop"], env=os.environ.copy(), timeout=60)
        return 0
    tools = host_tools()
    args = arguments_for(opts.vendor, opts.build_type, tools)
    from configs.output_paths import build_logs

    player.LOGS = build_logs(
        ROOT, args.vendor, player.DISTRIBUTION_CHANNEL, args.build_type
    )
    env, sdk = player.environment(args)
    with player.build_lock():
        if opts.command == "configure":
            configure(args, env, sdk)
            return 0
        require_configuration(args, env, sdk)
        if opts.command == "prepare-packages":
            prepare_packages(args, env)
        elif opts.command == "build":
            build(args, env, sdk)
        elif opts.command == "test":
            test(args, env, sdk, opts.level)
        elif opts.command == "package":
            build_sha256 = require_build(args)
            hosted = env.get("GITHUB_ACTIONS") == "true"
            tagged = env.get("GITHUB_REF", "").startswith("refs/tags/")
            signing_mode = "ephemeral-ci-key" if hosted else None
            if tagged or (hosted and args.build_type == "Release"):
                from configs.ci_support import signing_env

                env, signing_mode = signing_env(env)
            player.package(
                args, env, sdk, build_sha256=build_sha256, signing_mode=signing_mode
            )
            if hosted:
                from configs.ci_support import ci_package_metadata

                ci_package_metadata(
                    args.vendor,
                    args.build_type,
                    signing_mode=signing_mode,
                )
        else:
            apk = require_packaged_build(args, require_build(args))
            adb = sdk / "platform-tools" / ("adb.exe" if os.name == "nt" else "adb")
            player.run([adb, "install", "-r", apk], env=env)
            player.run(
                [
                    adb,
                    "shell",
                    "monkey",
                    "-p",
                    player.android_identity()["application_id"],
                    "1",
                ],
                env=env,
            )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, ValueError, OSError, subprocess.SubprocessError) as error:
        print(f"Android workflow failed: {error}", file=sys.stderr)
        raise SystemExit(1)
