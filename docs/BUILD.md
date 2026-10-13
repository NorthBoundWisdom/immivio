# Building Immivio

Immivio has one playback edition. Inference models, MNN and ncnn are excluded.

## Dependency and toolchain ownership

`source_roots.lock.jsonc.in` is the sole reviewed dependency authority. FreeCM's standard `dependencies` entries pin source repositories by full Git commit, matching the source-root workflow used by PCBAtlas Android. The namespaced `immivio` section holds toolchain requirements, Maven resolution/checksums, Go module/checksum data, Python wheel pins and vendored-resource provenance. FreeCM core remains unmodified.

`configs/dependency_manifest.py generate` renders Gradle catalogs/locks/verification metadata, Go manifests, native receipt compatibility records and Python requirements. These generated inputs are ignored by Git and must not be edited independently. `verify` rejects drift and verifies embedded hand/background/license bytes against the master lock. `--init` and `--update` render inputs automatically; builds verify them.

mpv, FFmpeg and native helper libraries use commit-pinned FreeCM source roots. The optional Linux build copies those roots into a disposable tree and reuses the pinned upstream mpv-android build recipes. Source roots remain unmodified. The Lua 5.2.4 source uses a pinned LuaDist mirror because the official Lua Git repository has no 5.2.4 release tag. Official Godot and mpv Android binaries remain checksum-pinned distribution assets with their corresponding source commits recorded; this does not imply those binaries are compiled by this repository.

Maven/Go/Python package versions retain their native ecosystem identities and integrity checks. Their entire reviewed lock data lives inside the master lock rather than independent package-version files. The old native archive records are generated only to validate historical source-frame receipts; they no longer acquire or materialize native source trees.

Install the Python, JDK, Go and Android SDK components specified in the toolchain configuration. Local builds use `JAVA_HOME` and `ANDROID_HOME` / `ANDROID_SDK_ROOT`. Windows/macOS initialization prepares the locked Godot editor; `GODOT_EXE` can select an editor with the exact locked version. Linux uses a supplied matching editor. CI provisions the SDK and host runtimes before dependency initialization.

```sh
git clone --recurse-submodules https://github.com/NorthBoundWisdom/immivio.git
cd immivio
python3 configs/source_root_workflow.py --init
python3 configs/source_root_workflow.py --update
python3 configs/android_workflow.py configure --vendor Quest --build-type Debug
python3 configs/android_workflow.py build --vendor Quest --build-type Debug
python3 configs/android_workflow.py test --vendor Quest --build-type Debug
python3 configs/android_workflow.py package --vendor Quest --build-type Debug
```

Use `Pico` or `OpenXR` for the other targets and `Release` for distributable packages. The same Python commands run in PowerShell. The previous build and preparation commands have been removed.

Only dependency `--init` accesses the network. After intentional Maven upgrades, maintainers can use `--init --refresh-packages` to harvest resolution and checksum changes back into the master lock, review its diff, then configure again. It selects host assets into the ignored active lock, prepares FreeCM seeds and prefetches Go/Gradle packages. `--update`, diagnostics, configuration, compilation, testing and packaging consume verified local inputs offline. Missing inputs require another initialization. Initialization selects current template assets while preserving local source-root settings; `--refreshpin` updates only Git commit pins. Release requires pinned source dependencies.

Configure is explicit. Build/Test/Package reject missing or stale configuration. Package requires a successful current Build. `run` installs an already packaged APK on the attached Android device. The FreeCM editor command manifest exposes these same actions.

Generated host tools, source roots and configuration live under ignored `build/`; Gradle and Go use repository-local `.cache/` stores. `--cleanbuild --dry-run` previews cleanup. Cleanup preserves dependency seed/source roots and signing material, but removes generated configurations and build outputs; run `--update` and Configure afterward.

## Playback backends

The default backend uses checksum-pinned, unmodified **mpv-android upstream release libraries**, through libmpv's public render API. mpv-android is the Android distribution, rather than a standalone Android SDK released by the mpv main project. Ordinary and packed stereo playback are supported by this path; it does not claim the private backend's decoded-frame PTS, PGS bitmap, MV-HEVC or Dolby capabilities.

The optional project backend remains isolated while public-API replacements are evaluated. Import it with both receipt and directory at every stage:

```sh
python3 configs/android_workflow.py configure --vendor Quest --build-type Debug \
  --mpv-dir /path/to/arm64-v8a --mpv-receipt /path/to/source-build.json
```

Supply the same two arguments to Build, Test and Package. The importer verifies source revision, source-lock identity, patches, headers and every library before staging any bytes. PGS/spatial/Dolby capabilities still require media and device validation.

To build the optional backend on Linux, install the native build prerequisites (Autoconf, Automake, Libtool, pkg-config, gperf, NASM, CMake, Bison, Flex, gettext, Meson 1.11.0 and Ninja), and enable unprivileged user/network namespaces. The build runs in a network namespace with no network access. Then use:

```sh
python3 configs/source_root_workflow.py --init --native-mpv
python3 configs/source_root_workflow.py --update
python3 configs/native_mpv_workflow.py configure
python3 configs/native_mpv_workflow.py build
python3 configs/native_mpv_workflow.py package
```

The source backend uses `build/native-mpv/`; its library output and receipt are under `build/native-mpv/output/`. No upstream source roots are patched in place. Public-API replacements will be validated one capability at a time before removing corresponding project patches.

## Outputs, signing and CI

APKs keep the `Immivio-<QUEST|PICO|OpenXR>-<version>-<debug|release>-<YYYYMMDD>.apk` naming contract. Each version 3 `.build.json` receipt includes source commit, FreeCM commit, resolved dependency commits, asset and package-lock digests, toolchain, backend, APK hash and signing certificate.

The application ID remains `com.wapok.thru3d`, preserving upgrades and user data with a compatible signing certificate. Existing `artifacts/signing/thru3d-signing.json` credentials are reused. Explicit `GODOT_ANDROID_KEYSTORE_<DEBUG|RELEASE>_*` variables take priority; partial overrides fail. Keep keys and credentials outside Git.

Windows/macOS CI uses these same explicit stages for all three targets. Tags build Release and use repository signing secrets when supplied. Publishing requires successful jobs on both hosts, complete pinned dependency receipts and matching tag/commit; canonical APKs come from macOS.

APK checks retain ARM64, ELF symbol/dependency closure and 16KB alignment, signature, ZIP alignment, application identity and exclusion of inference components. These checks do not establish headset playback performance.

## Python media tools

Optional fixture/benchmark packages (NumPy, OpenCV, Pillow, pillow-heif, ONNX Runtime and their dependencies) are fixed in `immivio.python`. Prepare them explicitly:

```sh
python3 configs/source_root_workflow.py --init --python-tools
python3 configs/python_tools.py verify --profile media-tools
python3 configs/python_tools.py run --profile media-tools tools/Generate-StereoFixtures.py --help
```

The native profile additionally pins Meson, Jinja2, MarkupSafe and packaging. `--init --native-mpv` prepares it. Python downloads require the hashes in the master lock; installs and script runs use local wheel caches offline.
