# Deferred refactor acceptance

R2–R5 code migration is complete; runtime acceptance is **pending**. The owner requested compilation and light static checks only, with no test matrix or APK packaging tests during this refactor. Automatic CI is skipped on the refactor checkpoint. No new device-performance or playback-quality claim is made.

## Compile evidence

- Android NDK syntax compilation of the split render bridge.
- Android Debug production Kotlin and JVM test-source compilation, using one Gradle worker.
- Compilation of changed Godot scripts and fixtures without instantiating/running the tests.
- Static source boundary, JNI declaration/export-name parity, workflow syntax and website link checks.

These checks do not validate GL synchronization, user-data migrations, headset interaction or package delivery. The successful R1 tests/APK are a **historical baseline**, not evidence for the new frame contract or controller split.

## Central acceptance sequence

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
