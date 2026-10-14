# Testing Immivio

Prepare and configure dependencies as described in [BUILD.md](BUILD.md).

```sh
python3 -m unittest discover -s tests/workflow -v
python3 tools/test_prepare_android_release.py
python3 FreeCM/tools/validate_repo_commands.py .
python3 tools/Check-PublicSource.py
python3 configs/source_roots.py verify
python3 configs/check_environment.py
python3 configs/android_workflow.py test --vendor Quest --build-type Debug
```

Settings migration tests preserve ordinary preferences, source masks and stereo locks, reject reactivation by stale UI controls, and verify repeated cleanup needs no additional write.

The Android workflow offers `--level l0` (workflow and publication boundaries), `l1` (JVM and Go integration), `l2` (Godot host behavior), and `all`. JVM/Go tests use the configured dependencies offline. The Godot suite writes logs and JUnit results under `artifacts/source-tests/`. A passing process must also emit exactly one completion report for the script being run; reaching the frame limit without finishing is a failure.

Native helper tests have one host entry point on macOS, Windows and Linux:

```sh
cmake -S native -B build/native-host -DCMAKE_BUILD_TYPE=Release
cmake --build build/native-host --config Release --parallel 2
ctest --test-dir build/native-host -C Release --output-on-failure
```

These tests exercise the production JSON writer against an independent Python Unicode oracle, and numeric seek tracing. They require CMake, a C++17 compiler and Python 3.11+, and keep assertions enabled in Release builds. GitHub CI runs them on both build hosts.

Workflow tests cover corrupt assets, offline acquisition boundaries, configuration staleness, separate Build/Package stages, safe cleanup, process timeouts and signing identity preservation. Release tests reject incomplete dependency provenance and mismatched tag/commit/host/variant or APK bytes.

Use the Android workflow for host tests and package verification. Rendering fixtures remain under `app/godot/tests/render_*.gd` for focused visual checks. Build and package each target before device verification. Existing device probes and media benchmarks remain available. Host/APK checks do not establish media or rendering correctness on a headset.

Host-environment tests verify SDK selection, actual downloads through a local HTTP fixture, checksum failures, failed responses and archive extraction boundaries. No external network or account is needed for these checks.

Use [ACCEPTANCE.md](ACCEPTANCE.md) for recorded local checks and the remaining device verification sequence, and [FRAME_CONTRACT.md](FRAME_CONTRACT.md) when adapting device reports. Historical results do not certify later source changes.

## Test responsibilities

- `tests/workflow` and the release tests protect configuration freshness, byte integrity, signing and publication boundaries. FreeCM's own implementation tests belong in FreeCM.
- `app/godot/tests/test_*.gd` exercise the current playback controller, captions, persistent state, menus and input behavior. The playback control and geometry suites use focused state transitions and invariants rather than constructing the old player implementation.
- Android/JVM and Go tests cover protocol parsing, actual loopback HTTP/range reads, account isolation, file operations and frame/resource ownership. Credential-dependent live checks report explicit skips.
- Retained `render_*.gd` checks need a real GPU renderer and have failure conditions such as pixel differences, invalid geometry, clipping or incomplete warmup. Saving a screenshot alone is not an automated regression result. They are not run by the headless suite. Thumbnail capture pixels live in `render_thumbnail_capture.gd`; `test_thumbnails.gd` covers cache and library behavior without waiting for a GPU.

Each headless Godot test calls `preload("res://tests/support/test_result.gd").prepare(self)` first. This creates a separate `user://` directory for that script and process, so caches and saved settings cannot come from a previous test or a normal app session. The directory is printed in its log for failure diagnosis. It ends with `preload("res://tests/support/test_result.gd").finish(self, exit_code)`. Keep the assertions in the test; the helper reports completion and exits. Do not print a success report from initialization or a timeout handler. The runner rejects missing, duplicate, malformed and foreign-script reports, nonzero exits, and engine errors even after a success report.

Prefer a small test that fails when a real contract is broken: stale callbacks must not revive a closed session, failed file operations must preserve the original, or corrupt bytes must not be published. Mock hardware/network boundaries where needed, while executing the production behavior being checked. Avoid tests that replace the whole subject with a mock, merely repeat constants or private control layouts, or duplicate a dependency's own suite.
