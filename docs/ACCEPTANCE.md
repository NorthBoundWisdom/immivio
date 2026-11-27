# Device acceptance

Run this checklist on a physical headset before a release that changes the
covered area. Host, GPU and emulator tests do not certify headset display,
audio, comfort or performance. Build and probe commands are in
[BUILD.md](BUILD.md) and [TESTING.md](TESTING.md).

## Checklist

Also verify the video compositor route on each target headset: eye order and
colour, effect fallback, seek/close, suspend/context recovery, and sustained
memory and thermal behaviour.

- [ ] **A01 — Playback, projections and packed alpha.** Open normal video, mono,
  SBS/TB (including half packing), VR180/fisheye and VR360. Check eye order,
  projection, lens FOV, color, alpha readiness and passthrough against known
  fixtures. Exercise pause/redraw, speed/exact seek, repeat/EOF and close/reopen.
  With the fixed 320×320 opaque mask, source/color dimensions must still follow
  the existing output-width setting. Check decoder/status and error recovery.
- [ ] **A02 — Locales and menu presentation.** Browse Library, Settings, About,
  credits/licenses, playback and every popup in Simplified Chinese, Traditional
  Chinese and Japanese, with English as the reference. Check untranslated text,
  clipping, scroll positions, first-open layout and transitions. Include Refresh,
  Done, Add server and Internal storage. Toolbar/title/timeline placement and
  pointer feedback must remain stable while pages redraw or await acknowledgement.
- [ ] **A03 — Controllers, hands and spatial controls.** Verify rays, triggers,
  grips, focus loss, menu following, reclining placement and explicit/system
  recentering. Test the left official palm gesture under Left/Right/Both pinch
  preferences: one open/close per deliberate gesture, no held repeat. Either
  hand may select an open menu. Fresh installs default to Right; legacy settings
  without the preference migrate to Both while retaining other choices. A
  preference change during pinch cancels ownership until release. Grip-stick
  immersive translation/zoom/alignment
  must wait for centered sticks, show feedback and retain per-file intent;
  list/slider capture excludes seeking or picture adjustment until the sticks
  return to center.
  Recenter clears immersive offsets while retaining stereo calibration.
- [ ] **A04 — Local files, removable storage and the real picker.** Verify access
  requests, denied/revoked permissions, refresh, readable/missing files and USB
  removal/ejection. Readers must close without stale handles. Exercise the actual
  document picker, including cancel, unusual names and returned URI grants;
  the picker UI is not covered by the grant driver. Browsing, thumbnails and
  late replies must preserve the existing behavior.
- [ ] **A05 — SMB and DLNA.** Verify authentication, share/server enumeration,
  folders, playback, random reads/seeks, reconnects, SMB signing/encryption and
  late-response cancellation. Use prepared servers and test accounts.
  Source/account removal must release its readers and network resources.
- [ ] **A06 — Media servers and version resume.** Check Plex, Emby, Jellyfin,
  Stash and XBVR with available owned fixtures, including nested/plugin folders.
  Emby/Jellyfin direct-play versions must retain separate local mode, track and
  resume intent and report the selected MediaSourceId. Record grouped-item
  versus selected-item server progress after another client watches a
  non-default version. Cross-client version-resume import is not promised:
  explicit version rows use local per-version resume, and default actions may
  receive older grouped-item progress. History-off must send no new progress
  or backfill; server failures must not interrupt local playback.
- [ ] **A07 — Subtitles and timing.** Play known GBK/GB18030 and Big5 sidecars
  from local/SMB sources; verify Auto/manual encoding after reopen, invalid
  override feedback and unchanged source hashes. Test embedded plus external
  primary/secondary text tracks, shared delay, independent choices, stale-cue
  clearing and primary-Off/same-track rules. For flat video, check below-screen
  captions across size/distance/rotation/SBS/TB and reclining, including outline
  bounds. Include screen sizes 5%/3000%, distances 0.1/50 m and ±85° pitch; the disabled percentage retains its value. Immersive projections keep
  their projected captions and flat-only hint. Repeat with history disabled.
- [ ] **A08 — Saved-mode and preference migration.** Upgrade installations with
  schema-1/2 per-file records, including missing/obsolete `profile`. Confirm
  schema 3 omits it while retaining projection, stereo/half packing, eye order,
  alignment, immersive adjustment, FOV, caption placement/encoding, track choices
  and audio/subtitle delay after reopen and restart. Verify current defaults,
  privacy gates, folder/sort memory, bookmarks, queues and native stereo locks;
  retired photo/inference settings must not reappear.
