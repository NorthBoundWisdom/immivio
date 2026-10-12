# Testing

## Source-only checks

```powershell
python tools/Check-PublicSource.py
python tools/test_model_assets.py
$env:GODOT_EXE = (Get-Command godot).Source
./tools/Test-Source.ps1
```

The public checker examines tracked files for excluded binary types, credentials and private paths. It is a publication boundary check, not a substitute for a full security review.

`test_ci_ai.py` checks same-recipe dependency transfer, corruption rejection before publication, source-frame validation and safe ZIP entries. `test_ci_android.py` also checks that AI and no-AI jobs select the corresponding builder, tag refs force Release, branch/PR refs default to Debug, manual builds can select Release, Debug ignores release signing inputs, and mismatched AI/build-type receipts are rejected.

`test_model_assets.py` uses synthetic bytes to check public/custom model identities, path normalization, hash corruption, complete validation before replacing an existing pack, contract/runtime rejection and conversion provenance. JVM `ModelRepositoryTest` checks lazy hash verification, failure recovery and rejection before model bytes are opened. Neither suite proves numerical model compatibility. Real AI builds still need matching models, the patched MNN runtime and device validation.

`python tools/test_ai_native_compat.py --ndk /path/to/ndk` cross-compiles an Android string-hash probe and confirms the inference compatibility header avoids LLVM 21's new external `std::__hash_memory` dependency. MNN and the inference wrapper use libc++'s provided inline fallback, preserving Godot's single existing C++ runtime. Hosted CI runs this probe with the locked NDK; final APK inspection still checks every strong native dependency/symbol.

`Test-Source.ps1` runs the Godot GDScript host suite without activating the Android toolchain. It includes localization, media-library/menu interaction, controller/hand logic, projection/eye-order, preferences and image/depth handling. An OpenXR loader can be absent during headless tests; XR/device behavior is not part of their result.

`test_recent_scan.gd` covers startup cleanup of deleted local files/folders, persisted removals, escaped Unicode paths, confirmed missing documents, unavailable volumes, permission loss, timeouts, bounded busy retries, stale callbacks and shutdown cancellation. Startup scans video/photo history asynchronously; network sources and unconfirmed provider failures retain their entries. These checks use generated placeholder files only and never decode or capture media.

The native depth stabilizer can also be tested with a C++17 compiler:

```bash
mkdir -p build/tests
g++ -std=c++17 -Wall -Wextra -Werror -I native/rvm tests/native/depth_stabilizer_test.cpp native/rvm/depth_stabilizer.cpp -o build/tests/depth_stabilizer_test
./build/tests/depth_stabilizer_test
```

`test_playback_tools.gd` covers per-video timing isolation/persistence, rejected controls, delayed cue clocks, stale picker/import callbacks, asynchronous import confirmation, editable queue metadata/order, shuffle coverage, saved queue state, ray-target separation and verified EOF advance. The first queue advance must wait for `eof_pair_post_draw`; single-video looping and paused/stale sessions cannot auto-advance. `SubtitleImportTest` exercises supported suffixes, exact Unicode bytes, empty files and the 16 MiB copy bound. Host and package checks do not establish Android document-provider UX or headset audio synchronization.

## Android tests

With the full toolchain configured, `Build-Player.ps1` runs JVM tests as part of plugin assembly. `Test-Player.ps1` provides the broader historical host/render checks. Additional `Test-*Device.ps1` tools require an authorized headset and their specified media/model fixtures.

Only project-generated synthetic media are distributed. Moving-person tests and student training require user-supplied, licensed media; original personal media, numerical captures and device identifiers are excluded. Generate your own fixtures before attempting those optional probes.

## What constitutes device verification

Record the APK hash, device/vendor, model hash, input media contract and test scope. Distinguish decoding, inference, presented unique video frames, engine ticks and final XR display. Test seeking, pause/resume, menu interactions, permission revocation, background/foreground transitions, stereo alignment and sustained operation separately.

Host tests and ELF/APK inspection do not prove passthrough visuals, audio synchronization, physical hand/controller interaction or sustained frame rate. PICO export success is not PICO hardware validation.

`test_controller_canvas.gd` exercises controller grip movement, trigger tap/slider ownership, cancellation, relocated/rotated canvas alignment, projection changes and the maximum flat-screen interaction distance. `test_flat_screen_controls.gd` also covers grip-driven resizing across stereo/depth layouts. Device pose reports can confirm menu alignment and XR playback; physical button feel still needs manual headset feedback.

