# Cleanup investigation (2026-11-12)

This records the B1–B4 investigation requested by TODO.md. Evidence below refers
to `ad9f142`, before the follow-up removals, so the references remain reviewable
with `git show ad9f142:<path>`. Follow-up decisions are separate commits.
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

## B4: profile (owner decision pending)

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
Do not change profile constants, storage, validation or Debug commands until the
owner chooses between fixing the dimensions and retaining a documented control.

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
