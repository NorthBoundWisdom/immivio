"""Project mutation locks exclude concurrent writers and recover on process exit."""

from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from configs.dependencies import clean_build
from configs.workspace_lock import workspace_mutation_lock

ROOT = Path(__file__).resolve().parents[2]


class WorkspaceLock(unittest.TestCase):
    def test_nested_cleanup_and_exception_release_the_same_workspace(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "build").mkdir()
            with self.assertRaisesRegex(RuntimeError, "fixture"):
                with workspace_mutation_lock(root):
                    clean_build(root)
                    raise RuntimeError("fixture")
            self.assertFalse((root / "build").exists())
            with workspace_mutation_lock(root, timeout_seconds=0):
                pass

    def test_another_thread_cannot_enter_until_the_owner_releases(self):
        with tempfile.TemporaryDirectory() as temporary, ThreadPoolExecutor() as pool:
            root = Path(temporary)

            def enter():
                with workspace_mutation_lock(root, timeout_seconds=0.1):
                    return "entered"

            with workspace_mutation_lock(root):
                with self.assertRaises(TimeoutError):
                    pool.submit(enter).result(timeout=5)
            self.assertEqual(pool.submit(enter).result(timeout=5), "entered")

    def test_process_exit_releases_the_os_lock_without_cleanup(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            process = subprocess.Popen(
                [
                    sys.executable,
                    "-I",
                    "-S",
                    "-c",
                    """
import sys
sys.path.insert(0, sys.argv[1])
from configs.workspace_lock import workspace_mutation_lock
with workspace_mutation_lock(sys.argv[2]):
    print('locked', flush=True)
    sys.stdin.read()
""",
                    str(ROOT),
                    str(root),
                ],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            try:
                with ThreadPoolExecutor() as pool:
                    ready = pool.submit(process.stdout.readline)
                    try:
                        self.assertEqual(ready.result(timeout=10).strip(), "locked")
                        with self.assertRaises(TimeoutError):
                            with workspace_mutation_lock(root, timeout_seconds=0.1):
                                self.fail("Concurrent mutation was allowed")
                    finally:
                        process.kill()
                process.communicate(timeout=10)
                with workspace_mutation_lock(root, timeout_seconds=0.1):
                    pass
            finally:
                if process.poll() is None:
                    process.kill()
                process.communicate(timeout=10)


if __name__ == "__main__":
    unittest.main()
