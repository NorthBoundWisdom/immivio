#!/usr/bin/env python3
# Usage: python3 tools/validate_repo_commands.py [repo_root]
"""Validate project commands using the bundled FreeCM implementation."""

import argparse
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from configs import FREECM_ROOT
from freecm.errors import RepoCommandManifestError
from freecm.repo_commands import validate_repo_command_manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("repo_root", nargs="?", type=Path, default=ROOT)
    args = parser.parse_args()
    try:
        summary = validate_repo_command_manifest(args.repo_root)
    except RepoCommandManifestError as error:
        print(error, file=sys.stderr)
        return 1
    print(
        f"Validated {summary.manifest_path} "
        f"({summary.configuration_count} Configs, {summary.variant_count} variants)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
