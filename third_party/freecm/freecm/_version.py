"""Version helpers for FreeCM."""

from __future__ import annotations

from importlib.metadata import PackageNotFoundError, version
from pathlib import Path


def _source_tree_version() -> str | None:
    version_path = Path(__file__).resolve().parents[1] / "VERSION"
    if not version_path.is_file():
        return None
    value = version_path.read_text(encoding="utf-8").strip()
    return value or None


_source_version = _source_tree_version()
if _source_version is not None:
    __version__ = _source_version
else:
    try:
        __version__ = version("freecm")
    except PackageNotFoundError:
        __version__ = "0+unknown"
