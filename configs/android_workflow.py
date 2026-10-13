#!/usr/bin/env python3
# Usage: python3 configs/android_workflow.py configure --vendor Quest --build-type Debug
# Usage: python3 configs/android_workflow.py build|test|package|run --vendor Quest --build-type Debug
"""Explicit, offline Android build workflow shared by local use and CI."""

import argparse
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
    lock_data,
    go_environment,
    openlist_workspace,
    stage_vendors,
)
from configs.source_roots import workflow
from freecm.asset_seeds import require_asset_seeds
from freecm.repo_commands import validate_repo_command_manifest
from repomgrandroid.workflow import AndroidWorkflowConfig, run_test_level

VENDORS = ("Quest", "Pico", "OpenXR")
BUILD_INPUTS = (
    "source_roots.lock.jsonc",
    "source_roots.lock.jsonc.in",
    "configs/toolchain.json",
    "android/build.gradle",
    "android/player-plugin/build.gradle",
    "android/settings.gradle",
    "android/gradle/libs.versions.toml",
    "android/gradle/dependency-cache.gradle",
    "android/gradle/wrapper/gradle-wrapper.properties",
    "android/gradle/verification-metadata.xml",
    "cloud/openlist/go.mod",
    "cloud/openlist/go.sum",
    "app/godot/export_presets.cfg",
)


def arguments_for(vendor, build_type, tools, *, mpv_dir=None, mpv_receipt=None):
    return SimpleNamespace(
        vendor=vendor,
        build_type=build_type,
        godot=tools["godot"],
        templates=Path(tools["templates"]),
        gradle=tools["gradle"],
        sdk=None,
        java_home=None,
        ndk=TOOLCHAIN["android"]["ndk"],
        cmake=TOOLCHAIN["android"]["cmake"],
        plugin_only=False,
        mpv_dir=mpv_dir,
        mpv_receipt=mpv_receipt,
    )


def configuration_path(vendor, build_type):
    return ROOT / f"build/configurations/{vendor}-{build_type}.json"


def input_signature(args):
    roots = workflow.require_dependency_roots()
    inputs = {name: digest(ROOT / name) for name in BUILD_INPUTS}
    for directory, pattern in [
        ("configs", "*.py"),
        ("cloud/openlist", "*.go"),
        ("native/mpv/patches", "*"),
        ("android", "**/*gradle.lockfile"),
    ]:
        inputs.update(
            {
                str(p.relative_to(ROOT)): digest(p)
                for p in (ROOT / directory).glob(pattern)
                if p.is_file()
            }
        )
    inputs["FreeCM"] = subprocess.check_output(
        ["git", "-C", str(ROOT / "FreeCM"), "rev-parse", "HEAD"], text=True
    ).strip()
    inputs["resolved_commits"] = roots.resolved_commits
    inputs["backend"] = "source_frame" if args.mpv_dir else "standard_libmpv_render"
    if args.mpv_dir:
        inputs["mpv_receipt"] = digest(args.mpv_receipt)
        record = json.loads(Path(args.mpv_receipt).read_text())
        inputs["mpv_libraries"] = {
            item["name"]: digest(Path(args.mpv_dir) / item["name"])
            for item in record["libraries"]
        }
    return inputs


def dependency_receipt():
    roots = workflow.require_dependency_roots()
    assets = lock_data()["assets"]
    return {
        "schema_version": 2,
        "freecm_commit": subprocess.check_output(
            ["git", "-C", str(ROOT / "FreeCM"), "rev-parse", "HEAD"], text=True
        ).strip(),
        "dependency_mode": roots.mode,
        "dependency_commits": roots.resolved_commits,
        "dependency_assets": {
            name: [
                {"id": r["id"], "sha256": r["sha256"], "sizeBytes": r["sizeBytes"]}
                for r in spec["files"]
            ]
            for name, spec in assets.items()
        },
        "dependency_manifests": {
            name: digest(ROOT / name)
            for name in (
                "source_roots.lock.jsonc.in",
                "configs/toolchain.json",
                "android/gradle/libs.versions.toml",
                "android/gradle/verification-metadata.xml",
                "cloud/openlist/go.mod",
                "cloud/openlist/go.sum",
            )
        },
        "gradle_locks": {
            str(p.relative_to(ROOT)): digest(p)
            for p in (ROOT / "android").glob("**/*gradle.lockfile")
        },
        "toolchain": TOOLCHAIN,
    }


def configure(args, env, sdk):
    require_asset_seeds(ROOT)
    (
        player.prepare_mpv()
        if not args.mpv_dir
        else player.prepare_source_mpv(args.mpv_dir, args.mpv_receipt)
    )
    # Vendors are pure inputs; OpenList compilation belongs to Build.
    stage_vendors()
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
                "generated_properties": digest(ROOT / "build/android.properties"),
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
        or not (ROOT / "build/godot-api/godot-lib.template_debug.aar").is_file()
    ):
        raise RuntimeError("Generated configuration is missing; run configure again")
    if data.get("generated_properties") != digest(
        ROOT / "build/android.properties"
    ) or data.get("staged_mpv") != {
        p.name: digest(p)
        for p in (ROOT / "android/player-plugin/src/main/jniLibs/arm64-v8a").glob(
            "*.so"
        )
    }:
        raise RuntimeError(
            "Generated backend configuration changed; run configure again"
        )
    require_asset_seeds(ROOT)
    if (
        args.build_type == "Release"
        and workflow.require_dependency_roots().mode != "pinned"
    ):
        raise RuntimeError("Release builds require pinned dependencies")


