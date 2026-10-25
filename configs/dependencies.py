# Internal: verified OpenXR addon archive and preinstalled host tools.
import hashlib
import json
import os
from pathlib import Path
import shutil
import tempfile
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parents[1]

import tomllib

TOOLCHAIN = json.loads((ROOT / "configs/toolchain.json").read_text())
CATALOG = tomllib.loads((ROOT / "android/gradle/libs.versions.toml").read_text())
TOOLCHAIN.update(
    android_gradle_plugin=CATALOG["versions"]["agp"],
    kotlin=CATALOG["versions"]["kotlin"],
)
ASSET_HINT = "Run python3 configs/prepare_assets.py --download."


def digest(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def vendors_manifest():
    return json.loads((ROOT / "third_party/openxr-vendors/manifest.json").read_text())


def verify_vendor_archive(path, record):
    if (
        not path.is_file()
        or path.stat().st_size != record["sizeBytes"]
        or digest(path) != record["sha256"]
    ):
        raise RuntimeError(
            f"Missing or invalid OpenXR addon: {path.name}. {ASSET_HINT}"
        )


def vendors_archive():
    record = vendors_manifest()
    path = ROOT / ".cache/openxr-vendors" / record["fileName"]
    verify_vendor_archive(path, record)
    return path


def prepare_vendor_archive():
    """Explicitly download this one archive; all consumers verify it offline."""
    record = vendors_manifest()
    path = ROOT / ".cache/openxr-vendors" / record["fileName"]
    try:
        verify_vendor_archive(path, record)
        return path
    except RuntimeError:
        pass
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="download-", dir=path.parent) as temporary:
        staging = Path(temporary) / record["fileName"]
        with urlopen(record["url"], timeout=60) as response, staging.open(
            "wb"
        ) as output:
            received = 0
            while chunk := response.read(1024 * 1024):
                received += len(chunk)
                if received > record["sizeBytes"]:
                    raise RuntimeError(
                        "OpenXR addon download exceeds the expected size"
                    )
                output.write(chunk)
        verify_vendor_archive(staging, record)
        os.replace(staging, path)
    return path


def clean_build(root, *, dry_run=False):
    from configs.workspace_lock import workspace_mutation_lock

    with workspace_mutation_lock(root):
        build = root / "build"
        if build.is_symlink():
            raise RuntimeError(f"Refusing to clean symlinked build directory: {build}")
        if dry_run and build.exists():
            print(f"Would remove {build}")
        if build.exists() and not dry_run:
            shutil.rmtree(build)


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
    player.extract(vendors_archive(), destination)
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
