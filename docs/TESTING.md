# Testing Immivio

Prepare and configure dependencies as described in [BUILD.md](BUILD.md).

```sh
python3 -m unittest discover -s tests/workflow -v
python3 -m unittest discover -s tests/website
python3 tools/test_prepare_android_release.py
python3 tools/Check-PublicSource.py
python3 configs/check_environment.py
python3 configs/android_workflow.py test --vendor Quest --build-type Debug
```

`android_workflow.py test` accepts `--level l0` (workflow and publication boundaries), `l1` (JVM), `l2` (Godot host behavior) or `all`. JVM tests use the prepared dependencies offline. Godot logs and JUnit results go to `artifacts/tests/godot/`.

Native helper tests run on any host with CMake, a C++17 compiler and Python 3.11+:

```sh
cmake -S native -B build/native/host -DCMAKE_BUILD_TYPE=Release
cmake --build build/native/host --config Release --parallel 2
ctest --test-dir build/native/host -C Release --output-on-failure
```

## What the suites cover

- `tests/workflow` and the release tests: configuration freshness, offline acquisition, byte integrity, signing, store-package rules, output layout and publication boundaries. Archive tests use a local HTTP fixture; no external network or account is needed.
- `app/godot/tests/test_*.gd`: playback control, captions, persistent state, menus, input and presentation behavior on the host.
- Android/JVM tests: protocol parsing, loopback HTTP/range reads, SMB recovery, account isolation, file operations and frame/resource ownership. Credential-dependent live checks report explicit skips.
- `tests/native`: the JSON writer, seek tracing and subtitle-channel snapshots.

Host results do not establish headset display, audio or performance; use [device acceptance](ACCEPTANCE.md) for that.

## Writing tests

Each headless Godot test starts with `preload("res://tests/support/test_result.gd").prepare(self)`, which gives the script its own `user://` directory, and ends with `.finish(self, exit_code)`. Keep assertions in the test; do not report success from initialization or a timeout handler. The runner rejects missing, duplicate or foreign completion reports, nonzero exits and engine errors.

Prefer small tests that fail when a real contract breaks: stale callbacks must not revive a closed session, failed file operations must preserve the original, corrupt bytes must not be published. Mock hardware and network boundaries, but execute the production behavior under test. Avoid tests that only repeat constants or private layouts.

## Private-member test boundary

Tests observe frozen snapshots (geometry, text, materials, stable node/texture IDs as values) and drive deterministic input through explicit `test_*` commands instead of calling private members. The [baseline inventory](audits/godot-private-access-before.json) lists the members that must stay at zero direct accesses from `app/godot/tests/`; source CI enforces it:

```sh
python3 tools/audit_godot_test_access.py --check-baseline docs/audits/godot-private-access-before.json
```

Use `--output <file>` to list the remaining private accesses.

## GPU render fixtures

`app/godot/tests/render_*.gd` need a real GPU and are not part of the headless suite. Run them with:

```sh
godot --xr-mode off --rendering-method gl_compatibility --rendering-driver opengl3 --path app/godot --script res://tests/<fixture>.gd
```

| Fixture | Checks | Optional output variable |
| --- | --- | --- |
| `render_background_performance.gd` | Cached sky versus reference timings (add `--disable-vsync`) | Writes to `artifacts/reports/background-performance/` |
| `render_background_optimization.gd` | Paired reference/production sky timings and images; set `IMMIVIO_SKY_REFERENCE` to an expanded reference shader | Writes to `artifacts/reports/background-optimization/` |
| `render_seek_highlight.gd` | Timeline highlight edge coverage | `IMMIVIO_HIGHLIGHT_DIR` |
| `render_menu_transitions.gd` | No stale page during menu switches | `IMMIVIO_TRANSITIONS_DIR` |
| `render_library_page_switch.gd` | Window coverage across library page switches | `IMMIVIO_PAGE_SWITCH_DIR` |
| `render_library_padding.gd` | Panel inset geometry | `IMMIVIO_PADDING_DIR` |
| `render_library_menu.gd` | Library and network-source renders | `QUEST_NETWORK_PREVIEW_ONLY=1` |
| `render_playback_popup_continuity.gd` | Title/timeline stability across popup transitions | `IMMIVIO_POPUP_FRAMES_DIR` |
| `render_playback_page_switch.gd` | Timeline stability across Library/Playback/Info | `IMMIVIO_PLAYBACK_PAGES_DIR` |
| `render_stereo_pointer.gd`, `render_pointer_style.gd` | Beam disparity, stroke coverage and fade | `IMMIVIO_RAY_STYLE_DIR` |
| `render_menu_pictures.gd` | Thumbnail orientation, transparency and corner clipping | — |
| `render_thumbnail_capture.gd` | Thumbnail capture pixels | — |
| `render_stereo_detection.gd` | Packed-stereo sampling; `IMMIVIO_STEREO_SAMPLE_DIR` adds private samples kept outside Git | — |
| `render_packed_alpha_pair.gd` | Mask pixels and opaque/packed shader switching | — |
| `render_upstream_playback.gd` | Caption opacity and fisheye/equirectangular disparity | Writes to `artifacts/captures/upstream-playback/` |
| `render_video_layers.gd` | Backdrop, hole and foreground composition | — |

Save outputs under `artifacts/`. A saved screenshot alone is not a pass; each fixture has explicit failure conditions. `benchmarks/background_compare.py` is the strict pixel guard for analytic sky shader changes.

## Optional live Jellyfin test

