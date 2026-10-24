"""Provenance for the bundled FreeCM subset; no upstream checkout is required."""

import hashlib
import json

from configs import FREECM_ROOT


def provenance():
    metadata = json.loads((FREECM_ROOT / "UPSTREAM.json").read_text(encoding="utf-8"))
    fingerprint = hashlib.sha256()
    for path in sorted(FREECM_ROOT.rglob("*")):
        if not path.is_file() or "__pycache__" in path.parts:
            continue
        if path.suffix not in (".py", ".json", ".md") and path.name not in (
            "LICENSE",
            "VERSION",
        ):
            continue
        fingerprint.update(path.relative_to(FREECM_ROOT).as_posix().encode("utf-8"))
        fingerprint.update(b"\0")
        fingerprint.update(hashlib.sha256(path.read_bytes()).digest())
    return {"commit": metadata["commit"], "sha256": fingerprint.hexdigest()}
