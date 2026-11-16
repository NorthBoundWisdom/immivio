# Player validation evidence — 2026-11-16

This dated record covers the selective Thru3D 0.17.12 ports (`959abc2`) and the
reviewed performance implementation. It records host, desktop GPU, Android
emulator and package checks. No physical headset was installed or tested in
this round; the earlier PICO manual acceptance does not certify these changes.

Implementation and provenance are maintained in [Upstream ports](../SELECTED_UPSTREAM_PORTS.md)
and [Runtime source build](../../third_party/mpv/SOURCE_BUILD.md). Reproduction
commands are in [Testing](../TESTING.md#selective-017-playback-checks); current
physical checks remain in [Device acceptance](../ACCEPTANCE.md).

## Completed checks

| Check | Result |
| --- | --- |
| Godot host behavior | 105 scripts passed |
| Android JVM | 236 tests, no failures/errors; 11 existing environment-dependent skips |
| Native host | 5 passed |
| Workflow | 130 passed |
| Release tooling | 18 passed |
| Source checks | Ruff, GDScript/Kotlin format, public-source boundary, resource references, translations and whitespace passed |
| Packages | Quest, PICO and generic OpenXR Debug builds/exports passed inspection; all eight mpv/FFmpeg libraries matched the source-build receipt |

Desktop GPU checks covered caption fill/outline opacity, spherical and full/half
fisheye SBS/TB focus sampling, backdrop equivalence, transparent video holes,
foreground occlusion and release of hidden backdrop texture references.

The native Android GLES probe covered encoded-color copies (per-channel error
at most 2), vertical flips, stereo fisheye regions, GL state restoration,
nonblocking swapchain waits/retries, route ownership, PBO cancellation and
rollback after partial Surface/reference creation failures.

Only the disposable fixture was installed on `emulator-5554`. Normal and
injected MediaCodec hint-rejection cases delivered real Surface buffers while
paused, completed six seek/pause/speed cycles and acknowledged decoder shutdown.
The final runs observed 25 and 27 buffer callbacks respectively; the rejection
case logged exactly one retry without hints. These callback totals are fixture
observations, not FPS measurements. The public libmpv fixture also passed muted
AAudio, seek/pause/speed and HDR-control checks. The fixture and remote temporary
files were removed, and adbd was restored to non-root mode.

Regression coverage includes deferred route switches retaining independent
settings snapshots, original file identity, forced alpha, stereo corrections,
subtitle timing, exact position and pause intent; stale requests cannot reopen a
new movie. Refresh-cap reapplication, XR pause versus session loss, Surface
failure cleanup and SMB deadline/cleanup ownership are covered too.

## Limits and physical acceptance

The emulator's B-frame H.264 direct-Surface startup stalled with both the original
official FFmpeg libraries and the source-built runtime. The passing zero-B-frame
fixture does not establish compatibility with arbitrary hardware streams.

Quest/PICO/other OpenXR compositor orientation, eye order, HDR/color accuracy,
focus accuracy and comfort, caption-follow behavior, session/context recovery,
Adreno decoder-image fences and real SMB/NAS interoperability still require
physical verification. Use matched files, positions and refresh caps with the
`auto`, `picture` and `shader` benchmark routes. Buffer submissions do not prove
compositor presentation. No headset FPS, power, temperature or long-duration
memory improvement is claimed by these results.

## Local validation packages

These are ignored local artifacts, not published releases. Their hashes identify
the reviewed working-tree builds made before the documentation amendment.

Each package contains the new video-layer library and the eight verified playback libraries. Paths below are relative to the repository root.

- `QUEST`: `artifacts/packages/QUEST/appstore/debug/Immivio-QUEST-1.0.0-appstore-debug-20261116.apk`; SHA-256 `1f3df1c3601f3048cc842d98347813b89035291524adf7e7942eca5ec99ebb26`.
- `PICO`: `artifacts/packages/PICO/appstore/debug/Immivio-PICO-1.0.0-appstore-debug-20261116.apk`; SHA-256 `3a7458ad1e5dc881ab823f79e9733eefaa92568e6a761d1954d29b7a4a4e707d`.
- `OpenXR`: `artifacts/packages/OpenXR/appstore/debug/Immivio-OpenXR-1.0.0-appstore-debug-20261116.apk`; SHA-256 `5870afdfea4357be4e0ba286c7e6824f2c24456a6e65a3b66863551c505a15e2`.
