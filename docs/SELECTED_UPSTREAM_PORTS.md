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

## Selective 0.16.5 ports (`9a6a905..da5f86c`)

### P1 — subtitle encoding

`SubtitleEncoding.kt`, `SubtitleCharsetDetector.kt`, `third_party/icu-charset/`, the detection fixtures in `SubtitleEncodingTest.kt`, and the choice policy in `file_subtitle_encoding.gd` derive from upstream GPL-3.0 code (ICU material retains Unicode-3.0). `SubtitleCopies.kt` and integration use Immivio's existing resource and per-file persistence owners. Read at most 8 MiB per text subtitle, retain at most eight discovered sidecars, and delete converted copies after native shutdown. No original is rewritten. Sidecar keys follow stable filenames/server-track identities rather than listing order; source locators remain behind hashes. Per-track overrides take effect on reopening, to avoid replacing live native resources. Opaque document providers still require explicit subtitle selection; no sibling access is inferred. No narration, translation or cloud integration is included.

### P2 — Emby/Jellyfin playback reporting

`MediaServerPlayback.kt`, `media_server_playback.gd` and reporter test scenarios derive from upstream `9a6a905..da5f86c`. Binding uses Immivio’s existing resolved stream table. Plex, STRM, local, SMB and DLNA have no report context. Unknown native/server track mappings are omitted; no guessed track IDs are sent.

Report confirmed playback start, throttled progress and stop to Emby/Jellyfin only while playback history is enabled. Turning history off discards queued reports, including stop; already dispatched HTTP cannot be recalled. Failures do not retry starts or affect playback.

### P3 — Emby/Jellyfin media versions

`playableDetail`/selected stream behavior derives from upstream EmbyClient; URI and menu integration are rewritten for Immivio. At most 16 directly playable item MediaSources are listed. Additional parts, transcoding and provider changes are excluded. Server-level resume remains available on the legacy default action; explicit versions use local per-version progress.

Offer direct-play Emby/Jellyfin versions on the details page. Explicit version URIs isolate resume, mode and track preferences; the unselected URI keeps the legacy identity. Report the selected MediaSourceId. Missing or unsupported selected versions fail without silently playing another file.

### P4 — Emby/Jellyfin folder browsing

The folders-mode exclusion policy derives from upstream EmbyClient. Immivio additionally excludes Photo to preserve its existing server-video scope. The 0.15.2 photo/media-type filter path and 0.16.2 child-artwork fallback do not exist in this architecture, so those paths are not introduced.

Preserve UserView and provider-defined folders by excluding unsupported leaves instead of whitelisting container types. Folder artwork continues to use the folder identity. Photo leaves remain excluded; no server photo viewer is added.

### P5 — Subtitle filename filter

`subtitle_picker_filter.gd` clean/default/filter policy derives from upstream, rewritten without DesktopFiles, cloud search or archive dependencies. The picker uses Immivio’s library ray/capture routes. Listings are bounded to 128 files and never recurse. Server APIs expose tracks rather than directory files, so no invented server directory search is performed. Selection is guarded by video URI and session; filename filtering is temporary, not persisted.

Add a title-seeded subtitle filename filter with ray keyboard and scroll-only thumbsticks. Local/SMB adjacent text files are listed within the current directory; server playback filters its available external tracks. Keep the system picker for document providers and other locations.

### P6 — External VIEW/SEND playback

The URI validation/temporary inbox ideas derive from upstream ExternalPlaybackRequest/IntentReader/Activity; integration is rewritten for Immivio. All external openings use session-only opaque identities, including file openings, so they create no new history or permanent grants. External HTTP headers and URI userinfo are rejected, so playlists receive no caller credentials. Content STRM is bounded and requires an absolute target, then uses the existing STRM resolver. External STRM chains may target HTTP(S) or saved SMB sources only; local/content targets are rejected to keep untrusted shortcuts outside app-private paths. Plain external files are opened as descriptors and checked against the actual descriptor path to close URI symlink races. Arbitrary providers, DRM, SEND_MULTIPLE, custom HTTP authentication and saved external-playback sessions are not promised.

Accept one validated Android VIEW/SEND video through a separate ingress, preserving the existing single-engine Activity reuse route. Content access is a temporary descriptor lease, never a persisted URI grant. Requests expire after 60 seconds and own at most four leases; provider preparation has an 8-second UI deadline and a bounded worker queue.

### P7 — Display refresh preference

Implemented against Immivio XrDisplay and settings migration, without importing an upstream display subsystem. Invalid stored rates migrate to 72 Hz; valid stored requests survive device changes, with a runtime fallback. A runtime with no advertised rates receives no request and shows no selector. Physical rate acceptance and power consumption require headset verification.

