# Testing Immivio

Prepare and configure dependencies as described in [BUILD.md](BUILD.md).

```sh
python3 -m unittest discover -s tests/workflow -v
python3 tools/test_prepare_android_release.py
python3 tools/Check-PublicSource.py
python3 configs/prepare_assets.py
python3 configs/check_environment.py
python3 configs/android_workflow.py test --vendor Quest --build-type Debug
```

Settings migration tests preserve ordinary preferences, source masks and stereo locks, reject reactivation by stale UI controls, and verify repeated cleanup needs no additional write.

`test_playback_tools.gd` also checks repeat-queue wrapping, single-entry reopening at zero, retained shuffle traversal, settings persistence and manual boundaries. `test_local_thumbnails.gd` executes visible-item scheduling, one outstanding decoder request, shared-cache integration, SBS/TB/panorama crops, cancellation, lifecycle return, stale-directory/changed-file reply rejection, preview-marker eviction and replacement by displayed-frame captures. Android `LocalThumbnailPolicyTest` checks local-source boundaries and decode-size limits; actual codec extraction requires Android execution. `test_headset_presence.gd` checks runtime/native absence precedence, pause/resume without seeking, duplicate events, manual-pause retention and closed-video protection. `HeadsetPresenceStateTest` checks native proximity/display transitions, initial screen-off and callbacks after shutdown.

On each supported headset, verify repeat off/on with one and multiple videos, then remove it during the last video's completion. Audio/video must stop and the queue must wait for return. Test removal during playback, manual pause and first-frame loading; confirm continued position, unchanged projection and no playback after closing. Repeat with casting on/off and a system menu: focus loss alone must not count as removal. Record which native/OpenXR event was delivered and any display-fallback delay. Browse fresh local SBS/TB/360 samples and a large directory, change folders during extraction, clear cache and start playback; verify thumbnail correctness, cancellation, input responsiveness and decoder availability. Host fixtures do not establish sensor delivery, codec compatibility or headset performance.

`test_stereo_detection.gd` checks unmarked SBS/TB image matches, unrelated/low-detail negatives, bounded consensus, worker execution, per-file automatic/manual provenance and cancellation on manual choices or file changes. `render_stereo_detection.gd` exercises the production full-frame GPU sampling path at 192×108; a left-eye-only thumbnail must not be recognized as another packed pair. `IMMIVIO_STEREO_SAMPLE_DIR` optionally supplies private `key-06.png` through `key-08.png` samples under ignored build directories for device-specific validation. These samples are never committed. Clear stereo metadata/names and saved manual settings take priority; uncertain content remains unchanged.

`test_network_sources.gd` exercises the unified Network media entry with asynchronous synthetic SMB, DLNA and media-server replies: four-item navigation, source identity/deduplication, flat provider-specific add/manage routes, complete protocol titles, return paths, retained folder/account state and stale-result rejection after switching sections. Delayed listings must retain an untouched chooser; only the matching submitted save may return to the source list. `QUEST_NETWORK_PREVIEW_ONLY=1` selects the matching source-list/setup renders in `render_library_menu.gd`.

`test_library_padding.gd` checks production control geometry against the shared four-sided panel inset across grid/list file browsing, network source choices, settings, media-server pages and file selection. It verifies centred content, scrollbar edge spacing and the retained ray hit width. Run `render_library_padding.gd` with a real GPU and `IMMIVIO_PADDING_DIR` under `artifacts/` for deterministic synthetic screenshots without any network or personal-media access.

The Android workflow offers `--level l0` (workflow and publication boundaries), `l1` (JVM integration), `l2` (Godot host behavior), and `all`. JVM tests use the configured dependencies offline. The Godot suite writes logs and JUnit results under `artifacts/tests/godot/`. A passing process must also emit exactly one completion report for the script being run; reaching the frame limit without finishing is a failure.

Native helper tests have one host entry point on macOS, Windows and Linux:

```sh
cmake -S native -B build/native/host -DCMAKE_BUILD_TYPE=Release
cmake --build build/native/host --config Release --parallel 2
ctest --test-dir build/native/host -C Release --output-on-failure
```

