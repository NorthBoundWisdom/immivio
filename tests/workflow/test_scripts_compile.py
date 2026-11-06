"""Compile all checked-in Python benchmark and media-tool entrypoints."""

from pathlib import Path
import py_compile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ScriptsCompile(unittest.TestCase):
    def test_benchmark_and_tool_scripts_compile(self):
        scripts = sorted(
            {
                path
                for pattern in ("benchmarks/*.py", "tools/*.py", "tools/media/*.py")
                for path in ROOT.glob(pattern)
            }
        )
        self.assertTrue(scripts)
        with tempfile.TemporaryDirectory() as folder:
            for index, script in enumerate(scripts):
                with self.subTest(script=script.relative_to(ROOT)):
                    py_compile.compile(
                        str(script),
                        cfile=str(Path(folder) / f"{index}.pyc"),
                        doraise=True,
                    )