def build(args, env, sdk):
    player.prepare_openlist(env)
    player.build_plugin(args, env, sdk)
    path = ROOT / f"build/configurations/{args.vendor}-{args.build_type}.built.json"
    path.write_text(
        json.dumps(
            {
                "inputs": input_signature(args),
                "aar": digest(
                    player.BIN / f"player-plugin-{args.build_type.lower()}.aar"
                ),
                "openlist": digest(player.BIN / "cloudcore.aar"),
            },
            indent=2,
        )
        + "\n"
    )


def require_build(args):
    path = ROOT / f"build/configurations/{args.vendor}-{args.build_type}.built.json"
    if not path.exists():
        raise RuntimeError("Run build before package or run")
    data = json.loads(path.read_text())
    if data != {
        "inputs": input_signature(args),
        "aar": digest(player.BIN / f"player-plugin-{args.build_type.lower()}.aar"),
        "openlist": digest(player.BIN / "cloudcore.aar"),
    }:
        raise RuntimeError("Build inputs changed; run build again")


def test(args, env, sdk, level):
    if level in ("l0", "all"):
        run_test_level(
            AndroidWorkflowConfig(
                repo_root=ROOT,
                python_check_files=tuple(
                    str(p.relative_to(ROOT)) for p in (ROOT / "configs").glob("*.py")
                ),
            ),
            "l0",
            env=env,
        )
        validate_repo_command_manifest(ROOT)
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
        )
        player.run(
            [sys.executable, ROOT / "tools/test_prepare_android_release.py"], env=env
        )
        from configs.ci_support import check_export_path

        check_export_path(args.templates, args.gradle, env)
    if level in ("l1", "all"):
        run_test_level(
            AndroidWorkflowConfig(
                repo_root=ROOT,
                gradle_wrapper=ROOT / "android/gradlew",
                l1_gradle_tasks=(
                    "-p",
                    str(ROOT / "android"),
                    "--offline",
                    ":player-plugin:testDebugUnitTest",
                ),
            ),
            "l1",
            env=env,
        )
        source, _ = openlist_workspace()
        goenv = go_environment(env)
        goenv["CGO_ENABLED"] = "0"
        player.run(
            ["go", "test", "-timeout", "180s", "./cloudcore"],
            cwd=source,
            env=goenv,
            log="cloudcore-tests.log",
        )
    if level in ("l2", "all"):
        from configs.ci_support import host_tests

        host_tests(args.godot)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "command",
        choices=("configure", "build", "test", "package", "run", "stop-gradle"),
    )
    parser.add_argument("--vendor", choices=VENDORS, default="Quest")
    parser.add_argument(
        "--build-type",
        choices=("Debug", "Release"),
        default=os.environ.get("CI_BUILD_TYPE", "Debug"),
    )
    parser.add_argument("--level", choices=("l0", "l1", "l2", "all"), default="all")
    parser.add_argument("--mpv-dir", type=Path)
    parser.add_argument("--mpv-receipt", type=Path)
    opts = parser.parse_args(argv)
    from configs.ci_support import build_type_for_ref

    opts.build_type = build_type_for_ref(opts.build_type)
    if bool(opts.mpv_dir) != bool(opts.mpv_receipt):
        parser.error("--mpv-dir and --mpv-receipt must be supplied together")
    paths = ROOT / "build/host-tools/paths.json"
    if opts.command == "stop-gradle":
        if not paths.is_file():
            print("No initialized Gradle installation to stop")
            return 0
        tools = json.loads(paths.read_text())
        if not Path(tools["gradle"]).is_file():
            print("No initialized Gradle installation to stop")
            return 0
        env = os.environ.copy()
        env["GRADLE_USER_HOME"] = str(ROOT / ".cache/gradle")
        player.run([tools["gradle"], "--stop"], env=env, timeout=60)
        return 0
    if not paths.exists():
        raise RuntimeError("Run FreeCM --init and --update first")
    tools = json.loads(paths.read_text())
    args = arguments_for(
        opts.vendor,
        opts.build_type,
        tools,
        mpv_dir=opts.mpv_dir,
        mpv_receipt=opts.mpv_receipt,
    )
    env, sdk = player.environment(args)
    with player.build_lock():
        if opts.command == "configure":
            configure(args, env, sdk)
            return 0
        require_configuration(args, env, sdk)
        if opts.command == "build":
            build(args, env, sdk)
        elif opts.command == "test":
            test(args, env, sdk, opts.level)
        elif opts.command == "package":
            require_build(args)
            if (
                os.environ.get("GITHUB_ACTIONS") == "true"
                and args.build_type == "Release"
            ):
                from configs.ci_support import signing_env

                env, _ = signing_env(env)
            player.package(args, env, sdk)
            if os.environ.get("GITHUB_ACTIONS") == "true":
                from configs.ci_support import ci_package_metadata

                ci_package_metadata(args.vendor, args.build_type)
        else:
            require_build(args)
            from configs.ci_support import latest_receipt

            receipt = latest_receipt(args.vendor, args.build_type)
            apk = ROOT / "artifacts" / receipt["apk"]
            if digest(apk) != receipt["sha256"]:
                raise RuntimeError("APK differs from its receipt")
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
