"""Measure production playback on an Android device/emulator using original video bytes.

Requires a no-AI Debug APK. Supports the 2D diagnostic or normal XR entry.
Defaults to a hash-verified local file. Optional ADB loopback HTTP is not a Wi-Fi test.
"""

import argparse
import base64
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import statistics
import shlex
import subprocess
import threading
import time

from mpv_seek_strategy_device import Device, PACKAGE
from mpv_startup_device import MediaServer


@contextmanager
def device_lock(serial):
    root = Path(__file__).resolve().parents[1] / ".cache"
    root.mkdir(exist_ok=True)
    key = hashlib.sha256(serial.encode()).hexdigest()[:16]
    with (root / f"playback-{key}.lock").open("a+b") as lock:
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
            raise RuntimeError("Another playback probe owns this device") from error
        yield


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--adb", default="adb")
    parser.add_argument("--serial", required=True)
    parser.add_argument("--apk", required=True, type=Path)
    parser.add_argument("--original", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--seconds", type=int, default=30)
    parser.add_argument(
        "--start-ms",
        type=int,
        default=0,
        help="Initial playback position, e.g. a bounded real-media EOF regression",
    )
    parser.add_argument(
        "--entry",
        choices=("2d", "xr"),
        default="2d",
        help="Normal headset VR launcher or diagnostic 2D activity",
    )
    parser.add_argument("--borrow-color", choices=("yes", "no"), default="yes")
    parser.add_argument(
        "--controls",
        action="store_true",
        help="Also verify pause, seek, pinned pixel readback and resume",
    )
    parser.add_argument("--transport", choices=("local", "http"), default="local")
    parser.add_argument(
        "--mpv-log-level",
        choices=("no", "warn", "info", "debug"),
        help="Temporary Debug log-level A/B; restored on exit",
    )
    parser.add_argument(
        "--producer-pool",
        choices=("reuse", "expand"),
        default="reuse",
        help="Temporary producer allocation policy A/B",
    )
    parser.add_argument(
        "--mpv-options",
        help="Temporary Debug mpv options, e.g. opengl-pbo=yes; restored on exit",
    )
    parser.add_argument(
        "--stereo",
        action="store_true",
        help="Use the production SBS layout for packed stereo media",
    )
    parser.add_argument("--projection", type=int, choices=(0, 1, 2, 3), default=0)
    parser.add_argument(
        "--opaque-fast",
        choices=("yes", "no"),
        default="yes",
        help="Cached borrowed-color handoff A/B",
    )
    parser.add_argument(
        "--warmup-seconds",
        type=float,
        default=5,
        help="Steady-playback warmup before sampling",
    )
    parser.add_argument(
        "--stress-pin",
        action="store_true",
        help="With --controls, keep pixel textures pinned while playback advances",
    )
    parser.add_argument(
        "--gpu-frames",
        type=int,
        choices=range(0, 8),
        default=2,
        help="Producer GPU work budget; 0 restores legacy unbounded submission",
    )
    parser.add_argument(
        "--expect-eof",
        action="store_true",
        help="Require a stable retained final pair after playback ends",
    )
    parser.add_argument(
        "--replay-after-eof",
        action="store_true",
        help="After settled EOF, require playback to restart in a new generation",
    )
    args = parser.parse_args()
    if (
        args.seconds < 5
        or args.warmup_seconds < 0
        or args.start_ms < 0
        or not args.original.is_file()
    ):
        parser.error(
            "Need an existing original, at least five measurement seconds and nonnegative warmup/start"
        )
    if args.stress_pin and not args.controls:
        parser.error("--stress-pin requires --controls")
    if args.expect_eof and args.controls:
        parser.error("Use --expect-eof separately from --controls")
    if args.replay_after_eof and not args.expect_eof:
        parser.error("--replay-after-eof requires --expect-eof")
    with device_lock(args.serial):
        measure(args)


def measure(args):
    args.output.mkdir(parents=True, exist_ok=True)
    device = Device(args.adb, args.serial, args.output)

    def set_property(name, value, *, optional=False):
        # adb shell reconstructs a shell command; keep option values a single literal argument.
        device.run("shell", "setprop", name, shlex.quote(value), optional=optional)

    installed = (
        device.run("shell", "pm", "path", PACKAGE).strip().removeprefix("package:")
    )
    installed_sha = device.run("shell", "sha256sum", installed).split()[0]
    with args.apk.open("rb") as apk:
        if installed_sha != hashlib.file_digest(apk, "sha256").hexdigest():
            raise RuntimeError("Installed APK differs from --apk")
    result = {
        "state": "running",
        "apk_sha256": installed_sha,
        "serial": args.serial,
        "borrow_color_requested": args.borrow_color == "yes",
        "samples": [],
        "entry": args.entry,
        "scope": "Distinct libmpv render transactions drawn by the Godot "
        + args.entry
        + " owner; "
        "not independently verified unique decoded images, compositor scanout or exact video PTS. "
        "Original bytes, no resize/reencode. Emulator results do not prove headset throughput.",
        "source": {
            "path": str(args.original.resolve()),
            "size": args.original.stat().st_size,
            "transport": args.transport,
        },
        "device": {
            key: device.run("shell", "getprop", key).strip()
            for key in ("ro.product.model", "ro.kernel.qemu", "ro.build.version.sdk")
        },
    }
    server = MediaServer(args.original, 0)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    port = server.server_address[1]
    previous_log = device.run("shell", "getprop", "debug.vrpp.mpv.log").strip()
    previous_pool = device.run("shell", "getprop", "debug.vrpp.mpv.pool").strip()
    previous_options = device.run("shell", "getprop", "debug.vrpp.mpv.opts").strip()
    previous_opaque = device.run(
        "shell", "getprop", "debug.vrpp.bridge.opaque_fast"
    ).strip()
    previous_gpu = device.run("shell", "getprop", "debug.vrpp.mpv.gpu_frames").strip()
    result["mpv_log_level"] = args.mpv_log_level or previous_log or "info"
    result["producer_pool"] = args.producer_pool
    result["mpv_options"] = (
        args.mpv_options if args.mpv_options is not None else previous_options
    )
    result["start_ms"] = args.start_ms
    result["stereo_sbs"] = args.stereo
    result["projection"] = args.projection
    result["opaque_fast"] = args.opaque_fast
    result["warmup_seconds"] = args.warmup_seconds
    result["stress_pin"] = args.stress_pin
    result["gpu_frames"] = args.gpu_frames
    save = lambda: (args.output / "result.json").write_text(
        json.dumps(result, indent=2), encoding="utf-8"
    )

    def scene_marker():
        # XR startup emits more than eight events immediately after app_started.
        # Filter before tailing so a completed fast startup cannot disappear.
        command = (
            'grep \'"event":"app_started"\' files/diagnostics/events.jsonl | tail -n 1'
        )
        lines = device.run(
            "shell", "run-as", PACKAGE, "sh", "-c", shlex.quote(command), optional=True
        )
        return next(
            (
                line
                for line in reversed(lines.splitlines())
                if '"event":"app_started"' in line
            ),
            "",
        )

    try:
        set_property("debug.vrpp.mpv.pool", args.producer_pool)
        set_property("debug.vrpp.bridge.opaque_fast", args.opaque_fast)
        set_property("debug.vrpp.mpv.gpu_frames", str(args.gpu_frames))
        if args.mpv_options is not None:
            set_property("debug.vrpp.mpv.opts", args.mpv_options)
        if args.mpv_log_level:
            set_property("debug.vrpp.mpv.log", args.mpv_log_level)
        device.run("reverse", f"tcp:{port}", f"tcp:{port}")
        previous_scene = scene_marker()
        device.run("shell", "am", "force-stop", PACKAGE)
        if args.transport == "local":
            # Stream directly into the debug app's private fixture directory; no storage permission,
            # second on-device copy or modification of the supplied original is needed.
            with args.original.open("rb") as source:
                subprocess.run(
                    [
                        args.adb,
                        "-s",
                        args.serial,
                        "shell",
                        "-T",
                        "run-as",
                        PACKAGE,
                        "sh",
                        "-c",
                        "'mkdir -p files/fixtures && cat > files/fixtures/mpv_performance.mp4'",
                    ],
                    stdin=source,
                    check=True,
                    timeout=180,
                )
            source_args = {"fixture": "mpv_performance"}
            with args.original.open("rb") as source:
                source_sha = hashlib.file_digest(source, "sha256").hexdigest()
            remote_sha = device.run(
                "shell",
                "run-as",
                PACKAGE,
                "sha256sum",
                "files/fixtures/mpv_performance.mp4",
            ).split()[0]
            if remote_sha != source_sha:
                raise RuntimeError("Device video differs from the supplied original")
            result["source"]["sha256"] = source_sha
        else:
            source_args = {
                "uri": f"http://127.0.0.1:{port}/sample.mp4",
                "title": "playback_performance",
            }
        device.run("shell", "input", "keyevent", "KEYCODE_WAKEUP")
        # Direct shell launch avoids Android 16's background receiver launch restriction.
        # The diagnostic 2D activity is Debug-only and protected by android.permission.DUMP.
        if args.entry == "xr":
            device.run(
                "shell",
                "am",
                "start",
                "-n",
                PACKAGE + "/com.godot.game.GodotAppLauncher",
                "-a",
                "android.intent.action.MAIN",
                "-c",
                "org.khronos.openxr.intent.category.IMMERSIVE_HMD",
            )
        else:
            device.run(
                "shell",
                "am",
                "start",
                "-n",
                PACKAGE + "/org.vrpassthroughplayer.plugin.MpvDiagnosticActivity",
            )
        deadline = time.monotonic() + 60
        while not (marker := scene_marker()) or marker == previous_scene:
            if time.monotonic() >= deadline:
                raise TimeoutError("Godot scene did not finish startup")
            time.sleep(0.5)
        receipt = device.request(
            "open",
            "open",
            **source_args,
            benchmark=True,
            enabled=False,
            stereo=args.stereo,
            profile="320x320",
            projection=args.projection,
            position_ms=args.start_ms,
            borrow_color=args.borrow_color == "yes",
        )
        first = device.wait(
            "open",
            receipt,
            lambda r: r["native_status"].get("unique_post_draw_frames", 0)
            >= (1 if args.expect_eof else 3),
            timeout=120,
        )
        if bool(first["diagnostic_2d"]) != (args.entry == "2d"):
            raise RuntimeError("Playback entry differs from the requested case")
        result["capabilities_at_first_frame"] = device.read("capabilities_latest.json")
        if args.entry == "xr":
            deadline = time.monotonic() + 15
            while True:
                capabilities = result["capabilities_at_first_frame"] or {}
                xr = capabilities.get("xr", {})
                if (
                    xr.get("initialized")
                    and xr.get("viewport_use_xr")
                    and not xr.get("preview")
                    and capabilities.get("captured_unix_seconds", 0)
                    >= json.loads(marker)["unix_seconds"] - 1
                ):
                    break
                if time.monotonic() >= deadline:
                    raise RuntimeError(
                        "Normal XR runtime did not initialize with a fresh capability snapshot"
                    )
                # The diagnostic file can be observed between truncation and write.
                time.sleep(0.2)
                result["capabilities_at_first_frame"] = device.read(
                    "capabilities_latest.json"
                )
        if (
            first["native_status"]["max_output_width"] != 0
            or first["native_status"]["frame_cap_fps"] != 0
        ):
            raise RuntimeError(
                "Clear the player's output-width/frame-rate cap before measuring original playback"
            )
        if (
            "max_gpu_frames" in first["native_status"]
            and first["native_status"]["max_gpu_frames"] != args.gpu_frames
        ):
            raise RuntimeError("Producer GPU budget differs from the requested case")
        active_fast = first["native_status"].get("bridge", {}).get("opaque_state_fast")
        if active_fast is not None and active_fast != (args.opaque_fast == "yes"):
            raise RuntimeError("Opaque handoff setting differs from the requested case")
        result["first_report"] = first
        time.sleep(args.warmup_seconds)
        result["memory_before"] = device.run("shell", "dumpsys", "meminfo", PACKAGE)
        deadline = time.monotonic() + args.seconds
        previous = None
        last_fresh = time.monotonic()
        while time.monotonic() < deadline:
            report = device.read(f"mpv_player_{receipt['id']}.json")
            if report and report["sample_monotonic_us"] != previous:
                if (
                    report["request_id"] != receipt["id"]
                    or sum(
                        c["request_key"] == receipt["request"]
                        for c in report["commands"]
                    )
                    != 1
                ):
                    raise RuntimeError("Playback report belongs to a different request")
                if previous is not None and report["sample_monotonic_us"] < previous:
                    raise RuntimeError("App monotonic clock reset during measurement")
                if report["media"]["state"] == "failed":
                    raise RuntimeError(
                        "Playback failed: " + str(report["native_status"])
                    )
                if report["media"]["session_id"] != first["media"]["session_id"]:
                    raise RuntimeError("Playback session changed during measurement")
                previous = report["sample_monotonic_us"]
                last_fresh = time.monotonic()
                result["samples"].append(report)
                save()
            if time.monotonic() - last_fresh > 10:
                raise RuntimeError(
                    "Playback telemetry stopped; check headset focus and app lifecycle"
                )
            time.sleep(1)
        samples = result["samples"]
        if len(samples) < 3:
            raise RuntimeError("Too few fresh samples")
        a, b = samples[0], samples[-1]
        elapsed = (b["sample_monotonic_us"] - a["sample_monotonic_us"]) / 1e6
        n0, n1 = a["native_status"], b["native_status"]
        bypasses = n1.get("bridge", {}).get("opaque_state_bypasses", 0)
        if args.opaque_fast == "no" and bypasses:
            raise RuntimeError(
                "Opaque handoff fast path was enabled during the disabled case"
            )

        def mean_delta(before, after, total, count):
            if (
                total not in before
                or total not in after
                or count not in before
                or count not in after
            ):
                return None
            calls = after[count] - before[count]
            return (after[total] - before[total]) / calls if calls > 0 else None

        result["summary"] = {
            "elapsed_seconds": elapsed,
            "distinct_render_owner_fps": (
                n1["unique_post_draw_frames"] - n0["unique_post_draw_frames"]
            )
            / elapsed,
            "engine_draw_fps": (b["engine_drawn_frames"] - a["engine_drawn_frames"])
            / elapsed,
            "engine_fps_median": statistics.median(r["engine_fps"] for r in samples),
            "producer_render_fps": (n1["rendered"] - n0["rendered"]) / elapsed,
            "hwdec": n1["details"]["hwdec_current"],
            "format": b["media"]["format"],
            "bridge_before": n0.get("bridge"),
            "bridge_after": n1.get("bridge"),
            "producer_color_bytes_before": n0.get("color_texture_bytes"),
            "producer_color_bytes_after": n1.get("color_texture_bytes"),
            "producer_color_allocations": n1.get("color_allocations"),
            "render_call_mean_us": mean_delta(
                n0, n1, "render_call_us", "render_call_count"
            ),
            "gpu_pending_peak": n1.get("gpu_pending_peak"),
            "gpu_backpressure_skipped_before": n0.get("gpu_backpressure_skipped"),
            "gpu_backpressure_skipped_after": n1.get("gpu_backpressure_skipped"),
            "capture_to_ready_mean_us": mean_delta(
                n0, n1, "capture_to_ready_us", "capture_ready_count"
            ),
            "bridge_capture_mean_us": mean_delta(
                n0.get("bridge", {}),
                n1.get("bridge", {}),
                "capture_cpu_us",
                "capture_calls",
            ),
            "decoder_drops_before": n0["details"].get("decoder_frame_drop_count"),
            "decoder_drops_after": n1["details"].get("decoder_frame_drop_count"),
            "vo_drops_before": n0["details"].get("vo_frame_drop_count"),
            "vo_drops_after": n1["details"].get("vo_frame_drop_count"),
        }
        result["memory_after"] = device.run("shell", "dumpsys", "meminfo", PACKAGE)
        if args.expect_eof:
            if not (
                b["media"]["state"] == "ended"
                and n1.get("eof_source_resolved")
                and n1.get("eof_pair_post_draw")
            ):
                raise RuntimeError("EOF did not retain and draw the final opaque pair")
            # A transient matching ticket is insufficient: keep-open must settle,
            # retaining the drawn image without repeatedly rendering it into new IDs.
            terminal = samples[-3:]
            if not all(
                s["media"]["state"] == "ended"
                and s["native_status"].get("eof_pair_post_draw")
                for s in terminal
            ):
                raise RuntimeError("Need three fresh completed EOF observations")
            identities = {
                (
                    s["native_status"]["rendered"],
                    s["native_status"]["published"],
                    s["media"]["presentation_identity"]["frame_id"],
                    s["media"]["presentation_identity"]["slot_token"],
                )
                for s in terminal
            }
            if len(identities) != 1:
                raise RuntimeError(
                    "EOF is still rendering or replacing its retained pair"
                )
            result["eof_retained"] = True
            result["eof_rendering_settled"] = True
            if args.replay_after_eof:
                generation = b["media"]["generation"]
                epoch = b["media"]["presentation_identity"]["source_epoch"]
                rec = device.request("replay-eof", "playing", enabled=True)
                replayed = device.wait(
                    "replay-eof",
                    rec,
                    lambda r: r["media"]["state"] == "playing"
                    and r["media"]["generation"] > generation
                    and r["media"]["presentation_identity"]["source_epoch"] > epoch
                    and r["native_status"].get("unique_post_draw_frames", 0) >= 3
                    and not r["native_status"].get("eof_source_resolved")
                    and 0
                    <= float(
                        r["native_status"].get("details", {}).get("position_seconds")
                        or -1
                    )
                    < 10,
                )
                result["eof_replay"] = {
                    "state": "passed",
                    "ended_generation": generation,
                    "replay_generation": replayed["media"]["generation"],
                    "source_epoch": replayed["media"]["presentation_identity"][
                        "source_epoch"
                    ],
                }
        if args.controls:
            rec = device.request("pause", "playing", enabled=False)
            paused = device.wait(
                "pause",
                rec,
                lambda r: r["native_status"].get("details", {}).get("paused") == "yes",
            )
            generation = paused["media"]["generation"]
            rec = device.request("pixels", "pixels")
            pixel_request = rec["id"]
            if args.stress_pin:
                rec = device.request("play-during-pin", "playing", enabled=True)
            pixels = device.wait(
                "pixels",
                rec,
                lambda r: r["pixel_probe"].get("request_id") == pixel_request
                and r["pixel_probe"].get("state") in ("captured", "failed"),
                timeout=90,
            )
            probe = pixels["pixel_probe"]
            if (
                probe["state"] != "captured"
                or not probe["native_pin_released"]
                or not probe["wrappers_detached"]
            ):
                raise RuntimeError("Pinned pixel capture failed: " + str(probe))
            advanced = (
                pixels["native_status"]["rendered"]
                - paused["native_status"]["rendered"]
            )
            if args.stress_pin and advanced <= 0:
                raise RuntimeError(
                    "No producer progression during pinned capture; stress check inconclusive"
                )
            for name in [i["file"] for i in probe["images"]] + [
                probe["mask_reference"]["mask_file"]
            ]:
                data = device.run(
                    "shell", "run-as", PACKAGE, "base64", "files/diagnostics/" + name
                )
                (args.output / name).write_bytes(base64.b64decode(data))
            if args.stress_pin:
                rec = device.request("pause-after-pin", "playing", enabled=False)
                device.wait(
                    "pause-after-pin",
                    rec,
                    lambda r: r["native_status"].get("details", {}).get("paused")
                    == "yes",
                )
            rec = device.request("seek-zero", "seek", position_ms=0, seek_mode="exact")
            sought = device.wait(
                "seek-zero",
                rec,
                lambda r: r["media"]["generation"] > generation
                and r["layout"]["playback_control"]["state"] == "idle"
                and not r["layout"]["frame_hold"]["frozen"]
                and r["native_status"].get("session_id") == r["media"]["session_id"],
                timeout=90,
            )
            before = sought["native_status"].get("unique_post_draw_frames", 0)
            rec = device.request("resume", "playing", enabled=True)
            resumed = device.wait(
                "resume",
                rec,
                lambda r: r["native_status"].get("unique_post_draw_frames", 0)
                > before + 3,
            )
            result["controls"] = {
                "state": "passed",
                "pause_generation": generation,
                "seek_generation": sought["media"]["generation"],
                "pixel_capture": probe["state"],
                "producer_renders_during_pin": advanced,
                "resume_unique_frames": resumed["native_status"][
                    "unique_post_draw_frames"
                ],
            }
        result["state"] = "measured"
        print(json.dumps(result["summary"], indent=2), flush=True)
    except BaseException as error:
        result["state"] = "failed"
        result["error"] = str(error)
        raise
    finally:
        if device.process:
            try:
                rec = device.request("close", "close")
                device.wait(
                    "close", rec, lambda r: r["media"]["session_id"] <= 0, timeout=20
                )
                result["closed"] = True
            except Exception as error:
                result["close_error"] = str(error)
                result["state"] = "failed"
        device.run("reverse", "--remove", f"tcp:{port}", optional=True)
        if args.mpv_log_level:
            set_property("debug.vrpp.mpv.log", previous_log, optional=True)
        if args.mpv_options is not None:
            set_property("debug.vrpp.mpv.opts", previous_options, optional=True)
        set_property("debug.vrpp.mpv.pool", previous_pool, optional=True)
        set_property("debug.vrpp.bridge.opaque_fast", previous_opaque, optional=True)
        set_property("debug.vrpp.mpv.gpu_frames", previous_gpu, optional=True)
        server.shutdown()
        server.server_close()
        result["http_requests"] = server.requests
        save()
        if "close_error" in result:
            raise RuntimeError("Playback cleanup failed: " + result["close_error"])


if __name__ == "__main__":
    main()