`test_panel_pointer.gd` covers laser stopping and reticle feedback on panel gaps, hidden controls, angled side panels, raised popups and curved surfaces, including transformed/scaled menus, invalid rays, tracking loss and foreground occlusion. Unavailable action buttons hide and return when enabled; informational rows and scrolling bounds remain intact. `test_xr_menu_compositor.gd` also checks blank-panel feedback through native-layer mapping. Physical controller/hand feedback still needs headset validation.

`test_quick_playback_settings.gd` exercises controller rays, slider ownership/release, actual speed commands, screen-size persistence, curve/loop selection, popup switching and stick suspension. `render_playback_toolbar.gd` provides synthetic English/Chinese previews of the compact popups. Playback omits the passthrough shortcut. `test_library_footer_resume.gd` checks that application pause/resume and XR focus transitions retain menu/screen poses and follow offsets. `test_system_recenter.gd` separately covers long-Home reset notifications, stale camera poses, a 180-degree reference-space rotation, follow/reclining modes, focus/tracking loss, duplicate requests, manual recenter and flat/immersive playback. System recenter waits for three tracked scene frames; focus recovery alone never schedules it. These host checks do not establish the physical system-button sequence on a headset.

Settings actions and choices use shared 0.065 m control height, 18 px text and inline icons. Informational rows retain their text without button backgrounds. `render_settings_style.gd`, with `SETTINGS_STYLE_PREVIEW_DIR` set, renders synthetic English/Chinese previews of video, library and photo settings, including Info, queue and paged audio choices. `render_ui_warmup.gd` checks that the changed controls still render and reuse prepared layouts. Media tiles, transport controls and slider capture areas keep their separate interaction roles.

With Reclining mode off (the default), flat-playback controls retain the canvas-centre direction and a world-vertical plane; idle head movement cannot tilt them. Flat-video placement also stays vertical during drag/follow/presentation, including under a rotated parent. Non-playback reset uses horizontal head direction and eye-relative height. `test_view_follow.gd` also exercises the General settings toggle, immediate orientation changes, full-pose reclining follow at steep pitch/roll, recentering, upright restoration, persistence across restart, and the independent Follow switch. Immersive controls sit 0.28 m below and 1.4 m along the reset/content gaze; their plane matches that gaze and remains stable until content orientation/reset changes. Playback panel scaling is 0.75 × 2/3; compositor capture uses unscaled camera/quad transforms and physical bounds to preserve visible size and ray targets. UI capture excludes the scene laser but includes its reticle. Slider capture freezes the placement plane. Tests cover these mode-specific poses and scaled pointer interaction. Standard quality uses 2x eye-buffer MSAA; Enhanced uses 4x for visible flat media and 2x for immersive media; High uses 4x. `viewport_msaa_3d` reports the active setting. `render_geometry_msaa.gd` compares numeric edge coverage and subpixel area stability using generated solid quads only; it saves no images and requires a real graphics context.

`test_ui_presentation.gd` exercises delayed/duplicate/stale GPU acknowledgements, page-pose freezing, bounded pending metadata, fixed first-open capture bounds and synthetic warmup without control activation. `render_ui_warmup.gd` renders all warmup pages on a real GPU and checks completion/resource cleanup without image readback. Debug device steps `player_settings`, `player_playback`, `player_screen`, `player_bar` and `ui_reset_stats` exercise actual presented ray targets; record warmup completion, capture/presented serials, layout revisions, rect changes and UI frame gaps using generated media only.

`render_ui_text_quality.gd` compares a generated CJK glyph with a high-resolution raster reference after registering ink bounds (MSDF and hinted raster line metrics differ). It saves numeric error/coverage only. `test_xr_menu_compositor.gd` checks front-face and bounds rejection, mapping onto an angled original control, pointer location and CJK/Latin font coverage. On a headset, confirm `ui_compositor.native_supported`, `presentation.ready`, increasing `presentation.blits`, empty `presentation.error`, nonzero UI draw calls, fixed 3072×2048 capture, and `menu_world_up_dot` near one for flat playback with Reclining mode off, `menu_facing_content_dot` near one and `timeline_content_offset` near `[0,-0.28,-1.4]` for immersive playback, `menu_scale` near `[0.75,0.666667]`, and `projected_ray_count == 0`. Exercise menu switching, hidden clearing, slider input and session resume without reading customer pixels. Native overlays intentionally remain above tracked models; ray/reticle feedback is included in the overlay.

## Ordinary playback performance

Build and install a no-AI Debug APK, then compare the legacy settings with the optimized defaults in the same package:

```bash
python3 benchmarks/mpv_playback_device.py --serial DEVICE --apk PLAYER.apk --original VIDEO.mp4 --borrow-color no --producer-pool expand --mpv-log-level debug --output artifacts/perf/copy
python3 benchmarks/mpv_playback_device.py --serial DEVICE --apk PLAYER.apk --original VIDEO.mp4 --borrow-color yes --producer-pool reuse --mpv-log-level info --controls --output artifacts/perf/borrow
```

