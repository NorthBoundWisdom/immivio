# Internal: workspace-level mutation locking shared by FreeCM workflows.

from __future__ import annotations

import errno
import hashlib
import json
import os
import secrets
import shutil
import socket
import subprocess  # nosec B404
import sys
import threading
import time
from collections.abc import Callable, Iterator
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Literal, cast

# Immivio uses only the workspace lock, independently of FreeCM source-root locks.
# Preserve the upstream protocol so existing command clients share the same lock.
WORKSPACE_LOCK_NAME = ".freecm.workspace.lock"
WORKSPACE_LOCK_OWNER_FILE_NAME = "owner.json"
WORKSPACE_LOCK_PROTOCOL_VERSION = 1
WORKSPACE_LOCK_TIMEOUT_MS = 5000
WORKSPACE_LOCK_RETRY_DELAY_MS = 50
WORKSPACE_LOCK_INITIALIZATION_GRACE_MS = 2000
WORKSPACE_LOCK_CONTRACT = {
    "schemaVersion": WORKSPACE_LOCK_PROTOCOL_VERSION,
    "ownerFileName": WORKSPACE_LOCK_OWNER_FILE_NAME,
    "timeoutMs": WORKSPACE_LOCK_TIMEOUT_MS,
    "retryDelayMs": WORKSPACE_LOCK_RETRY_DELAY_MS,
    "initializationGraceMs": WORKSPACE_LOCK_INITIALIZATION_GRACE_MS,
}

_RECLAIM_CLAIM_FILE_NAME = ".reclaim"
_ABANDONED_MARKER_PREFIX = ".abandoned."
_OWNER_PROBE_INTERVAL_SECONDS = 0.25
_WINDOWS_RENAME_RETRY_DELAYS_SECONDS = (0.01, 0.02, 0.04, 0.08, 0.1)
_HELD_WORKSPACE_LOCKS: dict[Path, tuple[int, int, str]] = {}
_HELD_WORKSPACE_LOCKS_MUTEX = threading.Lock()
_CURRENT_PROCESS_START_TOKEN: str | None = None
_CURRENT_PROCESS_START_TOKEN_INITIALIZED = False
_CURRENT_PROCESS_START_TOKEN_PID: int | None = None

ProcessState = Literal["live", "dead", "unknown"]


@dataclass(frozen=True)
class WorkspaceLockOwner:
    token: str
    pid: int
    process_start_token: str | None
    hostname: str
    implementation: str
    acquired_at: str

    def as_json_dict(self) -> dict[str, object]:
        return {
            "schemaVersion": WORKSPACE_LOCK_PROTOCOL_VERSION,
            "token": self.token,
            "pid": self.pid,
            "processStartToken": self.process_start_token,
            "hostname": self.hostname,
            "implementation": self.implementation,
            "acquiredAt": self.acquired_at,
        }

    @classmethod
    def from_json_dict(cls, data: object) -> WorkspaceLockOwner:
        if not isinstance(data, dict):
            raise ValueError("expected object")
        if data.get("schemaVersion") != WORKSPACE_LOCK_PROTOCOL_VERSION:
            raise ValueError("unsupported schemaVersion")
        token = data.get("token")
        pid = data.get("pid")
        process_start_token = data.get("processStartToken")
        hostname = data.get("hostname")
        implementation = data.get("implementation")
        acquired_at = data.get("acquiredAt")
        if not isinstance(token, str) or not token:
            raise ValueError("invalid token")
        if not isinstance(pid, int) or isinstance(pid, bool) or pid <= 0:
            raise ValueError("invalid pid")
        if process_start_token is not None and (
            not isinstance(process_start_token, str) or not process_start_token
        ):
            raise ValueError("invalid processStartToken")
        if not isinstance(hostname, str) or not hostname:
            raise ValueError("invalid hostname")
        if not isinstance(implementation, str) or not implementation:
            raise ValueError("invalid implementation")
        if not isinstance(acquired_at, str) or not acquired_at:
            raise ValueError("invalid acquiredAt")
        return cls(
            token=token,
            pid=pid,
            process_start_token=process_start_token,
            hostname=hostname,
            implementation=implementation,
            acquired_at=acquired_at,
        )


