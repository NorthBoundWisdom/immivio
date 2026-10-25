#!/usr/bin/env python3
# Usage: python3 configs/prepare_assets.py [--download]
"""Verify the OpenXR addon cache, or explicitly download the recorded archive."""

import argparse
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from configs.dependencies import prepare_vendor_archive, vendors_archive
from configs.workspace_lock import workspace_mutation_lock


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--download", action="store_true", help="Allow downloading the addon"
    )
    args = parser.parse_args(argv)
    with workspace_mutation_lock(ROOT):
        path = prepare_vendor_archive() if args.download else vendors_archive()
    print(f"Verified OpenXR addon: {path}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, ValueError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
