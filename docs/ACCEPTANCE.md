# Device and build acceptance

## Unreleased (`52f2fb5..HEAD`) — pending device acceptance

No headset was available for this round. The checks below cover the unshipped selected ports and review corrections; historical device results later in this document do not certify this source. Raw logs, APK inspection output, size reports and synthetic-server evidence remain under ignored `artifacts/upstream-round4/`; emulator evidence is under `artifacts/emulator-acceptance-2026-11-04/`.

### Offline and local integration results — 2026-11-04

| Check | Actual result and boundary |
| --- | --- |
| H2 Debug packaging | Quest, Pico and OpenXR each completed configure → build → package using existing tools/dependencies and the existing signing identity. Final APK inspection passed the shared manifest gate, ELF checks, alignment and signature verification. No key was created or changed. APK source revision at this step was `d9f3f6e`; subsequent changes in this round add tests or documentation, not runtime behavior. |
| H2 size baseline | Built the same three Debug targets from local tag `v0.9.4` (commit `63584ef`) in a detached worktree. Used Analyze-ApkSize.py on each pair; growth is about 246 KB per target, mainly DEX (application changes plus ICU detector classes), ICU notices and new scripts. DEX costs cannot be attributed to ICU alone. |
| H3 upgrade migration | In AVD Thru3D_Perf_API36, baseline and current signed Debug packages used the same existing key. Seeded legacy history=false, then changed sharpness to 0.4 through the existing Debug settings route. After adb install -r and 2D diagnostic restart, both values remained and controls/pinch_hand was both. |
| H3 clean install | Cleared only this app's isolated test-emulator data, launched current 2D diagnostics, changed another setting through the existing Debug route, and restarted. controls/pinch_hand remained right_hand. This is Android persistence validation, not physical hand interaction. |
| H3 external intents | HTTP video and file video matched the ingress and forwarded to the normal launcher. HTTP application/octet-stream and BROWSABLE intents did not resolve to this app. The private-file case reached only the rejecting ingress, without forwarding; no independent rejection receipt was available. The shell could not grant the external-storage document URI (SecurityException), and SEND matched ingress without proving readable provider access. |
| H3 external playback/reuse | Not certified: the normal VR launcher on the emulator crashed in OvrContextFactory/EGL context creation. Repeated launches therefore did not provide a stable Godot session for instance-reuse or playback acceptance. No product code was changed for the emulator. The 2D diagnostic route itself ran successfully. |
| H3 browser | Chrome resolved and ACTION_VIEW launched its first-run Activity with emulator networking disabled. Actual release-page loading/browser return behavior remains unverified. No extra remote page download was performed. |
| H4 GitHub schema | One unauthenticated curl with User-Agent Immivio-dev returned HTTP 200, tag v0.9.4 and the exact matching repository release URL. Minimized real-response fixture passes latest/same-version and available/newer-tag JVM checks. No automatic check, APK download or install was added. |
| H5 Jellyfin | Official jellyfin/jellyfin:latest, server 12.4.0, synthetic two-version movie and nested folder. Production JVM clients retained folder containers, listed two versions, selected the requested PlaybackInfo source and read an authenticated range. Playing/Progress/Stopped all returned success; server resume was 120000 ms. History-off sent zero additional reports and did not change server progress. |
| H5 isolation and cleanup | Docker internal-network port publishing was unavailable, so a loopback-only test bridge forwarded to container localhost via Docker exec. The container had no external egress. Removed the owned container/network, bridge, server data, temporary credentials and synthetic media. The official image remains cached. No Emby server was exercised. |

Current-source APKs from H2 (version numbers are unchanged):

| Platform | APK under artifacts/upstream-round4/H2 | Bytes | SHA-256 | Growth vs same-platform v0.9.4 |
| --- | --- | --- | --- | --- |
| Quest | `HEAD-Immivio-QUEST-0.9.4-debug-20261104.apk` | 170206259 | `69f0c727b467e7a1e0ad413a6d7b551519ef0388b6cc1f3155fbee302335e9f4` | +246339 bytes |
| Pico | `HEAD-Immivio-PICO-0.9.4-debug-20261104.apk` | 170403011 | `48c320734e004c594cd74379ec5d5562993ea484a8ba360b3140f67ec2a79740` | +246343 bytes |
| OpenXR | `HEAD-Immivio-OpenXR-0.9.4-debug-20261104.apk` | 170402779 | `8320d63fb520119ea794c728d38f4670a081a6b8656e56c9316cc902248a5ec2` | +246359 bytes |

Round 5 reproduced the apparent paused-resume failure on Jellyfin 12.4.0: the grouped movie returned 0 ms while the selected alternate version item retained 120000 ms. Jellyfin stores resume on the selected MediaSource item, and the version list ordering can change after playback. Both paused-start and playing 60s → 120s → pause → stop retain 120000 ms when read from that selected item. The live test now checks that identity (including a 60000 ms progress readback), independent of version ordering; no playback reporter change or media/threshold adjustment was needed. Original failure and corrected readback evidence are retained under artifacts/upstream-round5/I1/. Host/JVM/headless checks do not establish headset rendering, controller ergonomics, runtime permissions or smoothness.

### Headset acceptance still required

