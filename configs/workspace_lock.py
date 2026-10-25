"""Serialize project mutations with an OS lock released when its process exits."""

from contextlib import contextmanager
import errno
import os
from pathlib import Path
import threading
import time

if os.name == "nt":
    import msvcrt
else:
    import fcntl

_LOCKS = {}
_LOCKS_MUTEX = threading.Lock()
_HELD = threading.local()


@contextmanager
def workspace_mutation_lock(repo_root, *, timeout_seconds=5.0):
    path = Path(repo_root).resolve() / ".immivio.workspace.lock"
    deadline = time.monotonic() + timeout_seconds
    with _LOCKS_MUTEX:
        thread_lock = _LOCKS.setdefault(path, threading.RLock())
    if not thread_lock.acquire(timeout=max(0.0, timeout_seconds)):
        raise TimeoutError(f"Workspace is busy: {path.parent}")
    try:
        held = getattr(_HELD, "paths", set())
        if path in held:
            yield
            return
        path.parent.mkdir(parents=True, exist_ok=True)
        # Keep the file after release so all contenders lock the same inode.
        with path.open("a+b") as stream:
            if stream.tell() == 0:
                stream.write(b"\0")
                stream.flush()
            while True:
                try:
                    if os.name == "nt":
                        stream.seek(0)
                        msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1)
                    else:
                        fcntl.flock(stream.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                    break
                except OSError as error:
                    if error.errno not in (errno.EACCES, errno.EAGAIN, errno.EDEADLK):
                        raise
                    remaining = deadline - time.monotonic()
                    if remaining <= 0:
                        raise TimeoutError(
                            f"Workspace is busy: {path.parent}"
                        ) from error
                    time.sleep(min(0.05, remaining))
            held.add(path)
            _HELD.paths = held
            try:
                yield
            finally:
                held.remove(path)
                if os.name == "nt":
                    stream.seek(0)
                    msvcrt.locking(stream.fileno(), msvcrt.LK_UNLCK, 1)
                else:
                    fcntl.flock(stream.fileno(), fcntl.LOCK_UN)
    finally:
        thread_lock.release()
