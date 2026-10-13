# Deferred refactor acceptance

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

Windows/cross-platform execution is delegated to CI per the owner's updated scope. Real-headset, sustained-thermal/performance, private-backend and credentialed live-source checks are not certified by this local result. There are only Android emulators attached; no physical headset was tested. Previous compile-only evidence and R1 package results do not stand in for those checks.

## CI and device follow-up

1. Configure the prepared host environment; initialize enabled FreeCM inputs and prepare ordinary package caches if needed. Use the current commands in [BUILD.md](BUILD.md).
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
