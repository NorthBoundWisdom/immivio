# Third-party components

This directory retains upstream license texts, source locks, checksums and provenance. The application's overall GPL v3 choice does not replace these components' existing terms. See [licensing scope](../docs/LICENSING.md) for the component inventory and binary-release requirements.

- `mpv`: upstream headers, Android release provenance, library checksums and GPL/LGPL texts.
- `gradle`: Apache-2.0 license text used by the dependency-license maintenance tool; the Gradle wrapper implementation has been retired.
- `polyhaven`: CC0 source and attribution for the unmodified built-in background.
- `freecm`: the MIT-licensed command-validation, workspace-lock and Android helper subset; original license, version, commit, file hashes and local adaptations are retained in that directory.
- `openxr-vendors`: the version, source URL, byte size and checksum for the OpenXR addon archive.

Godot and its templates are preinstalled. `configs/prepare_assets.py --download` prepares the Godot OpenXR Vendors addon cache; Gradle prepares locked Maven dependencies. Keep their exact-version notices with redistributed outputs.

The repository includes only synthetic test media. Private human-video fixtures and model weights are excluded.

The CodeLibs JCIFS jar is staged by Gradle with unused HTTP/HTTPS NTLM adapters removed. Retained classes/resources keep upstream bytes and notices; SMB functions remain available.

The FreeCM snapshot's origin and file hashes live in `freecm/UPSTREAM.json`; see its [notice](freecm/NOTICE.md) and [MIT license](freecm/LICENSE). Addon checksums live in `openxr-vendors/manifest.json`. Gradle versions, locks and verification metadata live under `android/`. Host tools and large Android media libraries are prepared separately. `third_party/mpv/manifest.json` verifies the supplied Android libraries. See [BUILD.md](../docs/BUILD.md).
