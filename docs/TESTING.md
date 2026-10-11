# Testing

## Source-only checks

```powershell
python tools/Check-PublicSource.py
$env:GODOT_EXE = (Get-Command godot).Source
./tools/Test-Source.ps1
```

The public checker examines tracked files for excluded binary types, credentials and private paths. It is a publication boundary check, not a substitute for a full security review.

`Test-Source.ps1` runs the Godot GDScript host suite without activating the Android toolchain. It includes localization, media-library/menu interaction, controller/hand logic, projection/eye-order, preferences and image/depth handling. An OpenXR loader can be absent during headless tests; XR/device behavior is not part of their result.

The native depth stabilizer can also be tested with a C++17 compiler:

```bash
mkdir -p build/tests
g++ -std=c++17 -Wall -Wextra -Werror -I native/rvm tests/native/depth_stabilizer_test.cpp native/rvm/depth_stabilizer.cpp -o build/tests/depth_stabilizer_test
./build/tests/depth_stabilizer_test
```

## Android tests

With the full toolchain configured, `Build-Player.ps1` runs JVM tests as part of plugin assembly. `Test-Player.ps1` provides the broader historical host/render checks. Additional `Test-*Device.ps1` tools require an authorized headset and their specified media/model fixtures.

Only project-generated synthetic media are distributed. Moving-person tests and student training require user-supplied, licensed media; original personal media, numerical captures and device identifiers are excluded. Generate your own fixtures before attempting those optional probes.

## What constitutes device verification

Record the APK hash, device/vendor, model hash, input media contract and test scope. Distinguish decoding, inference, presented unique video frames, engine ticks and final XR display. Test seeking, pause/resume, menu interactions, permission revocation, background/foreground transitions, stereo alignment and sustained operation separately.

Host tests and ELF/APK inspection do not prove passthrough visuals, audio synchronization, physical hand/controller interaction or sustained frame rate. PICO export success is not PICO hardware validation.

## Ordinary playback performance

Build and install a no-AI Debug APK, then compare the legacy settings with the optimized defaults in the same package:

```bash
python3 benchmarks/mpv_playback_device.py --serial DEVICE --apk PLAYER.apk --original VIDEO.mp4 --borrow-color no --producer-pool expand --mpv-log-level debug --output artifacts/perf/copy
python3 benchmarks/mpv_playback_device.py --serial DEVICE --apk PLAYER.apk --original VIDEO.mp4 --borrow-color yes --producer-pool reuse --mpv-log-level info --controls --output artifacts/perf/borrow
```

The tool copies the original into the debug app's private fixture directory and verifies SHA-256 before playback; no transcoding or resolution cap is applied. It waits for a fresh Godot scene startup, checks the installed APK hash, records distinct rendered transaction owner draws separately from engine FPS, captures bridge copy/allocation counters and Android memory reports, and closes playback. Standard-libmpv transaction IDs do not independently certify unique decoded source images or exact source PTS. `--controls` additionally tests pause, an exact-seek request to zero, pinned Godot shader/mask readback and resume. The Debug-only 2D activity and receiver require `android.permission.DUMP`; neither is available in Release. `--transport http` instead serves the unchanged original through a range-capable ADB loopback server for transport comparisons. `--mpv-log-level debug` temporarily restores the old verbose logging for an A/B run and restores the prior property on exit.

Use several alternating runs and retain the raw JSON reports. Check `hwdec`, source dimensions and bridge counters before interpreting FPS. For example, the Android API 36 emulator's `c2.goldfish.hevc.decoder` rejects an 8192×4096 HEVC stream and mpv falls back to software decode. Such a run can verify texture ownership and eliminated copies, but cannot establish PICO hardware decoding throughput or XR compositor performance. Copy bytes describe explicit RGBA texture allocation, not total GPU/driver/process memory; borrowing can also change producer-ring occupancy. User videos, image readbacks and device reports stay in ignored `artifacts/` and are never committed.

For attribution, change one flag at a time while keeping CPU/GPU configuration and the remaining flags equal. The producer pool switch applies only to the standard-libmpv backend; Release always reuses allocated storage. The benchmark restores the previous Debug log/pool properties and rejects a configured output-width or frame-rate cap.

