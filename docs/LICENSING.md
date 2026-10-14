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
| AndroidX Media3 | Apache-2.0; retain applicable dependency/transitive notices when distributing an APK. |
| CodeLibs JCIFS | LGPL-2.1; keep its source/license obligations and those of transitive dependencies. |
| p115rsacipher adaptation | MIT; source and attribution in `third_party/p115rsacipher`. |
| Belfast Sunset (Pure Sky) | Unmodified Poly Haven background, CC0-1.0; source and attribution are kept with the image. |
| Project-generated test fixtures | Synthetic images, patterns and audio; no private source media is included. |


Names and branding identify this project. The software license does not promise trademark permission or endorsement by the project, device vendors or upstream authors.

## Source publication versus APK distribution

This repository contains the current Immivio application source, build scripts and dependency provenance. The removed inference/model system is no longer part of current builds. Historical releases retain their original source and distribution obligations. Compiled third-party libraries and personal media are excluded from Git.

When distributing a covered binary, GPL v3 requires corresponding source through an applicable delivery method. A root license file and links to upstream projects are not, by themselves, a complete binary source offer. Supply the relevant preferred forms for modification, required modifications, interfaces, build/install scripts, exact dependency sources and applicable installation information. Keep each binary release associated with its source tag and dependency versions.

Vendor SDK terms, the actual combined binary, distribution-channel terms and any GPL exceptions must also be checked before claiming complete binary-distribution compliance. GPL permissions do not grant rights to third-party SDKs or private media. This source publication does not declare the existing store/testing APK fully compliant.

## Embedded OpenList

OpenList v4.2.6 and the JNI adapter are distributed with their AGPL-3.0 obligations. The original project-owned source remains GPL-3.0-only; the combined application must also satisfy AGPL requirements applicable to its OpenList component. GPL v3 section 13 permits combination with AGPL v3. Replacing the frontend does not remove those obligations. Keep the exact upstream revision, modified Storage.Addition serializer, adapter, Go module manifests, dependency notices and build/install scripts with the binary's corresponding source. See third_party/openlist/NOTICE.md and configs/dependencies.py and configs/player_build.py.
