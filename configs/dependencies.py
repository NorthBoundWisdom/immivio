# Internal: FreeCM asset consumption and host dependency preparation.
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tomllib

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "FreeCM"))
from freecm.asset_seeds import asset_seed_root, require_asset_seeds
from freecm.jsonc import loads_jsonc
from freecm.workspace_lock import workspace_mutation_lock as workspace_lock

TOOLCHAIN = json.loads((ROOT / "configs/toolchain.json").read_text())
CATALOG = tomllib.loads((ROOT / "android/gradle/libs.versions.toml").read_text())
TOOLCHAIN.update(
    android_gradle_plugin=CATALOG["versions"]["agp"],
    kotlin=CATALOG["versions"]["kotlin"],
)
INIT_HINT = "Run python3 configs/source_root_workflow.py --init, then --update."


def digest(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def lock_data(root=ROOT):
    path = root / "source_roots.lock.jsonc"
    if not path.is_file():
        raise RuntimeError(INIT_HINT)
    return loads_jsonc(path.read_text(), path_label=str(path))


def asset_file(name, filename=None):
    data = lock_data()["assets"].get(name)
    if data is None:
        raise RuntimeError(f"Missing {name}. {INIT_HINT}")
    record = next(
        (
            item
            for item in data["files"]
            if filename is None or item["fileName"] == filename
        ),
        None,
    )
    if record is None or record["type"] != "file":
        raise RuntimeError(f"Unknown asset file: {name}/{filename}")
    path = asset_seed_root(ROOT, name) / record["fileName"]
    if (
        not path.is_file()
        or path.stat().st_size != record["sizeBytes"]
        or digest(path) != record["sha256"]
    ):
        raise RuntimeError(f"Invalid asset: {name}/{path.name}. {INIT_HINT}")
    return path


def select_assets(*, native=False):
    """Select the host's asset subset in the machine-local active lock."""
    from configs.source_roots import workflow

    workflow.ensure_active_lock_file(ROOT)
    with workspace_lock(ROOT):
        data = lock_data()
        template = loads_jsonc(
            (ROOT / "source_roots.lock.jsonc.in").read_text(),
            path_label="source_roots.lock.jsonc.in",
        )
        names = {"Gradle", "GodotTemplates", "OpenXRVendors", "MpvAndroid"}
        if sys.platform == "darwin":
            names |= {
                "GodotMacOS",
                "NotoLicense",
                "NotoSansCJKSC",
                "NotoSansCJKTC",
                "NotoSansCJKJP",
            }
        elif os.name == "nt":
            names.add("GodotWindows")
        native_marker = ROOT / ".cache/native-mpv-enabled"
        if native:
            native_marker.parent.mkdir(parents=True, exist_ok=True)
            native_marker.touch()
        if native_marker.exists():
            names |= {"MpvSources", "MpvBuilder", "MpvLinuxNdk"}
        data["assets"] = {name: template["assets"][name] for name in sorted(names)}
        pending = ROOT / "source_roots.lock.jsonc.pending"
        pending.write_text(json.dumps(data, indent=2) + "\n")
        pending.replace(ROOT / "source_roots.lock.jsonc")


def go_environment(env, *, online=False):
    env = env.copy()
    cache = ROOT / ".cache/go"
    env.update(
        GOBIN=str(cache / "bin"),
        GOMODCACHE=str(cache / "modules"),
        GOCACHE=str(cache / "build"),
        GOPATH=str(cache / "gopath"),
        GOTOOLCHAIN="local",
        GOFLAGS="-mod=readonly",
    )
    env["PATH"] = os.pathsep.join([str(cache / "bin"), env.get("PATH", "")])
    if not online:
        env.update(GOPROXY="off", GOSUMDB="off")
    return env


def openlist_workspace(*, include_tests=True):
    from configs.source_roots import workflow

    roots = workflow.require_dependency_roots(ROOT)
    source = roots.dependency_root_for("OpenList")
    destination = ROOT / "build/openlist"
    fingerprint = {
        "source": roots.resolved_commits["OpenList"],
        "module": digest(ROOT / "cloud/openlist/go.mod"),
        "sum": digest(ROOT / "cloud/openlist/go.sum"),
        "adapters": {
            p.name: digest(p) for p in sorted((ROOT / "cloud/openlist").glob("*.go"))
        },
    }
    marker = destination / ".immivio-inputs.json"
    if not marker.exists() or json.loads(marker.read_text()) != fingerprint:
        shutil.rmtree(destination, ignore_errors=True)
        shutil.copytree(source, destination, ignore=shutil.ignore_patterns(".git"))
        model = destination / "internal/model/storage.go"
        text = model.read_text()
        old = 'json:"addition" gorm:"type:text"'
        if text.count(old) != 1:
            raise RuntimeError("OpenList credential field changed; review the adapter")
        model.write_text(
            text.replace(old, 'json:"addition" gorm:"type:text;serializer:vrpp_secret"')
        )
        (destination / "cloudcore").mkdir(exist_ok=True)
        for path in (ROOT / "cloud/openlist").glob("*.go"):
            shutil.copy2(path, destination / "cloudcore" / path.name)
        for name in ("go.mod", "go.sum"):
            shutil.copy2(ROOT / "cloud/openlist" / name, destination / name)
        (destination / "public/dist").mkdir(parents=True, exist_ok=True)
        (destination / "public/dist/index.html").write_text(
            "<!doctype html><title>Immivio Cloud</title>"
        )
        marker.write_text(json.dumps(fingerprint, indent=2) + "\n")
    return destination, fingerprint


def export_dependencies():
    records = []
    for key in ("media3-exoplayer", "slf4j-api", "bcprov", "openxr-loader"):
        library = CATALOG["libraries"][key]
        records.append(
            library["module"] + ":" + CATALOG["versions"][library["version"]["ref"]]
        )
    return records


def stage_vendors():
    from configs import player_build as player

    destination = ROOT / "build/vendors"
    player.extract(asset_file("OpenXRVendors"), destination)
    shutil.copytree(
        destination / "asset/addons/godotopenxrvendors",
        player.PROJECT / "addons/godotopenxrvendors",
        dirs_exist_ok=True,
    )
    player.BIN.mkdir(parents=True, exist_ok=True)
    (player.BIN / "dependencies.json").write_text(
        json.dumps(export_dependencies()) + "\n"
    )


def prepare_host_assets():
    """Materialize only already verified assets; no network operations."""
    from configs import player_build as player

    require_asset_seeds(ROOT)
    output = ROOT / "build/host-tools"
    output.mkdir(parents=True, exist_ok=True)
    gradle_record = lock_data()["assets"]["Gradle"]["files"][0]
    gradle_archive = asset_file("Gradle")
    version = gradle_record["fileName"].removeprefix("gradle-").removesuffix("-bin.zip")
    gradle = (
        output
        / f"gradle-{version}/bin"
        / ("gradle.bat" if os.name == "nt" else "gradle")
    )
    if not gradle.exists():
        player.extract(gradle_archive, output)
    if os.name != "nt":
        gradle.chmod(0o755)
    godot = os.environ.get("GODOT_EXE")
    if not godot and sys.platform in ("darwin", "win32"):
        name = "GodotMacOS" if sys.platform == "darwin" else "GodotWindows"
        editor = output / "godot"
        executable = TOOLCHAIN["godot"]["executables"][
            "macos" if sys.platform == "darwin" else "windows"
        ]
        path = editor / executable
        if not path.exists():
            player.extract(asset_file(name), editor)
        if os.name != "nt":
            path.chmod(0o755)
        godot = str(path)
    godot = godot or shutil.which("godot")
    if not godot:
        raise RuntimeError("Set GODOT_EXE to the locked Godot editor")
    observed = subprocess.check_output(
        [godot, "--headless", "--version"], text=True
    ).strip()
    if observed != TOOLCHAIN["godot"]["version"]:
        raise RuntimeError(
            f'Expected {TOOLCHAIN["godot"]["version"]}, observed {observed}'
        )
    result = {
        "godot": str(Path(godot).absolute()),
        "templates": str(asset_seed_root(ROOT, "GodotTemplates")),
        "gradle": str(gradle.absolute()),
    }
    (output / "paths.json").write_text(json.dumps(result, indent=2) + "\n")
    return result


def initialize_packages(*, refresh_packages=False):
    """Network-capable package cache preparation, called exclusively by --init."""
    from configs import player_build as player
    from configs.android_workflow import arguments_for

    tools = prepare_host_assets()
    args = arguments_for("Quest", "Debug", tools)
    env, sdk = player.environment(args)
    if (
        subprocess.check_output(["go", "version"], env=env, text=True).split()[2]
        != "go" + TOOLCHAIN["go"]
    ):
        raise RuntimeError("Install the Go version specified in configs/toolchain.json")
    env["IMMIVIO_OFFLINE_BUILD"] = "0"
    online = go_environment(env, online=True)
    with workspace_lock(ROOT):
        workspace, _ = openlist_workspace()
    player.run(
        ["go", "list", "-deps", "-test", "./cloudcore"],
        cwd=workspace,
        env=online,
        log="go-download.log",
    )
    for tool in ("gomobile", "gobind"):
        player.run(
            [
                "go",
                "install",
                f'golang.org/x/mobile/cmd/{tool}@{TOOLCHAIN["gomobile"]}',
            ],
            env=online,
            log=f"{tool}-install.log",
        )
    tool_receipt = {
        name: {
            "sha256": digest(
                Path(online["GOBIN"]) / (name + (".exe" if os.name == "nt" else ""))
            ),
            "module": TOOLCHAIN["gomobile"],
        }
        for name in ("gomobile", "gobind")
    }
    (ROOT / ".cache/go/tools.json").write_text(
        json.dumps(tool_receipt, indent=2) + "\n"
    )
    stage_vendors()
    # Initialization prepares the same generated projects for package resolution.
    if refresh_packages:
        (ROOT / "android/gradle/verification-metadata.xml").write_text(
            """<?xml version="1.0" encoding="UTF-8"?>
<verification-metadata xmlns="https://schema.gradle.org/dependency-verification">
<configuration><verify-metadata>true</verify-metadata><verify-signatures>false</verify-signatures></configuration>
<components/>
</verification-metadata>
"""
        )
    player.configure_project(args, env, sdk)
    if sys.platform == "darwin":
        from configs.ci_support import install_macos_fonts

        install_macos_fonts(args.godot)
    player.run(
        [ROOT / "android/gradlew", "--version"], env=env, log="gradle-wrapper-init.log"
    )
    # Resolve plugin and matching Godot export configurations, including native tools.
    for directory in (ROOT / "android", player.PROJECT / "android/build"):
        flags = (
            ["--write-locks", "--write-verification-metadata", "sha256"]
            if refresh_packages
            else []
        )
        player.run(
            [
                tools["gradle"],
                "-p",
                directory,
                "--console=plain",
                *flags,
                "prepareDependencyCache",
            ],
            env=env,
            log="gradle-cache-" + directory.parent.name + ".log",
        )
        if refresh_packages and directory != ROOT / "android":
            shutil.copy2(
                directory / "gradle/verification-metadata.xml",
                ROOT / "android/gradle/verification-metadata.xml",
            )
            output = ROOT / "android/export-locks"
            output.mkdir(exist_ok=True)
            for path in directory.glob("**/*gradle.lockfile"):
                relative = path.relative_to(directory)
                target = output / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(path, target)
        elif refresh_packages:
            shutil.copy2(
                ROOT / "android/gradle/verification-metadata.xml",
                player.PROJECT / "android/build/gradle/verification-metadata.xml",
            )