Change the headset refresh-rate default to 72 Hz for power saving, or the closest available rate (lower on a tie). Offer only runtime-advertised rates in Display settings and reapply after session resume. This changes the previous runtime-selected refresh behavior.

### P8 — Immersive adjustments and centre guide

`immersive_adjustments.gd`, `picture_center_guide.gd` and its shader derive from upstream. The passive overlay, persistence and input dispatch are rewritten for Immivio. No upstream ControllerBindings, interface-move or seek-HUD subsystem is imported. Lists, popups, focus loss and pointer capture suppress adjustments; a fresh grip or a suppressed stick must centre first. Vertical/flat stereo alignment remains ±5%. Orientation still recentres at the current gaze on opening; only translations/zoom are remembered. No new haptic behavior is enabled.

Add centred grip-stick immersive translation/zoom, ±10% immersive horizontal stereo alignment, fading numeric range feedback and a passive centre ring/cross during picture movement. Store translations and zoom per video; recenter clears those offsets while preserving existing stereo calibration. Flat video and photos keep their previous ranges and controls.

### P9 — Optional last video mode

`video_mode_default.gd` layout sanitization derives from upstream; resolution, preference persistence and migration are integrated into Immivio. Default is off. The existing mode lock remains the default when reuse is off or no valid last layout exists. No 2D-to-3D option, effect state, file identity or alignment is stored in this global preference.

Add an opt-in last-video projection/stereo fallback for otherwise unrecognized formats. Per-file modes and recognized filename, container stereo or established frame-shape rules still win. Store only layout, projection, fisheye angle and eye order; photos and removed effects stay independent.

### P10 — Direct playback order cycle

Only the upstream direct-cycle interaction is adapted. No repeat-all, repeat-one, single-play enum or mpv loop protocol is introduced. Existing queue_shuffle booleans retain their meaning, malformed stored values migrate to false, and the existing internal single-file loop behavior is unchanged.

Cycle the playback-order toolbar icon directly between the existing Sequence and Shuffle behaviors. Keep the separate queue editor and saved boolean preference; each queue still ends once its available entries are exhausted.

### P11 — Smaller flat screens and farther menus

The upstream numeric range behavior is adapted to Immivio’s existing ScreenPresets, surface setters and menu-distance owner. No preset distances or fixed default values are rescaled. Existing valid saved values pass through unchanged; only corrupt/out-of-range menu values are clamped. No photo range changes are imported.

Extend flat-video distance down to 0.1 m and size down to 5%, keeping the logarithmic sliders and unchanged physical saved values/preset envelopes. Extend library/menu distance to 4 m and normalize malformed or out-of-range stored menu distances. Photos retain 0.3–10 m and 40–600% limits.

### P12 — Pointer feedback and scheduled UI repaints

`pointer_ray.gd`, `pointer_ray.gdshader` and `pointer_ray.gdshaderinc` derive from upstream. Repaint scheduling is rewritten around Immivio’s existing compositor, presentation queue and menu owners. No browser/Gecko branches or new interaction targets are imported. World-space rays remain excluded from the UI capture texture; reticles retain the existing mapped coordinates. Headset GPU appearance, latency and thermal effects require physical verification.

Draw soft-edged, screen-width-stable pointer ribbons with distinct actionable-target feedback. Coalesce menu repaints, settle changed content across three frames, render continuously during pointer capture, and refresh otherwise idle captured UI at 4 Hz. Preserve both-panel native capture and all existing ray mapping/acknowledgement rules.

### P13 — Private crash trails and consented log export

`CrashTrail.kt` memory-mapped ring derives from upstream. CrashRecords, DiagnosticLogs, consent UI and the existing Godot DiagnosticLog integration are rewritten for Immivio and reuse PlaybackErrors redaction. Private events rotate across two 256 KiB files; Java records are at most 64 Ki characters, prior reports 128 Ki characters, and exports at most 512 KiB. Unclean exits are described as possible crashes or OS reclamation, not automatically labeled crashes. Binary native tombstones, logcat and Wi-Fi sharing are omitted to keep privacy/resource bounds reviewable. Native faults retain the ring and available Android exit summary; their full native backtrace is not claimed.

Retain a bounded, redacted step ring and Java crash record across restarts. Show prior-session availability in About and require a separate confirmation before saving a diagnostic log to Download/Immivio/logs. Keep five app-owned exports; never upload or share logs automatically.

### P14 — USB system-mount and provider recovery (partial)

