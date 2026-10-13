#!/usr/bin/env python3
# Usage: python3 configs/dependency_manifest.py generate|verify|ci-tools|sdk-packages
"""Render ecosystem input files from the sole reviewed dependency lock.

FreeCM owns Git and asset fields. The namespaced immivio section owns package
manager resolution/checksum data and host requirements; no FreeCM core fork is needed.
"""

import argparse
import hashlib
import json
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "FreeCM"))
from freecm.jsonc import loads_jsonc

GENERATED_HEADER = "# Generated from source_roots.lock.jsonc.in; do not edit.\n"


def template(root=ROOT):
    path = root / "source_roots.lock.jsonc.in"
    data = loads_jsonc(path.read_text(encoding="utf-8"), path_label=str(path))
    if data.get("immivio", {}).get("schemaVersion") != 1:
        raise ValueError(
            "Expected immivio.schemaVersion 1 in source_roots.lock.jsonc.in"
        )
    return data


def catalog(root=ROOT):
    return template(root)["immivio"]


def json_text(value):
    return json.dumps(value, indent=2) + "\n"


def render_catalog(data):
    parts = [GENERATED_HEADER]
    for section, entries in data.items():
        parts.append(f"[{section}]\n")
        for name, value in entries.items():
            if isinstance(value, str):
                parts.append(f"{name} = {json.dumps(value)}\n")
            else:
                fields = []
                for key, val in value.items():
                    if isinstance(val, dict):
                        fields.extend(
                            f"{key}.{k} = {json.dumps(v)}" for k, v in val.items()
                        )
                    else:
                        fields.append(f"{key} = {json.dumps(val)}")
                parts.append(f"{name} = {{ " + ", ".join(fields) + " }\n")
        parts.append("\n")
    return "".join(parts)


def render_verification(components):
    ns = "https://schema.gradle.org/dependency-verification"
    ET.register_namespace("", ns)

    def node(parent, tag, **attrs):
        return ET.SubElement(parent, "{" + ns + "}" + tag, attrs)

    root = ET.Element("{" + ns + "}verification-metadata")
    config = node(root, "configuration")
    node(config, "verify-metadata").text = "true"
    node(config, "verify-signatures").text = "false"
    container = node(root, "components")
    for coordinate, artifacts in sorted(components.items()):
        group, name, version = coordinate.split(":")
        component = node(
            container, "component", group=group, name=name, version=version
        )
        for filename, hashes in sorted(artifacts.items()):
            if not hashes or any(
                not re.fullmatch("[0-9a-f]{64}", sha) for sha in hashes
            ):
                raise ValueError(
                    "Invalid artifact checksum: " + coordinate + "/" + filename
                )
            artifact = node(component, "artifact", name=filename)
            sha = node(
                artifact, "sha256", value=hashes[0], origin="source_roots.lock.jsonc.in"
            )
            for value in hashes[1:]:
                node(sha, "also-trust", value=value)
    ET.indent(root, space="   ")
    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        + ET.tostring(root, encoding="unicode")
        + "\n"
    )


def render_gradle_lock(data):
    lines = [GENERATED_HEADER]
    for coordinate, configs in sorted(data["modules"].items()):
        lines.append(coordinate + "=" + ",".join(configs) + "\n")
    lines.append("empty=" + ",".join(data["empty"]) + "\n")
    return "".join(lines)


def outputs(root=ROOT):
    data = template(root)
    meta = data["immivio"]
    result = {
        "configs/toolchain.json": json_text(meta["toolchain"]),
        "android/gradle/libs.versions.toml": render_catalog(meta["gradle"]["catalog"]),
        "android/gradle/verification-metadata.xml": render_verification(
            meta["gradle"]["verification"]
        ),
        "cloud/openlist/go.mod": "\n".join(meta["go"]["OpenList"]["mod"]) + "\n",
        "cloud/openlist/go.sum": "\n".join(meta["go"]["OpenList"]["sum"]) + "\n",
        "third_party/mpv/source-lock.json": json_text(meta["native"]["sourceLock"]),
        "third_party/mpv/manifest.json": json_text(meta["native"]["binary"]),
    }
    for name, value in meta["gradle"]["locks"].items():
        result[name] = render_gradle_lock(value)
    source = meta["native"]["sourceLock"]
    plan = {key: value for key, value in source.items() if key != "hash_provenance"}
    plan["sources"] = [
        {key: value for key, value in item.items() if key not in ("sha256", "bytes")}
        for item in source["sources"]
    ]
    result["third_party/mpv/source-plan.json"] = json_text(plan)
    for name, spec in meta.get("python", {}).items():
        requirements = [GENERATED_HEADER]
        for package, record in sorted(spec["packages"].items()):
            hashes = sorted({f["sha256"] for f in record["files"]})
            requirements.append(
                package
                + "=="
                + record["version"]
                + " "
                + " ".join("--hash=sha256:" + sha for sha in hashes)
                + "\n"
            )
        result["build/dependency_manifests/python-" + name + ".lock.txt"] = "".join(
            requirements
        )
    if "native-build" in meta.get("python", {}):
        result["tools/environment/mpv-linux/host-tools.lock.txt"] = result[
            "build/dependency_manifests/python-native-build.lock.txt"
        ]
    return result


