# Internal: source input lookup for native patch maintenance and regression probes.
from configs.source_roots import workflow
from configs.dependency_manifest import catalog


def source_root(name):
    return workflow.require_dependency_roots().dependency_root_for(name)


def source_commit(name):
    return workflow.require_dependency_roots().resolved_commits[name]


def archived_receipt_hash(name):
    """Historical distribution identity retained only for existing receipt compatibility."""
    return next(
        record["sha256"]
        for record in catalog()["native"]["sourceLock"]["sources"]
        if record["name"] == name
    )
