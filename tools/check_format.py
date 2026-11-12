"""Check tracked project sources using the pinned lint tools (no Android SDK)."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--gdformat", default="gdformat")
    parser.add_argument("--ktfmt", type=Path, default=os.environ.get("KTFMT_JAR"))
    args = parser.parse_args()
    if args.ktfmt is None or not args.ktfmt.is_file():
        parser.error(
            "Supply --ktfmt /path/to/ktfmt.jar or KTFMT_JAR (see configs/lint_tools.json)"
        )
    record = json.loads((ROOT / "configs/lint_tools.json").read_text())["ktfmt"]
    if hashlib.sha256(args.ktfmt.read_bytes()).hexdigest() != record["sha256"]:
        parser.error("ktfmt checksum differs from configs/lint_tools.json")
    files = subprocess.check_output(
        ["git", "ls-files"], cwd=ROOT, text=True
    ).splitlines()
    gdscript = [name for name in files if name.endswith(".gd")]
    kotlin = [name for name in files if name.endswith(".kt")]
    results = [subprocess.run(["ruff", "check", "."], cwd=ROOT).returncode]
    results.append(
        subprocess.run([args.gdformat, "--check", *gdscript], cwd=ROOT).returncode
    )
    with tempfile.TemporaryDirectory(prefix="immivio-lint-") as directory:
        arguments = Path(directory) / "ktfmt.args"
        arguments.write_text(
            "\n".join(
                [
                    "--kotlinlang-style",
                    "--do-not-remove-unused-imports",
                    "--dry-run",
                    "--set-exit-if-changed",
                    *kotlin,
                ]
            )
            + "\n",
            encoding="utf-8",
        )
        results.append(
            subprocess.run(
                ["java", "-jar", str(args.ktfmt.resolve()), "@" + str(arguments)],
                cwd=ROOT,
            ).returncode
        )
    print(
        f"Format checks: {len(gdscript)} GDScript, {len(kotlin)} Kotlin; {sum(bool(code) for code in results)} failed checks"
    )
    raise SystemExit(any(results))


if __name__ == "__main__":
    main()