- [ ] **A09 — Lifecycle, wearer presence and context recovery.** While the app
  stays in the foreground, verify playback continues through a wearer-presence
  change. Test activity suspend/resume, audio focus, reopen and recreated GL
  context. Resume in place without overriding manual pause or reviving closed media.
  Verify frozen seek transitions, retained frames and final-frame cleanup;
  host geometry/state checks do not certify headset pixels or audible output.
- [ ] **A10 — Manual update flow.** Request Check for updates, exercise
  checking/current/new-version/error states,
  and open the offered GitHub release page. Verify browser return, localized
  no-handler failure and manual retry. Startup/background/redraw must not check
  automatically.
- [ ] **A11 — Sustained rendering, cadence and comfort.** Measure memory/handles,
  thermal state, decoded/presented/XR cadence and perceived comfort separately.
  Look around in the cached sky and during supported video playback. On PICO,
  compare advertised refresh rates with a known 60-fps fixture, including 72 Hz,
  pause/resume and supported-rate fallback. A 72/60 cadence is not integer;
  record actual smoothness/power results rather than assuming zero judder.
  On Quest 2, use a local 4096×2048 HEVC SDR 59.94-fps clip with bright areas.
  Compare flat and VR180 SBS playback at fixed 72, 90 and 120 Hz where advertised.
  Record the display Hz and render FPS separately across play, pause and session
  resume, and note whether the highlights flicker at each actual refresh rate.
- [ ] **A12 — GPU ownership and transport.** Check borrowed color, cached opaque
  mask reuse, backpressure and complete version-2 frame descriptors. Exercise
  last draw → detach → consumer fence → producer release, pinned readback,
  seek-generation changes and context loss. Incomplete/stale pairs must not be
  presented, and close/reopen must not reuse resources from a former context.
  See [FRAME_CONTRACT.md](FRAME_CONTRACT.md) for report interpretation.
- [ ] **D1 — Unified device probes.** Run the selected-feature/player probes and
  `tools/run_device_diagnostics.py core`, `gpu` and `audio` with the matching
  installed Debug APK and explicit fixture requirements from
  [TESTING.md](TESTING.md#device-probes-and-local-media). Verify device selection,
  APK hash, unique request keys, current process/session correlation, bounded
  waits and timeout evidence. Preserve the run directories under
  `artifacts/captures/device/`. Host fake-ADB tests do not establish Android
  delivery, decode, audible output, XR display or performance.
- [ ] **D2 — External URI grant/revocation driver.**
  PICO currently blocks the fixture process from starting by broadcast. Use
  `tools/run_external_uri_probe.py` with its separate-UID fixture APK. Verify
  temporary grant → native FD decode → revocation → denied access, both before
  and after client-process restart, without a residual grant. Also use a real
  file manager's Open/Share/SEND path twice: one normal engine, released
  temporary resources, no permanent grant, and no temporary provider URI in
  history/per-file memory. Keep BROWSABLE,
  binary HTTP and app-private file paths excluded. Distinguish provider denial
  from decoder failure; this driver does not automate picker UI or device reboot.

- [ ] **D3 — Loopback connection peak.** Play SMB and media-server streams on a
  headset. Drag the timeline repeatedly while playing, then save the
  diagnostic log. Record the `loopback_connections` active count and peak,
  stream type and seek scenario as evidence for a future connection limit.
- [ ] **D4 — Surface route after XR resume.** On PICO and Quest, start video on
  the `surface` route. Remove and put on the headset, then open and dismiss the
  system menu in a separate pass. Record the XR session transitions and the
  playback session ID before and after each pass. Verify the same playback
  session resumes on `surface` without reopening the video.
- [ ] **D5 — SDR with HDR-to-SDR enabled.** Enable HDR-to-SDR and open a known
  SDR fixture that otherwise qualifies for Surface playback. Verify the route
  settles on `surface` and stays there as playback advances.

## Recording a result

For each item, record date, case ID, headset/runtime/OS, package channel and
build type, APK SHA-256, fixture hashes, starting settings, steps, observations
and the evidence directory. Use pass/fail/not-applicable with a concrete reason.
Keep credentials, personal media and device logs outside Git.
