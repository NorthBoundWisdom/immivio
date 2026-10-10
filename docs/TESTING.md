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

Build and install a no-AI Debug APK, then run the same package with both bridge paths:

```bash
python3 benchmarks/mpv_playback_device.py --serial DEVICE --apk PLAYER.apk --original VIDEO.mp4 --borrow-color no --output artifacts/perf/copy
python3 benchmarks/mpv_playback_device.py --serial DEVICE --apk PLAYER.apk --original VIDEO.mp4 --borrow-color yes --controls --output artifacts/perf/borrow
```

The tool copies the original into the debug app's private fixture directory and verifies SHA-256 before playback; no transcoding or resolution cap is applied. It waits for a fresh Godot scene startup, checks the installed APK hash, records distinct rendered transaction owner draws separately from engine FPS, captures bridge copy/allocation counters and Android memory reports, and closes playback. Standard-libmpv transaction IDs do not independently certify unique decoded source images or exact source PTS. `--controls` additionally tests pause, an exact-seek request to zero, pinned Godot shader/mask readback and resume. The Debug-only 2D activity and receiver require `android.permission.DUMP`; neither is available in Release. `--transport http` instead serves the unchanged original through a range-capable ADB loopback server for transport comparisons. `--mpv-log-level debug` temporarily restores the old verbose logging for an A/B run and restores the prior property on exit.

Use several alternating runs and retain the raw JSON reports. Check `hwdec`, source dimensions and bridge counters before interpreting FPS. For example, the Android API 36 emulator's `c2.goldfish.hevc.decoder` rejects an 8192×4096 HEVC stream and mpv falls back to software decode. Such a run can verify texture ownership and eliminated copies, but cannot establish PICO hardware decoding throughput or XR compositor performance. Copy bytes describe explicit RGBA texture allocation, not total GPU/driver/process memory; borrowing can also change producer-ring occupancy. User videos, image readbacks and device reports stay in ignored `artifacts/` and are never committed.

`test_ai_optional.gd` covers a plugin reporting AI disabled: ordinary playback and seeking must not request inference, saved automatic-depth settings must not reactivate it, live AI controls are disabled, and precomputed packed masks remain available. For a prepared Android toolchain, run plugin unit tests and assembly with `-PenableAi=false`, then inspect the AAR/APK for absent `libquest_rvm.so` and model directories. Also build the default AI configuration to check both sides of the switch when its external dependencies are available.

The standard-libmpv base build is exercised with `python3 tools/build_player.py --vendor Quest --build-type Release`. It runs the JVM suite and verifies the exported APK's signature, ZIP alignment, ELF architecture/alignment, shared-library dependency closure and strong dynamic symbols against bundled libraries and Android API 29 system stubs. `python3 tools/test_build_player.py` exercises corrupt cached downloads and malicious ZIP paths/symlinks without network access. Standard playback-clock tickets are tested separately from exact source-frame tickets: they may display opaque video, but cannot authorize inferred Alpha/depth pairs. AI-specific photo conversion tests are skipped in model-free builds, with a separate test ensuring disabled depth queues no inference and retains no source lease.

`python3 tools/ci_android.py test` runs source publication checks, both Python boundary suites, a Godot import and every `test_*.gd` host regression, preserving logs and a JUnit report. `tools/test_ci_android.py` covers Android-only template extraction, corrupt cache repair and complete/partial/absent signing settings without using real signing material. Builder tests also exercise an export that reports an error and hangs, and a silent command timeout. Before packaging, CI exercises the real patched Godot template with Gradle's Copy task using an export URI containing spaces and a literal `+`, verifying the exact destination on each host. Windows/macOS CI runs this suite and the Android builder; CI success establishes build/package behavior, not headset playback performance.
