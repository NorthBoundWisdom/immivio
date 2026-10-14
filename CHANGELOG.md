# Changelog

[Bilingual release notes](https://northboundwisdom.github.io/immivio/updates/)

Newest first, following product release milestones. Entries under 0.6.0 and earlier describe the original project; removed conversion features are historical, not current Immivio capabilities. Some development/source snapshots contained features before their product release. Original APK identifiers `0.2` and `0.4` are retained; `0.4` was also called `0.4.0` in release notes. Availability depends on device, server and media capabilities.

## 0.9.3 — 2026-10-14

- Set application version 0.9.3 / versionCode 17 for Quest, PICO and experimental OpenXR packages.

- Add independent reset actions to existing grading, subtitle, timing, eye-alignment and photo sliders. Reset only the current three-field grading popup page, retain whole-custom reset, and preserve disabled effects and unavailable controls. Adapt the upstream 0.8.0 behavior to the compact toolbar without restoring removed settings pages or conversion features.
- Keep only Original, Warm, Cool and Custom grading presets. Restore legacy Daylight saves as Original while retaining their custom parameters.

- Use one playback pipeline with verified upstream Android mpv/FFmpeg libraries; simplify the native source layout and remove unused source build dependencies and probes.
- Run Android CI on GitHub-hosted Windows and macOS machines. Fix MSVC numeric trace compilation and prepare the expanded gomobile module graph before offline AAR builds.
- Replace old player tests and screenshot-only scripts with focused controller, geometry and download checks. Require explicit Godot test completion, isolate test user data, and separate GPU thumbnail pixels from headless cache tests.

## 0.9.2 — 2026-10-14

- Set the application version to 0.9.2 / versionCode 16 for all Android targets. Create GitHub Releases on tag push independently of the Android build runners; attach verified APKs after both builds pass.

- Replace the separate video settings pages with one compact toolbar and mutually exclusive popups for subtitles, speed, grading, IPD, synchronization, queues and source information.
- Centre previous/play/next, move the middle-elided filename beside the battery/clock capsule, separate Close video, reduce padding and omit unavailable actions. Bring controls 20% closer and lower their timeline by 8 cm.
- Automatically advance after the final presented frame; return to the previous file-browser location at queue end. Remove user-facing looping, bookmark addition and seek-precision selection while retaining stored bookmarks.
- Follow system volume at unity player gain; remove application volume/mute preferences and their pointer, stick and keyboard controls.
- Apply Home recentering after the runtime publishes updated tracking in the same frame, refresh the native UI layer immediately and keep the file-browser centre on its remembered horizontal distance ring.
- Update the About repository URL and remove the contact email. Refresh regressions and guides for the supported controls, including immediate visibility of speed reset after slider edits.

## 0.9.1 — 2026-10-13

- Set the application version to 0.9.1 / versionCode 15 for all Android targets.
- Verify the PICO 4 fixes on the physical headset: stable windows, clear menu text and gaze-centred file-browser placement. Related host regressions passed; other build hosts remain delegated to CI.

- Centre the complete file-browser window on the current gaze when opening or explicitly recentering it, removing the downward offset while retaining upright/reclining orientation and fixed placement afterward.
- Remove the low-frame-rate UI fallback detector and persistent latch. Supported native menu layers remain active independently of application frame rate.
- Keep PICO windows and media placement when the runtime emits automatic tracking-space reset notifications. Explicit in-app recenter remains available; other runtimes retain their system-recenter handling.

## 0.9.0 — 2026-10-13

- Set the application version to 0.9.0 / versionCode 14 for Quest, PICO and experimental OpenXR packages.

- Complete local refactor regression and six Android package checks; migrate obsolete EOF/stereo fixtures to frame contract v2. Remove exact host-tool version requirements and select installed Android SDK components.

- Remove native inference/warp buffers, introduce version-2 playback descriptors, split Godot application controllers and Kotlin source/display ownership, and retire inference-specific verification matrices. Local regression and Debug/Release packaging passed; CI on other hosts and physical-headset acceptance remain pending.

- Start the architecture refactor: isolate retired-settings migration, remove dormant model-preheat/Alpha-FPS paths and unused inference JNI entry points, and preserve the current playback lease/fence contracts.

- Simplify FreeCM management: keep OpenList and the OpenXR addon active, restore Gradle/Go manifests and use prepared host tools and Android libraries.
- Retire superseded Windows test/package wrappers and the checked-in machine-specific mpv build receipt; retain device probes.

- Rename the independently maintained project, application and build artifacts to Immivio; the repository is now `NorthBoundWisdom/immivio`. Retain ordinary-player app identity/signing compatibility.
- Remove live AI depth, person matting, model preparation/training tools, inference libraries and AI-specific build jobs. Keep existing stereo/spatial media, ordinary photos and precomputed media masks.
- Remove the AI edition selector and conversion controls. Migrate obsolete preferences without reactivating effects.
- Make website/README icon corners transparent and apply the formal Immivio brand.

- Replace the application and website icon with the supplied neon panorama artwork.
- Maintain the bilingual website, installation guide and release notes; keep one repository README and technical changelog.

- Maintain this edition independently; retain the original license and history, and direct contributions/releases to NorthBoundWisdom.
- Reimplement selected original 0.7.0 behaviors: persist explicit audio/subtitle choices per video (with metadata matching after track renumbering), and retain volume/mute across launches.
- Double-tap the volume icon to toggle mute; keep existing single-tap controls. Muted volume uses a red icon.
- Offer five text-caption palettes across flat and projected/vertical captions. Show complete long library filenames in wrapped hover tips.
- Add persisted 1–3-row photo walls with ordered groups, aspect-preserving cards and bounded vertical placement.
- Retain DLNA subtitle links when metadata is incomplete, refresh from the containing directory and match by server object ID when resource URLs change. Identify playback HTTP requests as Thru3D rather than a generic libmpv client.
- Add sustained-low-frame-rate fallback to our existing native menu compositor, retaining its scene/curved fallback and input mapping.

- Made the library curved, added grip dragging with same-hand stick depth adjustment, and return to the previous browse position when closing video. Removed duplicate library/playback actions and aligned status controls with the action row.
- Stabilized hover tooltip bounds to prevent UI projection jumps, and recenter the visible library after sleep/focus recovery once head tracking returns.
- Prewarm library settings and 31 playback page/popup states; retain a bounded cache of prepared settings controls and move cache-size scans off the UI thread.
- Added a dedicated software IPD calibration tab with per-video horizontal/vertical alignment and reset; physical headset IPD remains unchanged.

- Tag pushes now force Release APKs; branch/PR pushes default to Debug, manual builds can choose either, and CI rejects mismatched build-type receipts.

- Added per-video subtitle/audio timing controls, reset actions and manual SRT/ASS/SSA/VTT subtitle selection with retained document permission.
- Added editable, persistent playback queues with reordering, removal, automatic next playback, queue repeat and shuffle; automatic advance waits for the final presented frame.

- Added a persistent Reclining mode in General settings, off by default, allowing tilted flat-video screens and menus while keeping Follow independent.

- Added a verified standard-libmpv backend and portable Android build entry point; documented its source-timing, PGS and Dolby metadata limits.
- Updated the color-grading regression to exercise subtitle distance through the current subtitle popup.

## 0.6.0 — 2026-10-11

- Added native stereo HEIC/HEIF spatial photos. Output is sRGB; compatibility and performance depend on media and device.
- Added side thumbnails, grouped Photo Wall and randomized Memory Fragments, with hand-driven overview browsing, expand/return placement and remembered layouts.
- Improved large-photo loading feedback, asynchronous switching and stable photo placement.
- Added one-button 3D/person preparation for selected ordinary flat photos, with 0%–200% depth strength and synchronized color/mask updates. Native stereo, panoramas and photo overviews retain their own presentation.
- Added session-scoped head following for flat video, individual/portrait photos and menus; it starts disabled at launch.
- Added a temporary environment-passthrough footer control, independent of media mode; person-Alpha playback keeps passthrough enabled.
- Added stereo/left-eye/right-eye video views and saved per-video horizontal/vertical alignment corrections (±5%, 0.05% steps). Monocular views display the selected logical eye to both headset eyes.
- Simplified menu closing/back controls, stopped treating every 2:1 video as VR180.
- Updated portable signing validation and public-source export boundaries: caller-owned keys and identity metadata remain private, missing/mismatched keys stop packaging, and export state uses persistent storage.

## 0.5.2 — 2026-10-11

- Added live 10–40 FPS person-Alpha processing controls (default 20) and an optional video/engine FPS overlay; actual throughput depends on device, media and load.
- Added device-dependent automatic quality defaults while preserving saved manual overrides.
- Fixed H.264 startup stalls/exits and cleaned stray photo-3D edges around hair, faces and arms.
- Raised photo 3D strength to 200% and added animated preparation feedback.
- Fixed DLNA directories with external subtitle metadata and 115 directory failures caused by duplicate names; ambiguous names now request renaming.

## 0.5.1 — 2026-10-11

- Added Plex phone/computer pairing, library browsing and original-file playback, with improved LAN connection selection.
- Added 0.25×–3× playback speed, audio pitch correction and one-button return to 1×.
- Reorganized Screen/Playback/Info settings. Added flat-screen distance, size and curvature controls, and −90°–90° picture rotation while subtitles stay upright.
- Added 50%–200% text subtitle sizing, independent flat-video vertical position and filename guidance.
- Improved modification-time sorting with folders first for local/SMB/cloud libraries, and ascending/descending DLNA name sorting.
- Fixed screen percentages and slider positions, straightened settings panels, and placed conditional speed/rotation resets beside their sliders.

## 0.5.0 — 2026-10-10

- Upgraded media-server sections, Continue Watching, Recently Added, categories, details, continuous loading and restored navigation/scroll state.
- Added capability-dependent favorites: server-backed where supported, otherwise local; no playback-progress writeback promise.
- Added Aliyun Drive, Quark and remote WebDAV connections. The 115 Open display name became 115.
- Added manual DLNA addresses and server-exposed external subtitles.
- Added photo adjustment controls and a separate 2×–8× magnifier referenced to actual displayed image size; flat-photo distance is 0.3–10 m and size 40%–600%.
- Fixed immersive opening alignment, stale mode locks and Quest passthrough clarity while retaining selected display quality.
- Improved embedded web-login scaling/input and reauthentication entry points.
- Removed unused JCIFS HTTP adapters and strengthened package checks while retaining required HTTP media compatibility.

## 0.4.2 — 2026-10-10

- Added horizontal/vertical immersive text subtitles with improved first-character alignment, multiline/bilingual layouts and long-line wrapping.
- Added live directional placement and extended subtitle distance to 0.1–10 m.
- Improved cloud-folder external-subtitle matching, including language suffixes and paged directories.
- Added text subtitles exposed by supported Emby, Jellyfin, Stash and XBVR servers.
- Extended external dubbing/audio discovery to supported cloud/media-server sources, including `movie.si.mix.m4a` naming.

## 0.4.1 — 2026-10-09

- Rebuilt the QUEST release as application version 0.4.1 / versionCode 8.
- No separate user-facing feature additions were recorded for this packaging revision; it retains the 0.4 feature set.

## 0.4 — 2026-10-09

Also called **0.4.0** in release notes; actual APK versionName was **0.4**.

- Improved photo-to-3D processing reuse, landscape/portrait depth and stable placement after zoom/reset.
- Added half-width SBS and half-height top-bottom stereo layouts, improved format detection and corrected some fisheye proportions.
- Simplified mode controls and moved eye swapping into playback settings.
- Added 115 Open/OneDrive authorization and switched Baidu sign-in to authorization. Existing Baidu accounts need reauthorization; saved legacy 115 accounts remain compatible.
- Added persistent name/modification-time/size sorting for local, SMB and cloud libraries.
- Added optional, confirmation-based file management, disabled by default: supported local/SMB deletion and 115 Open recycle-bin operations.
- Added bundled local/SMB video/subtitle/dubbing renaming, preserving history/bookmark links after complete success.
- Added removable-storage shortcuts, volume-change refresh and a control to stop app reads/preloading; this is not system-level safe eject.
- Added live subtitle distance/position controls, improved long track lists and refreshed About links.

## 0.3.1 — 2026-10-09

- Stabilized VR subtitles relative to video and improved PICO controller compatibility.
- Improved older-Android storage authorization, status/error feedback and directory refresh after permission changes.
- Distinguished charging from connected-but-not-charging power; showed red battery state below 20% when not charging.
- Moved 115 SMS send/verify actions above the keyboard.
- Enlarged launcher artwork while preserving the Thru3D / Media Player wordmark.

## 0.3.0 — 2026-10-09

- Added persistent timestamp bookmarks with timeline/list navigation, deletion and undo; no ratings or editing.
- Added larger immersive photo presentation, softer edges and slide/fade transitions.
- Added single-hand pinch-drag photo navigation and two-hand zoom; capped photo 3D strength at 100%, independently of video.
- Improved portrait depth, edge completion, adjacent-photo preload, looping and conversion-cache reuse/cleanup.
- Moved cloud/media-server forms and web login into VR and improved input layout/hand response.
- Added faster seeking with separate bookmark precision preferences and audio-track selection on the control bar.
- Allowed thumbstick playback shortcuts with ordinary video controls while retaining list/pointer-capture isolation.
- Improved subtitle placement/distance, Jellyfin connections, settings and near-hand/menu/background rendering.

## 0.2.1 — 2026-10-08

- Retained the displayed frame while seeking and corrected timeline targets jumping back before completion.
- Added recent-playback source-frame previews, poster fallback, bounded preview caches and paged history.
- Added controller/hand visual models and improved input/profile handling.
- Added separate QUEST/PICO and experimental standard OpenXR exports while retaining Quest 2 compatibility.

## 0.2 — 2026-10-07

- Upgraded SMB2/3 compatibility, encryption and direct share/subfolder access without enabling SMB1.
- Added global display-quality presets and live sharpness for videos/photos.
- Reorganized settings and added real restart/exit controls.
- Improved PICO panel/input integration and controller fallbacks, keeping accounts/media links compatible.

## 0.1.0 — 2026-10-07

- Initial standalone Android VR/MR video/photo test release.
- Added flat/180°/360° and stereo viewing, supported person-matting passthrough and depth-based 2D-to-3D rendering.
- Provided local/LAN/media-library access, audio tracks, subtitles and controller-ray/hand interaction.
- Supplied separate Quest/PICO builds with multilingual UI and dependency notices.