These tests exercise the production JSON writer against an independent Python Unicode oracle, numeric seek tracing, and both production subtitle-channel snapshots (independent command IDs, shared delay metadata and invalid-timeline clearing), plus collision-safe subtitle-slot application order. They require CMake, a C++17 compiler and Python 3.11+, and keep assertions enabled in Release builds. GitHub CI runs them on the macOS build host.

Workflow tests cover corrupt assets, offline acquisition boundaries, configuration staleness, separate Build/Package stages, safe cleanup, process timeouts and signing identity preservation. Release tests reject incomplete dependency provenance and mismatched tag/commit/host/variant or APK bytes.

Use the Android workflow for host tests and package verification. Rendering fixtures remain under `app/godot/tests/render_*.gd` for focused visual checks. Build and package each target before device verification. Existing device probes and media benchmarks remain available. Host/APK checks do not establish media or rendering correctness on a headset.

## Private-member test boundary

The [baseline inventory](audits/godot-private-access-before.json) records each
member, access count and every affected test file at `eead9b5`. It counts direct
dot-member accesses across all `app/godot/tests/**/*.gd`, including render
fixtures; comments and strings are excluded. The [current inventory](audits/godot-private-access-after.json)
retains the remaining work outside the first 20 members.

Tests observe frozen snapshots containing geometry, text, materials and stable
node/texture IDs as values. Snapshots do not expose live nodes or resources.
Explicit `test_*` commands drive deterministic input, ticks and fixture state;
render fixtures may request detached control copies. Snapshot immutability and
node/resource isolation are checked by `test_panel_pointer.gd`.

| Private member | Baseline accesses | Affected scripts | Public snapshot / test command |
| --- | --- | --- | --- |
| `_activate` | 183 | 35 | `test_activate` |
| `_buttons` | 136 | 56 | `controls_snapshot` |
| `_process` | 50 | 13 | `test_step` |
| `_choose` | 48 | 10 | `test_choose` |
| `_process_sticks` | 38 | 3 | `test_process_sticks` |
| `_apply_geometry` | 36 | 18 | `test_apply_geometry` |
| `_show_player_menu` | 36 | 15 | `test_show_player_menu` |
| `_quick_open` | 30 | 10 | `popup_snapshot` / `test_set_popup` |
| `_waiting_first` | 29 | 19 | `waiting_for_first_frame` / `test_set_waiting_for_frame` |
| `_on_setting_changed` | 26 | 8 | `test_setting_changed` |
| `_hover` | 23 | 12 | `hover_snapshot` / `test_set_hover` |
| `_show_library_menu` | 22 | 9 | `test_show_library_menu` |
| `_on_pointer_button` | 20 | 7 | `test_pointer_button` |
| `_on_pointer_release` | 20 | 6 | `test_pointer_release` |
| `_pointers` | 20 | 10 | `pointer_snapshot` / pointer test commands |
| `_update_hand_input` | 20 | 2 | `test_update_hand_input` |
| `_place_caption` | 16 | 6 | `test_place_caption` |
| `_place_menu` | 16 | 6 | `test_place_menu` |
| `_update_bounds` | 16 | 8 | `test_update_bounds` |
| `_backdrop` | 15 | 6 | `backdrop_snapshot` / `test_tag_menu` |

All 800 accesses to these 20 members were migrated. Other private accesses are
listed in the current inventory for later work. Source checks enforce that the
baseline's first 20 members stay at zero:

```sh
python3 tools/audit_godot_test_access.py --check-baseline docs/audits/godot-private-access-before.json
```

Regenerate the current inventory with `--output docs/audits/godot-private-access-after.json`.
The lexical audit has workflow fixtures for comments, quoted/triple-quoted text,
escaped quotes, chained access, aggregation and deterministic ordering.

## Rendering and visual checks

`render_background_performance.gd` compares the production cached starry sky with a dark clear, the legacy analytic sky without its star layers, and its 4K base-texture lookup. It warms each case for 60 frames, samples 180 frames, repeats the production sky, and checks looking down at the hills. Two independent 1440²/2048² viewports with 2× MSAA approximate stereo pixel load; they do not emulate headset hardware, OpenXR multiview or its compositor. Run with a real GPU and no frame cap:

```sh
godot --path app/godot --xr-mode off --rendering-method gl_compatibility --disable-vsync --script tests/render_background_performance.gd
```