To isolate cached opaque handoff on an SBS VR180 original, run these cases sequentially with the same APK and device configuration:

```bash
python3 benchmarks/mpv_playback_device.py --serial DEVICE --apk PLAYER.apk --original VIDEO.mp4 --stereo --projection 2 --mpv-options opengl-pbo=no --opaque-fast no --gpu-frames 2 --output artifacts/perf/handoff-off
python3 benchmarks/mpv_playback_device.py --serial DEVICE --apk PLAYER.apk --original VIDEO.mp4 --stereo --projection 2 --mpv-options opengl-pbo=no --opaque-fast yes --gpu-frames 2 --controls --stress-pin --output artifacts/perf/handoff-on
```

Add `--entry xr` on a headset to launch the normal VR activity and require an initialized OpenXR viewport. Keep the headset worn and the application focused. The report includes its initial runtime/tracking capability snapshot; separately retain vendor runtime metrics to distinguish application rendering from video transaction updates. Neither counter independently proves unique decoded images or final compositor pixels.

`--warmup-seconds` defaults to five. `--stress-pin` resumes playback while shader readbacks hold their texture leases, requires producer renders to advance, then re-pauses before the seek test. Compare opaque and mask-enabled readbacks for each eye and rotation; SBS eyes need not match each other. `--expect-eof` separately checks a retained final pair with a short synthetic clip, or use `--start-ms` to test the end of an unchanged real video. Loss of fresh telemetry for ten seconds fails the probe; do not count a headset sleep or foreground interruption as a completed playback test. Use `--mpv-options hwdec=no,opengl-pbo=no` to isolate that regression from emulator hardware-decoder startup. PBO settings are diagnostic overrides, not a production default change.

The probe takes a nonblocking per-device lock (use the same canonical serial), validates report request/session/clock identity, and restores all modified Debug properties on exit. Do not run other device probes or Godot exports against that device concurrently. A run with a playback failure, request overlap or wrong active setting is invalid for comparisons. `bridge_capture_mean_us` and `capture_to_ready_mean_us` measure CPU wall-clock capture and handoff intervals; reducing them does not establish a decoded-frame FPS increase, especially with software 8K decoding.

`test_ai_optional.gd` covers a plugin reporting AI disabled: ordinary playback and seeking must not request inference, saved automatic-depth settings must not reactivate it, live AI controls are disabled, and precomputed packed masks remain available. For a prepared Android toolchain, run plugin unit tests and assembly with `-PenableAi=false`, then inspect the AAR/APK for absent `libquest_rvm.so` and model directories. Also build the default AI configuration to check both sides of the switch when its external dependencies are available.

The standard-libmpv base build is exercised with `python3 tools/build_player.py --vendor Quest --build-type Release`. It runs the JVM suite and verifies the exported APK's signature, ZIP alignment, ELF architecture/alignment, shared-library dependency closure and strong dynamic symbols against bundled libraries and Android API 29 system stubs. `python3 tools/test_build_player.py` exercises corrupt cached downloads and malicious ZIP paths/symlinks without network access. Standard playback-clock tickets are tested separately from exact source-frame tickets: they may display opaque video, but cannot authorize inferred Alpha/depth pairs. AI-specific photo conversion tests are skipped in model-free builds, with a separate test ensuring disabled depth queues no inference and retains no source lease.

`python3 tools/ci_android.py test` runs source publication checks, both Python boundary suites, a Godot import and every `test_*.gd` host regression, preserving logs and a JUnit report. `tools/test_ci_android.py` covers Android-only template extraction, corrupt cache repair and complete/partial/absent signing settings without using real signing material. Builder tests also exercise an export that reports an error and hangs, and a silent command timeout. Before packaging, CI exercises the real patched Godot template with Gradle's Copy task using an export URI containing spaces and a literal `+`, verifying the exact destination on each host. Windows/macOS CI runs this suite and the Android builder; CI success establishes build/package behavior, not headset playback performance.
