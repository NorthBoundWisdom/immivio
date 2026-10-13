# Immivio architecture

Immivio is a Godot/OpenXR interface over an Android media-library plugin, libmpv playback and shared GPU rendering. It is independently maintained from the original project's 0.6.0 baseline.

## Application and input

`app/godot/scripts/main.gd` coordinates libraries, playback, photos, settings and XR input. Controller rays/triggers and supported hand gestures select controls. Grip placement, reclining mode, follow behavior and recentering retain their existing contracts. Lists and captured sliders suppress playback shortcuts until the stick returns to center.

`xr_menu_compositor.gd` owns the Android-Surface menu presenter, its acknowledged presentation queue, curved mapping and scene fallback. Sustained low frame rates latch the fallback until restart. Menu pose and ray targets use the same presented layout.

## Playback

`MpvVideoBridge.kt` owns MPV source sessions, immutable texture leases, audio focus and frame delivery. `native/mpv/mpv_source.cpp` owns decoding/render transactions, source epochs, seeks and EOF. `native/render-bridge` manages GPU resources and fences; source buffers cannot be reused before the last consumer releases ownership.

The standard backend provides playback-clock estimates rather than verified source-image PTS. The optional verified project backend exposes additional private source/PGS/spatial contracts. Both work without an inference runtime. Existing SBS/TB, projection, eye alignment, subtitles, playback speed and precomputed mask data remain media/rendering features.

Per-video track intent is stored in the existing checksummed mode store. Track metadata guards against ID reuse; stale-session reports cannot restore another source's choices. Global sound preferences are coalesced and flushed on suspend/close. Timing corrections and playback queues remain independent of track selection.

Some frame descriptors and saved-mode fields retain legacy names such as `model_generation`, `alpha_requested` and `depth_requested` for compatibility with immutable frame validation and old settings. Their presence does not enable inference. Live effect requests are rejected; obsolete automatic-conversion preferences are ignored/cleared, and no model loader or preparation worker exists.

## Photos and libraries

`PhotoBridge.kt` transfers and decodes sources off the render thread. Foreground/preload bridges transfer source ownership without deleting active files. `PhotoPreviewBridge` supplies bounded gallery thumbnails. Spatial/HEIF metadata and supported native stereo decoding are independent of AI conversion.

`photo_display.gd` handles ordinary/native-stereo images, preload/navigation, magnification and gallery presentation. Photo walls preserve aspect ratio and ordered groups, with a bounded vertical budget for multiple rows. Depth/portrait workers and their backend entry points have been removed.

The Android plugin owns local grants, SMB, WebDAV, DLNA, media-server adapters and cloud account authorization. Credentials remain in application-private storage. DLNA subtitle refresh matches server-scoped object IDs and uses a complete directory listing to confirm removal when item metadata is incomplete.

## Removed subsystems

The MNN/ncnn runtime, RVM matting, monocular depth, photo conversion/portrait jobs, model catalogs, training/conversion scripts, model diagnostics and AI CI matrix have been removed. Ordinary rendering/native stereo remain supported. The build has one product identity and three headset targets.

`native/CMakeLists.txt` builds the media-delete library, render bridge and MPV bridge. It has no inference dependencies. Packaging excludes obsolete cached model directories/libraries and rejects an APK if they are accidentally reintroduced.
