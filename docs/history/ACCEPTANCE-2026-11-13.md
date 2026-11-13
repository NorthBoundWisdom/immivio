# Acceptance evidence snapshot — 2026-11-13

This is a historical snapshot. Versions, test counts, device results and
pending wording below describe their original checkpoints; they are not a
current task list. Retired photo/inference/cloud features and former host jobs
appear only as historical context. Current physical checks are maintained in
[Device acceptance](../ACCEPTANCE.md#current-device-acceptance).

---

# Device and build acceptance

## Dependency refresh — 2026-11-13 (pending)

- On Quest, PICO and generic OpenXR headsets, verify startup, session creation,
  suspend/resume, recentering, controller/hand input and ordinary/packed-alpha
  playback with Khronos OpenXR loader 1.1.65 and OpenXR Vendors 5.1.0. Record
  the APK hash and runtime version; host builds cannot certify runtime behavior.
- With bcprov 1.87 and SLF4J 2.0.20, verify SMB authentication, share enumeration,
  random reads/seeks, reconnects, signing and SMB 3 encryption against a prepared
  test server. Host crypto/packaging tests do not replace device/server checks.
- After an authorized push, confirm the Android workflow runs one macOS build
  and no Windows build; observe Source checks and the website workflow using
  the updated full-SHA Actions pins. Exercise artifact upload/download and the
  existing release-receipt checks during the next authorized release.

## Fixed opaque mask and saved modes — 2026-11-13 (pending)

- Upgrade an existing installation with schema-1/2 per-file modes. Verify saved
  projection, SBS/TB/half packing, eye order/alignment, immersive adjustments,
  fisheye FOV, primary/secondary subtitles, caption placement/encoding, track
  choices and audio/subtitle delays survive reopening and restarting. The new
  schema-3 bank must omit `profile`, including when the legacy record lacked it
  or contained an obsolete value.
- On Quest, PICO and generic OpenXR, verify normal and packed-alpha playback,
  pause/seek, stereo revisions, suspend/resume and context recovery with the
  fixed 320×320 opaque mask. Pair evidence should retain the source/color
  dimensions selected by the existing output-width setting; no decoder or
  video-size change is intended.

## Source and input ownership — 2026-11-13 (pending)

- Verify local-volume permission/refresh/eject and SMB/DLNA browsing, navigation,
  account editing and late-response cancellation with state owned by the source
  controller. Menu drawing and interaction should match the previous behavior.
- Verify controller/hand rays, focus loss, head tracking, grips, menu following
  and explicit/system recentering through the new input-source object on the
  supported headsets. Host input fixtures do not certify XR runtime delivery.

Host evidence for the ownership/test-interface changes: 102 Godot scripts,
126 workflow tests and the existing JVM suite passed. Desktop GPU checks
covered seek-edge alpha, six library pages, 24 audio layouts and 122 stereo
render assertions, with representative captures reviewed. These checks leave
the headset cases above pending. Logs/captures are under ignored
`artifacts/reports/architecture-20261113/`.

## Cached night sky follow-up — 2026-11-10

The owner reported drops to about 60 FPS while looking around after the stationary home result below. The final night renderer now generates the static star field and Milky Way once at 8192×4096 in linear HDR, stores RGB9E5 mipmaps, and keeps only the hill silhouette analytic. Rotation and brightness reuse the texture; leaving the scene releases it. The cache occupies 178,956,972 bytes (about 171 MiB) including mipmaps, trading additional memory and startup work for lower steady rendering cost.

The installed Pico/Debug/appstore APK before final code cleanup has SHA-256 `5491b72d17cac827eabc4a8affc1a38f91fed82e8d03bbd7e4bfe7743cc73918`. Initial focused starry-home runtime logs show 72 FPS and about 4–7 ms app GPU time, compared with about 12 ms after the UI-only optimization. The subsequent observer ran for 90 seconds and collected 89 focused head poses spanning 111° and eight fresh runtime FPS records, all 72 FPS (GPU median 4.145 ms, p95 4.34 ms). The FPS records do not cover that entire pose-observation window; a later screenshot contains owner-started video playback, so it is not used as starry-home evidence. The owner subsequently reported the result was essentially satisfactory.

All 102 headless Godot scripts passed; the real-GPU background test passed 70 checks including cache storage/reuse/release, and paired sky captures were reviewed across upward, horizon, downward, pole, seam and dimmed views. Logs remain under ignored `artifacts/reports/pico-performance/starry-followup/` and `artifacts/tests/godot/`; pre-cache APK/receipt are preserved in `artifacts/archive/pico-performance/pre-star-cache/`. Local captures and device logs are not repository assets. These observations do not certify every viewpoint or long thermal operation.

## PICO 4 home rendering — 2026-11-10

This earlier UI-only optimization of the 0.9.10 worktree was built as Pico/Debug/appstore, installed over the matching Debug identity with `adb install -r`, and measured on the stationary focused home page with no video. Both runs used the original starry sky, 1504×1504 eye buffers, 2× MSAA and foveation off. The optimized APK SHA-256 is `931bdb13f874adea750f27f1418ff87c24d1e3367558fef4d5810992be6e0948`.

| PICO runtime measurement | Baseline | Optimized |
| --- | --- | --- |
| Median reported FPS | 53 / 72 | 72 / 72 |
| Median app GPU time | 18.55 ms | 12.56 ms |
| Median app CPU time | 0.935 ms | 0.47 ms |
| Median GPU utilization | 99% | 88% |
| Reported composition layers | 6 | 4 |

After warmup, all 97 one-second runtime samples in the sustained optimized capture reported 72 FPS; GPU time p95 was 12.7 ms. The physical stereo screenshot also shows 72 FPS. Beams render directly in the main stereo projection, as in 0.9.0, retaining the current analytic thin edges/fade and avoiding two full-eye copies/layers. The native UI presenter acknowledges successful copies and leaves unchanged captures in the retained Android Surface buffer.

Six JVM surface/frame tests, four focused Godot behavior scripts (composition, panel ray geometry, redraw continuity and UI presentation), and real-GPU beam style/stereo renders passed. APK packaging verified the signature, native dependencies, alignment and application identity. Evidence is under ignored `artifacts/reports/pico-performance/`, `artifacts/captures/device/pico-performance/` and `artifacts/tests/godot/pico-performance/`; the original package/receipt are preserved in `artifacts/archive/pico-performance/baseline/`. The attempted dark-background baseline did not apply its setting and is explicitly excluded from the comparison. These results cover this observed home scene, not video playback, every head pose or long thermal operation.

## 0.9.5 (`v0.9.4..v0.9.5`) — device acceptance remains pending

No headset was available for rounds 4 and 5. The checks below cover the selected ports and review corrections included in v0.9.5; historical device results later in this document do not certify this source. Raw logs, APK inspection output, size reports and synthetic-server evidence remain under ignored `artifacts/upstream-round4/`; emulator evidence is under `artifacts/emulator-acceptance-2026-11-04/`. Round 5 host, native, Jellyfin and new APK evidence is under `artifacts/upstream-round5/`. This range includes the first post-v0.9.4 commit (FreeCM removal).

Latest UI regression evidence is retained under `artifacts/playback-startup-20261105/` and `artifacts/header-pointer-20261105/`: all 99 Godot scripts pass, including first-frame control placement, exclusive curved pages and informational header reticles. A real GPU pixel test reproduces and fixes clipped highlight antialiasing; the owned Android emulator confirms zero visible startup timeline displacement and curved popup switching. These checks do not certify physical controller/hand interaction or headset comfort for the final tag.

### Offline and local integration results — 2026-11-04

| Check | Actual result and boundary |
| --- | --- |
| H2 Debug packaging | Quest, Pico and OpenXR each completed configure → build → package using existing tools/dependencies and the existing signing identity. Final APK inspection passed the shared manifest gate, ELF checks, alignment and signature verification. No key was created or changed. APK source revision at this step was `d9f3f6e`; subsequent round-4 changes add tests or documentation. The round-5 runtime package is recorded below. |
| H2 size baseline | Built the same three Debug targets from local tag `v0.9.4` (commit `63584ef`) in a detached worktree. Used Analyze-ApkSize.py on each pair; growth is about 246 KB per target, mainly DEX (application changes plus ICU detector classes), ICU notices and new scripts. DEX costs cannot be attributed to ICU alone. |
| H3 upgrade migration | In AVD Thru3D_Perf_API36, baseline and current signed Debug packages used the same existing key. Seeded legacy history=false, then changed sharpness to 0.4 through the existing Debug settings route. After adb install -r and 2D diagnostic restart, both values remained and controls/pinch_hand was both. |
| H3 clean install | Cleared only this app's isolated test-emulator data, launched current 2D diagnostics, changed another setting through the existing Debug route, and restarted. controls/pinch_hand remained right_hand. This is Android persistence validation, not physical hand interaction. |
| H3 external intents | HTTP video and file video matched the ingress and forwarded to the normal launcher. HTTP application/octet-stream and BROWSABLE intents did not resolve to this app. The private-file case reached only the rejecting ingress, without forwarding; no independent rejection receipt was available. The shell could not grant the external-storage document URI (SecurityException), and SEND matched ingress without proving readable provider access. |
| H3 external playback/reuse | Not certified: the normal VR launcher on the emulator crashed in OvrContextFactory/EGL context creation. Repeated launches therefore did not provide a stable Godot session for instance-reuse or playback acceptance. No product code was changed for the emulator. The 2D diagnostic route itself ran successfully. |
| H3 browser | Chrome resolved and ACTION_VIEW launched its first-run Activity with emulator networking disabled. Actual release-page loading/browser return behavior remains unverified. No extra remote page download was performed. |
| H4 GitHub schema | One unauthenticated curl with User-Agent Immivio-dev returned HTTP 200, tag v0.9.4 and the exact matching repository release URL. Minimized real-response fixture passes latest/same-version and available/newer-tag JVM checks. No automatic check, APK download or install was added. |
| H5 Jellyfin | Official jellyfin/jellyfin:latest, server 12.4.0, synthetic two-version movie and nested folder. Production JVM clients retained folder containers, listed two versions, selected the requested PlaybackInfo source and read an authenticated range. Playing/Progress/Stopped all returned success; server resume was 120000 ms. History-off sent zero additional reports and did not change server progress. |
| H5 isolation and cleanup | Docker internal-network port publishing was unavailable, so a loopback-only test bridge forwarded to container localhost via Docker exec. The container had no external egress. Removed the owned container/network, bridge, server data, temporary credentials and synthetic media. The official image remains cached. No Emby server was exercised. |
| I1 paused resume | Reused only the cached Jellyfin 12.4.0 image with --pull=never, the same 600-second media and default resume thresholds. Paused-start and playing 60s → 120s → pause() → stop both retained 120000 ms on the selected version item; an additional 60000 ms Progress readback prevents stale resume from masking failure. The original grouped-item readback was 0 while the selected item's UserData was 120000 ms. Fixed test identity/order assumptions, without changing the playback reporter or fixture media. History-off dispatched no new reports. Removed owned container, internal network, bridge, credentials, server data and synthetic media. |
| I2 DLNA repeatability | Before correction, 2/50 filtered Gradle executions failed (4%). Diagnosed requests reaching another local service: on this macOS/JDK, a wildcard ServerSocket can share an occupied specific loopback port. A deterministic occupied-port regression failed before correction. Bound the HTTP fixture to its advertised 127.0.0.1 address, made the cross-thread offset list safe, and kept all exact offset assertions with diagnostic rejection causes. After correction, 0/50 failed; no sleeps or relaxed assertions. Product DLNA code is unchanged. |
| J1 dual text captions | JVM validation, 35 Godot behavior checks, three native host helper tests and Android JNI/libmpv compilation passed. Covers embedded/external text, independent secondary command fences, shared delay, composition, stale clearing, primary-off/same-track rules, per-file restore/relocation/privacy and measured multiline bounds. No headset libmpv/XR rendering was exercised. Narration/live subtitle/cast/3D text protection are excluded. |
| J2 below-screen captions | 741 Godot checks passed, including actual transformed caption/outline bounds across 5–3000% scale, 0.1–50 m distance, five rotations, mono/SBS/TB, two text sizes. Those round-5 assertions used world-Y bounds; upright mode removed the requested placement pitch. Per-file restore/move/privacy, slider-value retention and immersive disable/hint passed. These are geometry/state checks; physical readability and GPU rendering remain owner acceptance. |

Current-source APKs from H2 (version numbers are unchanged):

| Platform | APK under artifacts/upstream-round4/H2 | Bytes | SHA-256 | Growth vs same-platform v0.9.4 |
| --- | --- | --- | --- | --- |
| Quest | `HEAD-Immivio-QUEST-0.9.4-debug-20261104.apk` | 170206259 | `69f0c727b467e7a1e0ad413a6d7b551519ef0388b6cc1f3155fbee302335e9f4` | +246339 bytes |
| Pico | `HEAD-Immivio-PICO-0.9.4-debug-20261104.apk` | 170403011 | `48c320734e004c594cd74379ec5d5562993ea484a8ba360b3140f67ec2a79740` | +246343 bytes |
| OpenXR | `HEAD-Immivio-OpenXR-0.9.4-debug-20261104.apk` | 170402779 | `8320d63fb520119ea794c728d38f4670a081a6b8656e56c9316cc902248a5ec2` | +246359 bytes |

Round 5 reproduced the apparent paused-resume failure on Jellyfin 12.4.0: the grouped movie returned 0 ms while the selected alternate version item retained 120000 ms. Jellyfin stores resume on the selected MediaSource item, and the version list ordering can change after playback. Both paused-start and playing 60s → 120s → pause → stop retain 120000 ms when read from that selected item. The live test now checks that identity (including a 60000 ms progress readback), independent of version ordering; no playback reporter change or media/threshold adjustment was needed. Original failure and corrected readback evidence are retained under artifacts/upstream-round5/I1/. Host/JVM/headless checks do not establish headset rendering, controller ergonomics, runtime permissions or smoothness.


Round 5 Quest Debug package, built after J1/J2 at `9ae2a8a` (subsequent I3 changes are documentation only):

| APK under artifacts/upstream-round5/APK | Bytes | SHA-256 | Change vs H2 Quest | Inspection |
| --- | --- | --- | --- | --- |
| `Round5-Immivio-QUEST-0.9.4-debug-20261104.apk` | 170230734 | `7ec701473d7838ef921f906cc6e896e2bb44aa0ffdf69126945ab903ca4901cf` | +24475 bytes (+23.90 KiB, +0.01438%) | Shared final-manifest gate, ELF/ZIP alignment and existing-key signature verification passed; new secondary JNI export present. Signing-material hashes unchanged. |

### Headset acceptance still required

Use the matching current Debug or release-candidate package and a separate synthetic test library. Record headset/runtime, APK SHA-256, settings state and concrete results; do not publish credentials or personal media.

1. **Official palm menu gesture.** With controls hidden, use the left official palm gesture under each Left/Right/Both pinch preference. Expect exactly one open/close per deliberate gesture, regardless of pinch preference. A held gesture must not repeat; the right system-reserved gesture must not be relied on to open the app menu.
2. **Primary pinch and migration.** On a fresh installation change an unrelated setting, restart, and confirm Right remains selected. Upgrade a legacy settings profile without the key and confirm Both plus retained ordinary preferences. Test Left, Right and Both on single-hand photo swipes/taps and video control summoning; either hand must still select an already-open menu. The secondary hand may assist an active photo zoom. Changing preference during a pinch must cancel ownership and require release before reuse.
3. **Grip-stick immersive adjustments and mutual exclusion.** Play synthetic VR180, VR360 and fisheye clips. Centre the sticks before holding grip; test left X/Y translation, right zoom and horizontal alignment to ±10%. Confirm numeric/range feedback, centre guide fade and per-file reopen memory. Open a list/popup or capture a slider while deflecting a stick: only scrolling/UI interaction may occur, with no seek or picture adjustment. After leaving it, input must remain suppressed until centre. Verify flat video/photos retain their previous controls and ranges; recenter clears immersive offsets while preserving stereo calibration.
4. **Open the release page on the headset.** Click About → Check for updates explicitly, verify checking/current/new-version/error states, then open the offered GitHub release page. Expect the system browser and a usable return to Immivio; without a handler, expect the localized browser-opening error and manual retry. Startup, backgrounding and redraw must not initiate update requests. Do not install an APK as part of this check.
5. **External opening from a real file manager.** Share/open one synthetic readable content/file video with the required temporary read grant, then SEND. Expect playback, release of temporary resources after close, no new permanent grant/history identity, and one normal Godot engine on two successive deliveries. Confirm BROWSABLE and binary HTTP associations remain excluded and app-private file paths are rejected. Distinguish a provider grant denial from player decoding failure.
6. **Real Emby server.** No separate Emby test server is created in rounds 5 or 6; the owner must use their own server. Use an owned test account with nested/plugin folders and two direct-play versions. Confirm folder visibility, separate version resume/mode/track preferences, exact resumed-version selection and correct MediaSourceId in start/progress/stop reports. Known limitation: detail().position_ms reads the grouped item, and explicit version rows use only local per-version resume. Jellyfin retains selected-version progress on its own item, so progress from a non-default version watched in another client is not imported here; the default action can use older grouped-item progress. Emby's corresponding model is still unverified. Add a cross-client check: watch a non-default version in another client, then return to Immivio, open both the default action and that explicit version row, and record the server's grouped/selected-item progress versus Immivio's prior local version position. Verify and record the current behavior; cross-client version-resume import is not promised. Disable history and verify no newly dispatched reports or backfill when re-enabled. Server failures must not interrupt local playback; record requests without retaining account tokens.
7. **GBK/Big5 subtitle playback.** Use known synthetic Chinese lines with timed cues in GBK/GB18030 and Big5 beside local/SMB video. Verify native subtitle text, cue timing, Auto detection and manual override after reopen. An invalid override must show the hint while retaining the original track. Confirm source-file hashes are unchanged. Repeat a document-provider selection where readable sibling access is unavailable.
8. **PICO 72 Hz with 60 fps video.** Select 72 Hz if advertised, play a known synthetic 60 fps clip, and record buffering, presented-frame/drop counters and perceived cadence over a sustained interval. Compare another advertised rate if available and repeat after pause/resume. Expect the requested supported rate/fallback to reapply and playback to remain stable; 72/60 is not an integer cadence, so do not assume zero judder. Owner acceptance of smoothness and power/thermal behavior is still pending.
9. **Dual text subtitles.** Play a synthetic video with an embedded English text track and import an external Chinese SRT (the import still selects primary). Enable Dual subtitles, choose Primary/Secondary targets, and form the embedded-plus-external pair. Expect primary above secondary, per-track encoding choices and one shared delay. Use very different line lengths and wrapped multiline cues; neither block should clip on flat or immersive 180/360/fisheye projections. Change primary to the selected secondary: expect secondary Off. Turn primary Off and back on with distinct tracks: both hide while off, then the retained second track resumes. Pause, seek forward/backward and reopen the file; expect synchronized current cues without stale text and restoration of the distinct choices when history/file memory is enabled. Repeat with history off and verify no new secondary preference is saved.
10. **Captions below the screen.** On synthetic 2D, SBS/TB and flat spatial video, enable the last subtitle-style control at 5% and 3000% screen sizes and near/far distances; rotate the screen through both directions, then enable reclining mode and place it at −60°, +60° and +85° pitch. Expect captions to stay in the screen plane with the small normal offset while remaining below its bottom edge, rather than moving toward the viewer. Expect readable primary/secondary captions entirely below the actual lowest screen edge with a small gap; physical readability at the extreme combinations needs owner judgment. The vertical-position slider is disabled but retains its value, and turning below-screen off restores that placement. Switch to an immersive projection: the toggle is disabled with the flat-only hint and the ordinary projected caption path remains active. Return to flat, open file B and return to A: B defaults off and A restores its own choice; photos have no such layout change.



## Selected upstream ports on PICO 4 — 2026-10-24

A physical PICO 4 (A8110), PICO OS 5.13.7 / Android 10, passed automated checks through the normal OpenXR launcher with live head tracking and two views. Test media was synthetic; captured UI layers and binocular compositor screenshots were reviewed. Ray events were generated in software through production pointer methods, not by physically pressing controllers.

| Area | Result |
| --- | --- |
| STRM | Local relative paths, authenticated-connection routing through a synthetic SMB2 guest share, and HTTP redirects all reached current-session native presented frames |
| Loading/errors | A delayed HTTP source showed elapsed waiting feedback and recovered to playback; empty STRM displayed the localized error and Info panel |
| Directory memory | Android directory enumeration, list/icon position retention, persistent write and restoration after process restart passed |
| Concurrent browsing | Compact/full library and playback controls remained captured, visible and ray-selectable together |
| Spatial controls | Lock, independent screen movement, hide/reopen, unlock and opacity adjustment passed |
| Cinema layout | Ray-selected 150-inch preset, aspect-preserving size, logarithmic distance input, fixed defaults and recenter restoration passed |

Device validation found and fixed missing secondary-menu capture/ray mapping, dropped cinema choice dispatch and missing logarithmic pointer metadata. Terminal debug failures now bypass telemetry throttling so a stopped source cannot leave an obsolete opening report.

The complete feature suite used APK SHA-256 `a35745cb3ce8f4c6390e6fca992c5035f6dee6b0a834ef0de14d3796be6be036`. The subsequently installed package changes Android application classification to video; its exact hash is in ignored `artifacts/device-acceptance-20261024/result.json`. Final APK inspection confirms `appCategory=2` and `isGame=false`. PICO classifies this sideloaded immersive SDK package under Library → Unknown sources, rather than the ordinary 2D Apps category; the entry is present. A concrete `MAIN`/`LAUNCHER` Activity forwards to the normal OpenXR alias with clear-top/single-top flags. Cold launch, repeat launch with the same PID, and native playback passed on the final installed build. After cleanup, the delivered app reported a focused XR session with live tracking and two views. Resource-pane automatic foreground handoff through simulated clicks is not certified; physical controller actuation was not performed. Tracking/boundary protection was not disabled.

The legacy standard package failed PICO entitlement checks even when its original APK was restored; both original and replacement signatures used certificate SHA-256 `c231d4cb72806711c9e946757580f9bf469ea969ef88ec70008a602b8025cfa6`. Independent Immivio identities entered XR successfully. The standard legacy installation and temporary Dev installation were removed at the owner's request. Preferences were backed up and copied to the independent application. Synthetic device media, temporary SMB account and ADB reverse mappings were removed. Other independently installed applications were not removed.

Raw request-matched receipts, current-session playback reports, settings backup and screenshots remain under ignored `artifacts/device-acceptance-20261024/`. Headset lens comfort, real controller actuation, other vendors and sustained thermal behavior are outside this automated result.


R2–R5 code migration has reached local acceptance. The owner subsequently authorized the deferred checks and narrowed the completion criterion to producing installable packages on this machine; other platforms are delegated to CI. Earlier compile-only results remain historical evidence.

Host tools are no longer pinned to exact versions. Required language/library features, Godot editor/template matching, Android application targets and native library integrity remain enforced.

## UI iteration regression results — 2026-10-13

The owner authorized completing the checks skipped during live PICO UI iteration and submitting the complete source changes. The final local test run uses `Pico` / `Release`; other build hosts and headset vendors remain CI/device follow-up.

| Check | Result |
| --- | --- |
| Godot host regressions | 75/75 passed |
| JVM tests | 234 passed; 11 optional credential-dependent cases skipped |
| Go `cloudcore` tests | Passed |
| Python workflow tests | 31 passed |
| Release selection/publication tests | 13 passed |
| Website tests | 4 passed; bilingual page, JavaScript and metadata checks passed |
| Source/environment | Public-source boundary, command manifest, source-root verification and installed tool compatibility passed |
| Visual QA | Synthetic English/Chinese toolbar, title/status header and popup renders inspected |

The regressions retain source, storage, decoder, stereo, subtitle, pointer-capture and stick-latching coverage. Obsolete volume, bookmark-addition, precision-selector and full-settings-page expectations now verify retirement or their replacement behavior. Tests cover queue EOF after acknowledged drawing, return to files, fixed-distance Home reset and duplicate notification coalescing. The speed-reset visibility bug found during validation was corrected and its real slider interaction checked.

JUnit, build/package receipts, synthetic renders and physical PICO installation records are retained under ignored `artifacts/`. Host tests and synthetic images do not establish physical controller accuracy, source-service availability or sustained headset performance. Historical checks below belong to the earlier refactor checkpoint.

## Local acceptance results — 2026-10-13

| Check | Result |
| --- | --- |
| Python workflow tests | 31 passed, including host-component selection and stale-build checks |
| Release selection/publication tests | 13 passed |
| Website tests | 4 passed; all six bilingual pages checked |
| JVM tests | 234 passed; 11 credential-dependent optional cases skipped |
| Godot host tests | All 75 passed |
| Go `cloudcore` tests | Passed |
| Android builds/packages | Quest, Pico, OpenXR × Debug and Release: all six passed local packaging/verification |
| Package integrity | APK hashes match receipts; ARM64 ELF, JNI/dependency checks, 16KB, ZIP alignment, signatures and application identity checked |
| Source checks | Public-source boundary, command manifest and workflow syntax passed |

Three initially failing Godot cases still referenced retired `warped`/inference behavior or lacked a version-2 EOF descriptor. Their fixtures were migrated to supported packed stereo and versioned source-frame completion. Focused reruns and the complete Godot suite passed afterward.

The final packages, build receipts and `SHA256SUMS.txt` live under ignored `artifacts/`. Source remains in Git; binaries and signing material do not.

Windows/cross-platform execution is delegated to CI per the owner's updated scope. Real-headset, sustained-thermal/performance, credentialed live-source checks are not certified by this local result. There are only Android emulators attached; no physical headset was tested. Previous compile-only evidence and R1 package results do not stand in for those checks.

## CI and device follow-up

1. Configure the prepared host environment; prepare the verified OpenXR addon archive and ordinary package caches if needed. Use the current commands in [BUILD.md](../BUILD.md).
2. Run `tests/workflow`, release selection/publication tests and website checks. Verify production-source changes reject stale build receipts.
3. Run the JVM/Go tests and all Godot tests. Updated gate, frame-descriptor and source-mask fixtures must pass. Verify weak owner references, controller field adapters, stale callbacks, source cancellation and lifecycle persistence.
4. Build and package each Quest, Pico and OpenXR target on the required hosts. Check JNI exports, dependency closure, ELF/ZIP alignment, signature, identity and absence of inference artifacts.
5. On actual headsets, record the installed APK hash, device/runtime/build versions and legal fixture hashes. Keep private media and logs outside Git.

## Required device cases

| Area | Cases and evidence |
| --- | --- |
| Color/mask transport | Copy and borrowed paths; cached mask reuse; ring backpressure; reject incomplete/mismatched version-2 descriptors |
| Ownership | Last draw → detach → consumer fence → producer release; pinned thumbnail/pixel readback; reopen and context loss without deleting old names in a new context |
| Timeline | Pause/redraw, exact/keyframe seek, frozen seek transition, EOF after final acknowledged draw, repeat/restart, playback-clock corrections |
| UI/input | Ray/trigger and hand controls, list scrolling, slider capture and stick recenter, recenter/reclining/follow, video↔library transitions |
| IO | Permission denial/revocation, storage eject, source/account removal, late resolution after close, subtitle import, partial failures and descriptor/network-lease cleanup |
| Persistence | Audio/mute, subtitle/track choices, queues, bookmarks and native stereo locks; retired settings remain unavailable |
| Sustained operation | Memory/handle growth, thermal state, decoded/presented/XR cadence measured separately; no claim from emulator images or engine FPS alone |

The old inference-mode/motion/Alpha-owner verification matrices have been retired. Remaining seek, storage, URI, audio and native format probes are supporting tools; inspect their fixture/receipt requirements before running them. Port any old diagnostic payload assumptions to [FRAME_CONTRACT.md](../FRAME_CONTRACT.md). A device probe result only establishes its explicitly recorded scope.

## Cleanup follow-up (2026-11-12)

- On Chinese, Traditional Chinese and Japanese interfaces, browse the library,
  settings and playback menus after translation cleanup to check for unintended
  English text.
- Confirm normal and packed-alpha playback after removal of unused calibration
  images, including the retained independent-alpha diagnostic video.
- Confirm the remaining Python selected-feature/playback/seek/startup device
  probes can enter through the retained debug receiver after legacy local-access
  facilities are removed. Run `tools/run_external_uri_probe.py` on the target
  headset for external URI grants, revocation and process restart; the rebuilt
  driver has host/build verification only until device evidence is recorded.

- After retiring the three Debug A/B controls, confirm ordinary/packed-alpha
  playback, pause, seek, repeat/EOF and close on the headset using the fixed
  production capture/borrow path; compare cadence and retained-frame cleanup.

- After merging MPV media state, verify open/close/reopen, seek/revision changes,
  decoder/status reporting and failure recovery; diagnostic snapshots should
  expose presentation revision and omit the retired codec/SurfaceTexture fields.

- After enabling translation provenance checks, browse all three translated
  locales for unintended English; specifically verify Refresh, Done, Add server
  and Internal storage, whose directly translated labels now have catalog entries.

- Run the shared Python core/GPU/audio and player probes on each supported
  headset after rebuilding the current Debug APK. Confirm request-key/process
  correlation and timeout evidence; host fake-ADB tests do not verify Android
  permission delivery, decoding, audible output or XR presentation.

- Manual local-access acceptance: readable/missing files, denied or revoked
  storage access and ejection must produce the correct player outcome without
  stale readers; this probe category has not been rebuilt.
- Manual document-picker acceptance: selection, cancellation, unusual file names
  and returned URI grants must work through the real system picker; no picker
  automation is claimed.
- Manual seek-image acceptance: confirm the frozen transition image, pause/redraw,
  rapid seek changes and final-frame retention on the headset; no device pixel
  comparison driver has been rebuilt.

- After removing the unused non-cached capture JNI entry, verify ordinary and
  packed-alpha playback, pause/seek transitions and frozen-frame retention on the
  headset. Confirm opaque-mask cache reuse and borrowed producer lease cleanup;
  host compilation and symbol checks do not establish device rendering behavior.
