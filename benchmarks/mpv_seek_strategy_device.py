"""Compare actual production headset seeks using fresh debug receipts and playback-clock estimates."""

import argparse
import json
from pathlib import Path
import random
import statistics
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tools.device_probe import Device as ProbeDevice, PLAYER_FIXTURES, output_directory


class Device(ProbeDevice):
    def seek(self, label, target_ms, mode):
        receipt = self.request(label, "seek", position_ms=target_ms, seek_mode=mode)
        report = self.wait(
            label,
            receipt,
            lambda r: r["layout"]["playback_control"]["state"] == "idle"
            and not r["layout"]["frame_hold"]["frozen"]
            and r["layout"]["playback_control"]["target_ms"] == target_ms
            and r["native_status"].get("session_id") == r["media"]["session_id"],
        )
        trace = report["seek_trace"]
        start = max(i for i, event in enumerate(trace) if event["stage"] == "requested")
        trace = trace[start:]
        stages = {event["stage"]: event for event in trace}
        if "target_presented" not in stages:
            raise RuntimeError("No new frame binding")
        actual = report["media"]["presentation_identity"]
        if (
            actual.get("source_pts_verified", False)
            or actual.get("source_ticket_origin") != "standard_libmpv_render"
            or not actual.get("source_ticket_valid", False)
            or report["native_status"]["details"]["hwdec_current"] != "mediacodec"
        ):
            raise RuntimeError(
                "No completed hardware-decoded libmpv render transaction"
            )
        if report["diagnostic_2d"]:
            raise RuntimeError("Not the normal VR entry")
        actual_ms = actual["pts_us"] / 1000
        row = {
            "mode": mode,
            "target_ms": target_ms,
            "estimated_clock_ms": actual_ms,
            "decoded_frame_pts_verified": False,
            "clock_offset_ms": actual_ms - target_ms,
            "request_to_bind_ms": stages["target_presented"]["time_ms"]
            - stages["requested"]["time_ms"],
            "request_to_freeze_ms": stages["frozen"]["time_ms"]
            - stages["requested"]["time_ms"],
            "submit_to_bind_ms": stages["target_presented"]["time_ms"]
            - stages["seek_started"]["time_ms"],
            "freeze_copy_us": stages["frozen"]["freeze_copy_us"],
            "source_epoch": actual["source_epoch"],
            "generation": actual["generation"],
            "native_seek_mode": report["native_status"].get("seek_mode"),
            "receipt": receipt["request"],
        }
        return row


def arguments(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=5037)
    parser.add_argument("--adb", required=True)
    parser.add_argument("--serial", required=True)
    parser.add_argument("--apk", required=True, type=Path)
    sources = parser.add_mutually_exclusive_group(required=True)
    sources.add_argument(
        "--fixture",
        choices=PLAYER_FIXTURES,
        help="Explicitly prepared app-private fixture",
    )
    sources.add_argument(
        "--uri-file",
        type=Path,
        help="Authorized actual network video JSON with uri/title",
    )
    parser.add_argument("--packets", required=True, type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--repeats", type=int, default=3)
    return parser.parse_args(argv)


def main():
    args = arguments()
    args.output = output_directory(args.output, "seek")
    device = Device(args.adb, args.serial, args.output, port=args.port)
    installed_sha = device.verify_apk(args.apk)
    packet_data = json.loads(args.packets.read_text(encoding="utf-8-sig"))
    keys = sorted(
        {
            float(p["pts_time"])
            for p in packet_data["packets"]
            if "K" in p.get("flags", "")
        }
    )
    intervals = [(a, b) for a, b in zip(keys, keys[1:]) if 4 <= b - a <= 6]
    intervals = [intervals[1], intervals[-2]]
    cases = [
        {
            "gop_start_ms": round(a * 1000),
            "gop_end_ms": round(b * 1000),
            "fraction": fraction,
            "target_ms": round((a + (b - a) * fraction) * 1000),
        }
        for a, b in intervals
        for fraction in (0.02, 0.5, 0.9)
    ]
    result = {
        "state": "running",
        "apk_sha256": installed_sha,
        "serial": args.serial,
        "cases": cases,
        "scope": "Normal Quest VR production decode, GPU freeze and libmpv/Godot binding; not physical-controller feel or compositor timing",
        "rows": [],
    }

    def save():
        return (args.output / "result.json").write_text(
            json.dumps(result, indent=2), encoding="utf-8"
        )

    save()
    try:
        source = {"fixture": args.fixture}
        if args.uri_file:
            entry = json.loads(args.uri_file.read_text(encoding="utf-8-sig"))
            source = {
                "uri": entry["uri"],
                "title": entry.get("title", "network_seek_test"),
            }
        result["source"] = source
        receipt = device.request(
            "open",
            "open",
            **source,
            enabled=False,
            stereo=True,
            seek_mode="speed",
        )
        device.wait(
            "open",
            receipt,
            lambda r: r["media"]["frame_counter"] >= 2
            and r["media"]["format"].get("width") == 8192,
        )
        receipt = device.request("pause", "playing", enabled=False)
        device.wait(
            "pause",
            receipt,
            lambda r: r["native_status"]["details"].get("paused") == "yes",
        )
        schedule = [(case, repeat) for repeat in range(args.repeats) for case in cases]
        random.Random(20261008).shuffle(schedule)
        for index, (case, repeat) in enumerate(schedule):
            for mode in (("speed", "exact") if index % 2 == 0 else ("exact", "speed")):
                origin = 27000 if case["target_ms"] < 15000 else 3000
                device.seek(f"origin-{index}-{mode}", origin, "speed")
                label = f"seek-{index}-{mode}"
                row = (
                    case
                    | {"repeat": repeat + 1}
                    | device.seek(label, case["target_ms"], mode)
                )
                result["rows"].append(row)
                save()
            print(
                json.dumps(
                    {
                        "pair": index + 1,
                        "total_pairs": len(schedule),
                        "last": result["rows"][-2:],
                    }
                ),
                flush=True,
            )
        result["diagnostic_process"] = device.process
        result["summary"] = {
            mode: {
                "count": len(rows := [r for r in result["rows"] if r["mode"] == mode]),
                "median_ms": statistics.median(r["request_to_bind_ms"] for r in rows),
                "max_ms": max(r["request_to_bind_ms"] for r in rows),
                "max_abs_clock_offset_ms": max(abs(r["clock_offset_ms"]) for r in rows),
            }
            for mode in ("speed", "exact")
        }
        result["state"] = "passed"
        print(json.dumps(result["summary"]), flush=True)
    except BaseException as error:
        result["state"] = "failed"
        result["error"] = str(error)
        raise
    finally:
        save()


if __name__ == "__main__":
    main()
