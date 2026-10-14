# Immivio architecture

Immivio is a Godot/OpenXR interface over an Android media-library plugin, libmpv playback and shared GPU rendering. It is independently maintained from the original project's 0.6.0 baseline.

## Application and input

`app/godot/scripts/main.gd` assembles the scene and connects lifecycle/events. Input, photo, playback/queue, preferences and XR presentation coordinators own their respective behavior/state. The main scene retains narrow adapters for existing integrations; controllers access it through weak references. `player_settings_migration.gd` owns the idempotent cleanup of retired effect preferences; ordinary audio, subtitles, queues and native stereo locks are preserved. Controller rays/triggers and supported hand gestures select controls. Grip placement, reclining mode, follow behavior and recentering retain their existing contracts. Lists and captured sliders suppress playback shortcuts until the stick returns to center.

`xr_menu_compositor.gd` owns the Android-Surface menu presenter, its acknowledged presentation queue and curved mapping. Native layers are selected by runtime support; frame rate does not switch off native UI composition. Unsupported layers use the scene fallback. Menu pose and ray targets use the same presented layout.

PICO runtime space-reset notifications preserve existing menu/media placement: these notifications also occur automatically and do not expose user intent. Explicit in-app recenter still places content in front of the current gaze. Other runtimes retain deferred system recenter after tracked scene frames. Focus recovery alone never requests placement changes.

Opening or explicitly recentering the file browser places its stable layout envelope centre on the current head gaze at the configured library distance. Upright/reclining mode controls panel orientation. The navigation/footer offset is accounted for once during placement; subsequent head movement leaves the window fixed unless the user enables Follow.

## Playback

`MpvVideoBridge.kt` coordinates MPV sessions, audio focus and frame delivery. `PlaybackHost` holds decoder lifetime, `PlaybackSourceResources` owns FD/network/subtitle resources, and `PlaybackDisplayLeases` holds consumer GL leases under the session lock. `native/mpv/src/mpv_source.cpp` owns decoding/render transactions, source epochs, seeks and EOF. `native/render-bridge` manages GPU resources and fences; source buffers cannot be reused before the last consumer releases ownership.

The player provides playback-clock estimates rather than verified source-image PTS. It uses the public libmpv render API. Existing SBS/TB, projection, eye alignment, subtitles, playback speed and precomputed mask data remain media/rendering features.

Per-video track intent is stored in the existing checksummed mode store. Track metadata guards against ID reuse; stale-session reports cannot restore another source's choices. Global sound preferences are coalesced and flushed on suspend/close. Timing corrections and playback queues remain independent of track selection.

Frame descriptors use [contract version 2](FRAME_CONTRACT.md), with source identity, presentation revision and same-fence color/mask completion. Model/inference/warp fields are retired. Saved-mode compatibility is handled by settings migration, separately from transport validation.

## Photos and libraries

`PhotoBridge.kt` transfers and decodes sources off the render thread. Foreground/preload bridges transfer source ownership without deleting active files. `PhotoPreviewBridge` supplies bounded gallery thumbnails. Spatial/HEIF metadata and supported native stereo decoding are independent of AI conversion.

`photo_display.gd` handles ordinary/native-stereo images, preload/navigation, magnification and gallery presentation. Photo walls preserve aspect ratio and ordered groups, with a bounded vertical budget for multiple rows. Depth/portrait workers and their backend entry points have been removed.

The Android plugin owns local grants, SMB, WebDAV, DLNA, media-server adapters and cloud account authorization. Credentials remain in application-private storage. DLNA subtitle refresh matches server-scoped object IDs and uses a complete directory listing to confirm removal when item metadata is incomplete.

## Removed subsystems

The MNN/ncnn runtime, RVM matting, monocular depth, photo conversion/portrait jobs, model catalogs, training/conversion scripts, model diagnostics and AI CI matrix have been removed. Ordinary rendering/native stereo remain supported. The build has one product identity and three headset targets.

`native/CMakeLists.txt` builds the media-delete library, render bridge and MPV bridge. It has no inference dependencies. Packaging excludes obsolete cached model directories/libraries and rejects an APK if they are accidentally reintroduced.

## Native source and test layout

Each module under `native/` owns its CMake target and keeps implementation files in `src/`. Render bridge headers describe internal GL resources and remain beside its implementation; they are not a public test API. Reusable MPV helpers live under `native/mpv/include/immivio/mpv/` and are consumed as `<immivio/mpv/...>` through the `Immivio::MpvHeaders` target. Upstream libmpv headers remain under `native/mpv/include/mpv/` with their original notices.

`tests/native/` owns native regression executables and their verification scripts. The host CMake graph builds JSON and seek trace tests without JNI, Android SDK libraries or a prepared libmpv binary. Android builds use the same helper target and build the three production shared libraries. Cross-directory dependencies use target include directories and linked targets; source files never include another `.cpp` file.

The old `photo_stereo_gpu_probe.cpp` referenced removed `PhotoEgl`/`photo_stereo` conversion entry points and has been retired with that subsystem. Current photo and native stereo checks remain in the Godot tests and supported device probes.

## Refactoring status

[REFACTOR_PLAN.md](REFACTOR_PLAN.md) records completed code batches and remaining acceptance. The native renderer has separate GL state, slot, frozen-frame and JNI modules; it only captures RGBA source color and opaque R8 masks. It preserves borrowed producer ownership and seven slots pending device measurement. Runtime/cross-platform/package acceptance is deferred by the owner; see [ACCEPTANCE.md](ACCEPTANCE.md).
