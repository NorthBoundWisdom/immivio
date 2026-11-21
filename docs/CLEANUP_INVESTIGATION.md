# Cleanup investigation (2026-11-12)

This records the historical B1–B4 cleanup investigation. Initial evidence
refers to `ad9f142`, before the follow-up removals, and remains reviewable with
`git show ad9f142:<path>`. Later sections record their own follow-up scope.
These investigations and their implementation follow-ups are complete; current
behavior is described in [ARCHITECTURE.md](ARCHITECTURE.md), and physical checks
are maintained in [ACCEPTANCE.md](ACCEPTANCE.md#current-device-acceptance).
No headset behavior was verified by this investigation.

## B1: debug fixture inventory

The player whitelist is in
`android/player-plugin/src/debug/java/org/vrpassthroughplayer/plugin/DebugDiagnosticsReceiver.kt:307–355`.
After removal of the device runners, the inventory was:

| Fixture | Remaining consumer | Manifest / preparation | Decision |
| --- | --- | --- | --- |
| `mp03_frame_identity` | Default player diagnostic open, selected-feature probe, audio fixture generator | `tests/fixtures/mp03_frame_identity.json`, `tools/media/generate_mp03_fixture.py` | Retain |
| `mp06_text_subtitles` | Manual player/subtitle diagnostics | `tests/fixtures/mp06_text_subtitles.json`, `tools/media/generate_mp06_subtitle_fixture.py` | Retain |
| `mp08_8k_high_30` | `benchmarks/mpv_seek_strategy_device.py:174`, `benchmarks/mpv_startup_device.py:174` | Private local MP4, no repository generator or manifest | Retain; document preparation |
| `mpv_performance` | `benchmarks/mpv_playback_device.py:245–273` uploads caller-supplied media | Supplied local source or network URI | Retain |
| `mp05_person_still` | None | None | Remove whitelist entry |
| `mp07_motion_4k` | None after runner removal | `tools/media/generate_mp07_motion_fixture.py:24` requires private `--source`; generated manifest not tracked | Remove entry and unused generator |
| `mp08_8k_low` | None | None | Remove entry |
| `mp08_8k_high` | None | None | Remove entry |
| `mp08_8k_long` | None | None | Remove entry |
| `mp08_4k` | None | None | Remove entry |
| `depth_2d` | None | None | Remove entry |

Reproduce with `git grep -n -E 'mp05_person_still|mp07_motion_4k|mp08_|depth_2d|mpv_performance'`.
The C03/C04 GPU/core fixtures are a separate whitelist in `MpvDiagnostics.kt:45`.
Their bundled videos remain in use. The subtitle manifest has an older output
path than its generator; this was reported without regenerating media.

## B2: debug-only switches

`QuestPlayerPlugin.kt:591–593` reads `normal_fast`, `frame_cap`, `borrow_color`.
The three bridge setters (`MpvVideoBridge.kt:48–65`) only mutate fields when
`BuildConfig.DEBUG` is true. No tool or benchmark sends these command keys.

| Switch | Effect | Production default |
| --- | --- | --- |
| `normal_fast` | Chooses opaque capture versus the older texture-capture branch; completes pending copies/uploads during the same draw (`:721`, `:739`, `:883`) | Fast opaque path |
| `frame_cap` | Overrides native frame cadence (`:124`, `:300`, `:356`) | Unlimited (`0`) |
| `borrow_color` | Enables borrowing the immutable producer texture instead of copying it (`:878`) | Borrowing enabled |

Deletion must preserve these defaults. Removing the controls loses the Debug A/B
comparison, but changes no Release path. The default follow-up is to remove them;
no active scripted performance investigation depends on them.

## B3: media state

`media_state.gd` has one subclass, `mpv_media_state.gd`. Its `apply_event()`
(`media_state.gd:42`) has no callers anywhere in the repository. Consequently
all five branches (`state`, `format`, `frame`, `codec`, `error`) are unused.
`revise_effect()` and `_valid_id()` also have no external callers.

Current production callbacks update state directly in `mpv_video_display.gd`:
pair binding sets identity, format and frame counter (`:1970–1984`), `_on_state`
sets playback/decoder/state (`:2021–2070`), and `_on_error` sets failure (`:2079–2090`).

- `surface_timestamp_ns`, `coalesced_notifications`, `codec_dropped_frames` and
  `transform` have no independent readers; the first three only leak zero-valued
  legacy fields into the base snapshot.
- The base `frame_pairing` string is replaced by the subclass string. No report
  auditor or test reads either field. Remove both snapshot markers.
- `effect_revision` still receives `claimed.presentation_revision` (`:1974`).
  Keep that information under its real name, `presentation_revision`.
- Session/generation IDs, format revision, frame count, format, playback, decoder,
  state and error remain used. Keep lifecycle and snapshot behavior for them.
- `test_playback_frame_contract.gd:51` uses the subclass and verifies frame
  identity provenance; it does not depend on legacy event branches or fields.

Follow-up: merge the retained state into `mpv_media_state.gd`, delete the base and
its UID, keep frame-contract assertions intact, and rerun the full Godot suite.

## B4: profile (historical investigation; implemented)

`session.dims` comes from the profile string (`MpvVideoBridge.kt:115`) and is
passed to renderer creation and completed frame contracts (`:869–870`, `:976–977`).
The native bridge allocates the numeric R8 mask at twice the per-eye width
(`native/render-bridge/src/render_bridge.hpp:151–154`). It does not select the
video decoder dimensions. It still affects buffer allocation and GPU work;
this investigation does not establish that changing it is visually equivalent.

Normal file restoration resets to `AUTOMATIC_PROFILE = "320x320"`
(`mpv_video_display.gd:510`), rather than restoring the stored profile. There is
no ordinary UI profile control; Debug open/profile commands can change it
(`:2165`, `:2205`). A per-file profile is still written (`:2422`), and
`file_mode_memory.gd:51` requires it when validating a saved mode.

The per-file value is redundant for ordinary restoration. Removing it requires a
versioned migration so existing geometry/stereo preferences are not rejected.
The owner chose fixed dimensions and removal of the saved field on 2026-11-13.
That decision was implemented in `28f656d`: the opaque mask is fixed at 320×320,
schema 3 migrates schema-1/2 records without requiring `profile`, and the runtime
and Debug profile parameters are removed. Geometry, stereo, subtitle, track,
encoding and timing preferences are retained. The description above records
the investigative baseline, rather than the current implementation.

## Review follow-up evidence

R2: `prepareDependencyCache` resolves every non-AndroidTest configuration
(`android/gradle/dependency-cache.gradle`). `debugCompileClasspath` requests
`core-common:2.1.0` through `core-runtime:2.1.0` / `lifecycle-livedata:2.6.1`, and
`annotation:1.1.0` through AndroidX dependencies including `activity:1.8.1`.
Dependency insight shows locks selecting `core-common:2.2.0` and
`annotation:1.2.0`. The two extra POM records were regeneration side effects,
not new locked/runtime dependencies. They were reverted; offline assemble and
JVM tests pass with the existing prepared cache. This does not claim an empty
cache can perform an offline build.

R6: search all 18 public names introduced by `ad9f142` for local `var`, `for` and
function-parameter declarations in main and every test file referencing main
(41 files). Main has only the expected member declarations. The five test-local
hits (`viewer` / `eye`) belong to outer SceneTree test scopes, not the classes
inheriting main. The main subclasses override only the seven retained input
hooks. No member-shadowing declaration was found; no local renames are needed.

T3: `app/godot/tests/test_render_scripts_load.gd` already enumerates every
`render_*.gd`, calls `load`, `reload`, `can_instantiate`, and checks construction.
Its normal host run checks 33 scripts without running their GPU rendering loop.
It is included in the existing Godot suite. No duplicate loader was added.

## T2: catalog provenance findings

The new check found four direct I18n calls without translations: `Refresh`
(`media_server_browser.gd`, `network_sources.gd`), `Done` (`library_file_actions.gd`),
`Add server` (`library_menu.gd`) and `Internal storage` (`ui_warmup.gd`). Add their
three locale translations.

Retain `Paused`, `Ended`, `Opening`, `Failed` through the explicit dynamic-key
list: `player_menu.gd` capitalizes `playback_state` before translation. The
checker requires that producer expression to remain present.

The following 35 keys have no matching literal in production GDScript, Kotlin
or licenses.json and no dynamic producer. Full-repository fixed-string searches
were also reviewed before removing them from each locale. Partial matches in
longer UI labels, historical documentation and negative tests do not produce
these standalone keys:

`Discovered`, `Stereo viewing`, `Inspect`, `SMB network`, `Player`, `Screen curve`, `Loop`, `Eye order`, `Projection`, `Alpha resolution`, `View`, `Sample`, `Volume`, `Audio track`, `Mute`, `Previous`, `Next`, `Muted`, `Remove`, `Back`, `Sign in`, `Character`, `Continue`, `Search again`, `Show`, `Support`, `Website`, `Seek mode`, `Speed`, `Top`, `Upper`, `Lower`, `Bottom`, `Select a file`, `Screen`.

## Dependency-preparation follow-up with Gradle 9.8.2

The R2 rollback passed ordinary offline assemble/test against the prepared cache.
A later explicit `prepareDependencyCache --write-locks` run on 9.8.2 failed on
`annotation-1.1.0.pom` verification in `:player-plugin:debugCompileClasspath`.
That task resolves additional configurations/descriptors and is also used when
preparing CI caches. It therefore needs verification coverage that the ordinary
cached build did not exercise. This is stronger evidence than the earlier
assemble-only result; the POMs are required preparation metadata, not runtime
version upgrades or a dependency introduced by the URI fixture.

Regenerate with `prepareDependencyCache --write-locks
--write-verification-metadata sha256` and `-PincludeUriFixture=true`, then rerun
`prepareDependencyCache` without metadata-writing flags. Both tasks pass.
Gradle adds exactly the previously observed annotation 1.1.0 and core-common
2.1.0 POM hashes. Existing root/player locks remain byte-identical; the new
conditional fixture owns its newly generated lock. The fixture APK builds
offline and contains only the MP03 asset matching the repository manifest.

A follow-up omission experiment on the now-prepared cache subsequently passed
without the annotation record. That warm-cache result does not contradict the
first 9.8.2 verification failure, and cannot establish that a fresh CI resolver
will not need the POM. Keep the Gradle-generated descriptor coverage; distinguish
selected runtime versions from descriptor-verification inputs. No claim is made
that every repeated warm-cache task will re-check every descriptor.

## Dependency refresh — 2026-11-13

The runtime/tooling refresh is limited to the dependencies below. Application
identity, release version, Godot, Gradle, AGP and jcifs remain unchanged.

| Dependency | Previous | Selected release | Source |
| --- | --- | --- | --- |
| Khronos Android OpenXR loader | 1.1.54 | 1.1.65 | [Khronos release](https://github.com/KhronosGroup/OpenXR-SDK-Source/releases/tag/release-1.1.65) |
| Pillow | 12.3.0 | 13.0.0 | [Release notes](https://pillow.readthedocs.io/en/stable/releasenotes/13.0.0.html) |
| bcprov-jdk18on | 1.85 | 1.87 | [Maven Central metadata](https://repo.maven.apache.org/maven2/org/bouncycastle/bcprov-jdk18on/maven-metadata.xml), [upstream tag](https://github.com/bcgit/bc-java/tree/r1rv87) |
| SLF4J API | 1.7.36 | 2.0.20 | [Release notes](https://www.slf4j.org/news.html) |

SLF4J 2.1.0 alpha releases were excluded. Bouncy Castle 1.87 is published as an
unqualified version in Maven Central and has the upstream `r1rv87` tag; the
website's older 1.86 announcement is not used as the package-version authority.

OpenXR Vendors 5.1.0 remains the latest stable addon. Its
[configuration](https://github.com/GodotVR/godot_openxr_vendors/blob/5.1.0-stable/config.gradle)
uses OpenXR headers 1.1.49, and its packaged Android vendor AARs do not embed an
OpenXR loader. The application supplies the separately pinned Khronos AAR.
Successful host packaging does not establish headset runtime compatibility.

Gradle 9.8.2 generated the locks and SHA-256 records for each Android dependency
separately, including the conditional URI fixture and generated Godot export.
Strict offline `prepareDependencyCache` passed after each update. Root-project,
root-settings, URI-fixture and asset-pack locks are unchanged. The generated
export settings lock records only the empty `incomingCatalogForLibs0`
configuration. Plugin/export locks
change only the three intended runtime versions, with no new runtime module.
Additional verification records cover the new releases, SLF4J's parent/BOM, and
previously unrecorded descriptors for core 1.7.0, lifecycle-common 2.3.1 and
error_prone_parent 2.30.0. Those descriptor records do not change selected
dependency versions. Existing verification hashes are preserved.

Pillow was installed in the existing local media-tools environment. C04's four
assets and manifest, plus the five stereo clips, five PNGs and their manifest,
are byte-identical before/after the upgrade (16 files total). C04 itself uses
OpenCV; the stereo generator exercises Pillow drawing, font loading, blending
and PNG output. `pip check` passed. Comparison evidence is under ignored
`artifacts/reports/dependency-upgrade-20261113/`.

Actions pins resolve to official release commits: checkout 7.0.1, setup-python
7.1.0, setup-java 6.2.0, upload-artifact 7.0.2 and download-artifact 8.0.2.
configure-pages 6.0.0, upload-pages-artifact 5.0.0, deploy-pages 5.0.1 and
setup-android 4.0.4 already point at the latest release commits. All 16 external
action references match the upstream release SHAs and accept their configured
inputs; `actionlint` passed. The existing archive upload behavior remains the
default, and download-artifact's default digest-mismatch failure is retained.
Hosted workflow execution follows the normal [publishing procedure](BUILD.md#outputs-signing-and-ci).
Physical headset/server verification is maintained in
[ACCEPTANCE.md](ACCEPTANCE.md#current-device-acceptance).

Local validation passed: 124 workflow tests, 4 website tests, 17 release
preparation tests, 195 JVM tests (10 additional tests skipped) and 102 Godot
scripts, including the render-script loading checks. Source-boundary, website,
translation/resource consistency, Ruff and diff checks passed. Quest, PICO and
OpenXR Debug builds and packaging passed the normal APK verification. Each APK
contains exactly one ARM64 OpenXR loader, byte-identical to the library in the
official 1.1.65 AAR. No device installation, push, tag or release was performed.

## Cleanup checkpoint — 2026-11-21

The preceding 37-file worktree was preserved in six local commits.

| Commit | Scope |
| --- | --- |
| `7070db2` | Playback history, media records, directory-memory retry and regression tests |
| `6539789` | Android stream reads, removal of the reader-set snapshot lock and unused keep rules |
| `d5ee38b` | Build fingerprints, Gradle checks and workflow tests |
| `95039b8` | Website downloads and the Pages refresh after release upload |
| `35bd22b` | Unused Godot gesture, subtitle, library and loop helpers |
| `77403ca` | Architecture, build and contribution documentation |

All three published v1.0.0 APKs verified with the same temporary CI certificate,
which differs from the pinned PICO Store certificate. The audit stopped at
that mismatch as requested. [APK hashes and certificate fingerprints](ACCEPTANCE.md#published-v100-apk-signing-audit)

Tag-signing enforcement, release retry handling, bookmark and subtitle
migration, the navigation decision, CI and stream diagnostics, and the disk
inventory are pending. The full test rerun is also pending. Existing headset
validation items remain recorded in [device acceptance](ACCEPTANCE.md#current-device-acceptance).

## Cleanup continuation — 2026-11-21

This pass started at `32f17b2`. Work is committed locally by topic.

### Signing and publication

- The v1.0.0 tag's signing directory is outside its artifact upload paths.
  The current signing paths are also outside the Android Actions caches and
  uploads. The GitHub API returned 8 OpenXR, 27 PICO and 17 Quest downloads
  at 16:33 CST. [Signing audit](ACCEPTANCE.md#published-v100-apk-signing-audit)
- The tag's `Release / macOS` job requires all three repository signing
  secrets before it prepares dependencies. Formal Web and Store Release
  packages use the pinned PICO Store certificate on all three platforms.
  `apksigner` checks the exported APK. Publication rejects missing or
  different fingerprints and requires a formal CI signer in every receipt.
  Non-tag CI development builds can still use temporary signing.
- Retrying publication skips existing assets with matching names and
  SHA-256 digests. A same-day hash change or a cross-day filename change
  stops the job with a new-patch-version message. The workflow checks every
  platform before uploading missing files, uses the GitHub API asset digest
  or hashes the remote binary when the digest is absent, and verifies the
  final asset set. An identical retry leaves release notes alone.
- The next-release section of the English and Chinese website update pages
  explains the one-time signing transition and local-data loss on uninstall.
  Its heading leaves the next version and date open.

### Owner setup before publishing

1. In the repository's **Settings → Secrets and variables → Actions**, add
   `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEY_ALIAS` and
   `ANDROID_KEY_PASSWORD` as repository secrets for the key matching the
   pinned PICO Store certificate. The repository owner supplies those values.
   [Build and signing setup](BUILD.md#pico-store-apks)
2. Append the following bilingual notice to the
   [v1.0.0 GitHub Release](https://github.com/NorthBoundWisdom/immivio/releases/tag/v1.0.0).

**中文文案**

> **升级提醒**　本页提供的 v1.0.0 APK 使用了临时签名。从下一版开始，Quest、PICO 和 OpenXR 的 APK 都将使用正式签名。如果你安装了本页的 v1.0.0 APK，请先卸载，再安装新版本。卸载会清除本机的播放历史和账号设置。

**English copy**

> **Upgrade notice**　The v1.0.0 APKs attached to this release used a temporary signing key. Starting with the next release, Quest, PICO and OpenXR APKs will use the official signing key. If you installed one of the v1.0.0 APKs from this page, uninstall it before installing the next release. Uninstalling clears local playback history and account settings.

### Playback, CI and device verification

- The normal rename handler now moves bookmarks. A record already associated
  with the destination wins. The old bookmark association is retired and
  `bookmark_rename_conflict` records the number of source markers. An
  unchanged URI performs no bookmark write. Both local storage and SMB use
  `RenameBundle`, which renames eligible same-stem subtitle and audio
  companions and returns the completed moves. Saved external subtitle URIs
  are rewritten for exact matches in the same folder, including references
  saved under other videos. Partial or failed renames do not run migration.
- The subtitle action opens the existing library and immediately opens the
  subtitle picker. The stop action reopens the existing library after
  closing playback. Opening the library already leaves its folder and
  scroll state in the library controller, with the existing compact-mode
  restriction on Settings. The device probe explicitly sets its test
  folder or Settings state after opening. None of those callers needs a
  separate `preserve_navigation` argument, so the argument and its
  call-site values were removed.
- Android push CI now runs on `main` and tags. PRs targeting `main` use the PR
  trigger. The concurrency group keys on the ref and cancels older runs for
  that ref except tags. The jcifs and ICU inputs now use Gradle file
  providers. Both early-resolution warnings disappeared. Forced rebuilds
  produced byte-identical filtered JARs, and ICU verification tracks the
  whole input archive and its checksum record.
- The loopback HTTP server records active connections and each new peak in
  existing diagnostics. Saving diagnostics also records current and peak
  counts. The cached thread pool remains unbounded. On a headset, test
  local/SMB rename with companions, return from playback and subtitle
  picking, and record peak counts during steady network playback and
  repeated timeline dragging. No headset was connected during this pass.
  [Device acceptance](ACCEPTANCE.md#current-device-acceptance)

### Disk inventory for approval

The local snapshot on 2026-11-21 measured **16.29 GiB** in `artifacts/`
and **6.06 GiB** in `build/intermediates/`. Within artifacts, the archive
accounted for 11.45 GiB, packages 3.99 GiB, reports 0.56 GiB and captures
0.27 GiB. Sizes below come from `du -sk`. Shared files or filesystem clones
can make recovered space differ from the sum.

Retention covers complete APKs and receipts associated with published
versions reported by GitHub, from `v0.6.0-fork.1` through `v1.0.0`, and
at least the newest complete APK/receipt pair for each vendor and build
type across both channels. The date in the package name determines
newness, with APK modification time breaking same-day ties. The three
verified v1.0.0 APKs and their receipts in the signing-audit directory
are retained. Ambiguous archives, credential-like paths and unrelated
evidence remain outside the candidate list.

| Vendor / build | Newest complete APK retained with its adjacent receipt |
| --- | --- |
| OpenXR Debug | `artifacts/packages/OpenXR/web/debug/Immivio-OpenXR-1.0.0-web-debug-20261121.apk` |
| OpenXR Release | `artifacts/reports/cleanup-v1.0.0-signing.fqBWAP/Immivio-OpenXR-1.0.0-web-release-20261113.apk` |
| PICO Debug | `artifacts/packages/PICO/web/debug/Immivio-PICO-1.0.0-web-debug-20261121.apk` |
| PICO Release | `artifacts/packages/PICO/appstore/release/Immivio-PICO-1.0.0-appstore-release-20261115.apk` |
| Quest Debug | `artifacts/packages/QUEST/web/debug/Immivio-QUEST-1.0.0-web-debug-20261121.apk` |
| Quest Release | `artifacts/packages/QUEST/web/release/Immivio-QUEST-1.0.0-web-release-20261114.apk` |

The following candidates total approximately **10.20 GiB**. Dates are local
modification dates. The three files in the `direct` subdirectory are partial
downloads from the signing audit.

| Candidate path | MiB | Date or version |
| --- | ---: | --- |
| `build/intermediates/legacy-apk-inspection/` | 6,201.17 | 2026-11-06, expanded APK inspection files |
| `build/intermediates/gradle-install-thread.txt` | 0.19 | 2026-11-10 |
| `artifacts/archive/legacy-build/F4-retry-unsigned.apk` | 162.30 | 2026-11-04, unsigned retry |
| `artifacts/archive/legacy-build/depth/` | 282.75 | 2026-10-12 |
| `artifacts/archive/legacy-build/godot-api/` | 107.51 | 2026-10-10 |
| `artifacts/archive/legacy-build/rvm/` | 85.72 | 2026-10-12 |
| `artifacts/archive/legacy-build/rvm-ratio-one/` | 14.28 | 2026-10-12 |
| `artifacts/archive/legacy-build/ports-mpv-sdk/` | 29.03 | 2026-11-04 |
| `artifacts/archive/legacy-build/native-clean-release/` | 10.04 | 2026-10-14 |
| `artifacts/archive/legacy-build/native-layout-android/` | 7.62 | 2026-10-14 |
| `artifacts/archive/legacy-build/native-host/` | 4.32 | 2026-11-04 |
| `artifacts/archive/legacy-build/ci-export-path/` | 0.11 | 2026-11-05 |
| `artifacts/reports/cleanup-v1.0.0-signing.fqBWAP/direct/Immivio-OpenXR-1.0.0-web-release-20261113.apk` | 6.02 | v1.0.0, partial download |
| `artifacts/reports/cleanup-v1.0.0-signing.fqBWAP/direct/Immivio-PICO-1.0.0-web-release-20261113.apk` | 5.66 | v1.0.0, partial download |
| `artifacts/reports/cleanup-v1.0.0-signing.fqBWAP/direct/Immivio-QUEST-1.0.0-web-release-20261113.apk` | 6.25 | v1.0.0, partial download |
| `artifacts/archive/legacy-build/dependency_seed_repos/MpvSources/` | 64.97 | 2026-10-13 |
| `artifacts/archive/legacy-build/dependency_seed_repos/FFmpeg/` | 660.28 | 2026-10-13 |
| `artifacts/archive/legacy-build/dependency_seed_repos/Libxml2/` | 69.73 | 2026-10-13 |
| `artifacts/archive/legacy-build/dependency_seed_repos/GodotMacOS/` | 162.72 | 2026-10-13 |
| `artifacts/archive/legacy-build/dependency_seed_repos/MbedTLS/` | 161.39 | 2026-10-13 |
| `artifacts/archive/legacy-build/dependency_seed_repos/Gradle/` | 144.60 | 2026-10-13 |
| `artifacts/archive/legacy-build/dependency_seed_repos/Mpv/` | 151.53 | 2026-10-13 |
| `artifacts/archive/legacy-build/dependency_seed_repos/MpvLinuxNdk/` | 704.42 | 2026-10-13 |
| `artifacts/archive/legacy-build/dependency_seed_repos/PythonPackages/` | 81.09 | 2026-10-13 |
| `artifacts/archive/legacy-build/dependency_seed_repos/GodotOpenXRHands/` | 900.83 | 2026-10-13 |
| `artifacts/archive/legacy-build/dependency_source_roots/FFmpeg/` | 115.61 | 2026-10-13 |
| `artifacts/archive/legacy-build/dependency_source_roots/GodotOpenXRHands/` | 309.54 | 2026-10-13 |

### Validation

| Suite | Baseline passed | This pass |
| --- | ---: | ---: |
| Godot | 105 | 105 |
| Android JVM | 225 | 226, 11 skipped |
| Workflow | 140 | 143 |
| Release | 18 | 22 |
| Native | 5 | 5 |
| Website | 4 | 4 |

Ruff, actionlint, website/source checks and `git diff --check` passed.
Publication tests use local fixtures and mock uploads. A real formally
signed release still needs a GitHub tag run after the owner configures the
repository signing secrets. This pass used no private
key or password. No candidate was deleted, and no push, tag, version
change or publication was performed.
