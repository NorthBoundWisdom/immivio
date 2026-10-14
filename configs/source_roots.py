#!/usr/bin/env python3
# Usage: python3 configs/source_roots.py show --format json
"""FreeCM dependency roots and offline diagnostics for Immivio."""

import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
FREECM_ROOT = REPO_ROOT / "FreeCM"
if not (FREECM_ROOT / "freecm").is_dir():
    raise RuntimeError("Initialize FreeCM: git submodule update --init FreeCM")
sys.path.insert(0, str(FREECM_ROOT))
sys.path.insert(0, str(REPO_ROOT))
from freecm.dependency_roots import (
    DependencyRootConfig,
    DependencyRootSpec,
    bind_dependency_root_workflow,
)

workflow = bind_dependency_root_workflow(
    globals(),
    DependencyRootConfig(
        repo_root=REPO_ROOT,
        repo_display_name="Immivio",
        dependency_root_specs=(
            DependencyRootSpec(
                "OpenList",
                "OpenList",
                "OPENLIST_SOURCE_ROOT",
                ("go.mod", "go.sum", "internal/model/storage.go", "LICENSE"),
            ),
        ),
        default_required_relative_paths=(),
    ),
)

if __name__ == "__main__":
    if "verify" in sys.argv[1:]:
        from freecm.asset_seeds import require_asset_seeds

        require_asset_seeds(REPO_ROOT)
    raise SystemExit(workflow.main())