The tool copies the original into the debug app's private fixture directory and verifies SHA-256 before playback; no transcoding or resolution cap is applied. It waits for a fresh Godot scene startup, checks the installed APK hash, records distinct rendered transaction owner draws separately from engine FPS, captures bridge copy/allocation counters and Android memory reports, and closes playback. Standard-libmpv transaction IDs do not independently certify unique decoded source images or exact source PTS. `--controls` additionally tests pause, an exact-seek request to zero, pinned Godot shader/mask readback and resume. The Debug-only 2D activity and receiver require `android.permission.DUMP`; neither is available in Release. `--transport http` instead serves the unchanged original through a range-capable ADB loopback server for transport comparisons. `--mpv-log-level debug` temporarily restores the old verbose logging for an A/B run and restores the prior property on exit.

For private media restricted to numerical performance analysis, do not use this copying harness, pixel commands, `--controls` or `--stress-pin`. The Debug/DUMP-only receiver's `open` command accepts `local_path` for a readable file already under shared storage, mutually exclusive with a network `uri`. Set `benchmark=true` before opening to disable automatic thumbnail loading/capture, and retain only technical counters. Do not copy private media into regression fixtures or retain raw content-bearing metadata. `test_performance_privacy.gd` exercises the thumbnail guard using generated metadata and a host that refuses pixel pins.

The opaque material can be compared with the general pair shader using generated patterns only:

```bash
godot --path app/godot --rendering-method gl_compatibility --script res://tests/render_opaque_pair.gd
```

This requires a real graphics context, compares numeric colour/alpha samples and native-handle binding, and saves no images. `THRU3D_OPAQUE_REPORT` optionally selects a numeric JSON report destination. Headless host tests do not establish GPU parity or headset performance.

For numerical seek attribution, set `debug.vrpp.mpv.seek_trace=1` before opening a Debug source, then restore the previous property after measurement. Each seek temporarily subscribes to MPV trace messages, suppresses raw MPV logcat output, and reduces recognized demux/MediaCodec messages to numeric timestamps, PTS, byte totals and bounded 100 ms buckets. At playback restart or a 12.8-second timeout, allow another 250 ms to reduce the numeric log tail before restoring the subscription level. MPV's event and log queues are separate, and changing the level destroys the pending log buffer. Wait for `seek_trace_drained` before recording totals and reject a timeout or nonzero `queue_overflows`. Counts include this bounded log tail, not solely the first target image. Message formats follow the pinned upstream sources; absent counters are unavailable evidence, not zero decoder work. Receipt timestamps can lag decoder operations and are not GPU timestamps.

Native seek phases distinguish renderer quiescence, command return, core seek notification, new-frame availability, render entry/return, publication and consumer acquisition. For standard-libmpv runs, verify `seek_event_at_us <= seek_frame_available_at_us <= seek_render_started_at_us`; frame info alone cannot certify the new epoch before the seek event. Keep explicit decoded-PTS verification separate from standard playback-clock estimates. The log reducer is exercised with synthetic strings only:

To diagnose a freeze after the first seek frame, Debug `debug.vrpp.mpv.seek_tail_ms` extends numeric tracing from 250 ms to at most 5000 ms after restart. Bounded buckets include decoder input/output, render entry/completion, consumer acquisition and observed audio/playback clocks. Distinguish continued decoding/acquisition from the final `unique_post_draw_frames` count: a monotonic-PTS display gate can incorrectly reject a corrected playback-clock estimate while the decoder continues. `post_draw_gap_max_us` measures gaps between distinct drawn transactions within one processing generation; lifecycle pauses also contribute and must be identified separately. Neither transaction count nor playback-clock PTS independently certifies unique decoded images.

```bash
c++ -std=c++17 -Wall -Wextra -Werror native/mpv/tests/seek_trace_test.cpp -o /tmp/thru3d-seek-trace-test
/tmp/thru3d-seek-trace-test
```

Use several alternating runs and retain the raw JSON reports. Check `hwdec`, source dimensions and bridge counters before interpreting FPS. For example, the Android API 36 emulator's `c2.goldfish.hevc.decoder` rejects an 8192×4096 HEVC stream and mpv falls back to software decode. Such a run can verify texture ownership and eliminated copies, but cannot establish PICO hardware decoding throughput or XR compositor performance. Copy bytes describe explicit RGBA texture allocation, not total GPU/driver/process memory; borrowing can also change producer-ring occupancy. Producer/source readbacks require media whose permissions allow them. User videos, image readbacks and device reports stay in ignored `artifacts/` and are never committed.