The fixture also compares a copy of the completed HDR cache. It writes frame-time medians/p95, requested/actual VSync, available rendering timings and sky screenshots under `artifacts/reports/background-performance/`. GPU timing values of zero mean the backend did not supply a measurement. Diagnostic variants remove visible details to isolate cost; they are not proposed visual replacements. No video, UI or personal settings are loaded.

To compare with the legacy per-pixel star field, capture its expanded reference shader **before editing**:

```sh
python3 - <<'PY'
from pathlib import Path
shaders = Path('app/godot/shaders')
reference = (shaders / 'procedural_sky.gdshader').read_text().replace(
    '#include "res://shaders/procedural_scenery.gdshaderinc"',
    (shaders / 'procedural_scenery.gdshaderinc').read_text())
output = Path('build/tests/background-optimization/original_sky.gdshader')
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(reference)
PY
```

Run the paired timing/capture probe:

```sh
IMMIVIO_SKY_REFERENCE="$PWD/build/tests/background-optimization/original_sky.gdshader" godot --path app/godot --xr-mode off --disable-vsync --script tests/render_background_optimization.gd
```

This probe uses explicit offscreen draws to keep running when its host window is occluded. It compares reference/production/reference timings at 1024² and 2048² for upward, level and downward views, and captures twelve paired images including the pole, panorama seam, small head rotations and reduced brightness. The reference uses its original gamma-encoded 4K base; production uses an 8K linear HDR cache containing the star field. Both use the same scene parameters and 2× MSAA. Results and the reference hash go under `artifacts/reports/background-optimization/`; compare timings within the same run and avoid overlapping other GPU workloads. Review brightness, star detail, the horizon and seam in the paired images. Cached resampling is not pixel-identical to analytic per-eye antialiasing.

`benchmarks/background_compare.py` remains the strict pixel guard for analytic shader changes that promise equivalent output; it is not an acceptance test for cached resampling. `test_background.gd` additionally checks 8K RGB9E5/mipmap storage, cache reuse during rotation/brightness changes, and release on scene changes when run with a real renderer. Its headless run checks lifecycle/state only. Neither host probe establishes headset frame rate: record focused runtime samples and head poses while looking around, and distinguish the frame-rate sample interval from the pose-observation interval.

Host-environment tests verify SDK selection, actual downloads through a local HTTP fixture, checksum failures, failed responses and archive extraction boundaries. No external network or account is needed for these checks.

Use [ACCEPTANCE.md](ACCEPTANCE.md) for recorded local checks and the remaining device verification sequence, and [FRAME_CONTRACT.md](FRAME_CONTRACT.md) when adapting device reports. Historical results do not certify later source changes.

## Test responsibilities

- `tests/workflow` and the release tests protect configuration freshness, byte integrity, signing and publication boundaries. Archive tests use a local HTTP fixture to check explicit downloads, offline reuse and corrupt bytes. The build scripts are also exercised in an isolated source copy with Python site packages disabled, including asset verification and build receipts without Git metadata or optional editor configuration. Workspace-lock tests cover nested calls, concurrent threads and processes, and release after process exit.
- `app/godot/tests/test_*.gd` exercise the current playback controller, captions, persistent state, menus and input behavior. The playback control and geometry suites use focused state transitions and invariants rather than constructing the old player implementation.
- Android/JVM tests cover protocol parsing, actual loopback HTTP/range reads, account isolation, file operations and frame/resource ownership. Credential-dependent live checks report explicit skips.
- Retained `render_*.gd` checks need a real GPU renderer and have failure conditions such as pixel differences, invalid geometry, clipping or incomplete warmup. Saving a screenshot alone is not an automated regression result. They are not run by the headless suite. Thumbnail capture pixels live in `render_thumbnail_capture.gd`; `test_thumbnails.gd` covers cache and library behavior without waiting for a GPU.

`render_seek_highlight.gd` checks the real hovered timeline material with MSAA disabled at two pixel densities and two angles. It requires fractional alpha coverage outside the logical rectangle, opaque coverage inside, and transparent pixels beyond the narrow antialiasing band. Run it with a real renderer, for example `godot --xr-mode off --rendering-method gl_compatibility --rendering-driver opengl3 --path app/godot --script res://tests/render_seek_highlight.gd`. Set `IMMIVIO_HIGHLIGHT_DIR` to a directory under `artifacts/` to save its edge samples.

