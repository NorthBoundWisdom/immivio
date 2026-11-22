# Licensing scope

SPDX-License-Identifier: GPL-3.0-only

Copyright (C) 2026 FFSky Studio and contributors.

Unless a file or the provenance records identify a different license, project-owned application source, build tools and technical documentation in this repository are available under the GNU General Public License, version 3 only. The complete, unmodified license text is in the root `LICENSE` file. No warranty is provided, as described in that license.

## Why GPL v3

The native player bridge directly links libmpv and libavcodec. The recorded dependency build uses GPL mpv and FFmpeg with GPL/version3 enabled. Publishing the combined application under GPL v3 is the chosen route for the current implementation. This is a deliberate license choice for project-owned work, not a claim that the mere presence of an external model automatically determines the entire application's license.

Sources: [mpv Copyright](https://github.com/mpv-player/mpv/blob/master/Copyright), [FFmpeg legal information](https://ffmpeg.org/legal.html), and GPL v3 sections 1, 5 and 6 in [LICENSE](../LICENSE). The recorded revisions and build options, rather than an upstream repository's current default alone, determine the actual binary dependency profile.

## Third-party material

The project license does not replace third-party notices or claim ownership of upstream files.

| Component | License / treatment |
| --- | --- |
| libmpv / FFmpeg | Recorded GPL build; upstream release source revisions and build provenance are recorded. Upstream headers retain their notices. |
| Godot | MIT engine and corresponding template notices. |
| Hand fallback meshes and texture | Unmodified MIT Godot OpenXR hand demo assets; full license and pinned upstream provenance in `app/godot/models/hands`. These glTF buffers are runtime visuals, not AI weights. |
| Godot OpenXR Vendors | External addon; preserve the addon and each vendor component's actual license. No vendor SDK binaries are vendored here. |
| ICU4J charset detector 78.1 | Unicode-3.0; only `Charset*.class` are packaged, with verified upstream SHA-256 and notices in `third_party/icu-charset`. |
| CodeLibs JCIFS | LGPL-2.1; keep its source/license obligations and those of transitive dependencies. |
| Belfast Sunset (Pure Sky), Blouberg Sunrise 2 | Unmodified Poly Haven panoramas, CC0-1.0; source, checksums and attribution are kept with the images. |
| Project-generated test fixtures | Synthetic images, patterns and audio; no private source media is included. |


Names and branding identify this project. The software license does not promise trademark permission or endorsement by the project, device vendors or upstream authors.

## Source publication versus APK distribution

This repository contains the current Immivio application source, build scripts and dependency provenance. Historical releases retain their original source and distribution obligations. Compiled third-party libraries and personal media are excluded from Git.

When distributing a covered binary, GPL v3 requires corresponding source through an applicable delivery method. A root license file and links to upstream projects are not, by themselves, a complete binary source offer. Supply the relevant preferred forms for modification, required modifications, interfaces, build/install scripts, exact dependency sources and applicable installation information. Keep each binary release associated with its source tag and dependency versions.

Vendor SDK terms, the actual combined binary, distribution-channel terms and any GPL exceptions must also be checked before claiming complete binary-distribution compliance. GPL permissions do not grant rights to third-party SDKs or private media.

All eight mpv/FFmpeg libraries are rebuilt from locked source archives. Their static dependencies and LLVM runtime notices are recorded in [source-build provenance](../third_party/mpv/SOURCE_BUILD.md). Include that lock, build script, patches and the recorded corresponding sources when distributing a binary.

## Code adapted from GPL-3.0 forks

Immivio continues from [zerochocobo/Thru3D-Media-Player](https://github.com/zerochocobo/Thru3D-Media-Player) (shared history up to 0.6.0). Later behavior was adapted selectively; integration code follows Immivio's own playback, menu and persistence architecture. Files listed below derive in whole or part from the named GPL-3.0 source.

| Upstream | Derived files or behavior |
| --- | --- |
| Thru3D-Media-Player 0.13.3 (`9a6a905`) | `StrmFile.kt`, `StrmHttp.kt` and their test scenarios; `screen_presets.gd` |
| Thru3D-Media-Player 0.13.3–0.16.5 (`9a6a905..da5f86c`) | `SubtitleEncoding.kt`, `SubtitleCharsetDetector.kt`, `third_party/icu-charset/` (ICU material remains Unicode-3.0), `file_subtitle_encoding.gd`; `MediaServerPlayback.kt`, `media_server_playback.gd`; Emby/Jellyfin version selection and folder exclusion; `subtitle_picker_filter.gd`; external VIEW/SEND URI validation; `immersive_adjustments.gd`, `picture_center_guide.gd` and its shader; `video_mode_default.gd` layout sanitization; `pointer_ray.gd`, `pointer_ray.gdshader`, `pointer_ray.gdshaderinc`; the `CrashTrail.kt` ring; USB recovery policy; `provider_icons.gd` and Plex library modes; pinch/menu hand policy; `dual_subtitles.gd` and the secondary subtitle channel in `native/mpv/mpv_source.cpp` (`42bbca9`); `file_subtitle_layout_memory.gd` and below-screen captions (`ef83472`) |
| Thru3D-Media-Player 0.17.4–0.17.12 (`da5f86c..959abc2`) | `SmbRecovery.kt`, `SmbBrowseRequests.kt`, `SmbLanScan.kt` and their tests; `subtitle_follow.gd`, `flat_subtitle_canvas.gd`, `subtitle_canvas_fade.gd`; stereo focus placement and smoothing; `DecoderCapacity.kt`; `video_layers.gd`, `video_layer_layout.gd` and `native/xr-layer`; the mpv/FFmpeg patches in `third_party/mpv`; OpenXR headers in `third_party/openxr` |
| Thru3D-Media-Player 0.18.x (`a2f51d9`, `fcca23f`) | Seek snapshot, frame pins and held-stick preview; playback timing monitor |
| [DiggerPriest/VERTOconnect-Immersive-Experiences-VR-Player](https://github.com/DiggerPriest/VERTOconnect-Immersive-Experiences-VR-Player) (`1567215`) | Queue repeat; `HeadsetPresenceMonitor.kt`, `HeadsetPresenceState.kt` and their tests |
