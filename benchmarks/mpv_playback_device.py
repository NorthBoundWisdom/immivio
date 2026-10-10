"""Measure production playback on an Android device/emulator using original video bytes.

Requires a no-AI Debug APK. Uses the 2D Godot entry, not the XR compositor.
Defaults to a hash-verified local file. Optional ADB loopback HTTP is not a Wi-Fi test.
"""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import statistics
import subprocess
import threading
import time

from mpv_seek_strategy_device import Device, PACKAGE
from mpv_startup_device import MediaServer


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--adb", default="adb")
    parser.add_argument("--serial", required=True)
    parser.add_argument("--apk", required=True, type=Path)
    parser.add_argument("--original", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--seconds", type=int, default=30)
    parser.add_argument("--borrow-color", choices=("yes", "no"), default="yes")
    parser.add_argument("--controls", action="store_true", help="Also verify pause, seek, pinned pixel readback and resume")
    parser.add_argument("--transport", choices=("local", "http"), default="local")
    parser.add_argument("--mpv-log-level", choices=("no", "warn", "info", "debug"), help="Temporary Debug log-level A/B; restored on exit")
    args = parser.parse_args()
    if args.seconds < 5 or not args.original.is_file():
        parser.error("Need an existing original video and at least five measurement seconds")
    args.output.mkdir(parents=True, exist_ok=True)
    device = Device(args.adb, args.serial, args.output)
    installed = device.run("shell", "pm", "path", PACKAGE).strip().removeprefix("package:")
    installed_sha = device.run("shell", "sha256sum", installed).split()[0]
    with args.apk.open("rb") as apk:
        if installed_sha != hashlib.file_digest(apk, "sha256").hexdigest():
            raise RuntimeError("Installed APK differs from --apk")
    result = {"state": "running", "apk_sha256": installed_sha, "serial": args.serial,
              "borrow_color_requested": args.borrow_color == "yes", "samples": [],
              "scope": "Distinct libmpv render transactions drawn by the Godot 2D owner; "
                       "not independently verified unique decoded images, compositor scanout or exact video PTS. "
                       "Original bytes, no resize/reencode. Emulator results do not prove headset throughput.",
              "source": {"path": str(args.original.resolve()), "size": args.original.stat().st_size, "transport": args.transport},
              "device": {key: device.run("shell", "getprop", key).strip() for key in
                         ("ro.product.model", "ro.kernel.qemu", "ro.build.version.sdk")}}
    server = MediaServer(args.original, 0)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    port = server.server_address[1]
    previous_log = device.run("shell", "getprop", "debug.vrpp.mpv.log").strip()
    result["mpv_log_level"] = args.mpv_log_level or previous_log or "info"
    save = lambda: (args.output / "result.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    def scene_marker():
        lines = device.run("shell", "run-as", PACKAGE, "tail", "-n", "8", "files/diagnostics/events.jsonl", optional=True)
        return next((line for line in reversed(lines.splitlines()) if '"event":"app_started"' in line), "")
    try:
        if args.mpv_log_level:
            device.run("shell", "setprop", "debug.vrpp.mpv.log", args.mpv_log_level)
        device.run("reverse", f"tcp:{port}", f"tcp:{port}")
        previous_scene = scene_marker()
        device.run("shell", "am", "force-stop", PACKAGE)
        if args.transport == "local":
            # Stream directly into the debug app's private fixture directory; no storage permission,
            # second on-device copy or modification of the supplied original is needed.
            with args.original.open("rb") as source:
                subprocess.run([args.adb, "-s", args.serial, "shell", "-T", "run-as", PACKAGE, "sh", "-c",
                                "'mkdir -p files/fixtures && cat > files/fixtures/mpv_performance.mp4'"],
                               stdin=source, check=True, timeout=180)
            source_args = {"fixture": "mpv_performance"}
            with args.original.open("rb") as source:
                source_sha = hashlib.file_digest(source, "sha256").hexdigest()
            remote_sha = device.run("shell", "run-as", PACKAGE, "sha256sum", "files/fixtures/mpv_performance.mp4").split()[0]
            if remote_sha != source_sha:
                raise RuntimeError("Device video differs from the supplied original")
            result["source"]["sha256"] = source_sha
        else:
            source_args = {"uri": f"http://127.0.0.1:{port}/sample.mp4", "title": "playback_performance"}
        device.run("shell", "input", "keyevent", "KEYCODE_WAKEUP")
        # Direct shell launch avoids Android 16's background receiver launch restriction.
        # This Debug-only entry is protected by android.permission.DUMP.
        device.run("shell", "am", "start", "-n", PACKAGE + "/org.vrpassthroughplayer.plugin.MpvDiagnosticActivity")
        deadline = time.monotonic() + 60
        while not (marker := scene_marker()) or marker == previous_scene:
            if time.monotonic() >= deadline:
                raise TimeoutError("Godot scene did not finish startup")
            time.sleep(.5)
        receipt = device.request("open", "open", **source_args, benchmark=True, enabled=False, stereo=False,
                                 profile="320x320", projection=0, borrow_color=args.borrow_color == "yes")
        first = device.wait("open", receipt, lambda r: r["native_status"].get("unique_post_draw_frames", 0) >= 3,
                            timeout=120)
        if not first["diagnostic_2d"]:
            raise RuntimeError("Unexpected XR entry")
        result["first_report"] = first
        result["memory_before"] = device.run("shell", "dumpsys", "meminfo", PACKAGE)
        deadline = time.monotonic() + args.seconds
        previous = None
        while time.monotonic() < deadline:
            report = device.read(f"mpv_player_{receipt['id']}.json")
            if report and report["sample_monotonic_us"] != previous:
                if report["media"]["state"] == "failed":
                    raise RuntimeError("Playback failed: " + str(report["native_status"]))
                if report["media"]["session_id"] != first["media"]["session_id"]:
                    raise RuntimeError("Playback session changed during measurement")
                previous = report["sample_monotonic_us"]
                result["samples"].append(report)
                save()
            time.sleep(1)
        samples = result["samples"]
        if len(samples) < 3:
            raise RuntimeError("Too few fresh samples")
        a, b = samples[0], samples[-1]
        elapsed = (b["sample_monotonic_us"]-a["sample_monotonic_us"])/1e6
        n0, n1 = a["native_status"], b["native_status"]
        result["summary"] = {"elapsed_seconds": elapsed,
            "distinct_render_owner_fps": (n1["unique_post_draw_frames"]-n0["unique_post_draw_frames"])/elapsed,
            "engine_draw_fps": (b["engine_drawn_frames"]-a["engine_drawn_frames"])/elapsed,
            "engine_fps_median": statistics.median(r["engine_fps"] for r in samples),
            "producer_render_fps": (n1["rendered"]-n0["rendered"])/elapsed,
            "hwdec": n1["details"]["hwdec_current"], "format": b["media"]["format"],
            "bridge_before": n0.get("bridge"), "bridge_after": n1.get("bridge"),
            "decoder_drops_before": n0["details"].get("decoder_frame_drop_count"),
            "decoder_drops_after": n1["details"].get("decoder_frame_drop_count")}
        result["memory_after"] = device.run("shell", "dumpsys", "meminfo", PACKAGE)
        if args.controls:
            rec = device.request("pause", "playing", enabled=False)
            paused = device.wait("pause", rec, lambda r: r["native_status"].get("details", {}).get("paused") == "yes")
            generation = paused["media"]["generation"]
            rec = device.request("pixels", "pixels")
            pixels = device.wait("pixels", rec, lambda r: r["pixel_probe"].get("state") in ("captured", "failed"), timeout=90)
            probe = pixels["pixel_probe"]
            if probe["state"] != "captured" or not probe["native_pin_released"] or not probe["wrappers_detached"]:
                raise RuntimeError("Pinned pixel capture failed: " + str(probe))
            for name in [i["file"] for i in probe["images"]] + [probe["mask_reference"]["mask_file"]]:
                data = device.run("shell", "run-as", PACKAGE, "base64", "files/diagnostics/" + name)
                (args.output / name).write_bytes(base64.b64decode(data))
            rec = device.request("seek-zero", "seek", position_ms=0, seek_mode="exact")
            sought = device.wait("seek-zero", rec, lambda r: r["media"]["generation"] > generation
                                and r["layout"]["playback_control"]["state"] == "idle"
                                and not r["layout"]["frame_hold"]["frozen"]
                                and r["native_status"].get("session_id") == r["media"]["session_id"], timeout=90)
            before = sought["native_status"].get("unique_post_draw_frames", 0)
            rec = device.request("resume", "playing", enabled=True)
            resumed = device.wait("resume", rec, lambda r: r["native_status"].get("unique_post_draw_frames", 0) > before + 3)
            result["controls"] = {"state": "passed", "pause_generation": generation,
                "seek_generation": sought["media"]["generation"], "pixel_capture": probe["state"],
                "resume_unique_frames": resumed["native_status"]["unique_post_draw_frames"]}
        result["state"] = "measured"
        print(json.dumps(result["summary"], indent=2), flush=True)
    except BaseException as error:
        result["state"] = "failed"; result["error"] = str(error)
        raise
    finally:
        if device.process:
            try:
                rec = device.request("close", "close")
                device.wait("close", rec, lambda r: r["media"]["session_id"] <= 0, timeout=20)
                result["closed"] = True
            except Exception as error:
                result["close_error"] = str(error)
                result["state"] = "failed"
        device.run("reverse", "--remove", f"tcp:{port}", optional=True)
        if args.mpv_log_level:
            device.run("shell", "setprop", "debug.vrpp.mpv.log", previous_log or '""', optional=True)
        server.shutdown(); server.server_close()
        result["http_requests"] = server.requests
        save()
        if "close_error" in result:
            raise RuntimeError("Playback cleanup failed: " + result["close_error"])


if __name__ == "__main__":
    main()