`render_menu_transitions.gd` uses real GPU capture with synthetic red, green and blue pages. It verifies that switching the active menu and expanding its projection hide the preceding texture until the new draw completes, and that each new page subsequently appears. Run it with the same real-renderer flags; `IMMIVIO_TRANSITIONS_DIR` optionally saves transition frames under `artifacts/`. `test_ui_presentation.gd` covers native acknowledgement gating without hardware, including keeping ordinary redraws visible. `test_window_height.gd` covers height persistence, slider-release placement, flat/immersive video controls and reclining placement. Headset lens comfort and native runtime presentation still need device acceptance.

`render_library_page_switch.gd` switches the production library between Settings and Network media four times, checking all twelve rendered transition frames for loss of window coverage. `IMMIVIO_PAGE_SWITCH_DIR` optionally saves the frames. `test_library_page_presentation.gd` covers the same continuity policy for native quad and cylinder layers, preserves acknowledgement-based input readiness, and rejects reuse after changing placement, bounds, curvature or the visible menu set.

`render_stereo_pointer.gd` renders the production 3D beam in the main scene from separate left/right eye poses with 2× MSAA and verifies depth-dependent disparity. Its independent orthographic UI capture must contain only the hit reticle. Production beams use the main XR projection, without additional per-eye pointer viewports or composition layers. Run it with the OpenGL compatibility renderer. `test_panel_ray_projection.gd` checks controller-to-hit geometry, UI/main-scene separation and tracking/fallback visibility.

`XrSurfacePresenterTest` checks that a successful Android Surface copy consumes its capture once, an unchanged serial needs no further copy, a failed copy can retry, and acknowledging an older frame cannot discard a newer capture. Surface replacement and context loss require a fresh copy even when the serial is reused. This keeps idle UI paint scheduling effective through the native presenter; frame ownership tests alone do not establish headset frame rate.

`render_pointer_style.gd` checks the production beam at two pixel densities and four angles with MSAA disabled. It measures thin-stroke coverage, fractional edge alpha and decreasing opacity toward the hit point. `IMMIVIO_RAY_STYLE_DIR` optionally saves synthetic captures under `artifacts/captures/ui/`.

`render_menu_pictures.gd` renders known RGBA quadrants through the production rounded thumbnail/cover material. It checks colour orientation, source-image transparency and rounded-corner clipping. Run it with the OpenGL compatibility renderer.

`test_pointer_redraw_continuity.gd` delays native GPU acknowledgements after clicking production library navigation on flat and cylindrical captures. The laser must keep stopping on the displayed panel and follow hand motion while replacement controls remain inactive. It also checks retired panel nodes, transparent padding, floating buttons and their round corners, tracking loss, incompatible projections and a closing playback-library companion. Panel/button geometry travels with capture metadata so visual occlusion follows the acknowledged image independently of input readiness.

Each headless Godot test calls `preload("res://tests/support/test_result.gd").prepare(self)` first. This creates a separate `user://` directory for that script and process, so caches and saved settings cannot come from a previous test or a normal app session. The directory is printed in its log for failure diagnosis. It ends with `preload("res://tests/support/test_result.gd").finish(self, exit_code)`. Keep the assertions in the test; the helper reports completion and exits. Do not print a success report from initialization or a timeout handler. The runner rejects missing, duplicate, malformed and foreign-script reports, nonzero exits, and engine errors even after a success report.

Prefer a small test that fails when a real contract is broken: stale callbacks must not revive a closed session, failed file operations must preserve the original, or corrupt bytes must not be published. Mock hardware/network boundaries where needed, while executing the production behavior being checked. Avoid tests that replace the whole subject with a mock, merely repeat constants or private control layouts, or duplicate a dependency's own suite.

## Owned local Jellyfin port integration