def workspace_lock_path(repo_root: Path) -> Path:
    return repo_root.resolve() / WORKSPACE_LOCK_NAME


@contextmanager
def workspace_mutation_lock(
    repo_root: Path,
    *,
    timeout_seconds: float = WORKSPACE_LOCK_TIMEOUT_MS / 1000.0,
    poll_seconds: float = WORKSPACE_LOCK_RETRY_DELAY_MS / 1000.0,
    initialization_grace_seconds: float = WORKSPACE_LOCK_INITIALIZATION_GRACE_MS / 1000.0,
) -> Iterator[None]:
    lock_path = workspace_lock_path(repo_root)
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    _acquire_workspace_lock(
        lock_path,
        timeout_seconds=timeout_seconds,
        poll_seconds=poll_seconds,
        initialization_grace_seconds=initialization_grace_seconds,
    )
    try:
        yield
    finally:
        _release_workspace_lock(lock_path)


def _acquire_workspace_lock(
    lock_path: Path,
    *,
    timeout_seconds: float,
    poll_seconds: float = WORKSPACE_LOCK_RETRY_DELAY_MS / 1000.0,
    initialization_grace_seconds: float = WORKSPACE_LOCK_INITIALIZATION_GRACE_MS / 1000.0,
) -> None:
    thread_id = threading.get_ident()
    deadline = time.monotonic() + timeout_seconds
    owner_probe_cache: dict[str, tuple[float, bool]] = {}
    while True:
        with _HELD_WORKSPACE_LOCKS_MUTEX:
            held = _HELD_WORKSPACE_LOCKS.get(lock_path)
            if held is not None and held[0] == thread_id:
                _HELD_WORKSPACE_LOCKS[lock_path] = (thread_id, held[1] + 1, held[2])
                return
            held_by_other_thread = held is not None

        if held_by_other_thread:
            if time.monotonic() >= deadline:
                raise TimeoutError(_timeout_message(lock_path, _read_owner(lock_path))) from None
            time.sleep(max(0.0, min(poll_seconds, deadline - time.monotonic())))
            continue

        owner = _new_owner()
        try:
            lock_path.mkdir()
        except FileExistsError:
            observed_owner = _read_owner(lock_path)
            observed_identity = _path_identity(lock_path)
            stale = observed_owner is not None and (
                _owner_is_abandoned(lock_path, observed_owner)
                or _owner_is_stale_throttled(
                    observed_owner,
                    owner_probe_cache,
                )
            )
            invalid_mature = (
                observed_owner is None
                and observed_identity is not None
                and _lock_age_seconds(lock_path) >= initialization_grace_seconds
            )
            if (stale or invalid_mature) and _try_reclaim_lock(
                lock_path,
                observed_owner=observed_owner,
                observed_identity=observed_identity,
                invalid_mature=invalid_mature,
            ):
                continue
            if time.monotonic() >= deadline:
                raise TimeoutError(_timeout_message(lock_path, observed_owner)) from None
            time.sleep(max(0.0, min(poll_seconds, deadline - time.monotonic())))
            continue

        _write_owner(lock_path, owner)
        if not _confirm_new_owner(
            lock_path,
            owner,
            deadline=deadline,
            poll_seconds=poll_seconds,
        ):
            continue
        with _HELD_WORKSPACE_LOCKS_MUTEX:
            _HELD_WORKSPACE_LOCKS[lock_path] = (thread_id, 1, owner.token)
        return


