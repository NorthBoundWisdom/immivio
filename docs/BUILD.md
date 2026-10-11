# Building from source

The model-free Android player has a Python build entry point for macOS, Linux and Windows. The historical AI build uses PowerShell 7 on Windows and a Linux source build of patched libmpv. Paths are configurable; source and build output must remain separate. This repository does not bundle SDKs, compiled libraries or runtime model weights.

## Base player: no AI models

```sh
python3 tools/build_player.py --vendor Quest --build-type Debug
python3 tools/build_player.py --vendor Quest --build-type Release
```

Use `--vendor Pico` or `--vendor OpenXR` for the other Android presets. These are **Android APKs**, not macOS/Windows desktop applications. The desktop Godot path remains a development preview.

Supply Python 3.11+, curl, Go 1.27.x, Godot 4.7.2 with its Android export templates, and an Android SDK containing platform 36, build-tools 36.1.0, NDK 30.0.16248370 and CMake 4.1.2. Go 1.27.0 is verified on a Windows workstation; hosted CI provisions 1.27.1. The default Gradle fallback is 9.8.1 with AGP 9.2.0 and Kotlin 2.3.21; JDK 25 is supported by this workflow. Local builds reuse a compatible installation selected by `--gradle` or `GRADLE_HOME`, then the shared Gradle cache. They discover `JAVA_HOME`, `ANDROID_HOME`/`ANDROID_SDK_ROOT`, `GODOT_EXE`, `GODOT_TEMPLATES_DIR` and Android Studio's macOS JDK. Explicit paths/version overrides are available with `--java-home`, `--sdk`, `--godot`, `--templates`, `--gradle`, `--ndk` and `--cmake`. Shared Windows installations can therefore serve multiple users without copying SDKs into each checkout. Hosted Actions builds continue to use the locked Gradle fallback.

The script performs the following dependency preparation automatically:

- Downloads the fixed official mpv-android APK from `third_party/mpv/manifest.json`, checks its SHA256 and every extracted ARM64 library, and uses the public libmpv render API. No custom mpv patch, MNN, ncnn, or model assets are required.
- Downloads the fixed OpenList source archive, applies the project's encrypted credential storage adapter, and runs the pinned gomobile/gobind to build `cloudcore.aar` from source. Go resolves its versioned dependency graph with the upstream `go.mod`/`go.sum` and checksum database.
- Installs the checksum-pinned OpenXR Vendors addon and assembles the matching Godot Android template. The installed SDKs/templates are not edited.

Downloads and dependency sources live under ignored `.cache/`; generated plugin libraries and Android templates remain ignored. `--prepare-only` prepares dependencies; `--plugin-only` builds the Android AAR and runs JVM tests. An exclusive build lock protects this Python workflow's shared output. Do not run the historical PowerShell builder concurrently in the same checkout.

