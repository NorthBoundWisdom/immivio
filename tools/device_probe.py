"""Shared ADB transport, APK identity and request/report evidence for device probes."""

from __future__ import annotations

from contextlib import contextmanager
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = "com.northboundwisdom.immivio"
RECEIVER = "org.vrpassthroughplayer.plugin.DebugDiagnosticsReceiver"
PLAYER_FIXTURES = (
    "mp03_frame_identity",
    "mp06_text_subtitles",
    "mp08_8k_high_30",
    "mpv_performance",
)


def output_directory(value: Path | str | None, probe: str) -> Path:
    base = (ROOT / "artifacts/captures/device").resolve()
    name = (
        datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        + "-"
        + uuid.uuid4().hex[:8]
    )
    target = Path(value).resolve() if value else base / probe / name
    target = target.resolve()
    if not target.is_relative_to(base):
        raise ValueError("Probe output must be under artifacts/captures/device/")
    target.mkdir(parents=True, exist_ok=True)
    return target


@contextmanager
def device_lock(serial: str):
    directory = ROOT / ".cache"
    directory.mkdir(exist_ok=True)
    key = hashlib.sha256(serial.encode()).hexdigest()[:16]
    with (directory / f"playback-{key}.lock").open("a+b") as lock:
        try:
            if os.name == "nt":
                import msvcrt

                if lock.seek(0, 2) == 0:
                    lock.write(b"0")
                    lock.flush()
                lock.seek(0)
                msvcrt.locking(lock.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl

                fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as error:
            raise RuntimeError("Another probe owns this device") from error
        yield


class Device:
    def __init__(self, adb, serial, output, *, package=PACKAGE, port=5037):
        if not serial or not re.fullmatch(
            r"[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+", package
        ):
            raise ValueError("Need an explicit serial and Android package name")
        self.base = [str(adb), "-P", str(port), "-s", str(serial)]
        self.package = package
        self.output = Path(output)
        self.output.mkdir(parents=True, exist_ok=True)
        self.process = None
        self.last_report = None

    def adb_bytes(self, *args, optional=False, timeout=35):
        try:
            result = subprocess.run(
                [*self.base, *map(str, args)], capture_output=True, timeout=timeout
            )
        except subprocess.TimeoutExpired as error:
            raise TimeoutError(
                f"ADB command timed out after {timeout} seconds"
            ) from error
        if result.returncode and not optional:
            raise RuntimeError(
                (result.stderr + result.stdout).decode("utf-8", errors="replace")
            )
        return result.stdout if result.returncode == 0 else b""

    def run(self, *args, optional=False, timeout=35):
        """Raw ADB arguments; use shell() for individually quoted shell arguments."""
        return self.adb_bytes(*args, optional=optional, timeout=timeout).decode(
            "utf-8-sig", errors="replace"
        )

    def stream(self, *args, source, timeout=180):
        """Stream original media without loading or rewriting it on the host."""
        with Path(source).open("rb") as stream:
            try:
                result = subprocess.run(
                    [*self.base, *map(str, args)],
                    stdin=stream,
                    capture_output=True,
                    timeout=timeout,
                )
            except subprocess.TimeoutExpired as error:
                raise TimeoutError(
                    f"ADB stream timed out after {timeout} seconds"
                ) from error
        if result.returncode:
            raise RuntimeError(
                (result.stderr + result.stdout).decode("utf-8", errors="replace")
            )

    def _shell_text(self, *args, optional=False):
        return self.run("shell", shlex.join(list(map(str, args))), optional=optional)

    def shell(self, *args, optional=False):
        return self._shell_text(*args, optional=optional)

    def read(self, filename, *, package=None):
        if not re.fullmatch(r"[A-Za-z0-9_-][A-Za-z0-9_.-]*", filename):
            raise ValueError("Invalid diagnostic filename")
        text = self.run(
            "exec-out",
            "run-as",
            package or self.package,
            "cat",
            "files/diagnostics/" + filename,
            optional=True,
        )
        try:
            value = json.loads(text)
            return value if isinstance(value, dict) else None
        except ValueError:
            return None

    def save_json(self, label, value):
        if not re.fullmatch(r"[A-Za-z0-9_-][A-Za-z0-9_.-]*", label):
            raise ValueError("Invalid evidence label")
        path = self.output / (label + ".json")
        temporary = path.with_suffix(".tmp")
        temporary.write_text(
            json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        temporary.replace(path)

    def verify_apk(self, apk, *, package=None):
        package = package or self.package
        paths = [
            line.removeprefix("package:")
            for line in self._shell_text("pm", "path", package).splitlines()
            if line.startswith("package:")
        ]
        if len(paths) != 1:
            raise RuntimeError(
                "Need one installed base APK (split packages are unsupported)"
            )
        actual = self._shell_text("sha256sum", paths[0]).split()
        with Path(apk).open("rb") as source:
            expected = hashlib.file_digest(source, "sha256").hexdigest()
        if not actual or actual[0] != expected:
            raise RuntimeError("Installed APK hash differs from the supplied APK")
        self.save_json(
            "installed-" + package, {"package": package, "apk_sha256": expected}
        )
        return expected

    def send_request(
        self,
        label,
        action,
        extras=None,
        *,
        component=None,
        receipt_package=None,
        receipt_pattern="debug_request_{key}.json",
        accepted=("accepted",),
        track_process=True,
        include_stopped=False,
        timeout=15,
    ):
        key = "probe_" + uuid.uuid4().hex
        arguments = [
            "am",
            "broadcast",
            "-n",
            component or self.package + "/" + RECEIVER,
            "-a",
            action,
            "--es",
            "request",
            key,
        ]
        if include_stopped:
            arguments.insert(2, "--include-stopped-packages")
        for name, value in (extras or {}).items():
            flag = (
                "--ez"
                if isinstance(value, bool)
                else (
                    "--ei"
                    if isinstance(value, int)
                    else "--ef" if isinstance(value, float) else "--es"
                )
            )
            arguments.extend(
                [
                    flag,
                    name,
                    str(value).lower() if isinstance(value, bool) else str(value),
                ]
            )
        self.save_json(
            key + "-request",
            {
                "request": key,
                "action": action,
                "component": component or self.package + "/" + RECEIVER,
            },
        )
        self._shell_text(*arguments)
        deadline = time.monotonic() + timeout
        receipt = None
        while time.monotonic() < deadline:
            observed = self.read(
                receipt_pattern.format(key=key), package=receipt_package
            )
            if observed is not None:
                receipt = observed
            if receipt and receipt.get("request") == key:
                self.save_json(key + "-receipt", receipt)
                self.save_json(label + "-receipt", receipt)
                if receipt.get("state") not in accepted:
                    raise RuntimeError("Rejected request: " + str(receipt))
                if track_process:
                    if (
                        receipt.get("action") != action
                        or type(receipt.get("id")) is not int
                        or receipt["id"] <= 0
                    ):
                        raise RuntimeError("Invalid diagnostic receipt identity")
                    process = receipt.get("diagnostic_process")
                    if not process or (self.process and self.process != process):
                        raise RuntimeError(
                            "App process changed; cannot combine this run"
                        )
                    self.process = process
                return receipt
            time.sleep(0.1)
        self.save_json(
            label + "-receipt-timeout", {"request": key, "last_receipt": receipt}
        )
        raise TimeoutError("No matching request receipt: " + label)

    def request(self, label, operation, **extras):
        return self.send_request(
            label,
            self.package + ".DEBUG_PLAYER_MPV",
            {"operation": operation, **extras},
        )

    def wait_report(
        self,
        label,
        receipt,
        filename,
        condition=lambda report: True,
        *,
        command_key=False,
        timeout=60,
        fail_on_error=False,
        observer=None,
    ):
        deadline = time.monotonic() + timeout
        started = time.monotonic()
        self.last_report = None
        while time.monotonic() < deadline:
            report = self.read(filename)
            if report is not None:
                self.last_report = report
            if report:
                identity = report.get("request_id") == receipt.get("id")
                if report.get("request_key") is not None:
                    identity = identity and report["request_key"] == receipt["request"]
                if not command_key:
                    identity = (
                        identity and report.get("request_key") == receipt["request"]
                    )
                if command_key:
                    identity = (
                        identity
                        and sum(
                            command.get("request_key") == receipt["request"]
                            for command in report.get("commands", [])
                        )
                        == 1
                    )
                process = report.get("diagnostic_process")
                if process is None:
                    # Godot player reports echo the unique command key instead.
                    identity = identity and command_key
                else:
                    identity = identity and process == receipt.get("diagnostic_process")
                if identity:
                    if observer:
                        observer(report, time.monotonic() - started)
                    if (
                        fail_on_error
                        and report.get("media", {}).get("state") == "failed"
                    ):
                        self.save_json(label + "-failed", report)
                        raise RuntimeError(
                            "Player failed: " + str(report.get("native_status"))
                        )
                    if condition(report):
                        self.save_json(label + "-report", report)
                        return report
            time.sleep(0.12)
        self.save_json(
            label + "-timeout",
            {"request": receipt["request"], "last_report": self.last_report},
        )
        raise TimeoutError("No matching report completion: " + label)

    def wait(
        self,
        label,
        receipt,
        condition,
        timeout=60,
        *,
        fail_on_error=True,
        observer=None,
    ):
        return self.wait_report(
            label,
            receipt,
            f"mpv_player_{receipt['id']}.json",
            condition,
            command_key=True,
            timeout=timeout,
            fail_on_error=fail_on_error,
            observer=observer,
        )
