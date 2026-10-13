# Building Immivio

Immivio has one playback edition. Inference models, MNN and ncnn are excluded.

## Dependency and toolchain ownership

`FreeCM/` is a pinned submodule. `source_roots.lock.jsonc.in` owns Git source pins and download URLs, SHA-256 hashes and exact sizes. `configs/toolchain.json` owns host tool requirements; `android/gradle/libs.versions.toml`, Gradle dependency locks and verification metadata own Maven packages; `cloud/openlist/go.mod` and `go.sum` own the embedded core's Go modules. Native mpv source records under `third_party/mpv` remain corresponding-source and receipt provenance, not a separate downloader.

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

Only dependency `--init` accesses the network. After intentional Maven upgrades, maintainers can use `--init --refresh-packages` to regenerate the committed Gradle locks and verification metadata, review their diff, then configure again. It selects host assets into the ignored active lock, prepares FreeCM seeds and prefetches Go/Gradle packages. `--update`, diagnostics, configuration, compilation, testing and packaging consume verified local inputs offline. Missing inputs require another initialization. Initialization selects current template assets while preserving local source-root settings; `--refreshpin` updates only Git commit pins. Release requires pinned source dependencies.

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

APKs keep the `Immivio-<QUEST|PICO|OpenXR>-<version>-<debug|release>-<YYYYMMDD>.apk` naming contract. Each version 2 `.build.json` receipt includes source commit, FreeCM commit, resolved dependency commits, asset and package-lock digests, toolchain, backend, APK hash and signing certificate.

The application ID remains `com.wapok.thru3d`, preserving upgrades and user data with a compatible signing certificate. Existing `artifacts/signing/thru3d-signing.json` credentials are reused. Explicit `GODOT_ANDROID_KEYSTORE_<DEBUG|RELEASE>_*` variables take priority; partial overrides fail. Keep keys and credentials outside Git.

Windows/macOS CI uses these same explicit stages for all three targets. Tags build Release and use repository signing secrets when supplied. Publishing requires successful jobs on both hosts, complete pinned version 2 receipts and matching tag/commit; canonical APKs come from macOS.

APK checks retain ARM64, ELF symbol/dependency closure and 16KB alignment, signature, ZIP alignment, application identity and exclusion of inference components. These checks do not establish headset playback performance.
