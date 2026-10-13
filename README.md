# Thru3D Media Player

This repository is maintained independently by **NorthBoundWisdom**. It originated from [zerochocobo/Thru3D-Media-Player](https://github.com/zerochocobo/Thru3D-Media-Player); the original GPL-3.0 license and source history are retained. Issues, contributions and releases for this edition belong to [this repository](https://github.com/NorthBoundWisdom/Thru3D-Media-Player). Selected 0.7.0 behaviors have been reimplemented on our existing architecture; this branch is not a full upstream 0.7.0 merge.

[简体中文](README.zh-CN.md) · [Changelog](CHANGELOG.md) · [中文更新日志](CHANGELOG.zh-CN.md)

Standalone Android VR/MR media player for Meta Quest and PICO. Thru3D combines a Godot OpenXR interface, Android media access, a native libmpv renderer, and MNN inference for video matting and depth-based stereo rendering.

Current source version: **0.6.0** (Android versionCode **13**). An experimental standard OpenXR Android export is also available.

Minimum compatibility targets are **Quest 2** and **PICO Neo3**. Source/build compatibility does not establish hardware performance or interaction acceptance on every device.

Download installable APKs from [GitHub Releases](https://github.com/NorthBoundWisdom/Thru3D-Media-Player/releases), under each release's **Assets**. Tag ZIP/TAR downloads contain source code. Release assets include PICO, QUEST and OpenXR APKs in AI and No AI variants, with SHA256 hashes and build receipts. See the release notes for signing and installation compatibility.

## Features

- Video and photo viewing: flat, 180° and 360° projections; mono and side-by-side stereo.
- Person matting and passthrough composition for supported 180° video projections.
- Depth-based 2D-to-3D viewing for flat mono videos and photos.
- Local Android document access, SMB, WebDAV, DLNA and media-server libraries; 115, Baidu, Aliyun Drive, Quark and OneDrive connections.
- Audio tracks, text subtitles and flat-video PGS bitmap subtitles; 0.25×–3× playback speed with pitch correction and per-file viewing preferences.
- Plex phone/computer pairing and original-file library playback.
- Dolby Vision Profile 5 color handling on compatible hardware; no blanket profile, certification or native HDR claim.
- Picture rotation, flat-screen distance/size/curvature and text subtitle sizing/position; subtitles remain upright when the picture rotates.
- Controller ray/trigger selection and hand interaction; English, Chinese and Japanese UI.
- Persistent timestamp bookmarks, source-frame previews for recent playback, and paged media navigation.
- Rendered hands/controllers and display-quality controls, including sharpness and flat-screen adjustments.
- VR-native account forms and in-app web login; speed-first and precise seek policies.
- Immersive photo presentation, pinch-drag navigation, adjacent-photo preload and cached 3D conversion; photo stereo strength is adjustable up to 200%.

- Media-server sections, filters, details, continuation pages and capability-dependent favorites; manual DLNA endpoints and exposed external subtitles.
- Photo distance/size controls and a separate 2–8× magnifier referenced to the displayed image; source-dependent file management.

## Synchronization and playback queues

Playback settings include Synchronization and Queue. Subtitle and audio offsets range from −10 to +10 seconds in 50 ms steps, with separate resets and per-video persistence. The subtitle popup and Synchronization page can load SRT/ASS/SSA/VTT through the Android document picker without a matching video filename. Reopening the video attempts to restore the chosen document; select it again or forget the association if its permission is lost.

The queue supports play, move up/down, remove and clear. Add videos opens the library for individual additions or the currently loaded list; paged sources can be added page by page without recursively scanning remote folders. Up to 500 entries and their order persist across restarts without starting playback. Auto-play next, repeat queue and shuffle default off. Single-video looping takes precedence. Automatic next playback starts at zero after the final frame is presented; manual navigation retains resume behavior.

- Explicit per-video audio/subtitle choices, persistent sound level/mute, five text-caption palettes and double-tap 3D/mute shortcuts.
- Photo walls with remembered 1–3-row layouts; wrapped full-filename hover tips.

## Source release

This repository contains application source, build scripts, third-party source pins/patches, and tests. Model weights, compiled dependencies, signing keys, personal media and development records are excluded.

**AI is optional at build time.** The model-free Python workflow prepares verified non-AI dependencies automatically; supply the host toolchain described in [BUILD.md](docs/BUILD.md). It retains ordinary video/photo playback, existing stereo videos, text subtitles and media browsing. Standard mpv has additional capability limits, including unavailable PGS bitmap subtitles and unverified source-frame PTS; see the [build-mode comparison](docs/BUILD.md#build-modes-and-compatibility). The AI conversion workflow now defaults to public upstream RVM weights adapted for the player. Build-selected model packs also support compatible custom/distilled weights under their own IDs and hashes. The historical student weights are not hosted, and raw upstream checkpoints still require conversion. See [model requirements](docs/MODELS.md) before starting an AI-enabled Android build. This source snapshot is not presented as a complete corresponding-source offer for an existing APK.

The desktop Godot tests and native depth-stabilizer test can run without model weights or an Android toolchain.

## Architecture

```text
Godot scenes / GDScript / OpenXR
              │
Android Kotlin plugin: media libraries, permissions, playback sessions
              │ JNI
libmpv / FFmpeg → shared GPU video textures → Godot stereo rendering
              └ MNN OpenCL: recurrent matting and monocular depth
```

| Directory | Purpose |
| --- | --- |
| `app/godot` | XR scenes, menus, shaders, localization and host tests |
| `android` | Kotlin Godot plugin, Gradle wrapper and JVM tests |
| `native` | JNI media bridge, rendering and inference backends |
| `cloud/openlist` | Embedded OpenList Go adapter and synthetic tests |
| `tools` | Build, conversion and verification entry points |
| `models` | Model contracts, checksums and licenses; no weights |
| `third_party` | Dependency sources, patches, provenance and notices |
| `benchmarks`, `tests` | Verification programs and synthetic fixtures |

## Getting started

```powershell
git clone https://github.com/NorthBoundWisdom/Thru3D-Media-Player.git Thru3D
cd Thru3D
python tools/Check-PublicSource.py

# Source-only tests: point this at your Godot executable.
$env:GODOT_EXE = (Get-Command godot).Source
./tools/Test-Source.ps1
```

For Android, prepare the toolchain described in [BUILD.md](docs/BUILD.md). AI-enabled builds additionally require externally supplied, version-matched models.

For an Android base player without AI, prepare Godot Android templates, Go, a JDK and the Android SDK, then use the portable entry point. It verifies/downloads standard mpv libraries and builds the OpenList AAR from source:

```sh
python3 tools/build_player.py --vendor Quest --build-type Release
```

Use `--vendor Pico` or `--vendor OpenXR` for the other Android targets. The following is the retained AI-enabled workflow:

```powershell
$env:THRU3D_TOOL_ROOT = Join-Path $HOME '.cache/thru3d-toolchain'
./tools/Import-ModelAssets.ps1 -FromDirectory ./external-model-assets
./tools/Build-Player.ps1 -ToolRoot $env:THRU3D_TOOL_ROOT -UsePreparedModelAssets -XrVendor Quest
# PICO uses a separate export preset and vendor loader.
./tools/Build-Player.ps1 -ToolRoot $env:THRU3D_TOOL_ROOT -UsePreparedModelAssets -XrVendor Pico
# Experimental: requires a compatible standard OpenXR runtime on the device.
./tools/Build-Player.ps1 -ToolRoot $env:THRU3D_TOOL_ROOT -UsePreparedModelAssets -XrVendor OpenXR
```

Rebuildable outputs use `build/output/`; temporary data uses `tmp/`. Formal release archives and private signing material use persistent directories, all excluded from public Git. A locally built application has your own signing identity. It cannot necessarily update an installed distribution signed by another key.

## Controls

Hold a controller grip to move the canvas (or drag a corner to resize it). Tap the trigger outside controls to show or hide the playback bar at the canvas centre; the playback panel uses 75% width and 2/3 height; flat video and its controls stay vertical relative to the floor by default. Settings → General offers Reclining mode (off by default), which allows tilted screens and menus, applies immediately and persists independently of Follow. Immersive controls sit below the reset gaze centre and face that direction; menu reset uses the horizontal viewing direction unless Reclining mode is enabled; the trigger also selects controls and drags sliders. Open the VR menu with the left Menu button. Point a controller ray at a control and press that controller's trigger. Libraries, settings, list popups and photo menus use thumbsticks only for scrolling. The ordinary video control bar allows seek, volume and immersive zoom shortcuts; pointer capture suppresses them, with a return-to-center gate after capture or lists close. Hand pointing/pinching is also supported. Desktop input is intended for development previews.

Timeline dragging defaults to **Fast seek**, starting near a keyframe for a quicker response. Choose **Settings → Video → Seek mode → Exact seek** when landing at the requested time matters more than latency. The choice is saved across restarts and is also available in playback settings. Dragging previews the target; releasing the trigger submits one seek. Bookmarks can follow this setting or select their own precision.

Playback controls stay aligned with the canvas-centre direction at a readable distance. Their plane follows the current view while idle, and stays fixed during a slider drag. Supported headsets display menus through a native high-resolution XR overlay with scalable text. Display quality also controls video geometry antialiasing; Enhanced uses stronger antialiasing for flat-screen edges while keeping immersive playback lighter.

AI and no-AI Android builds install as separate applications (**Thru3D AI** and **Thru3D No AI**) with different package IDs and local signing keys. The no-AI app keeps its existing identity; both can coexist on one headset with independent data.

The library uses a curved window. Aim at it and hold the controller grip to drag it left/right, or in both axes in reclining mode. While holding grip, move that controller’s stick up/down to adjust distance between 0.8 and 3 metres; releasing saves the distance. Video grips likewise drag placement, with grip plus stick controlling depth. Closing a video hides playback controls and returns to the previous directory and browse position. Library settings are prewarmed at startup, and cache-size statistics run in the background. The library footer contains only follow, temporary passthrough and battery/clock status in one row. User menu/back actions cannot dismiss the library. Video playback omits follow and temporary passthrough, retains one close-video action to stop playback and return to the library, and places all floating actions and battery/clock above the timeline. The status capsule matches the action height, colour and corners. Settings actions and choices share a single-row style with inline icons, and information is shown as plain text. The right side of play provides video-mode, screen, playback-speed and loop shortcuts with compact popups above the bar; full settings remain available. The playback bar has no passthrough entry. Closing a short-press Home dialog or recovering XR focus does not automatically centre application screens or menus. Holding Home requests recentering after the new tracked camera pose is available, placing content in front of the current view; manual in-app Recenter also remains available.

Playback Settings → IPD exposes software inter-eye separation compensation, vertical alignment and reset for stereo VR180 content. Corrections are percentages of one displayed eye, saved per video on release; they do not alter lens spacing or XR runtime IPD. Select the correct SBS/TB layout first. Playback settings and popups are prewarmed, and common pages retain and reuse their controls.

## Status and limitations

- Early source release; Android ARM64 builds use separate Quest, PICO and experimental standard OpenXR presets.
- Quest 3 has been used during development. PICO packaging checks do not establish PICO hardware playback, passthrough or hand-tracking validation.
- Matting quality, GPU support and sustained performance depend on the model, device and video. Host/packaging checks are not headset performance measurements.
- AI depth operates on flat mono content; video matting is limited to supported sources, including the dedicated spatial-video path; photo portrait matting applies to selected ordinary flat photos.
- Cloud/media-service adapters depend on third-party services and user authorization.

Read [architecture](docs/ARCHITECTURE.md), [build](docs/BUILD.md), [models](docs/MODELS.md) and [testing](docs/TESTING.md) for implementation details. Contributions are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md).

## License

Project-owned source is released under **GPL-3.0-only**. See [LICENSE](LICENSE) for the complete GNU GPL v3 text and [licensing scope](docs/LICENSING.md) for third-party code, models, assets and binary distribution requirements. Third-party components keep their existing licenses; this declaration does not relicense them or grant rights to excluded assets.

The embedded OpenList component is **AGPL-3.0**; its adapter, pinned build recipe and upstream/dependency notices are included. Combined binary distribution must satisfy its applicable AGPL obligations as explained in the licensing scope.

## Spatial media and photo layouts

- Native stereo HEIC/HEIF spatial photos and iPhone MV-HEVC spatial video playback; spatial video can use the supported people-passthrough path. Spatial-photo output is sRGB, not a native HDR claim.
- Side thumbnails, Photo Wall and Memory Fragments, with asynchronous loading feedback and remembered layouts.
- Portrait passthrough for selected ordinary flat photos, with 0–200% stereo strength. Native stereo/panorama photos and overview grids are outside this portrait path.
- Session-scoped head following for flat videos, single photos/portraits and menus; an independent environment-passthrough footer control. No permanent spatial-anchor or full-wall head-lock claim.
- Stereo/left-view/right-view video display and per-video horizontal/vertical alignment. Both eyes display the selected logical view in single-view mode; it does not disable one panel or alter headset IPD.
