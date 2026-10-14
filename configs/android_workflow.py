#!/usr/bin/env python3
# Usage: python3 configs/android_workflow.py configure --vendor Quest --build-type Debug
# Usage: python3 configs/android_workflow.py prepare-packages|build|test|package|run --vendor Quest --build-type Debug
"""Explicit, offline Android build workflow shared by local use and CI."""

import argparse
import json
import os
from pathlib import Path
import re
import shutil
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
    host_tools,
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
    "third_party/mpv/manifest.json",
    "android/gradle/verification-metadata.xml",
    "cloud/openlist/go.mod",
    "cloud/openlist/go.sum",
    "app/godot/export_presets.cfg",
    "app/godot/project.godot",
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
    return ROOT / f"build/configurations/{vendor}-{build_type}.json"


def input_signature(args):
    roots = workflow.require_dependency_roots()
    inputs = {name: digest(ROOT / name) for name in BUILD_INPUTS}
    for directory, pattern in [
        ("configs", "*.py"),
        ("cloud/openlist", "*.go"),
        ("android/player-plugin/src/main", "**/*.kt"),
        ("android/player-plugin/src/main", "**/*.java"),
        ("android/player-plugin/src/main", "**/*.xml"),
        ("native", "**/*.cpp"),
        ("native", "**/*.h"),
        ("native", "**/*.hpp"),
        ("native", "**/CMakeLists.txt"),
        ("app/godot/scripts", "**/*.gd"),
        ("app/godot/shaders", "**/*.gdshader"),
        ("app/godot", "*.tscn"),
        ("app/godot/addons/quest_player", "*.gd"),
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
    inputs["mpv_libraries"] = {
        name: digest(path) for name, path in player.mpv_libraries().items()
    }

    return inputs


def dependency_receipt():
    roots = workflow.require_dependency_roots()
    return {
        "schema_version": 2,
        "freecm_commit": subprocess.check_output(
            ["git", "-C", str(ROOT / "FreeCM"), "rev-parse", "HEAD"], text=True
        ).strip(),
        "dependency_mode": roots.mode,
        "dependency_commits": roots.resolved_commits,
        "dependency_assets": {
            name: [
                {
                    "id": item["id"],
                    "sha256": item["sha256"],
                    "sizeBytes": item["sizeBytes"],
                }
                for item in spec["files"]
            ]
            for name, spec in lock_data().get("assets", {}).items()
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
        "native_manifest_sha256": digest(ROOT / "third_party/mpv/manifest.json"),
    }


def configure(args, env, sdk):
    require_asset_seeds(ROOT)
    player.prepare_mpv()
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


def prepare_go_packages(source, env):
    """Cache the full module graph consumed by gomobile's generated module."""
    online = go_environment(env, online=True)
    # Package discovery alone omits modules which gomobile subsequently reads
    # with `go list -m all` and imports while tidying its generated bindings.
    player.run(
        ["go", "mod", "download", "all"],
        cwd=source,
        env=online,
        log="go-modules.log",
    )
    player.run(
        ["go", "list", "-deps", "-test", "./cloudcore"],
        cwd=source,
        env=online,
        log="go-dependencies.log",
    )
    prepare_binding_module_graph(source, online)


def prepare_binding_module_graph(source, env):
    """Warm gomobile's expanded module graph without compiling the bindings."""
    graph = subprocess.check_output(
        ["go", "list", "-m", "-json", "-tags=android", "all"],
        cwd=source,
        env=dict(env, GOOS="android", GOARCH="arm64"),
        text=True,
    )
    version = (
        subprocess.check_output(
            ["go", "env", "GOVERSION"],
            cwd=source,
            env=env,
            text=True,
        )
        .strip()
        .removeprefix("go")
    )
    if not re.fullmatch(r"\d+\.\d+(?:\.\d+)?", version):
        raise RuntimeError("Binding cache preparation requires a released Go toolchain")
    decoder = json.JSONDecoder()
    requires, replaces = [], []
    while graph.strip():
        module, end = decoder.raw_decode(graph.lstrip())
        graph = graph.lstrip()[end:]
        path, selected = module["Path"], module.get("Version", "")
        replacement = module.get("Replace")
        if replacement:
            target = (
                replacement.get("Dir")
                if not replacement.get("Version")
                else replacement["Path"]
            )
            replaces.append(
                f'{path} => {json.dumps(target, ensure_ascii=False)} {replacement.get("Version", "")}'
            )
        elif not selected:
            replaces.append(
                f'{path} => {json.dumps(Path(module["Dir"]).as_posix(), ensure_ascii=False)}'
            )
            # Tidy adds this requirement after seeing the generated wrapper's import.
            major = re.search(r"/v(\d+)$", path)
            selected = f'v{major[1] if major else "0"}.0.0'
        if selected:
            requires.append(f"{path} {selected}")
    directory = source.parent / "openlist-binding-modules"
    directory.mkdir(parents=True, exist_ok=True)
    (directory / "go.mod").write_text(
        f"module gobind\n\ngo {version}\n\nrequire (\n"
        + "\n".join(requires)
        + "\n)\n\nreplace (\n"
        + "\n".join(replaces)
        + "\n)\n",
        encoding="utf-8",
    )
    if (source / "go.sum").exists():
        shutil.copy2(source / "go.sum", directory / "go.sum")
    # gomobile promotes every listed module to a root requirement. This can
    # select newer transitive versions than `go mod download all` in the app.
    player.run(
        ["go", "mod", "download", "all"],
        cwd=directory,
        env=dict(env, GOFLAGS="-mod=mod"),
        log="go-binding-modules.log",
    )


def prepare_packages(args, env):
    """Resolve application packages with Go/Gradle; host tools remain untouched."""
    source, _ = openlist_workspace()
    prepare_go_packages(source, env)
    online = go_environment(env, online=True)
    online["IMMIVIO_OFFLINE_BUILD"] = "0"
    for directory in (ROOT / "android", player.PROJECT / "android/build"):
        player.run(
            [args.gradle, "-p", directory, "--console=plain", "prepareDependencyCache"],
            env=online,
            log="gradle-dependencies-" + directory.parent.name + ".log",
        )


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
        choices=(
            "configure",
            "prepare-packages",
            "build",
            "test",
            "package",
            "run",
            "stop-gradle",
        ),
    )
    parser.add_argument("--vendor", choices=VENDORS, default="Quest")
    parser.add_argument(
        "--build-type",
        choices=("Debug", "Release"),
        default=os.environ.get("CI_BUILD_TYPE", "Debug"),
    )
    parser.add_argument("--level", choices=("l0", "l1", "l2", "all"), default="all")
    opts = parser.parse_args(argv)
    from configs.ci_support import build_type_for_ref

    opts.build_type = build_type_for_ref(opts.build_type)
    if opts.command == "stop-gradle":
        import shutil

        gradle = os.environ.get("GRADLE_EXE") or shutil.which("gradle")
        if gradle and Path(gradle).is_file():
            player.run([gradle, "--stop"], env=os.environ.copy(), timeout=60)
        return 0
    tools = host_tools()
    args = arguments_for(
        opts.vendor,
        opts.build_type,
        tools,
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