`JellyfinLivePortsTest` skips unless `IMMIVIO_JELLYFIN_LIVE_JSON` names a JSON file with `url`, `username`, `password`, `movie_id` and `library_id`. Only loopback endpoints are accepted. Use a disposable server with synthetic two-version media; the test writes playback progress. Never point it at a personal library or commit its credentials.

```sh
"$GRADLE_EXE" -p android --offline :player-plugin:testDebugUnitTest --tests '*JellyfinLivePortsTest'
```

## Emulator runtime checks

These runners refuse physical devices and use only synthetic media:

```sh
python3 tools/test_mpv_android_runtime.py --serial emulator-5554 --port 5037
python3 tools/test_video_layers_android.py --serial emulator-5554 --port 5037
```

The first loads the prepared playback runtime and exercises muted AAudio, seek/pause/speed and HDR options without installing an app. The second builds the disposable `android/performance-fixture`, checks GLES composition and decoder-Surface delivery, then uninstalls it. Reports go to `artifacts/tests/`.

## Device probes and local media

All probes use `tools/device_probe.py` for ADB selection, installed-APK SHA-256 checks, unique request keys, process identity, bounded waits and JSON evidence. Pass `--serial`, optionally `--port`, and the installed Debug APK with `--apk`; the tools never install the player. Output goes to `artifacts/captures/device/<probe>/<run>/`.

If an emulator and a headset are on different ADB servers, check each server port with `adb -P PORT devices -l` and keep that port on every command. Competing ADB servers can starve the headset's USB interface; start emulator-only servers with `ADB_USB=0`.

| Script | Device | Media |
| --- | --- | --- |
| `tools/Test-SelectedFeaturesDevice.py` | Physical headset | Bundled MP03; optional prepared clips |
| `tools/run_device_diagnostics.py core` / `gpu` / `audio` | Android device | Bundled C03/C04 or MP06 audio clock |
| `tools/run_external_uri_probe.py` | Android device | MP03 inside a separate-UID fixture APK |
| `benchmarks/mpv_playback_device.py` | Android device; XR needs a headset | Explicit `--original` |
| `benchmarks/mpv_seek_strategy_device.py` | Physical headset | `--fixture` or `--uri-file`, plus FFprobe `--packets` |
| `benchmarks/mpv_startup_device.py` | Physical headset | `--fixture`, `--original` or `--uri-file` |
| `benchmarks/mpv_audio_probe.py`, `mpv_gpu_probe.py`, `c04_fixture_decode.py` | None | Saved report plus matching fixture |

Example: `python3 tools/run_device_diagnostics.py gpu --serial SERIAL --apk /path/to/debug.apk --fixture c03_sbs_grid`. Native probe success does not establish XR presentation, audible output or performance.

The player receiver accepts `mp03_frame_identity` (bundled), `mp06_text_subtitles`, `mp08_8k_high_30` and `mpv_performance`. Upload non-bundled fixtures yourself:

```sh
adb -s SERIAL exec-in run-as com.northboundwisdom.immivio sh -c 'mkdir -p files/fixtures; cat > files/fixtures/mp08_8k_high_30.mp4' < /path/to/owned.mp4
```

Fixture generators live in `tools/media/` (`generate_c03_fixtures.py`, `generate_mp06_audio_fixture.py`, `generate_mp06_subtitle_fixture.py`) and need FFmpeg.

### External URI grant automation

The URI fixture is excluded from normal builds. Build it after configuring the Debug player, then run the driver:

```sh
python3 - <<'PYCODE'
import subprocess
from configs.dependencies import find_gradle
subprocess.run([find_gradle(), '-p', 'android', '--offline',
                '-PincludeUriFixture=true', ':uri-fixture:assembleDebug'], check=True)
PYCODE
python3 tools/run_external_uri_probe.py --serial SERIAL --apk /path/to/current-player-debug.apk --fixture-apk android/uri-fixture/build/outputs/apk/debug/uri-fixture-debug.apk
```

The driver proves denial before grant, decodes through a granted FD, revokes, and proves denial before and after restarting the player. It never clears player data and always attempts revocation and fixture uninstall. It does not automate the system document picker.

### Debug system properties

Debug builds read `debug.immivio.*` when the native core initializes; reopen the source to apply changes. Release builds ignore them.

| Property | Meaning / default |
| --- | --- |
| `debug.immivio.mpv.max_width` | Color-width cap; `0` keeps source width |
| `debug.immivio.mpv.pool` | `expand` disables ready-slot reuse |
| `debug.immivio.mpv.gpu_frames` | GPU frame queue limit; default `2` |
| `debug.immivio.mpv.seek_trace` | `1` enables native seek traces |
| `debug.immivio.mpv.seek_tail_ms` | Seek-trace tail; default `250`, clamped to 250–5000 ms |
| `debug.immivio.mpv.opts` | Comma-separated libmpv `name=value` overrides |
| `debug.immivio.mpv.log` | libmpv log level; default `info` |
| `debug.immivio.bridge.opaque_fast` | `no` disables the cached opaque fast path |

### Android log labels

| Subsystem | Labels |
| --- | --- |
| Playback and native probes | `ImmivioMpv`, `ImmivioMpvSource` |
| GL ownership and frozen frames | `ImmivioGlOwner`, `ImmivioMpvFreeze` |
| Library, sidecars and captions | `ImmivioDlna`, `ImmivioSidecarAudio`, `ImmivioSubtitles` |
| Presence/session feedback | `ImmivioPlayer` |

```sh
adb logcat ImmivioMpvSource:I ImmivioMpv:V ImmivioPlayer:I ImmivioDlna:I '*:S'
```