`JellyfinLivePortsTest` skips explicitly unless `IMMIVIO_JELLYFIN_LIVE_JSON` names a private JSON file containing `url`, `username`, `password`, `movie_id` and `library_id`. Only loopback endpoints are accepted. Use an isolated server with synthetic, two-version movie media and a nested directory; the movie must be long enough for the server's resume threshold. The test logs in, checks folder containers and version selection, streams an authenticated byte range, reports both paused-start and playing → pause → stop sessions, reads resume from the selected version item (not the grouped movie, whose UserData may differ), and verifies disabling history sends no more reports or progress. Run with the existing offline Gradle dependency cache:

```sh
"$GRADLE_EXE" -p android --offline :player-plugin:testDebugUnitTest --tests '*JellyfinLivePortsTest'
```

Keep the JSON file, credentials, server data, media and logs under ignored `artifacts/`; remove the owned server/container and synthetic media after the run. Never point this mutating test at a personal library or commit its credentials.

Playback popup continuity: `test_playback_popup_continuity.gd` checks transport node retention, stable subtitle bounds, live timeline updates and capture-gated input. `test_playback_page_surfaces.gd` also covers compact-browser replacement without reanchoring. Run `render_playback_popup_continuity.gd` with the OpenGL compatibility renderer for three GPU frames at each open/close transition across ten production popups with ray clicks and a moving viewer. It compares the title/timeline pixels to the settled hover frame before each click; set `IMMIVIO_POPUP_FRAMES_DIR` to retain synthetic screenshots. This checks scene capture continuity; native headset comfort still requires wearer acceptance.

`test_playback_page_surfaces.gd` includes the first compact-library opening, return-to-playback placement and browser attachment during head translation with follow on/off across flat, fisheye and equirectangular video. `render_playback_page_switch.gd` drives the production host through Library, Playback and Info, comparing timeline pixels over three GPU frames per transition, including the first Library opening. Run it with the same OpenGL compatibility flags; `IMMIVIO_PLAYBACK_PAGES_DIR` optionally saves its synthetic frames. The library projection and hover margins must be reserved before its first open so navigation cannot resize the compositor or move the timeline.

`tests/workflow/test_pico_store.py` checks compiled store manifest/ZIP rules, real OpenXR metadata, package and version drift, ABI/channel/debug guards, signer mismatch, size, launcher duplication, optional app-ID validation and the same-track uploaded baseline. Store signing tests ensure a missing identity cannot silently generate a replacement key, artifact cleanup cannot remove a persistent identity, and legacy migration cannot overwrite a different key. A packaged PICO Release/appstore APK must also produce a passing `.store-report.json`; platform review remains separate.

`test_output_paths.py` verifies move-only migration, package/receipt pairing, collision preservation, cleanup boundaries, private-key and symlink rejection, nested CI summaries and automatic removal of temporary native inspection files. Release tests exercise the nested CI download layout and flattened publication bundle. Host-test temporary inputs live under `build/tests/godot/`; saved render evidence lives under `artifacts/captures/ui/`.

## Device probes and local media

All device probes use `tools/device_probe.py` for ADB selection/quoting, installed
APK SHA-256 checks, unique request keys, process identity, bounded waits and JSON
evidence. Choose the device with `--serial` and optionally `--port`. Supply the
exact installed current Debug APK with `--apk`; the tools do not install or
upgrade the player automatically. Default output is a unique run directory under
`artifacts/captures/device/<probe>/`; explicit `--output` (or `--out` for selected
features) must remain under `artifacts/captures/device/`.

| Script | Device required | Media | Source |
| --- | --- | --- | --- |
| `tools/Test-SelectedFeaturesDevice.py` | Physical headset | MP03 for player steps; optional prepared acceptance clips | Bundled MP03 / synthetic acceptance fixtures |
| `benchmarks/mpv_playback_device.py` | Android device; XR needs headset | Explicit `--original` | Caller-owned file, hash-verified upload or USB HTTP |
| `benchmarks/mpv_seek_strategy_device.py` | Physical headset | Explicit `--fixture` or `--uri-file`, plus `--packets` for exact media | Caller-prepared local/network source |
| `benchmarks/mpv_startup_device.py` | Physical headset | Explicit `--fixture`, `--original` or `--uri-file` | Caller-prepared local/network source |
| `tools/run_device_diagnostics.py core` | Android device | C03/C04 | Bundled |
| `tools/run_device_diagnostics.py gpu` | Android device with compatible GLES | C03/C04 | Bundled |
| `tools/run_device_diagnostics.py audio` | Android device with audio focus | MP06 audio clock | Bundled |
| `tools/run_external_uri_probe.py` | Android device; headset acceptance pending | MP03 in a separate-UID fixture APK | Conditional `android/uri-fixture` module |
| `benchmarks/mpv_audio_probe.py`, `mpv_gpu_probe.py`, `c04_fixture_decode.py` | No live device | Captured report and matching fixture | Reports from the native driver / bundled or generated media |

