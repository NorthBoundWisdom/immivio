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

Workflow tests cover corrupt assets, offline acquisition boundaries, configuration staleness, separate Build/Package stages, safe cleanup, verified optional backend imports, process timeouts and signing identity preservation. Release tests reject incomplete dependency provenance and mismatched tag/commit/host/variant or APK bytes.

Use the Android workflow for host tests and package verification. Rendering fixtures remain under `app/godot/tests/render_*.gd` for focused visual checks. Build and package each target before device verification. Existing device probes and media benchmarks remain available. Use the optional backend and its checked receipt for private PGS, spatial-video or Dolby tests; host/APK checks alone do not establish those capabilities on a headset.

Dependency-selection tests verify that disabled source entries need no seed or download, and explicitly enabling them requires prepared inputs. Host-environment checks inspect installations without installing or downloading tools.