For attribution, change one flag at a time while keeping CPU/GPU configuration and the remaining flags equal. The producer pool switch applies only to the standard-libmpv backend; Release always reuses allocated storage. The benchmark restores the previous Debug log/pool properties and rejects a configured output-width or frame-rate cap.

To isolate cached opaque handoff on an SBS VR180 original, run these cases sequentially with the same APK and device configuration:

```bash
python3 benchmarks/mpv_playback_device.py --serial DEVICE --apk PLAYER.apk --original VIDEO.mp4 --stereo --projection 2 --mpv-options opengl-pbo=no --opaque-fast no --gpu-frames 2 --output artifacts/perf/handoff-off
python3 benchmarks/mpv_playback_device.py --serial DEVICE --apk PLAYER.apk --original VIDEO.mp4 --stereo --projection 2 --mpv-options opengl-pbo=no --opaque-fast yes --gpu-frames 2 --controls --stress-pin --output artifacts/perf/handoff-on
```

Add `--entry xr` on a headset to launch the normal VR activity and require an initialized OpenXR viewport. Keep the headset worn and the application focused. The report includes its initial runtime/tracking capability snapshot; separately retain vendor runtime metrics to distinguish application rendering from video transaction updates. Neither counter independently proves unique decoded images or final compositor pixels.

`--warmup-seconds` defaults to five. `--stress-pin` resumes playback while shader readbacks hold their texture leases, requires producer renders to advance, then re-pauses before the seek test. Compare opaque and mask-enabled readbacks for each eye and rotation; SBS eyes need not match each other. `--expect-eof` separately checks a retained final pair with a short synthetic clip, or use `--start-ms` to test the end of an unchanged real video. Loss of fresh telemetry for ten seconds fails the probe; do not count a headset sleep or foreground interruption as a completed playback test. Use `--mpv-options hwdec=no,opengl-pbo=no` to isolate that regression from emulator hardware-decoder startup. EOF verification requires three fresh ended observations with a stable rendered/published count and retained pair identity, in addition to the source-resolution and post-draw completion flags. For a real clip, start roughly thirty seconds before its end and sample for forty-five seconds. Add `--replay-after-eof` to require playback from zero in a new generation/source epoch, with the old EOF completion invalidated. This catches repeated terminal redraws and a terminal hold that incorrectly blocks replay. PBO settings are diagnostic overrides, not a production default change.

The probe takes a nonblocking per-device lock (use the same canonical serial), validates report request/session/clock identity, and restores all modified Debug properties on exit. Do not run other device probes or Godot exports against that device concurrently. A run with a playback failure, request overlap or wrong active setting is invalid for comparisons. `bridge_capture_mean_us` and `capture_to_ready_mean_us` measure CPU wall-clock capture and handoff intervals; reducing them does not establish a decoded-frame FPS increase, especially with software 8K decoding.

`test_ai_optional.gd` covers a plugin reporting AI disabled: ordinary playback and seeking must not request inference, saved automatic-depth settings must not reactivate it, live AI controls are disabled, and precomputed packed masks remain available. For a prepared Android toolchain, run plugin unit tests and assembly with `-PenableAi=false`, then inspect the AAR/APK for absent `libquest_rvm.so` and model directories. Also build the default AI configuration to check both sides of the switch when its external dependencies are available.

The standard-libmpv base build is exercised with `python3 tools/build_player.py --vendor Quest --build-type Release`. It runs the JVM suite and verifies the exported APK's signature, ZIP alignment, ELF architecture/alignment, shared-library dependency closure and strong dynamic symbols against bundled libraries and Android API 29 system stubs. `python3 tools/test_build_player.py` exercises corrupt cached downloads and malicious ZIP paths/symlinks without network access. Standard playback-clock tickets are tested separately from exact source-frame tickets: they may display opaque video, but cannot authorize inferred Alpha/depth pairs. AI-specific photo conversion tests are skipped in model-free builds, with a separate test ensuring disabled depth queues no inference and retains no source lease.

`python3 tools/ci_android.py test` runs source publication checks, both Python boundary suites, a Godot import and every `test_*.gd` host regression, preserving logs and a JUnit report. `tools/test_ci_android.py` covers Android-only template extraction, corrupt cache repair and complete/partial/absent signing settings without using real signing material. Builder tests also exercise an export that reports an error and hangs, and a silent command timeout. Before packaging, CI exercises the real patched Godot template with Gradle's Copy task using an export URI containing spaces and a literal `+`, verifying the exact destination on each host. Windows/macOS CI runs this suite and the Android builder; CI success establishes build/package behavior, not headset playback performance.