def _release_workspace_lock(lock_path: Path) -> None:
    thread_id = threading.get_ident()
    with _HELD_WORKSPACE_LOCKS_MUTEX:
        held = _HELD_WORKSPACE_LOCKS.get(lock_path)
        if held is None or held[0] != thread_id:
            raise RuntimeError(f"Workspace lock is not held by this thread: {lock_path}")
        if held[1] > 1:
            _HELD_WORKSPACE_LOCKS[lock_path] = (thread_id, held[1] - 1, held[2])
            return
        token = held[2]

    owner = _read_owner(lock_path)
    if owner is None or owner.token != token:
        _forget_held_workspace_lock(lock_path, thread_id, token)
        raise RuntimeError(
            f"Workspace lock ownership changed before release: {lock_path}; "
            f"current owner: {_format_owner(owner)}"
        )
    tombstone = lock_path.with_name(f"{lock_path.name}.released.{token}")
    try:
        _rename_workspace_lock(lock_path, tombstone)
    except OSError as error:
        _mark_new_owner_abandoned(lock_path, owner)
        _forget_held_workspace_lock(lock_path, thread_id, token)
        raise RuntimeError(f"Unable to retire workspace lock: {lock_path}") from error
    _forget_held_workspace_lock(lock_path, thread_id, token)
    shutil.rmtree(tombstone)


def _forget_held_workspace_lock(lock_path: Path, thread_id: int, token: str) -> None:
    with _HELD_WORKSPACE_LOCKS_MUTEX:
        held = _HELD_WORKSPACE_LOCKS.get(lock_path)
        if held is not None and held[0] == thread_id and held[2] == token:
            del _HELD_WORKSPACE_LOCKS[lock_path]


def _rename_workspace_lock(lock_path: Path, tombstone: Path) -> None:
    for retry_delay in (*_WINDOWS_RENAME_RETRY_DELAYS_SECONDS, None):
        try:
            lock_path.rename(tombstone)
            return
        except OSError as error:
            if retry_delay is None or not _is_transient_windows_rename_error(error):
                raise
            time.sleep(retry_delay)


def _is_transient_windows_rename_error(error: OSError) -> bool:
    return os.name == "nt" and (
        error.errno in {errno.EACCES, errno.EBUSY, errno.EPERM}
        or getattr(error, "winerror", None) in {5, 32, 33}
    )


def _new_owner() -> WorkspaceLockOwner:
    return WorkspaceLockOwner(
        token=secrets.token_hex(16),
        pid=os.getpid(),
        process_start_token=_current_process_start_token(),
        hostname=_normalized_hostname(),
        implementation="python",
        acquired_at=datetime.now(timezone.utc)
        .isoformat(timespec="milliseconds")
        .replace("+00:00", "Z"),
    )


def _write_owner(lock_path: Path, owner: WorkspaceLockOwner) -> None:
    _write_owner_path(lock_path / WORKSPACE_LOCK_OWNER_FILE_NAME, owner)


def _write_owner_path(owner_path: Path, owner: WorkspaceLockOwner) -> None:
    with owner_path.open("x", encoding="utf-8") as owner_file:
        json.dump(owner.as_json_dict(), owner_file, sort_keys=True)
        owner_file.write("\n")
        owner_file.flush()
        os.fsync(owner_file.fileno())


def _confirm_new_owner(
    lock_path: Path,
    owner: WorkspaceLockOwner,
    *,
    deadline: float,
    poll_seconds: float,
) -> bool:
    claim_path = lock_path / _RECLAIM_CLAIM_FILE_NAME
    while True:
        current_owner = _read_owner(lock_path)
        if current_owner is None or current_owner.token != owner.token:
            return False
        if not claim_path.exists():
            return True
        if time.monotonic() >= deadline:
            claim_owner = _read_owner_path(claim_path)
            _mark_new_owner_abandoned(lock_path, owner)
            raise TimeoutError(
                f"Unable to acquire workspace lock: {lock_path}; "
                f"active reclaimer: {_format_reclaimer(claim_owner)}"
            )
        time.sleep(max(0.0, min(poll_seconds, deadline - time.monotonic())))


