"""Physical-headset checks for the selected upstream ports.

Requires the exact installed Debug APK. Media scenarios also need synthetic files
staged in /storage/emulated/0/Movies/ImmivioAcceptance20261024. The menus step
checks dropdowns/curvature/navigation without staging media. Uses software-generated
ray events through production menus, not physical controller actuation.
"""

import argparse
import json
from pathlib import Path
import shlex
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tools.device_probe import Device as ProbeDevice, PACKAGE, output_directory


class Device(ProbeDevice):
    def __init__(self, adb, port, serial, out):
        super().__init__(adb, serial, out, package=PACKAGE, port=port)
        self.out = self.output
        self.shell("input", "keyevent", "KEYCODE_WAKEUP")

    def adb(self, *args, timeout=30):
        return self.adb_bytes(*args, timeout=timeout)

    def shell(self, *args):
        return self.adb("shell", shlex.join(list(args)))

    def command(self, operation, extras=None, wait=None, timeout=35):
        values = {}
        for kind, name, value in extras or []:
            values[name] = (
                (str(value).lower() == "true")
                if kind == "--ez"
                else (
                    int(value)
                    if kind == "--ei"
                    else float(value) if kind == "--ef" else str(value)
                )
            )
        receipt = self.request(operation, operation, **values)
        key = receipt["request"]
        observations = []

        def observe(report, elapsed):
            native = report.get("native_status", {})
            observations.append(
                {
                    "elapsed": round(elapsed, 3),
                    "state": report.get("media", {}).get("state"),
                    "feedback": report.get("loading_feedback", {}),
                    "read_bytes_per_second": (
                        native.get("details", {}).get("read_bytes_per_second")
                        if native.get("session_id")
                        == report.get("media", {}).get("session_id")
                        else None
                    ),
                }
            )
            del observations[:-120]

        try:
            report = self.wait(
                key,
                receipt,
                lambda r: wait is None or wait(r, key),
                timeout=timeout,
                fail_on_error=False,
                observer=observe,
            )
        except (RuntimeError, TimeoutError):
            self.save(key, receipt, self.last_report or {})
            raise
        report["device_observations"] = observations
        self.save(key, receipt, report)
        return report, key

    def save(self, key, receipt, report):
        self.save_json(key, {"receipt": receipt, "report": report})

    def step(self, step):
        report, key = self.command(
            "selected_features_ui",
            [("--es", "step", step)],
            wait=lambda r, k: r.get("selected_features_ui", {}).get("request_key") == k,
            timeout=45,
        )
        result = report["selected_features_ui"]
        for item in result["checks"]:
            print(
                ("PASS" if item["passed"] else "FAIL")
                + ": "
                + item["title"]
                + " "
                + str(item.get("details")),
                flush=True,
            )
        (self.out / (step + ".json")).write_text(json.dumps(result, indent=2) + "\n")
        for local, command in [
            (
                step + "-ui.png",
                [
                    "exec-out",
                    "run-as",
                    PACKAGE,
                    "cat",
                    "files/diagnostics/acceptance_" + key + ".png",
                ],
            ),
            (step + "-headset.png", ["exec-out", "screencap", "-p"]),
        ]:
            data = self.adb(*command)
            if data.startswith(b"\x89PNG"):
                (self.out / local).write_bytes(data)
        if step == "menus":
            for suffix in ["dropdown", "closed"]:
                data = self.adb(
                    "exec-out",
                    "run-as",
                    PACKAGE,
                    "cat",
                    "files/diagnostics/acceptance_" + key + "_" + suffix + ".png",
                )
                if data.startswith(b"\x89PNG"):
                    (self.out / ("menus-" + suffix + "-ui.png")).write_bytes(data)
        if step == "library":
            data = self.adb(
                "exec-out",
                "run-as",
                PACKAGE,
                "cat",
                "files/diagnostics/acceptance_" + key + "_compact.png",
            )
            if data.startswith(b"\x89PNG"):
                (self.out / "library-compact-ui.png").write_bytes(data)
        return result


def main():
    global PACKAGE
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package", default=PACKAGE)
    parser.add_argument("--adb", default="adb")
    parser.add_argument("--port", type=int, default=5037)
    parser.add_argument("--serial", required=True)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--out", type=Path)
    parser.add_argument(
        "--step",
        choices=[
            "setup",
            "browse",
            "restore",
            "controls",
            "cinema",
            "library",
            "menus",
            "snapshot",
            "error",
        ],
    )
    parser.add_argument("--open-local")
    parser.add_argument("--open-uri")
    parser.add_argument("--expect-error")
    args = parser.parse_args()
    args.out = output_directory(args.out, "selected-features")
    PACKAGE = args.package
    d = Device(args.adb, args.port, args.serial, args.out)
    if d.shell("getprop", "ro.kernel.qemu").strip() == b"1":
        raise RuntimeError("A physical headset is required")
    actual = d.verify_apk(args.apk)
    if args.step:
        result = d.step(args.step)
        raise SystemExit(0 if result["passed"] else 1)
    if args.open_local or args.open_uri:
        extra = (
            [("--es", "local_path", args.open_local)]
            if args.open_local
            else [("--es", "uri", args.open_uri)]
        )
        extra += [
            ("--ez", "stereo", "false"),
            ("--ez", "benchmark", "true"),
            ("--ei", "projection", "0"),
        ]

        def ready(report, key):
            media = report.get("media", {})
            if media.get("state") == "failed":
                return True
            native = report.get("native_status", {})
            return (
                media.get("frame_counter", 0) >= 5
                and native.get("session_id") == media.get("session_id")
                and native.get("generation") == media.get("generation")
                and native.get("post_draw_frames", 0) > 0
            )

        report, key = d.command("open", extra, wait=ready, timeout=50)
        media = report["media"]
        result = {
            "request": key,
            "apk_sha256": actual,
            "state": media["state"],
            "error": media.get("error"),
            "frames": media["frame_counter"],
            "native_post_draw_frames": report.get("native_status", {}).get(
                "post_draw_frames"
            ),
            "diagnostic_2d": report.get("diagnostic_2d"),
            "format": media.get("format"),
        }
        (args.out / "last-open.json").write_text(json.dumps(result, indent=2) + "\n")
        print(json.dumps(result, indent=2), flush=True)
        if args.expect_error:
            raise SystemExit(0 if media.get("error") == args.expect_error else 1)
        raise SystemExit(
            0
            if media.get("state") != "failed" and not report.get("diagnostic_2d")
            else 1
        )
    parser.error("Choose --step, --open-local or --open-uri")


if __name__ == "__main__":
    main()
