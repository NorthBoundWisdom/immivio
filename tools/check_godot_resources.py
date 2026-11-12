"""Find orphan UIDs and Godot scripts/shaders unreachable from app or test/tool roots."""

from __future__ import annotations

import argparse
from collections import deque
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
TEXT_SUFFIXES = {
    ".gd",
    ".gdshader",
    ".gdshaderinc",
    ".tscn",
    ".tres",
    ".godot",
    ".py",
    ".kt",
    ".java",
    ".json",
}


def check(root: Path = ROOT, files: list[str] | None = None) -> list[str]:
    if files is None:
        files = subprocess.check_output(
            ["git", "-C", str(root), "ls-files"], text=True
        ).splitlines()
    known = set(files)
    errors = []
    uids = {}
    for name in files:
        if not name.endswith(".uid"):
            continue
        target = name[:-4]
        if target not in known or not (root / target).is_file():
            errors.append(f"Orphan UID: {name}")
        uid = (root / name).read_text(encoding="utf-8").strip()
        if uid in uids:
            errors.append(f"Duplicate UID: {name} and {uids[uid]}")
        uids[uid] = target
    texts = {}
    for name in files:
        path = root / name
        if path.suffix in TEXT_SUFFIXES and path.is_file():
            texts[name] = path.read_text(encoding="utf-8")
    targets = {
        name
        for name in known
        if name.startswith(("app/godot/scripts/", "app/godot/shaders/"))
        and not name.endswith(".uid")
    }
    classes = {}
    for name in targets:
        match = re.search(r"^class_name\s+(\w+)", texts.get(name, ""), re.M)
        if match:
            classes[match.group(1)] = name
    edges = {}
    for name, text in texts.items():
        references = set()
        for path in re.findall(r"res://([\w./-]+)", text):
            references.add("app/godot/" + path)
        references.update(re.findall(r"app/godot/[\w./-]+", text))
        references.update(
            uids[uid] for uid in re.findall(r"uid://[a-z0-9]+", text) if uid in uids
        )
        references.update(
            path
            for symbol, path in classes.items()
            if re.search(r"\b" + symbol + r"\b", text)
        )
        edges[name] = references & known
    roots = {"app/godot/project.godot"}
    roots.update(
        name
        for name in texts
        if name.startswith(
            ("app/godot/tests/", "tests/", "tools/", "benchmarks/", "configs/")
        )
    )
    reached = set()
    queue = deque(roots)
    while queue:
        name = queue.popleft()
        if name in reached:
            continue
        reached.add(name)
        queue.extend(edges.get(name, set()) - reached)
    errors.extend(
        f"Unreferenced Godot source: {name}" for name in sorted(targets - reached)
    )
    return errors


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    args = parser.parse_args()
    errors = check(args.root)
    for error in errors:
        print(error)
    print(f"Godot resource references: {len(errors)} errors")
    raise SystemExit(bool(errors))


if __name__ == "__main__":
    main()
