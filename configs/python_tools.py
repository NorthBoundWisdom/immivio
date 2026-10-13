#!/usr/bin/env python3
# Usage: python3 configs/python_tools.py run --profile media-tools tools/Generate-StereoFixtures.py [args...]
"""Run auxiliary scripts in an offline environment from the master package lock."""

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import venv

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from configs.dependency_manifest import catalog, generate


def python_path(profile):
    return (
        ROOT
        / ".cache/python-tools"
        / profile
        / ("Scripts/python.exe" if os.name == "nt" else "bin/python")
    )


def prepare(profile, *, online=False):
    spec = catalog()["python"].get(profile)
    if spec is None:
        raise ValueError("Unknown Python profile: " + profile)
    generate()
    requirements = ROOT / f"build/dependency_manifests/python-{profile}.lock.txt"
    wheels = ROOT / "build/dependency_seed_repos/PythonPackages" / profile
    wheels.mkdir(parents=True, exist_ok=True)
    if online:
        subprocess.run(
            [
                sys.executable,
                "-m",
                "pip",
                "download",
                "--only-binary=:all:",
                "--no-deps",
                "--require-hashes",
                "--index-url",
                "https://pypi.org/simple",
                "-r",
                str(requirements),
                "-d",
                str(wheels),
            ],
            check=True,
        )
    executable = python_path(profile)
    if not executable.exists():
        venv.EnvBuilder(with_pip=True).create(executable.parents[1])
    subprocess.run(
        [
            str(executable),
            "-m",
            "pip",
            "install",
            "--no-index",
            "--find-links",
            str(wheels),
            "--require-hashes",
            "--no-deps",
            "-r",
            str(requirements),
        ],
        check=True,
    )
    return executable


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, add_help=False)
    parser.add_argument("command", nargs="?", choices=("run", "verify"))
    parser.add_argument(
        "--profile", choices=tuple(catalog()["python"]), default="media-tools"
    )
    opts, tail = parser.parse_known_args(argv)
    if opts.command is None:
        parser.print_help()
        return 0
    if tail and tail[0] == "--":
        tail = tail[1:]
    executable = python_path(opts.profile)
    if not executable.is_file():
        raise RuntimeError(
            "Initialize Python tools with source_root_workflow.py --init --python-tools"
        )
    if opts.command == "verify":
        code = (
            "from importlib.metadata import version; import json; print(json.dumps({p:version(p) for p in "
            + repr(list(catalog()["python"][opts.profile]["packages"]))
            + "}))"
        )
        installed = json.loads(
            subprocess.check_output([str(executable), "-c", code], text=True)
        )
        if any(
            installed[name] != record["version"]
            for name, record in catalog()["python"][opts.profile]["packages"].items()
        ):
            raise RuntimeError("Python environment differs from the master lock")
    else:
        if not tail:
            parser.error("Specify a script")
        subprocess.run([str(executable), *tail], check=True)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, ValueError, OSError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
