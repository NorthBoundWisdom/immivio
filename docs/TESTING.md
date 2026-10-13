# Testing Immivio

## Source and host checks

```sh
python3 tools/Check-PublicSource.py
python3 tools/test_build_player.py
python3 tools/test_ci_android.py
python3 tools/test_prepare_android_release.py
python3 tools/check_website.py
python3 tools/ci_android.py test --godot /path/to/godot
```

The CI source runner imports the Godot project and runs every `test_*.gd` suite, saving logs and a JUnit report under ignored `artifacts/source-tests`. Source tests cover projection, native stereo, media libraries, photo navigation/preloading, persistent settings, subtitles, queues, timing, controller/hand interaction and XR menu geometry. They do not establish physical headset behavior.

Removed conversion/matting tests were retired with their implementations. Existing mixed suites now assert that old conversion controls and requests cannot reactivate inference, while retaining their ordinary-playback coverage. Per-file settings still accept compatible historical records, but ignore removed effect choices.

The source boundary checker excludes secrets, private paths, binaries and model files. The builder tests verify corrupt downloads, archive traversal, exact source-backend receipts, export failures/timeouts and preservation of the ordinary player's signing identity. Release tests reject wrong products, tags/commits, build types, hashes and incomplete platform sets.

## Android builds

`python3 tools/build_player.py --vendor Pico --build-type Debug` runs the Android JVM tests and builds/inspects the plugin and APK. Use Quest/OpenXR for the other exports. The APK inspection checks ARM64, ELF alignment and dependencies, signing, app identity and absence of removed inference libraries/models.

The JVM suite covers source ownership, photo preload promotion/cancellation, network/library behavior, track/queue state and playback gates. `DlnaLibraryTest` includes incomplete metadata, changing resource URLs, offline caches and confirmed subtitle removal.

## Rendering and device checks

Render fixtures use synthetic content. `render_independent_controls.gd` and existing menu/geometry render fixtures can generate local UI previews. Website screenshots are actual emulator captures with a separate manifest; the source video and raw device logs stay outside Git.

For device playback, use the existing `benchmarks/mpv_playback_device.py` with an installed matching Debug APK and media you are allowed to test. Select `--entry xr` on a headset and `--entry 2d` only for an emulator/debug preview. Retain source hashes and separate decode transactions, app draws and final compositor frames. Verify pause/resume, seek, retained EOF, lifecycle recovery and sustained playback independently.

Controller feel, hand tracking, headset compositor recovery, color correctness and comfort require device-specific checks. PICO packaging or an emulator screenshot does not prove PICO hardware performance.

## Website and icon checks

The website checker validates four English/Chinese routes, local anchors/assets, single-edition download choices and screenshot hashes. `node --check website/assets/site.js` checks script syntax. The branding helper keeps the original artwork, adds Android safe-area padding, and clips the website bitmap corners to transparency. Check exported legacy, adaptive and monochrome launcher resources when branding changes.
