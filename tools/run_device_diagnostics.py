"""Collect fresh native core/GPU/audio reports from an exact installed Debug APK."""

import argparse
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tools.device_probe import Device, PACKAGE, device_lock, output_directory


def collect(device, kind, *, fixture="c03_sbs_grid", hardware=True, timeout=120):
    extras = {"hardware": False if kind == "core" else hardware}
    if kind != "audio":
        extras["fixture"] = fixture
    receipt = device.send_request(
        kind, device.package + ".DEBUG_MPV_" + kind.upper(), extras
    )
    report = device.wait_report(
        kind, receipt, f"mpv_{kind}_{receipt['id']}.json", timeout=timeout
    )
    expected = "passed_native_checks" if kind == "audio" else "passed"
    if report.get("state") != expected:
        raise RuntimeError("Native diagnostic failed: " + str(report))
    device.save_json(
        "result",
        {
            "state": "passed",
            "kind": kind,
            "request": receipt["request"],
            "request_id": receipt["id"],
            "diagnostic_process": receipt["diagnostic_process"],
            "scope": "Native diagnostic only; no Godot/XR display, audible output or headset performance acceptance",
        },
    )
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("kind", choices=("core", "gpu", "audio"))
    parser.add_argument("--adb", default="adb")
    parser.add_argument("--serial", required=True)
    parser.add_argument("--port", type=int, default=5037)
    parser.add_argument("--apk", required=True, type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument(
        "--fixture", choices=("c03_sbs_grid", "c04_alpha_f180", "c04_independent_alpha")
    )
    parser.add_argument(
        "--software",
        action="store_true",
        help="Software decode for GPU/audio; core is always software",
    )
    parser.add_argument("--timeout", type=float, default=120)
    args = parser.parse_args()
    if args.timeout <= 0 or (args.kind == "audio" and args.fixture):
        parser.error("Need a positive timeout; audio uses its fixed bundled fixture")
    output = output_directory(args.output, args.kind)
    device = Device(args.adb, args.serial, output, package=PACKAGE, port=args.port)
    try:
        with device_lock(args.serial):
            device.verify_apk(args.apk)
            collect(
                device,
                args.kind,
                fixture=args.fixture or "c03_sbs_grid",
                hardware=not args.software,
                timeout=args.timeout,
            )
    except (RuntimeError, TimeoutError, OSError, ValueError) as error:
        device.save_json(
            "result", {"state": "failed", "kind": args.kind, "error": str(error)}
        )
        print(str(error), file=sys.stderr)
        return 1
    print(f"Captured {args.kind} report: {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
