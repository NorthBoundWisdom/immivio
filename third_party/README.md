# Third-party components

This directory retains upstream license texts, source locks, checksums and provenance. The application's overall GPL v3 choice does not replace these components' existing terms. See [licensing scope](../docs/LICENSING.md) for the component inventory and binary-release requirements.

- `mpv`: headers/provenance, exact source archives, library reference receipt and GPL/LGPL texts. The project's source-frame modification is in `native/mpv/patches`.
- `p115rsacipher`: original MIT notice and provenance for the Kotlin 115 RSA adaptation.
- `gradle`: wrapper Apache-2.0 license and notice.
- `polyhaven`: CC0 source and attribution for the unmodified built-in background.
- `openlist`: AGPL-3.0 upstream license, Go/gomobile and dependency notices; the local Go adapter is in `cloud/openlist`, with the checksum-pinned build and source modification in `configs/dependencies.py and configs/player_build.py`.

FreeCM prepares Godot and Godot OpenXR Vendors assets; Gradle prepares locked Maven dependencies. Keep their exact-version notices with redistributed outputs.

The repository includes only synthetic test media. Private human-video fixtures and model weights are excluded.

The CodeLibs JCIFS jar is staged by Gradle with unused HTTP/HTTPS NTLM adapters removed. Retained classes/resources keep upstream bytes and notices; SMB functions remain available. The combined binary OpenList obligations are recorded in the licensing scope above.

All dependency versions, source commits and integrity records are managed in `source_roots.lock.jsonc.in`. Native JSON receipt records are generated compatibility inputs, not independently maintained source locks. Full Git source roots are materialized through FreeCM.
