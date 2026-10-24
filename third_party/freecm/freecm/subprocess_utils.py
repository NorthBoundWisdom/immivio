"""Subprocess execution utilities."""

from __future__ import annotations

import subprocess  # nosec B404
from collections.abc import Sequence
from pathlib import Path


def run_logged_command(
    cmd: Sequence[str],
    *,
    cwd: Path | None = None,
    env: dict[str, str] | None = None,
    check: bool = True,
    prefix: str = ">> ",
) -> subprocess.CompletedProcess[str]:
    """Execute a subprocess command while printing it to stdout."""
    print(f"{prefix}{' '.join(str(c) for c in cmd)}")
    return subprocess.run(  # nosec B603
        [str(c) for c in cmd],
        cwd=str(cwd) if cwd else None,
        env=env,
        check=check,
        text=True,
    )
