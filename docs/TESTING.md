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

The Android workflow offers `--level l0` (workflow and publication boundaries), `l1` (JVM and Go integration), `l2` (Godot host behavior), and `all`. JVM/Go tests use the configured dependencies offline. The Godot suite writes isolated test user data and JUnit results under `artifacts/`.

Native helper tests have one host entry point on macOS, Windows and Linux:

```sh
cmake -S native -B build/native-host -DCMAKE_BUILD_TYPE=Release
cmake --build build/native-host --config Release --parallel 2
ctest --test-dir build/native-host -C Release --output-on-failure
```

These tests exercise the production JSON writer against an independent Python Unicode oracle, and numeric seek tracing. They require CMake, a C++17 compiler and Python 3.11+, and keep assertions enabled in Release builds. GitHub CI runs them on both build hosts.

Workflow tests cover corrupt assets, offline acquisition boundaries, configuration staleness, separate Build/Package stages, safe cleanup, process timeouts and signing identity preservation. Release tests reject incomplete dependency provenance and mismatched tag/commit/host/variant or APK bytes.

Use the Android workflow for host tests and package verification. Rendering fixtures remain under `app/godot/tests/render_*.gd` for focused visual checks. Build and package each target before device verification. Existing device probes and media benchmarks remain available. Host/APK checks do not establish media or rendering correctness on a headset.

Dependency-selection tests verify that disabled source entries need no seed or download, and explicitly enabling them requires prepared inputs. Host-environment checks inspect installations without installing or downloading tools.

Use [ACCEPTANCE.md](ACCEPTANCE.md) for recorded local checks and the remaining device verification sequence, and [FRAME_CONTRACT.md](FRAME_CONTRACT.md) when adapting device reports. Historical results do not certify later source changes.
