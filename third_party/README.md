# Third-party components

This directory retains upstream license texts, source locks, checksums and provenance. The application's overall GPL v3 choice does not replace these components' existing terms. See [licensing scope](../docs/LICENSING.md) for the component inventory and binary-release requirements.

- `mpv`: upstream headers, Android release provenance, library checksums and GPL/LGPL texts.
- `p115rsacipher`: original MIT notice and provenance for the Kotlin 115 RSA adaptation.
- `gradle`: Apache-2.0 license text used by the dependency-license maintenance tool; the Gradle wrapper implementation has been retired.
- `polyhaven`: CC0 source and attribution for the unmodified built-in background.
- `openlist`: AGPL-3.0 upstream license, Go/gomobile and dependency notices; the local Go adapter is in `cloud/openlist`, with the source modification and build recipe in `configs/dependencies.py` and `configs/player_build.py`.

Godot and its templates are preinstalled. FreeCM prepares the Godot OpenXR Vendors addon; Gradle prepares locked Maven dependencies. Keep their exact-version notices with redistributed outputs.

The repository includes only synthetic test media. Private human-video fixtures and model weights are excluded.

The CodeLibs JCIFS jar is staged by Gradle with unused HTTP/HTTPS NTLM adapters removed. Retained classes/resources keep upstream bytes and notices; SMB functions remain available. The combined binary OpenList obligations are recorded in the licensing scope above.

FreeCM source commits and addon checksums live in `source_roots.lock.jsonc.in`. Gradle versions, locks and verification metadata live under `android/`; Go modules are pinned in `cloud/openlist/go.mod` and `go.sum`. Host tools and large Android media libraries are prepared separately. `third_party/mpv/manifest.json` verifies the supplied Android libraries. See [BUILD.md](../docs/BUILD.md).