PICO detection and permission-aware recovery intent derive from upstream UsbClaimPolicy/LocalStorageVolumes; implementation follows Immivio’s existing OS-mounted source and LocalStoragePermissions policy. Fallback is reevaluated after permissions/mount changes, never persisted as a ban. Provider FileNotFound is “missing” only after a successful empty metadata query. Direct USB interface claiming, block IO, partition scanning and filesystem backends are skipped: upstream UsbStorage depends on additional UsbBulkDevice/UsbPartitions/native filesystem infrastructure absent here, making that a new storage-driver stack rather than a small port. Some PICO paths and opaque third-party providers can still fail; no hardware unmount or forced claim is attempted.

Improve verified mounted-volume fallback on Android 11+, distinguish missing permission, unmounted storage and provider failure, and give PICO-specific settings/reconnect guidance. Stopping App access closes related video/photo readers and known external descriptor leases without claiming hardware removal.

### P15 — Provider marks and Plex libraries

`provider_icons.gd` normalization and Plex collection-type/library-mode behavior derive from upstream. Marks are independently drawn monograms in the existing MenuIcons line system; no third-party brand SVG assets or unrelated provider aliases are imported. Existing Stash support keeps its generic server icon. Plex retains its current first-library default/data queries and all PlexConnectionSelector behavior; global history queries, library-artwork transcoding and Plex version selection are not imported.

Use consistent provider marks for existing Emby, Jellyfin, Plex, XBVR, DLNA, SMB and local sources. Open Plex at its library chooser and distinguish movie/TV libraries; choosing TV opens series navigation instead of a flat episode wall.

### P16 — Primary pinch and menu hand

The hand preference/normalization policy and tap hand context derive from upstream ControllerBindings/photo_hand_gestures. No controller remapping subsystem is imported. Settings use Immivio’s migration and General page. The selected hand initiates photo taps/swipes; a secondary hand can assist a selected-hand zoom to preserve the existing two-hand feature. Physical controller buttons and palm-wave navigation are unchanged. This default and the allowed secondary-hand assistance are explicit behavior decisions for review.

Add Left/Right/Both as the shared primary hand for content pinches and summoning controls. New installs default to Right; review correction F3 preserves Both for existing settings files without an explicit choice. The official palm menu gesture remains fixed to the left hand and does not use the pinch preference. Both hands still select controls in an already-open menu; the other hand may join an active photo zoom. Changing the setting cancels ownership and requires a fresh open-then-pinch.

### F1 — second-round review

Review correction to P1. SubtitleCopies now returns the original track on decoding, size-limit, staging or IO failure; discovered original leases remain owned until native shutdown. Failed explicit overrides keep the user choice for review and display “Encoding invalid”; automatic detection failures simply retain mpv’s original behavior. No retry loop or unbounded read is introduced.

### F2 — second-round review

Review correction to P3. Godot resume parsing now separates and validates the item ID/source query while retaining the full original URI for progress/mode/track memory. Resume deduplication includes source_id; detail progress matches exact URIs. An unavailable requested version offers no default-file action. Audit found Kotlin MediaLibraryUri already separates URI.path and sourceId and rejects foreign query fields; its existing round-trip and selected-stream tests remain authoritative. Other Godot medialib prefix uses only scope account/filter membership, not extract a scene ID.

### F3 — second-round review

Review correction to P16 following the updated product instruction. Preference migration receives the actual ConfigFile load result: an existing, successfully loaded file without controls/pinch_hand gets Both and saves once; missing/corrupt files use the fresh Right default. Explicit Left/Right/Both choices are preserved. Only optical pinch content gestures and pinch taps use the preference; official palm menu events remain left-only, and physical controller buttons are unchanged.

### F4 — second-round review

Review narrowing of P6. VIEW uses separate filters to avoid Android combining network schemes with application/octet-stream. SEND retains its video/binary type association (its URI is carried in EXTRA_STREAM), and request validation rejects binary/network SEND payloads too. Explicit text/plain STRM intents are rejected; content/file application/octet-stream STRM remains supported. Actual unsigned Godot export is checked through its final merged manifest; signing preparation and installation are not used.

### P17 — second-round review

Implemented independently in Kotlin UpdateCheck and an asynchronous, single-request Godot bridge. Only the About action initiates IO; construction, rendering, startup/resume and backgrounding do not check. The production endpoint is fixed HTTPS; the injectable HTTP test seam permits loopback only. Connect/read timeouts are 5/10 seconds, responses at most 256 KiB, and redirects are all rejected (including same-host, a conservative subset of the required cross-host ban). Only exact vMAJOR.MINOR.PATCH tags and an exact matching repository html_url are accepted. Version components compare numerically without integer overflow; draft/prerelease flags are rejected defensively. No account store, auth token, APK download, install permission or persistent update setting is used. About website/source entries in this edition are informational labels, so the release button uses a narrow new ACTION_VIEW bridge rather than adding a general URL opener.

