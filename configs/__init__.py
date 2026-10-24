"""Immivio build and dependency workflows."""

from pathlib import Path
import sys

# Always use the open-source snapshot, including on hosts with FreeCM installed.
FREECM_ROOT = Path(__file__).resolve().parents[1] / "third_party/freecm"
sys.path.insert(0, str(FREECM_ROOT))