def _mark_new_owner_abandoned(lock_path: Path, owner: WorkspaceLockOwner) -> bool:
    marker_path = _abandoned_marker_path(lock_path, owner.token)
    try:
        with marker_path.open("x", encoding="utf-8") as marker_file:
            marker_file.flush()
            os.fsync(marker_file.fileno())
        return True
    except FileExistsError:
        return True
    except OSError:
        return False


def _owner_is_abandoned(lock_path: Path, owner: WorkspaceLockOwner) -> bool:
    return _abandoned_marker_path(lock_path, owner.token).is_file()


def _abandoned_marker_path(lock_path: Path, owner_token: str) -> Path:
    token_digest = hashlib.sha256(owner_token.encode("utf-8")).hexdigest()
    return lock_path / f"{_ABANDONED_MARKER_PREFIX}{token_digest}"


def _read_owner(lock_path: Path) -> WorkspaceLockOwner | None:
    return _read_owner_path(lock_path / WORKSPACE_LOCK_OWNER_FILE_NAME)


def _read_owner_path(owner_path: Path) -> WorkspaceLockOwner | None:
    try:
        data = json.loads(owner_path.read_text(encoding="utf-8"))
        return WorkspaceLockOwner.from_json_dict(data)
    except (OSError, ValueError):
        return None


def _owner_is_stale(owner: WorkspaceLockOwner) -> bool:
    if owner.hostname != _normalized_hostname():
        return False
    state, process_start_token = _process_identity(owner.pid)
    if state == "dead":
        return True
    if state != "live":
        return False
    return (
        owner.process_start_token is not None
        and process_start_token is not None
        and owner.process_start_token != process_start_token
    )


def _owner_is_stale_throttled(
    owner: WorkspaceLockOwner,
    cache: dict[str, tuple[float, bool]],
) -> bool:
    now = time.monotonic()
    cached = cache.get(owner.token)
    if cached is not None and now - cached[0] < _OWNER_PROBE_INTERVAL_SECONDS:
        return cached[1]
    stale = _owner_is_stale(owner)
    cache.clear()
    cache[owner.token] = (now, stale)
    return stale


def _try_reclaim_lock(
    lock_path: Path,
    *,
    observed_owner: WorkspaceLockOwner | None,
    observed_identity: tuple[int, int] | None,
    invalid_mature: bool,
) -> bool:
    claim_owner = _acquire_reclaim_claim(lock_path)
    if claim_owner is None:
        return False
    claim_path = lock_path / _RECLAIM_CLAIM_FILE_NAME

    try:
        current_owner = _read_owner(lock_path)
        same_generation = (
            observed_identity is not None and _path_identity(lock_path) == observed_identity
        )
        if observed_owner is None:
            should_reclaim = same_generation and (
                (invalid_mature and current_owner is None)
                or (current_owner is not None and _owner_is_abandoned(lock_path, current_owner))
            )
        else:
            should_reclaim = (
                current_owner is not None
                and current_owner.token == observed_owner.token
                and (
                    _owner_is_abandoned(lock_path, current_owner) or _owner_is_stale(current_owner)
                )
            )
        if not should_reclaim:
            return False

        current_claim = _read_owner_path(claim_path)
        if current_claim is None or current_claim.token != claim_owner.token:
            return False

        tombstone = lock_path.with_name(f"{lock_path.name}.stale.{claim_owner.token}")
        try:
            lock_path.rename(tombstone)
        except OSError:
            return False
        shutil.rmtree(tombstone)
        return True
    finally:
        _remove_claim_if_owned(claim_path, claim_owner.token)


def _acquire_reclaim_claim(lock_path: Path) -> WorkspaceLockOwner | None:
    claim_path = lock_path / _RECLAIM_CLAIM_FILE_NAME
    claim_owner = _new_owner()
    try:
        _publish_owner_path(claim_path, claim_owner)
        return claim_owner
    except FileExistsError:
        observed_owner = _read_owner_path(claim_path)
        if observed_owner is not None and _owner_is_stale(observed_owner):
            _remove_stale_claim(
                claim_path,
                observed_owner=observed_owner,
            )
        return None
    except OSError:
        return None