def safe_path(root, name):
    path = (root / name).resolve()
    if not path.is_relative_to(root.resolve()):
        raise ValueError("Generated path escapes repository")
    return path


def generate(root=ROOT):
    for name, text in outputs(root).items():
        path = safe_path(root, name)
        path.parent.mkdir(parents=True, exist_ok=True)
        if path.exists() and path.read_text(encoding="utf-8") == text:
            continue
        pending = path.with_name(path.name + ".pending")
        pending.write_text(text, encoding="utf-8")
        pending.replace(path)


def verify(root=ROOT):
    errors = []
    for name, text in outputs(root).items():
        path = safe_path(root, name)
        if not path.is_file() or path.read_text(encoding="utf-8") != text:
            errors.append(name)
    for name, record in catalog(root)["vendored"].items():
        for filename, expected in record["files"].items():
            path = safe_path(root, filename)
            if (
                not path.is_file()
                or path.stat().st_size != expected["sizeBytes"]
                or hashlib.file_digest(path.open("rb"), "sha256").hexdigest()
                != expected["sha256"]
            ):
                errors.append(name + ": " + filename)
    if errors:
        raise RuntimeError(
            "Dependency inputs differ from the master lock; run --update:\n"
            + "\n".join(errors)
        )


def capture_gradle(root=ROOT):
    """Explicit --init --refresh-packages harvest; writes only the master lock."""
    data = template(root)
    gradle = data["immivio"]["gradle"]
    ns = {"v": "https://schema.gradle.org/dependency-verification"}
    xml = ET.parse(root / "android/gradle/verification-metadata.xml").getroot()
    components = {}
    for component in xml.findall("v:components/v:component", ns):
        coordinate = ":".join(
            component.get(key) for key in ("group", "name", "version")
        )
        components[coordinate] = {}
        for artifact in component:
            hashes = []
            for sha in artifact.findall("v:sha256", ns):
                hashes.append(sha.get("value"))
                hashes.extend(child.get("value") for child in sha)
            components[coordinate][artifact.get("name")] = sorted(set(hashes))
    gradle["verification"] = components
    for filename in list(gradle["locks"]):
        path = root / filename
        if not path.is_file():
            continue
        modules = {}
        empty = []
        for line in path.read_text().splitlines():
            if not line or line.startswith("#"):
                continue
            key, configs = line.split("=", 1)
            if key == "empty":
                empty = configs.split(",") if configs else []
            else:
                modules[key] = configs.split(",")
        gradle["locks"][filename] = {"modules": modules, "empty": empty}
    path = root / "source_roots.lock.jsonc.in"
    pending = path.with_suffix(".pending")
    pending.write_text(json_text(data))
    pending.replace(path)
    generate(root)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "command",
        choices=("generate", "verify", "ci-tools", "sdk-packages", "toolchain-json"),
    )
    args = parser.parse_args(argv)
    if args.command == "generate":
        generate()
    elif args.command == "verify":
        verify()
        print("Master dependency lock and generated inputs verified")
    else:
        tools = catalog()["toolchain"]
        if args.command == "toolchain-json":
            print(json.dumps(tools))
        elif args.command == "ci-tools":
            for name in ("python", "java", "go"):
                print(name + "=" + tools[name])
            print(
                "android_command_line_tools=" + tools["android"]["command_line_tools"]
            )
        else:
            android = tools["android"]
            print(
                "\n".join(
                    [
                        "platform-tools",
                        "platforms;android-" + str(android["platform"]),
                        "build-tools;" + android["build_tools"],
                        "ndk;" + android["ndk"],
                        "cmake;" + android["cmake"],
                    ]
                )
            )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, RuntimeError, OSError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
