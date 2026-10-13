#!/usr/bin/env python3
# Usage: python3 configs/source_root_workflow.py --init [--native-mpv]
# Usage: python3 configs/source_root_workflow.py --update
"""Prepare dependency inputs online; materialize and verify them offline."""

import sys
from pathlib import Path
from dataclasses import dataclass

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from configs.source_roots import workflow as manager
from configs.dependencies import initialize_packages, prepare_host_assets, select_assets
from freecm.dependency_workflow import DependencyRootWorkflowFacade
from freecm.source_root_workflow import SourceRootWorkflowScript
from freecm.workspace_lock import workspace_mutation_lock


@dataclass(frozen=True)
class Roots:
    dependency_roots: object

    @property
    def lock_data(self):
        return self.dependency_roots.lock_data


class Workflow(DependencyRootWorkflowFacade):
    def init_seed_repositories(self, repo_root=None, **kwargs):
        with workspace_mutation_lock(repo_root or self.repo_root):
            return super().init_seed_repositories(repo_root, **kwargs)

    def _wrap_dependency_roots(self, roots):
        return Roots(roots)


def update_host_assets():
    with workspace_mutation_lock(ROOT):
        prepare_host_assets()
    return 0


workflow = Workflow(manager.config)
script = SourceRootWorkflowScript(
    workflow,
    repo_display_name="Immivio",
    update_callback=update_host_assets,
)


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    refresh = "--refresh-packages" in argv
    if refresh:
        argv.remove("--refresh-packages")
        if "--init" not in argv:
            raise ValueError("--refresh-packages requires --init")
    native = "--native-mpv" in argv
    if native:
        argv.remove("--native-mpv")
        if "--init" not in argv:
            raise ValueError("--native-mpv requires --init")
    if "--init" in argv:
        select_assets(native=native)
    result = script.main(argv)
    if result == 0 and "--init" in argv:
        # Materialization is offline; release FreeCM's lock before package subprocesses.
        workflow.materialize_source_roots(allow_network=False)
        with workspace_mutation_lock(ROOT):
            initialize_packages(refresh_packages=refresh)
    return result


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, ValueError, OSError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
