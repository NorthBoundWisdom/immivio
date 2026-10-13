#!/usr/bin/env python3
# Usage: python3 configs/source_root_workflow.py --init|--update|--refreshpin|--pinlatest|--cleanbuild
"""Manage project source roots and OpenXR assets; host tools are preinstalled."""

import sys
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from configs.source_roots import workflow as manager
from freecm.dependency_workflow import DependencyRootWorkflowFacade
from freecm.source_root_workflow import SourceRootWorkflowScript


@dataclass(frozen=True)
class Roots:
    dependency_roots: object

    @property
    def lock_data(self):
        return self.dependency_roots.lock_data


class Workflow(DependencyRootWorkflowFacade):
    def _wrap_dependency_roots(self, roots):
        return Roots(roots)


workflow = Workflow(manager.config)
script = SourceRootWorkflowScript(workflow, repo_display_name="Immivio")


def main(argv=None):
    return script.main(argv)


if __name__ == "__main__":
    raise SystemExit(main())
