# Selected upstream features

This implementation adapts selected behaviors from zerochocobo/Thru3D-Media-Player through commit `9a6a905941ecb69e9484ef2bb87d2e3a27705594` (0.13.3). `StrmFile.kt`, `StrmHttp.kt`, their parser/HTTP test scenarios, and `screen_presets.gd` derive from that GPL-3.0 source. Other integration code follows Immivio's independently maintained playback, menu and persistence architecture. The shared baseline is `9d36169` (0.6.0). Original project attribution and the repository GPL-3.0 license remain in place.

## STRM

A local/SMB `.strm` file contains one accessible HTTP(S), SMB or local media address, or a relative path. The system picker can also select a STRM document; opaque document URIs require an absolute target. UTF-8 (optional BOM) and BOM-marked UTF-16 are supported, with comments/blank lines, a 64 KiB limit, at most four shortcut levels and loop rejection. HTTP redirects resolve relative paths against the final document URL. Parsing happens only on playback, not directory scanning.

SMB addresses reuse saved connections. Ambiguous accounts require a matching source connection; credentials are not taken from shortcut contents. Relative SMB paths cannot escape the share. Cloud providers, Kodi plugin URLs, header suffix syntax, scripts and playlists are not added. STRM is not a link-refresh service. History, mode memory and sidecar discovery retain the original shortcut URI. File operations act on the shortcut and existing companion-file rules, never the referenced movie.

## Loading feedback

Video preparation reports source resolution, sidecar loading, native setup and waiting/buffering. Actual video input throughput comes from libmpv's public `cache-speed` property, including loopback reads for SMB/media servers; unavailable rates are omitted. It is not a bandwidth estimate or a promise of server throughput. Photos show loading/wait time without inventing a measured speed. Signed URLs and credential fields are redacted from surfaced native diagnostics. A failure opens Info once; ordinary buffering does not force controls open.

## Browsing and control placement

Directory identities include source/account, folder and media filter. Up to 512 hashed identities retain a visible-item anchor, bounded index and sort preference. Restore uses the available listing, without crawling a server to reconstruct a position. Server-provided paging remains bounded by the existing browser. Switching list/icon mode keeps the first visible item when possible. Directory memory can be disabled separately; disabled playback history keeps new positions only in memory, and enabling history does not backfill them. Clearing history clears both persistent and session directory positions.

The toolbar folder action opens compact browsing with playback controls retained. The browser can expand, switch display mode, browse/sort and return to playback. Pointer capture continues to own sliders even when both panels are visible. The spatial lock is session-scoped, survives hide/reopen, and keeps related popups on the same plane while video placement changes. Explicit recenter is an escape hatch. Opacity affects the control-bar background, not labels or popup readability.

## Flat-screen cinema presets

TV presets fit 100/150-inch 16:9 envelopes; giant presets fit 22/32 m-wide 1.43:1 envelopes without stretching/cropping the media. Distance spans 1–50 m; the new size slider spans 100–3000%, while legacy smaller saved scales remain supported. Photos retain their own limits. Curvature, eye-height placement and the temporary grid use application coordinates, not detected room geometry. Fixed defaults survive temporary adjustments and restore on a new video or recenter. No auditorium, AI model, custom mpv build or cloud dependency is introduced.

## Verification

The parser tests include real loopback HTTP redirects, failures and bounded reads. `test_selected_upstream_features.gd` exercises navigation persistence/privacy, list/grid position, independent sorting, spatial lock, fixed screen defaults and buffering/error presentation. The existing JVM and Godot suites remain applicable. Physical PICO 4 automated playback, persistence, production ray routes and native UI captures are recorded in [ACCEPTANCE.md](ACCEPTANCE.md). The final package also passed normal Android launcher cold/repeat entry and native playback. PICO lists the sideloaded immersive SDK entry under Library → Unknown sources; simulated resource-pane automatic foreground handoff is not certified. These checks do not certify physical controller actuation, lens comfort, other headsets or sustained thermal performance.
