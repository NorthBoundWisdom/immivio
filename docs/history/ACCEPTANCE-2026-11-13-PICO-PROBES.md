# PICO probe validation — 2026-11-13

This is partial automated device evidence for A01/A02/A09/A12 and D1.
The automated results below do not certify other headsets,
physical controller actuation, wearer comfort, all projections/locales, audible
output, long-running performance or context-loss cleanup.

## Device and package

PICO 4 (A8110), Android 10/API 29, firmware 5.13.7, Pico OpenXR runtime 3.0.1.
The owner confirmed wearing/unlocking the headset. The setup report recorded
`session_focussed`, two views and live head tracking; advertised rates were
72 and 90 Hz. Installed 0.9.11/versionCode 25, Debug/appstore, normal application
ID, preserving app data. Source was bff8772 plus the fixes described below.
Final APK SHA-256:
`021ec9478d2d4d7a478dcfee2fc59508cabe52491b15265a2a6b33dabff38ab3`.

The previous session backed up settings under the ignored
`artifacts/captures/device/pico-validation-20261113/preflight/` directory.
The successful setup probe redirected subsequent settings/history to
`user://acceptance/`; no app data was cleared. Restarting the player reloads
its ordinary settings. Test media were project-owned bundled fixtures; their
SHA-256 values are in `pico-validation-20261113/retest/evidence-manifest.json`.
All evidence paths below are relative to `artifacts/captures/device/`.

## Results

| Case | Result and scope | Evidence directory |
| --- | --- | --- |
| D1 core | Passed native C03 software checks, exact installed APK and request/process matching | `core/20261113T142154Z-222d38ad/` |
| D1 GPU | Passed native C03 hardware/GLES checks | `gpu/20261113T142155Z-49c79092/` |
| D1 audio | Passed native MP06 clock/focus checks; speaker audibility remains unverified | `audio/20261113T142202Z-110c41af/` |
| A01/A12 alpha | Passed native GPU checks for C04 fisheye packed alpha and independent alpha; lens appearance remains unverified | `gpu/20261113T142513Z-9163771d/`, `gpu/20261113T142519Z-eaffd5ed/` |
| A02/D1 setup | Passed live OpenXR head tracking; isolated test preferences | `selected-features/20261113T142257Z-28413e7f/` |
| A02/D1 menus | Eleven checks passed: curved distance, held ray trigger, language dropdown open/select/one commit, credits scrolling/navigation retention and quality options. Chinese stereo headset capture inspected. No three-locale completeness claim | `selected-features/20261113T142300Z-84e21428/` |
| A01/A09/D1 player | MP03 open → pause → exact seek to 1500 ms → resume → close → reopen with SBS/VR180 request → close passed. Seek completed with generation change; close reported state closed/session zero. Reopen used a new session. Post-draw frames observed. Samples reported 71–72 engine fps | `playback-smoke/20261113T142442Z-66f9bbdd/` |
| D2 external URI | Blocked: PICO ProcessIntercept refused cold-starting the separate fixture process by broadcast. Restore receipt timed out, cleanup attempted and fixture uninstalled. No grant/decode/revocation pass claimed | `external-uri/20261113T141853Z-0728edb1/`, `pico-validation-20261113/retest/uri-system-intercept.txt` |

Closing/session-zero reports alone do not prove all GL resources were retired.
The 71–72 fps samples are short player observations. The menu capture includes
a PICO system/performance overlay reporting a lower instantaneous fps; sustained
cadence, thermal behavior and comfort remain A11 acceptance.

## Problems exposed and corrected

- System Profiler returned an empty USB tree even while IORegistry identified
  the PICO. Multiple ADB servers competed for its interface. Recovery used a
  dedicated libusb server on port 5042 and reconnect. See the discovery section
  in TESTING.md; the port/serial must be rediscovered each session.
- Native diagnostics expected `assets/media/*.mp4`, but Godot exports exclude
  media. Five small project-owned clips are now Android Debug-only assets.
  The rebuilt APK was inspected for all five files before installation.
- The external URI CLI parsed `--port` without forwarding it to Device. It now
  uses the requested port; a CLI regression test covers this path.
- Two main-scene UI probes still called the removed `_write_debug_report`
  wrapper. They now call the owned diagnostics module with a null guard.
  The original menu timeout remains in the earlier evidence directory;
  the corrected package passed setup and menu steps.

Host validation: 29 Python probe tests passed; the Godot selected-upstream
feature suite reported zero failures. PICO Configure/Build/Package passed.
No release was published and no account/server settings were changed.


## Owner confirmation after the automated session

On 2026-11-13, after disconnecting the device, the owner confirmed that manual
acceptance was also complete and authorized committing and pushing all changes.
A01–A12 are therefore recorded as accepted by the owner for this PICO session.
No additional per-case measurements, media inventory or cross-headset results
were supplied. The earlier automated limits above remain part of the evidence;
in particular, D2's separate-UID driver was blocked and was not rerun or passed.
The disposable root checklist was removed after the owner's confirmation.
