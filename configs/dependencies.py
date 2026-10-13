# Internal: project source/asset consumption and preinstalled host tools.
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "FreeCM"))
from freecm.asset_seeds import asset_seed_root
from freecm.jsonc import loads_jsonc

import tomllib

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


def go_environment(env, *, online=False):
    env = env.copy()
    # Respect the preconfigured Go environment and its normal package caches.
    env.update(GOTOOLCHAIN="local", GOFLAGS="-mod=readonly")
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


def host_tools():
    """Find installed tools; never install or download a host dependency."""
    from types import SimpleNamespace
    from configs import player_build as player

    def executable(variable, fallback):
        value = os.environ.get(variable) or shutil.which(fallback)
        path = (
            Path(shutil.which(value) or value).expanduser().absolute()
            if value
            else None
        )
        if path is None or not path.is_file():
            raise RuntimeError(
                f"Preinstall {fallback} or set {variable}; see docs/BUILD.md"
            )
        return str(path)

    godot = executable("GODOT_EXE", "godot")
    gradle = executable("GRADLE_EXE", "gradle")
    args = SimpleNamespace(godot=godot, templates=os.environ.get("GODOT_TEMPLATES_DIR"))
    templates, observed = player.template_directory(args, os.environ)
    if not (templates / "android_source.zip").is_file():
        raise RuntimeError(
            f"Preinstall matching Godot Android export templates in {templates}"
        )
    expected_template = observed.split(".official")[0]
    if (
        not (templates / "version.txt").is_file()
        or (templates / "version.txt").read_text().strip() != expected_template
    ):
        raise RuntimeError(
            f"Godot templates must match the installed editor {observed}"
        )
    return {"godot": godot, "templates": str(templates), "gradle": gradle}
