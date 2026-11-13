"""Inventory direct private-member access in Godot tests, excluding strings/comments."""

from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
LITERALS = re.compile(
    r'"""[\s\S]*?"""|\x27\x27\x27[\s\S]*?\x27\x27\x27'
    r'|"(?:\\[\s\S]|[^"\\])*"|\x27(?:\\[\s\S]|[^\x27\\])*\x27|\#[^\n]*'
)
ACCESS = re.compile(r"\.\s*(_[A-Za-z]\w*)\b")


def inventory(root: Path) -> dict:
    counts: Counter = Counter()
    files: dict[str, Counter] = defaultdict(Counter)
    scripts = sorted((root / "app/godot/tests").rglob("*.gd"))
    for path in scripts:
        code = LITERALS.sub(
            lambda match: re.sub(r"[^\n]", " ", match[0]),
            path.read_text(encoding="utf-8"),
        )
        for match in ACCESS.finditer(code):
            member = match[1]
            counts[member] += 1
            files[member][path.relative_to(root).as_posix()] += 1
    rows = [
        {
            "member": member,
            "accesses": count,
            "tests": [
                {"file": path, "accesses": accesses}
                for path, accesses in sorted(files[member].items())
            ],
        }
        for member, count in sorted(
            counts.items(), key=lambda item: (-item[1], item[0])
        )
    ]
    return {
        "schema_version": 1,
        "scope": "All app/godot/tests/**/*.gd; direct dot-member accesses only; strings/comments excluded",
        "scripts_scanned": len(scripts),
        "scripts_with_private_access": len(
            {p for values in files.values() for p in values}
        ),
        "total_accesses": sum(counts.values()),
        "members": rows,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--check-baseline", type=Path)
    args = parser.parse_args()
    result = inventory(ROOT)
    result["source_commit"] = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True
    ).strip()
    result["source_dirty"] = bool(
        subprocess.check_output(
            ["git", "status", "--porcelain", "--", "app/godot/tests"],
            cwd=ROOT,
            text=True,
        )
    )
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(
            json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
    print(
        f"Godot private access: {result['total_accesses']} references to "
        f"{len(result['members'])} members in {result['scripts_with_private_access']} scripts"
    )
    if args.check_baseline:
        baseline = json.loads(args.check_baseline.read_text(encoding="utf-8"))
        targets = {row["member"] for row in baseline["members"][:20]}
        remaining = [row for row in result["members"] if row["member"] in targets]
        for row in remaining:
            print(f"{row['member']}: {row['accesses']} remaining references")
        if remaining:
            raise SystemExit(1)
        print("Baseline's 20 most-accessed private members: 0 remaining references")


if __name__ == "__main__":
    main()