On restricted networks, `GRADLE_RO_DEP_CACHE` can point to a snapshot containing `modules-2` from a compatible Gradle installation. Keep the snapshot immutable while builds read it, omit lock/GC files, and retain a separate writable `GRADLE_USER_HOME`, following [Gradle's dependency-cache instructions](https://docs.gradle.org/current/userguide/dependency_caching.html#sec:copying_and_reusing_cache). Use short cache paths on Windows; platform-specific artifacts such as Windows AAPT2 still need their matching host binaries.

Release builds use an explicitly supplied `GODOT_ANDROID_KEYSTORE_RELEASE_*` environment or a reusable local key created under ignored `artifacts/signing/`. Keep that directory private and back up the key if future builds must update existing installations. No original distribution signing key is available.

APKs and build receipts are written to `artifacts/`. The workflow verifies signing, 16 KiB ZIP alignment, required ARM64 libraries and absence of AI model/library payloads. Public libmpv supplies playback-clock estimates rather than verified decoded-frame PTS; this provenance is retained through the display path, and such tickets cannot authorize AI inference. Real-headset decoding, audio synchronization and seek behavior still require device verification.

## Build modes and compatibility

Direct Gradle builds retain `enableAi=true` and `standardMpv=false` by default. The Python base-player entry point explicitly selects `enableAi=false` and `standardMpv=true`; it does not change the default AI build. `Build-Player.ps1 -WithoutAI` also selects the official mpv candidate unless another candidate is supplied explicitly.

| Capability | AI enabled + project mpv | AI disabled + project mpv | AI disabled + standard mpv |
| --- | --- | --- | --- |
| Build switches | Defaults | `-PenableAi=false` | `-PenableAi=false -PstandardMpv=true` |
| MNN, ncnn and matching model assets | Required | Excluded | Excluded |
| Ordinary video/photo playback, existing stereo, libraries and text subtitles | Available | Available | Available |
| Live matting and inferred 2D-to-3D | Available with models/device support | Disabled | Disabled |
| Precomputed stereo and packed masks | Available | Available | Available |
| Verified decoded-image PTS | Project source-frame API | Project source-frame API | Unavailable; playback-clock estimates only |
| Flat-video PGS bitmap subtitles | Project PGS API | Project PGS API | Unavailable; unsupported tracks are filtered out |
| Project Dolby Vision Profile 5 conversion metadata | Project frame flags, subject to device/media support | Project frame flags, subject to device/media support | No project frame flags; standard mpv color handling requires separate validation |

The standard backend never invents private source-frame or Dolby metadata and cannot authorize AI pairs. Its rendering counters describe render transactions, not independently verified unique decoded images. `standardMpv=true` with `enableAi=true` is rejected by Gradle and CMake.

Model-free builds, host/JVM tests and package integrity checks are exercised by CI. A successful model-free job does not validate the AI-enabled build: that regression still requires the original model/runtime dependencies and the documented AI workflow. Device playback, Dolby color correctness, PGS output and XR behavior need matching device evidence for each applicable backend.

## Windows/macOS CI

`.github/workflows/android-release.yml` runs the model-free Android Release workflow on GitHub-hosted `windows-2025` and `macos-15` runners. It runs on main pushes, `v*` tags, pull requests and manual dispatch. Each host builds PICO, Quest and experimental OpenXR APKs; manual dispatch can select one target. These jobs build **Android packages on Windows/macOS**, not desktop editions.

CI installs JDK 25, Go 1.27.1 and Python 3.13, provisions the locked Android SDK tools, and verifies Godot editor/template download hashes. Only Android templates are expanded from the full template archive. The macOS host also receives checksum-pinned Noto CJK SC/TC/JP fonts from the upstream Sans 2.004 revision so headless tests do not depend on Apple's on-demand fonts; they are host tooling, not APK assets. Godot source tests, dependency boundary tests and Android JVM tests must pass before packages are exported. The same `tools/build_player.py` performs native-library, signing and 16 KiB packaging checks. Actions are pinned to commit SHAs. Dependencies are cached per host OS/architecture; signing material is excluded from caches and uploaded artifacts.

The three targets share dependency preparation and editor configuration within one locked invocation. Subsequent targets reuse imported resources; the cross-run cache includes only `.godot/imported`, not editor/export credentials. Cache hits avoid rebuilding the verified OpenList AAR. A small Gradle copy check catches Windows export-URI incompatibilities before the Android build. Godot import/configuration is limited to 10 minutes and each export to 15 minutes; engine errors stop the process tree immediately and preserve logs instead of leaving a failed export hanging. Build receipts also record each target's build/verification duration.

CI caches Maven dependencies, Gradle distributions, verified downloads, Android templates, imported resources and the OpenList AAR plus its input/hash receipt. It omits Go's compiled/module caches and Gradle transformation caches: unchanged OpenList inputs reuse the verified AAR, while changes rebuild it from the locked source. Hosted jobs stop Gradle before archival so Windows file locks cannot prevent saving the cache.

On Windows, Android export launches the paired Godot engine `.exe` directly with captured output. The `_console.exe` launcher can remain alive after the engine has completed an Android/Gradle export; using the engine directly avoids that wait. Version checks, editor preparation and host tests retain the configured CLI executable. This behavior was reproduced and the direct-engine export verified on a Windows workstation before applying the CI fix.

Successful jobs publish `Android-noai-Release-Windows` / `Android-noai-Release-macOS` artifacts containing APKs, per-package build receipts, SHA256 sums and a CI summary. Test/build logs are uploaded separately even on failure. GitHub Releases are not published automatically.

Without signing secrets, each hosted job creates an ephemeral local CI signing key and records `ephemeral-ci-key` in its receipts. Such packages can be installed, but cannot update an app signed by a different key, including the local PICO installation. For stable update signatures, configure all three repository Actions secrets: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEY_ALIAS` and `ANDROID_KEY_PASSWORD`. Use a keystore whose store and key passwords match. The key is decoded only into the runner's temporary directory; pull-request jobs never receive these secrets. No local signing key is uploaded automatically.

## Source-only verification

Python 3.10+ is sufficient for `python tools/Check-PublicSource.py`. Godot host tests require the matching Godot executable but no Android toolchain or models:

```powershell
$env:GODOT_EXE = (Get-Command godot).Source
./tools/Test-Source.ps1
```

## AI workflow: pinned toolchain

The versions/hashes used by this source snapshot are in `tools/environment/toolchain.lock.json`, the Gradle wrapper, and third-party source locks. The application build checks Godot `4.7.2.stable.official.ed1daf0bf`; use its corresponding Android templates and Godot OpenXR Vendors `5.1.0`. Android plugin configuration uses Java 17, compile SDK 36, build-tools 36.1.0, NDK 29.0.14206865 and CMake 3.31.6. The 0.2.1 Quest export uses min SDK 32 / target SDK 34; PICO and experimental standard OpenXR use 29 / 36. The separately built mpv dependency uses its own locked Linux NDK r30. Do not silently mix these toolchains.

Set your own paths:

```powershell
$env:THRU3D_TOOL_ROOT = Join-Path $HOME '.cache/thru3d-toolchain'
$env:GODOT_EXE = (Get-Command godot).Source
```

Prepare this layout beneath `THRU3D_TOOL_ROOT`:

```text
jdk/jdk-17.0.20.1+1/
android-sdk/                       platform 36, tools, NDK and CMake above
godot-templates/4.7.2.stable/       matching extracted templates incl. android_source.zip
openxr-vendors/5.1.0/asset/addons/godotopenxrvendors/
ncnn/20260526/ncnn-20260526-android-vulkan/arm64-v8a/
mnn/source-3.6.1/                  pristine MNN source
mnn/source-3.6.1-vrpp/             generated patched source
mnn/build-android-arm64-lib-vrpp/libMNN.a
mpv/source-frame/arm64-v8a/        eight rebuilt/exported libraries
```

The build is a dependency assembly workflow, not an unattended SDK installer. Download exact-version tools from their upstream projects, accept applicable terms yourself, and retain their notices. Godot template Android export configuration must point at your JDK/SDK; the scripts supply the release signing environment when building Release.

## MNN

The matting graph depends on project-patched MNN 3.6.1. In Git Bash, with `THRU3D_TOOL_ROOT` pointing at your tool directory:

```bash
bash tools/Build-MnnAndroid.sh
```

This uses `tools/mnn/patch_mnn_vrpp.py` to copy/patch the pristine source and build the static ARM64 library. The unmodified upstream MNN runtime cannot be assumed equivalent. Keep the upstream Apache-2.0 notice with redistributed outputs.

## libmpv / FFmpeg

`third_party/mpv/source-plan.json` and `source-lock.json` identify the dependencies; `native/mpv/patches` contains the source-frame extension. The AI-enabled workflow requires that extension. The model-free standard backend instead uses the separately verified official libraries described above; the two backends have the capability differences listed in the build-mode table.

1. Fetch the locked dependency archives with `python tools/environment/mpv-linux/fetch_sources.py --cache <downloads>`.
2. On Linux, set `THRU3D_MPV_WORK` and `THRU3D_MPV_DOWNLOADS`; run the included bootstrap script in a disposable build environment with permission to install its host packages. Obtain Android NDK r30 from the official Android NDK distribution and the mpv-android builder at revision `fdf74f6830c47dbaa8a22ac79726e8303f1db5af`. Name the archives `android-ndk-r30-linux.zip` and `mpv-android-fdf74f6.tar.gz`; the bootstrap script records and verifies their exact SHA256. The dependency source archives are a separate locked set.
3. Run `bash tools/environment/mpv-linux/build_source.sh`. The build applies and verifies the exact mpv patch.
4. Set `THRU3D_MPV_EXPORT` to your chosen output directory, then run `python3 tools/environment/mpv-linux/export_candidate.py`. It verifies the extension, ARM64 ELF, 16 KiB alignment and dependency closure, then writes a new `third_party/mpv/source-build.json` for your library hashes.
5. Place the eight outputs under your Windows tool root's `mpv/source-frame/arm64-v8a`. Build in the same source checkout, or transfer the generated receipt to it together with the libraries.

The committed source-build receipt records reference library bytes. A different machine/toolchain may produce different binaries; rebuild/export a valid receipt instead of bypassing integrity checks. WSL is not asserted to have upstream mpv build support.

## Runtime models and APK

AI is enabled by default. Obtain the matching runtime models separately as explained in [MODELS.md](MODELS.md). The initial source release does not host the distilled matting weights.

For a base player without AI, use:

```powershell
./tools/Build-Player.ps1 -ToolRoot $env:THRU3D_TOOL_ROOT -WithoutAI -XrVendor Quest -BuildType Debug
```

`-WithoutAI` also supports Pico, OpenXR and Release. It skips model preparation/import and the ncnn/MNN requirements, omits the inference JNI library and model assets, and disables live person matting and video/photo 2D-to-3D controls. Ordinary playback, existing stereo videos, projected subtitles, media browsing, photo viewing, and precomputed packed alpha masks remain available. Saved AI preferences cannot reactivate inference in this build. Do not combine this option with `-IncludeDiagnostics` or `-UsePreparedModelAssets`.

The historical PowerShell base build still requires prepared Godot Android templates, OpenXR Vendors and OpenList's `cloudcore.aar`. With `-WithoutAI`, it defaults to checksum-pinned official mpv and the standard render API. Explicit `-MpvCandidate SourceFrame` remains available for a prepared private backend. The Python entry point above automates these base-player dependency preparation steps.

For direct Gradle plugin builds on macOS/Linux, use the shell wrapper and prepared dependencies. Pass an absolute Godot template AAR path:

```sh
sh android/gradlew -p android -PenableAi=false -PstandardMpv=true \
  -PgodotAarPath=/absolute/path/to/godot-lib.template_debug.aar \
  -PandroidNdkVersion=30.0.16248370 -PandroidCmakeVersion=4.1.2 \
  :player-plugin:assembleDebug :player-plugin:testDebugUnitTest
```

The NDK and CMake properties are optional overrides; their defaults retain the original versions. Use a JDK supported by the Gradle wrapper (Java 17 is the reference configuration). This command builds the plugin AAR, not the complete Godot APK. AI-enabled direct builds retain the ncnn/MNN properties and prepared model requirements. Rebuilding in the same checkout with `enableAi=false` synchronizes the asset staging directory and excludes stale inference libraries left in `jniLibs` by earlier builds.

```powershell
./tools/Import-ModelAssets.ps1 -FromDirectory ./external-model-assets
./tools/Build-Player.ps1 -ToolRoot $env:THRU3D_TOOL_ROOT -UsePreparedModelAssets -XrVendor Quest -BuildType Debug
./tools/Build-Player.ps1 -ToolRoot $env:THRU3D_TOOL_ROOT -UsePreparedModelAssets -XrVendor Pico -BuildType Debug
./tools/Build-Player.ps1 -ToolRoot $env:THRU3D_TOOL_ROOT -UsePreparedModelAssets -XrVendor OpenXR -BuildType Debug
```

The build creates/validates the Kotlin plugin AARs, imports/exports Godot, checks manifest/vendor settings, ELF/JNI linkage, model hashes, signing and 16 KiB packaging. These are build checks, not a headset playback acceptance test.

Compatibility targets start at Quest 2 and PICO Neo3. PICO/OpenXR retain min SDK 29 for older Android devices; Quest retains 32/34. Version 0.3.1 packaging checks preserve the legacy-storage flag and existing read/all-files declarations. Android 10 uses the runtime read grant with legacy storage; newer Android versions use the separate all-files access path.

Release builds use `-BuildType Release`. `Prepare-ReleaseSigning.ps1` creates your own reusable local signing key under ignored build outputs. Back it up privately. No distribution key, password or original user's settings are provided in this repository.

Distribution filenames identify platforms as `QUEST`, `PICO` and `OpenXR`, retaining the version and requested build date; for example `Thru3D-QUEST-0.3.1-release-20261009.apk`. Internal export-preset names and older debug fixture filenames can retain their existing names.

The historical full conversion/diagnostic path remains available without `-UsePreparedModelAssets`, but requires upstream/reference models, the pinned project student, converter tools and generated numerical oracles. It is not the minimal build path and does not fetch the missing student automatically.

Model conversion additionally uses ONNX Runtime, NumPy, ONNX simplification, Pillow/OpenCV and the matching MNN converter/Python bindings; distillation uses PyTorch and onnx2torch. These tools belong in separate local environments. The small model-tools requirements lock covers reference conversion packages, not every optional training/analysis tool.

## OpenList Android core

Build-Player invokes tools/environment/Prepare-OpenList.ps1. It downloads checksum-pinned OpenList and Go archives, applies the recorded encrypted Storage.Addition tag, and binds the local cloud/openlist adapter as an arm64 AAR using the fixed gomobile revision and 16KiB linker alignment. The generated AAR is exported alongside the Kotlin plugin. Only its private JNI management API and loopback media router are enabled. Test-CloudCore.ps1 uses a local synthetic WebDAV server to check encryption, original-file ranges and fresh-process persistence without personal accounts.
