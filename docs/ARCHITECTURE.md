# Immivio architecture

Immivio is a Godot/OpenXR interface over an Android media-library plugin, libmpv playback and shared GPU rendering. It is independently maintained from the original project's 0.6.0 baseline.

## Retained internal names

The Android package namespace `org.vrpassthroughplayer.plugin`, Godot addon
`quest_player`, plugin class `QuestPlayerPlugin` and Godot singleton `QuestPlayer`
retain their upstream names.
They are shared by Quest, PICO and generic OpenXR targets; these names do not
limit platform support. Keeping them avoids changing JNI symbols, reflection
strings, plugin metadata and component checks solely for cosmetic consistency.
The application ID remains `com.northboundwisdom.immivio` so updates preserve
installation identity and user data. Other internal labels can be renamed in
later isolated changes after release acceptance.

## Application and input

`app/godot/scripts/main.gd` assembles the scene and connects lifecycle/events. Input, playback/queue, preferences and XR presentation coordinators own their respective behavior/state. The main scene retains narrow adapters for existing integrations; controllers access it through weak references. `player_settings_migration.gd` owns the idempotent cleanup of retired effect preferences; ordinary audio, subtitles, queues and native stereo locks are preserved. Controller rays/triggers and supported hand gestures select controls. Grip placement, reclining mode, follow behavior and recentering retain their existing contracts. Lists and captured sliders suppress playback shortcuts until the stick returns to center.

The native menu texture contains the hit reticle, while `pointer_ray.gd` draws the world-space beam in the main scene through the main XR projection, without per-eye pointer viewports or composition layers. The UI uses an `XrUiSurfacePresenter` with generation-scoped frames and Android Surface GPU copies; ordinary GLES viewport textures retain Godot ownership. Beam edges use pixel-aware coverage and longitudinal fading. The playback browser is a compact switcher anchored above the control bar; closing playback restores the full library and Settings.

`xr_menu_compositor.gd` owns the Android-Surface menu presenter, its acknowledged presentation queue and curved mapping. Native layers are selected by runtime support; frame rate does not switch off native UI composition. Unsupported layers use the scene fallback. Menu pose and ray targets use the same presented layout.

PICO runtime space-reset notifications preserve existing menu/media placement: these notifications also occur automatically and do not expose user intent. Explicit in-app recenter still places content in front of the current gaze. Other runtimes retain deferred system recenter after tracked scene frames. Focus recovery alone never requests placement changes.

Opening or explicitly recentering the file browser places its stable layout envelope centre on the current head gaze at the configured library distance. Upright/reclining mode controls panel orientation. The navigation/footer offset is accounted for once during placement; subsequent head movement leaves the window fixed unless the user enables Follow.

## Playback

`MpvVideoBridge.kt` coordinates MPV sessions, audio focus and frame delivery. `PlaybackHost` holds decoder lifetime, `PlaybackSourceResources` owns FD/network/subtitle resources, and `PlaybackDisplayLeases` holds consumer GL leases under the session lock. `native/mpv/src/mpv_source.cpp` owns decoding/render transactions, source epochs, seeks and EOF. `native/render-bridge` manages GPU resources and fences; source buffers cannot be reused before the last consumer releases ownership.

The Godot singleton opens playback with `open_mpv_video(uri, startMs, stereo, profile, vulkan, topBottom, exactSeek)` and revises it with `revise_mpv_video(id, stereo, profile, positionMs, topBottom, exactSeek)`. These calls carry no inference requests. Filename-identified packed alpha stays in the source frame and is interpreted by the Godot shader. Per-file mode schema 2 reads schema-1 records while removing retired inference fields; ordinary mode, subtitle and timing preferences are preserved.

For unmarked packed stereo, `stereo_detection.gd` compares corresponding eye-image details in a bounded number of transient 192×108 GPU samples. Capture uses the existing pinned-frame/thumbnail ownership path; CPU matching runs on a worker and never persists or uploads the sampled images. Two consistent informative samples may select SBS/TB, while black or ambiguous frames leave the layout unchanged. Per-file `layout_auto` distinguishes new automatic choices from manual preferences; legacy saved modes remain manual until the user selects Auto detect. Request tokens reject results after a file switch or manual format change. Image evidence identifies packing, not VR projection or lens field of view.

The player provides playback-clock estimates rather than verified source-image PTS. It uses the public libmpv render API. Existing SBS/TB, projection, eye alignment, subtitles, playback speed and precomputed mask data remain media/rendering features.

Per-video track intent is stored in the existing checksummed mode store. Track metadata guards against ID reuse; stale-session reports cannot restore another source's choices. Global sound preferences are coalesced and flushed on suspend/close. Timing corrections and playback queues remain independent of track selection.

Frame descriptors use [contract version 2](FRAME_CONTRACT.md), with source identity, presentation revision and same-fence color/mask completion. Model/inference/warp fields are retired. Saved-mode compatibility is handled by settings migration, separately from transport validation.

## Libraries

The Android plugin owns local grants, SMB, DLNA, media-server adapters. Credentials remain in application-private storage. DLNA subtitle refresh matches server-scoped object IDs and uses a complete directory listing to confirm removal when item metadata is incomplete.

## Removed subsystems

The MNN/ncnn runtime, RVM matting, monocular depth, photo conversion/portrait jobs, model catalogs, training/conversion scripts, model diagnostics and AI CI matrix have been removed. Ordinary rendering/native stereo remain supported. The build has one product identity and three headset targets.

`native/CMakeLists.txt` builds the media-delete library, render bridge and MPV bridge. It has no inference dependencies. Packaging excludes obsolete cached model directories/libraries and rejects an APK if they are accidentally reintroduced.

## Native source and test layout

Each module under `native/` owns its CMake target and keeps implementation files in `src/`. Render bridge headers describe internal GL resources and remain beside its implementation; they are not a public test API. Reusable MPV helpers live under `native/mpv/include/immivio/mpv/` and are consumed as `<immivio/mpv/...>` through the `Immivio::MpvHeaders` target. Upstream libmpv headers remain under `native/mpv/include/mpv/` with their original notices.

`tests/native/` owns native regression executables and their verification scripts. The host CMake graph builds JSON and seek trace tests without JNI, Android SDK libraries or a prepared libmpv binary. Android builds use the same helper target and build the three production shared libraries. Cross-directory dependencies use target include directories and linked targets; source files never include another `.cpp` file.

## Refactoring status

The native renderer has separate GL state, slot, frozen-frame and JNI modules; it only captures RGBA source color and opaque R8 masks. It preserves borrowed producer ownership and seven slots pending device measurement. Runtime/cross-platform/package acceptance is deferred by the owner; see [ACCEPTANCE.md](ACCEPTANCE.md).