### G1 — fresh pinch default persistence

Third-round correction to F3. A missing/unreadable settings file seeds Right in the in-memory ConfigFile without an immediate write. Saving any subsequent preference carries that value, so a later launch cannot misclassify a fresh installation as legacy. Successfully loaded legacy files without a choice still migrate once to Both; explicit choices are preserved. No new schema or version flag is introduced.

### G2 — third-round review

Third-round completion of F4. A shared configs/android_manifest.py policy serves both the XML CLI and player_build.inspect_package after its actual aapt2 APK dump. Indentation, namespaces, resource IDs and typed scalar values are decoded structurally; category/game checks also use the tree. This keeps standalone configs-only workflows viable, adds no tool/dependency, and avoids any signing operation during host tests. The regression test executes inspect_package with only native/signature tool boundaries mocked and rejects compiled broad-network/BROWSABLE fixtures.

### G3 — third-round review

Third-round correction to P17. ReleasePageOpener validates the same fixed release URL, schedules ACTION_VIEW, and emits a request-ID/tag-scoped result only after startActivity succeeds or throws. The bridge returns that request ID for queue acceptance; late results, including an older launch of the same tag, cannot overwrite a newer check or retry. Failure leaves the release action available for a user-requested retry. There is no automatic browser retry or network check.

### G4 — third-round review

Third-round text completion for F2. media_server_browser.gd already renders menu.status through I18n.t; no routing change is needed. The resume/version integration test now removes the requested version, receives the actual error status and verifies the rendered text snapshot in all three locales. English remains the source-key fallback.


### J1 — dual text subtitles (0.16.2, GPL-3.0)

Behavior and selection/composition scenarios derive from upstream `42bbca9` (0.16.2), within `9a6a905..da5f86c`: `app/godot/scripts/dual_subtitles.gd`, `app/godot/tests/test_dual_subtitles.gd` and secondary-channel portions of `native/mpv/mpv_source.cpp`. Immivio's `dual_subtitles.gd`, native secondary snapshot/control channel, Kotlin boundary, mode-record extension and compact subtitle-panel integration are adapted to its own playback/session owners. No upstream store or rendering architecture is copied. `@UsedByGodot` registers `set_mpv_secondary_subtitle` in Godot's Java method registry; availability uses `PlatformMethods.supports`.

Both text tracks use the existing single subtitle delay and per-track charset overrides. The ordinary import action still selects primary. Secondary preferences live in existing `track_choices` records, migrate with file operations, and are written only when history and per-file memory are enabled. Missing/ambiguous track metadata does not select a different language. Caption sizing fits both wrapped text blocks inside the flat display or projected patch. Narration, live subtitles, cast, independent delays and 3D text protection are excluded; bitmap subtitles remain unsupported.

Native host tests decode production subtitle JSON with an independent Python parser, test separate command IDs/track IDs, shared delay metadata and blank text on timeline invalidation. Android NDK compilation verifies the complete JNI/libmpv integration. These checks do not execute an XR libmpv session or certify headset rendering.


### J2 — captions below flat video (0.16.3, GPL-3.0)

Behavior derives from upstream `ef83472` (0.16.3), within `9a6a905..da5f86c`: `file_subtitle_layout_memory.gd`, `mpv_video_display.gd`'s `subtitle_below_screen`, and `test_subtitle_layout_memory.gd`. Immivio stores a validated boolean in its existing per-file mode record; no additional upstream store is introduced. File relocation carries the complete record. New/unknown files default off, and history/per-file-memory privacy gates apply.

Only flat video (including packed SBS/TB and flat spatial playback) changes placement. A top-aligned caption is translated below the transformed screen's lowest point in the caption pose's own plane with a fixed 0.02 m gap, accounting for its measured multiline bounds and outline. Transformed mesh bounds conservatively cover curved screens; translation follows the pose down axis and keeps the 0.01 normal offset during reclining placement. The vertical slider is disabled while below-screen placement is selected and keeps its original value. Immersive projections retain their projected patch; the disabled UI explains the flat-only scope. Photos, narration, live subtitles, cast and 3D text protection are excluded. Host tests measure actual transformed bounds across scale/distance/rotation/stereo/text-size cases; physical readability remains owner acceptance.