For example, `python3 tools/run_device_diagnostics.py gpu --serial SERIAL --apk
/path/to/debug.apk --fixture c03_sbs_grid` verifies the installed bytes, sends
`DEBUG_MPV_GPU`, waits for matching request/process/ID and saves the raw report.
`core` is software-only; `--software` selects software decode for GPU/audio.
The native GPU and audio auditors can then inspect the saved `gpu-report.json`
or `audio-report.json`. Successful native probes do not establish Godot/XR
presentation, audible speaker output or headset performance.

Player reports must echo the unique command key; native core/GPU/audio reports
now echo it directly. Old, mismatched or cross-process reports cannot complete a
run. On timeout, the tools preserve the last receipt/report for inspection.
The playback probe's obsolete `--borrow-color` option has been removed; capture
uses the fixed production borrowed-color path.

Prepare any local player fixture explicitly in `files/fixtures/` using the Debug
app UID. For example:

```sh
adb -s SERIAL exec-in run-as com.northboundwisdom.immivio sh -c 'mkdir -p files/fixtures; cat > files/fixtures/mp08_8k_high_30.mp4' < /path/to/owned.mp4
```

The seek probe also needs FFprobe `--packets` for those exact bytes. Fixtures are
never downloaded automatically. Use each driver's `--help` for transport and
measurement controls.

The player receiver accepts only `mp03_frame_identity`, `mp06_text_subtitles`,
`mp08_8k_high_30` and `mpv_performance`. The default MP03 fixture is bundled;
the other three require explicit local preparation/upload. Missing, empty or
oversized files fail with `Prepare local fixture … before running the probe`,
including the app-private target path and permitted byte range. Unused legacy
fixture names and the private-source MP07 generator have been removed.

`benchmarks/mpv_audio_probe.py`, `mpv_gpu_probe.py` and `c04_fixture_decode.py`
audit supplied diagnostic JSON or decode bundled/generated fixtures. `dlna_catalog_probe.py` reads an explicitly supplied LAN DLNA
catalog; the background and host seek probes run on the host. The former local
access, selection and seek-hold auditors remain removed, with those categories
covered by manual acceptance. External URI testing now uses the conditional
fixture and Python driver below. No existing JVM or workflow cases were removed.

Generate the bundled C03 grid with
`python3 tools/media/generate_c03_fixtures.py --font /path/to/Arial.ttf` using
FFmpeg with the `drawtext` filter. The geometry, timing and encoding arguments
match the original recipe; font and FFmpeg/libx264 versions can change bytes.

For diagnostic report auditors, generate audio via
`python3 tools/media/generate_mp06_audio_fixture.py` (uses the bundled MP03 video)
and subtitles via `python3 tools/media/generate_mp06_subtitle_fixture.py`; push
the generated subtitle MKV to `files/fixtures/mp06_text_subtitles.mkv` when opening
it through the player receiver. GPU/core requests accept the bundled
`c03_sbs_grid`, `c04_alpha_f180` and `c04_independent_alpha` files; audio requests
use bundled `mp06_audio_clock`. Capture reports with the retained
`DEBUG_MPV_GPU`, `DEBUG_MPV_CORE` or `DEBUG_MPV_AUDIO` broadcasts, including a
unique `request` string, then pull the resulting JSON from `files/diagnostics`
using `run-as` before running the matching auditor. `tools/run_device_diagnostics.py` drives these three native report routes end to
end; host audits still require the matching media and optional media-tool packages.

The retired `normal_fast`, `frame_cap` and `borrow_color` player command options
are no longer read. Debug and Release use the same opaque capture path,
unlimited native cadence and borrowed producer color.


### Debug system properties