def _remove_stale_claim(
    claim_path: Path,
    *,
    observed_owner: WorkspaceLockOwner,
) -> None:
    current_owner = _read_owner_path(claim_path)
    removable = (
        current_owner is not None
        and current_owner.token == observed_owner.token
        and _owner_is_stale(current_owner)
    )
    if not removable:
        return

    tombstone = claim_path.with_name(f"{claim_path.name}.stale.{secrets.token_hex(16)}")
    try:
        claim_path.rename(tombstone)
    except OSError:
        return
    moved_owner = _read_owner_path(tombstone)
    if moved_owner is not None and moved_owner.token == observed_owner.token:
        try:
            tombstone.unlink()
        except OSError:
            pass
        return
    try:
        tombstone.rename(claim_path)
    except OSError:
        pass


def _publish_owner_path(owner_path: Path, owner: WorkspaceLockOwner) -> None:
    candidate_path = owner_path.with_name(f"{owner_path.name}.candidate.{owner.token}")
    try:
        _write_owner_path(candidate_path, owner)
        os.link(candidate_path, owner_path)
    finally:
        try:
            candidate_path.unlink()
        except OSError:
            pass


def _remove_claim_if_owned(claim_path: Path, claim_token: str) -> None:
    try:
        owner = _read_owner_path(claim_path)
        if owner is not None and owner.token == claim_token:
            claim_path.unlink()
    except OSError:
        pass


def _lock_age_seconds(lock_path: Path) -> float:
    return _path_age_seconds(lock_path)


def _path_age_seconds(path: Path) -> float:
    try:
        return max(0.0, time.time() - path.stat().st_mtime)
    except OSError:
        return 0.0


def _path_identity(path: Path) -> tuple[int, int] | None:
    try:
        stat = path.stat()
        return stat.st_dev, stat.st_ino
    except OSError:
        return None


def _timeout_message(
    lock_path: Path,
    owner: WorkspaceLockOwner | None,
) -> str:
    return (
        f"Unable to acquire workspace lock: {lock_path}; " f"current owner: {_format_owner(owner)}"
    )


def _format_owner(owner: WorkspaceLockOwner | None) -> str:
    if owner is None:
        return "missing or invalid owner metadata"
    return (
        f"pid={owner.pid}, hostname={owner.hostname}, "
        f"processStartToken={owner.process_start_token or '<unknown>'}, "
        f"implementation={owner.implementation}, acquiredAt={owner.acquired_at}"
    )


def _format_reclaimer(owner: WorkspaceLockOwner | None) -> str:
    if owner is None:
        return "invalid reclaimer metadata"
    return _format_owner(owner)


def _normalized_hostname() -> str:
    return socket.gethostname().strip().lower()


def _current_process_start_token() -> str | None:
    global _CURRENT_PROCESS_START_TOKEN
    global _CURRENT_PROCESS_START_TOKEN_INITIALIZED
    global _CURRENT_PROCESS_START_TOKEN_PID
    current_pid = os.getpid()
    if _CURRENT_PROCESS_START_TOKEN_INITIALIZED and _CURRENT_PROCESS_START_TOKEN_PID == current_pid:
        return _CURRENT_PROCESS_START_TOKEN
    _, token = _process_identity(current_pid)
    _CURRENT_PROCESS_START_TOKEN = token
    _CURRENT_PROCESS_START_TOKEN_INITIALIZED = True
    _CURRENT_PROCESS_START_TOKEN_PID = current_pid
    return token


def _process_identity(pid: int) -> tuple[ProcessState, str | None]:
    if pid <= 0:
        return "dead", None
    if os.name == "nt":
        return _windows_process_identity(pid)
    if sys.platform == "linux":
        return _linux_process_identity(pid)
    if sys.platform == "darwin":
        return _darwin_process_identity(pid)
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return "dead", None
    except PermissionError:
        return "unknown", None
    except OSError:
        return "unknown", None
    return "live", None