Use the matching current Debug or release-candidate package and a separate synthetic test library. Record headset/runtime, APK SHA-256, settings state and concrete results; do not publish credentials or personal media.

1. **Official palm menu gesture.** With controls hidden, use the left official palm gesture under each Left/Right/Both pinch preference. Expect exactly one open/close per deliberate gesture, regardless of pinch preference. A held gesture must not repeat; the right system-reserved gesture must not be relied on to open the app menu.
2. **Primary pinch and migration.** On a fresh installation change an unrelated setting, restart, and confirm Right remains selected. Upgrade a legacy settings profile without the key and confirm Both plus retained ordinary preferences. Test Left, Right and Both on single-hand photo swipes/taps and video control summoning; either hand must still select an already-open menu. The secondary hand may assist an active photo zoom. Changing preference during a pinch must cancel ownership and require release before reuse.
3. **Grip-stick immersive adjustments and mutual exclusion.** Play synthetic VR180, VR360 and fisheye clips. Centre the sticks before holding grip; test left X/Y translation, right zoom and horizontal alignment to ±10%. Confirm numeric/range feedback, centre guide fade and per-file reopen memory. Open a list/popup or capture a slider while deflecting a stick: only scrolling/UI interaction may occur, with no seek or picture adjustment. After leaving it, input must remain suppressed until centre. Verify flat video/photos retain their previous controls and ranges; recenter clears immersive offsets while preserving stereo calibration.
4. **Open the release page on the headset.** Click About → Check for updates explicitly, verify checking/current/new-version/error states, then open the offered GitHub release page. Expect the system browser and a usable return to Immivio; without a handler, expect the localized browser-opening error and manual retry. Startup, backgrounding and redraw must not initiate update requests. Do not install an APK as part of this check.
5. **External opening from a real file manager.** Share/open one synthetic readable content/file video with the required temporary read grant, then SEND. Expect playback, release of temporary resources after close, no new permanent grant/history identity, and one normal Godot engine on two successive deliveries. Confirm BROWSABLE and binary HTTP associations remain excluded and app-private file paths are rejected. Distinguish a provider grant denial from player decoding failure.
6. **Real Emby server.** Use an owned test account with nested/plugin folders and two direct-play versions. Confirm folder visibility, separate version resume/mode/track preferences, exact resumed-version selection and correct MediaSourceId in start/progress/stop reports. Disable history and verify no newly dispatched reports or backfill when re-enabled. Server failures must not interrupt local playback; record requests without retaining account tokens.
7. **GBK/Big5 subtitle playback.** Use known synthetic Chinese lines with timed cues in GBK/GB18030 and Big5 beside local/SMB video. Verify native subtitle text, cue timing, Auto detection and manual override after reopen. An invalid override must show the hint while retaining the original track. Confirm source-file hashes are unchanged. Repeat a document-provider selection where readable sibling access is unavailable.
8. **PICO 72 Hz with 60 fps video.** Select 72 Hz if advertised, play a known synthetic 60 fps clip, and record buffering, presented-frame/drop counters and perceived cadence over a sustained interval. Compare another advertised rate if available and repeat after pause/resume. Expect the requested supported rate/fallback to reapply and playback to remain stable; 72/60 is not an integer cadence, so do not assume zero judder. Owner acceptance of smoothness and power/thermal behavior is still pending.


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

The regressions retain source, storage, decoder, stereo, photo, subtitle, pointer-capture and stick-latching coverage. Obsolete volume, bookmark-addition, precision-selector and full-settings-page expectations now verify retirement or their replacement behavior. Tests cover queue EOF after acknowledged drawing, return to files, fixed-distance Home reset and duplicate notification coalescing. The speed-reset visibility bug found during validation was corrected and its real slider interaction checked.

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

The final packages, build receipts and `SHA256SUMS.txt` live under ignored `artifacts/`; a consolidated package record is `artifacts/refactor-acceptance/packages.json`. Source remains in Git; binaries and signing material do not.

Windows/cross-platform execution is delegated to CI per the owner's updated scope. Real-headset, sustained-thermal/performance, credentialed live-source checks are not certified by this local result. There are only Android emulators attached; no physical headset was tested. Previous compile-only evidence and R1 package results do not stand in for those checks.

## CI and device follow-up

1. Configure the prepared host environment; prepare the verified OpenXR addon archive and ordinary package caches if needed. Use the current commands in [BUILD.md](BUILD.md).
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
| UI/input | Ray/trigger and hand controls, list scrolling, slider capture and stick recenter, recenter/reclining/follow, video↔photo↔library transitions |
| IO | Permission denial/revocation, storage eject, source/account removal, late resolution after close, subtitle import, partial failures and descriptor/network-lease cleanup |
| Persistence | Audio/mute, subtitle/track choices, queues, bookmarks, gallery layout and native stereo locks; retired settings remain unavailable |
| Sustained operation | Memory/handle growth, thermal state, decoded/presented/XR cadence measured separately; no claim from emulator images or engine FPS alone |

The old inference-mode/motion/Alpha-owner verification matrices have been retired. Remaining seek, storage, URI, audio and native format probes are supporting tools; inspect their fixture/receipt requirements before running them. Port any old diagnostic payload assumptions to [FRAME_CONTRACT.md](FRAME_CONTRACT.md). A device probe result only establishes its explicitly recorded scope.