The native Debug playback core and render bridge read the `debug.immivio.*`
namespace. These values are read during native core/renderer initialization;
reopen the source to apply changes. Kotlin does not read these properties.

| Property | Meaning / default |
| --- | --- |
| `debug.immivio.mpv.max_width` | Debug color-width cap; `0` keeps source width |
| `debug.immivio.mpv.pool` | `expand` disables ready-slot reuse; reuse is the default |
| `debug.immivio.mpv.gpu_frames` | GPU frame queue limit; default `2` |
| `debug.immivio.mpv.seek_trace` | `1` enables native seek traces; off by default |
| `debug.immivio.mpv.seek_tail_ms` | Seek-trace tail; default `250`, overrides clamped to 250–5000 ms |
| `debug.immivio.mpv.opts` | Comma-separated libmpv `name=value` overrides; empty by default |
| `debug.immivio.mpv.log` | `no`, `fatal`, `error`, `warn`, `info`, `v`, `debug` or `trace`; Debug defaults to `info` |
| `debug.immivio.bridge.opaque_fast` | `no` disables the cached opaque-state fast path; on by default |

For example, `adb shell setprop debug.immivio.mpv.seek_trace 1` enables the
native seek trace for a newly opened source. The playback/startup device probes
save and restore the properties they modify. Release builds do not read these
Debug overrides.

### Android log labels

The renamed shared playback/library labels use `Immivio*` on PICO, Quest and
OpenXR targets. Select labels by subsystem when collecting logcat evidence:

| Subsystem | Labels |
| --- | --- |
| Playback and native probes | `ImmivioMpv`, `ImmivioMpvSource` |
| GL ownership and frozen frames | `ImmivioGlOwner`, `ImmivioMpvFreeze` |
| Library, sidecars and captions | `ImmivioDlna`, `ImmivioSidecarAudio`, `ImmivioSubtitles` |
| Presence/session feedback | `ImmivioPlayer` |

For example:

```sh
adb logcat ImmivioMpvSource:I ImmivioMpv:V ImmivioPlayer:I ImmivioDlna:I '*:S'
```

Plugin identifiers remain as documented in [ARCHITECTURE.md](ARCHITECTURE.md#retained-internal-names).
Thread and multicast-lock names are separate from logcat labels.

### External URI grant automation

The URI fixture is excluded from the default Gradle graph and every ordinary
player package. After configuring the Debug player, build the test APK explicitly:

```sh
python3 - <<'PYCODE'
import subprocess
from configs.dependencies import find_gradle
subprocess.run([find_gradle(), '-p', 'android', '--offline',
                '-PincludeUriFixture=true', ':uri-fixture:assembleDebug'], check=True)
PYCODE
python3 tools/run_external_uri_probe.py --serial SERIAL --apk /path/to/current-player-debug.apk --fixture-apk android/uri-fixture/build/outputs/apk/debug/uri-fixture-debug.apk
```

The driver verifies the installed player, installs/verifies the fixture, checks
separate UIDs and exact synthetic clip bytes, proves denial before grant, decodes
through a real granted FD, revokes permission, then proves denial both before and
after restarting the player process. A decoder error cannot count as a permission
denial. Receipts and native reports must match request key, ID and process.
The driver stops the player, never clears player data, and attempts revocation
and fixture uninstall even after failure. `--keep-fixture` retains only the test
APK; grant cleanup still runs. It does not automate the system document picker,
local-access preflight or seek pixel comparisons. Those remain manual checks.

The fixture packages only `mp03_frame_identity.mp4`; no personal source is used.
Default output is `artifacts/captures/device/external-uri/<run>/`. Host fake-ADB
checks and a built APK do not verify Android grant delivery; run this command on
the target headset and keep its result directory for acceptance.


The seek and startup drivers have no implicit media default. Seek requires
exactly one of `--fixture` or `--uri-file`; startup requires exactly one of
`--fixture`, `--original` or `--uri-file`. The four player fixture names are
validated by argument parsing. Selecting `--fixture mp08_8k_high_30` explicitly
still requires a locally prepared MP4; it is not bundled or generated by the
probe. A missing source choice fails before any ADB call. No synthetic fixture
is presented as a substitute for real-media headset performance evidence.