def _linux_process_identity(pid: int) -> tuple[ProcessState, str | None]:
    try:
        stat_text = Path(f"/proc/{pid}/stat").read_text(encoding="utf-8")
    except FileNotFoundError:
        return "dead", None
    except (PermissionError, OSError):
        return "unknown", None
    closing_parenthesis = stat_text.rfind(")")
    fields = stat_text[closing_parenthesis + 1 :].split()
    if closing_parenthesis < 0 or len(fields) <= 19:
        return "unknown", None
    try:
        boot_id = Path("/proc/sys/kernel/random/boot_id").read_text(encoding="utf-8").strip()
    except OSError:
        return "live", None
    if not boot_id:
        return "live", None
    return "live", f"linux:{boot_id}:{fields[19]}"


def _darwin_process_identity(pid: int) -> tuple[ProcessState, str | None]:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return "dead", None
    except PermissionError:
        return "unknown", None
    except OSError:
        return "unknown", None
    try:
        # The command and argv are fixed, and pid is already an integer.
        completed = subprocess.run(  # nosec B603 B607
            ["ps", "-p", str(pid), "-o", "lstart="],
            check=False,
            capture_output=True,
            text=True,
            timeout=2.0,
            env={**os.environ, "LC_ALL": "C"},
        )
    except (OSError, subprocess.SubprocessError):
        return "live", None
    token = completed.stdout.strip()
    return ("live", f"darwin:{token}" if completed.returncode == 0 and token else None)


def _windows_process_identity(pid: int) -> tuple[ProcessState, str | None]:
    import ctypes
    from ctypes import wintypes

    process_query_limited_information = 0x1000
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)  # type: ignore[attr-defined]
    kernel32.OpenProcess.restype = wintypes.HANDLE
    kernel32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    kernel32.GetProcessTimes.restype = wintypes.BOOL
    kernel32.GetProcessTimes.argtypes = [
        wintypes.HANDLE,
        ctypes.POINTER(wintypes.FILETIME),
        ctypes.POINTER(wintypes.FILETIME),
        ctypes.POINTER(wintypes.FILETIME),
        ctypes.POINTER(wintypes.FILETIME),
    ]
    kernel32.GetExitCodeProcess.restype = wintypes.BOOL
    kernel32.GetExitCodeProcess.argtypes = [wintypes.HANDLE, ctypes.POINTER(wintypes.DWORD)]
    kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
    handle = kernel32.OpenProcess(process_query_limited_information, False, pid)
    if not handle:
        get_last_error = cast(Callable[[], int], vars(ctypes)["get_last_error"])
        return ("dead", None) if get_last_error() == 87 else ("unknown", None)
    try:
        creation = wintypes.FILETIME()
        exit_time = wintypes.FILETIME()
        kernel = wintypes.FILETIME()
        user = wintypes.FILETIME()
        if not kernel32.GetProcessTimes(
            handle,
            ctypes.byref(creation),
            ctypes.byref(exit_time),
            ctypes.byref(kernel),
            ctypes.byref(user),
        ):
            return "unknown", None
        value = (creation.dwHighDateTime << 32) | creation.dwLowDateTime
        exit_code = wintypes.DWORD()
        if not kernel32.GetExitCodeProcess(handle, ctypes.byref(exit_code)):
            return "unknown", None
        still_active = 259
        if exit_code.value != still_active:
            return "dead", None
        return "live", f"windows:{value}"
    finally:
        kernel32.CloseHandle(handle)


__all__ = (
    "WORKSPACE_LOCK_CONTRACT",
    "WORKSPACE_LOCK_NAME",
    "WORKSPACE_LOCK_OWNER_FILE_NAME",
    "WorkspaceLockOwner",
    "workspace_lock_path",
    "workspace_mutation_lock",
)
