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

`test_network_sources.gd` exercises the unified Network media entry with asynchronous synthetic SMB, DLNA and media-server replies: four-item navigation, source identity/deduplication, flat provider-specific add/manage routes, complete protocol titles, return paths, retained folder/account state and stale-result rejection after switching sections. Delayed listings must retain an untouched chooser; only the matching submitted save may return to the source list. `QUEST_NETWORK_PREVIEW_ONLY=1` selects the matching source-list/setup renders in `render_library_menu.gd`.

`test_library_padding.gd` checks production control geometry against the shared four-sided panel inset across grid/list file browsing, network source choices, settings, media-server pages and file selection. It verifies centred content, scrollbar edge spacing and the retained ray hit width. Run `render_library_padding.gd` with a real GPU and `IMMIVIO_PADDING_DIR` under `artifacts/` for deterministic synthetic screenshots without any network or personal-media access.

The Android workflow offers `--level l0` (workflow and publication boundaries), `l1` (JVM integration), `l2` (Godot host behavior), and `all`. JVM tests use the configured dependencies offline. The Godot suite writes logs and JUnit results under `artifacts/source-tests/`. A passing process must also emit exactly one completion report for the script being run; reaching the frame limit without finishing is a failure.

Native helper tests have one host entry point on macOS, Windows and Linux:

```sh
cmake -S native -B build/native-host -DCMAKE_BUILD_TYPE=Release
cmake --build build/native-host --config Release --parallel 2
ctest --test-dir build/native-host -C Release --output-on-failure
```

These tests exercise the production JSON writer against an independent Python Unicode oracle, numeric seek tracing, and both production subtitle-channel snapshots (independent command IDs, shared delay metadata and invalid-timeline clearing), plus collision-safe subtitle-slot application order. They require CMake, a C++17 compiler and Python 3.11+, and keep assertions enabled in Release builds. GitHub CI runs them on both build hosts.

Workflow tests cover corrupt assets, offline acquisition boundaries, configuration staleness, separate Build/Package stages, safe cleanup, process timeouts and signing identity preservation. Release tests reject incomplete dependency provenance and mismatched tag/commit/host/variant or APK bytes.

Use the Android workflow for host tests and package verification. Rendering fixtures remain under `app/godot/tests/render_*.gd` for focused visual checks. Build and package each target before device verification. Existing device probes and media benchmarks remain available. Host/APK checks do not establish media or rendering correctness on a headset.

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

Each headless Godot test calls `preload("res://tests/support/test_result.gd").prepare(self)` first. This creates a separate `user://` directory for that script and process, so caches and saved settings cannot come from a previous test or a normal app session. The directory is printed in its log for failure diagnosis. It ends with `preload("res://tests/support/test_result.gd").finish(self, exit_code)`. Keep the assertions in the test; the helper reports completion and exits. Do not print a success report from initialization or a timeout handler. The runner rejects missing, duplicate, malformed and foreign-script reports, nonzero exits, and engine errors even after a success report.

Prefer a small test that fails when a real contract is broken: stale callbacks must not revive a closed session, failed file operations must preserve the original, or corrupt bytes must not be published. Mock hardware/network boundaries where needed, while executing the production behavior being checked. Avoid tests that replace the whole subject with a mock, merely repeat constants or private control layouts, or duplicate a dependency's own suite.

## Owned local Jellyfin port integration

`JellyfinLivePortsTest` skips explicitly unless `IMMIVIO_JELLYFIN_LIVE_JSON` names a private JSON file containing `url`, `username`, `password`, `movie_id` and `library_id`. Only loopback endpoints are accepted. Use an isolated server with synthetic, two-version movie media and a nested directory; the movie must be long enough for the server's resume threshold. The test logs in, checks folder containers and version selection, streams an authenticated byte range, reports both paused-start and playing → pause → stop sessions, reads resume from the selected version item (not the grouped movie, whose UserData may differ), and verifies disabling history sends no more reports or progress. Run with the existing offline Gradle dependency cache:

```sh
"$GRADLE_EXE" -p android --offline :player-plugin:testDebugUnitTest --tests '*JellyfinLivePortsTest'
```

Keep the JSON file, credentials, server data, media and logs under ignored `artifacts/`; remove the owned server/container and synthetic media after the run. Never point this mutating test at a personal library or commit its credentials.

Playback popup continuity: `test_playback_popup_continuity.gd` checks transport node retention, stable subtitle bounds, live timeline updates and capture-gated input. `test_playback_page_surfaces.gd` also covers compact-browser replacement without reanchoring. Run `render_playback_popup_continuity.gd` with the OpenGL compatibility renderer for three GPU frames at each open/close transition across ten production popups; set `IMMIVIO_POPUP_FRAMES_DIR` to retain synthetic screenshots. This checks scene capture continuity; native headset comfort still requires wearer acceptance.
