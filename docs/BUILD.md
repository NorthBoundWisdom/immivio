# Building Immivio

Immivio uses FreeCM for project source roots and the Android OpenXR addon. Tools and large native libraries belong to a prepared development environment, following MonsterRPG's approach. Configure, Build, Test and Package never install tools.

## Dependency ownership

| Input | Managed by |
| --- | --- |
| OpenList adapter source | FreeCM, fixed Git commit |
| OpenXR vendor Android addon | FreeCM, verified release archive |
| Android application/plugin packages | Gradle version catalog, lockfiles and verification metadata under `android/` |
| OpenList's Go modules | `cloud/openlist/go.mod` and `go.sum` |
| Python, JDK, Go, Gradle, Godot and export templates, Android SDK/NDK/CMake, gomobile/gobind | Preinstalled host environment; compatible host installations; Android project targets in `configs/toolchain.json` |
| Android ARM64 libmpv/FFmpeg libraries | Prepared host SDK directory, checked against `third_party/mpv/manifest.json` |
| Python media tools for fixtures | Preinstalled environment; `requirements-media-tools.txt` |

`source_roots.lock.jsonc.in` is a source/asset lock, not an embedded copy of package-manager manifests or a host installer. Edit Gradle/Go files directly and commit their native lock/checksum changes. Python wheel inventories and tool download URLs are not stored in FreeCM. If upgrading from the previous embedded master lock, replace the ignored machine-local `source_roots.lock.jsonc` with the new template once, preserving any wanted manual paths.

## Prepare the host once

Use compatible installed tools. Python needs the standard-library features available in 3.11+; Go must support the project module language version. JDK/Gradle compatibility is checked by the Android build plugin. No exact host tool versions are prescribed. `configs/toolchain.json` records Android application targets, not host versions. Use `JAVA_HOME`, `ANDROID_HOME` / `ANDROID_SDK_ROOT`, and `PATH` for the installed tools. `GODOT_EXE`, `GODOT_TEMPLATES_DIR` and `GRADLE_EXE` can select nonstandard installation paths. Godot's matching Android export templates must already contain `android_source.zip` and `version.txt`.

Large desktop media libraries and ordinary native build tools can be installed with the operating system's package manager, for example:

```sh
# macOS desktop/native development
brew install ffmpeg mpv pkgconf ninja meson
# Debian/Ubuntu desktop/native development
sudo apt install ffmpeg libmpv-dev pkg-config ninja-build meson
```

The desktop libraries installed by these commands cannot be packaged into Android. Prepare the eight Android ARM64 libraries listed in `third_party/mpv/manifest.json` in a separate SDK directory, then set `IMMIVIO_MPV_LIB_DIR` to it. The manifest records the supported upstream mpv-android release, download location and each library's checksum. A maintainer can unpack `lib/arm64-v8a/*.so` from that release APK once, outside the project build. The build verifies all selected library bytes before copying them. It does not download mpv, FFmpeg or their full Git histories.

Preinstall compatible `gomobile` and `gobind` tools and add their installation directory to `PATH`. The build uses those tools directly and records their binary hashes in its build cache; it does not install or require one particular tool revision.

NDK, CMake and Android Build Tools are selected from complete stable installations under the supplied Android SDK. The latest installed version is the default; `IMMIVIO_NDK_VERSION`, `IMMIVIO_CMAKE_VERSION` and `IMMIVIO_BUILD_TOOLS_VERSION` can select another installed component. Godot's templates must match the installed editor version. These compatibility relationships do not pin the editor or SDK tools to specific releases.

```sh
python3 configs/check_environment.py
```

Optional fixture/benchmark scripts use the active Python environment. If needed, install `requirements-media-tools.txt` there beforehand; this is not part of FreeCM initialization or CI. Host tests require working CJK system fonts, such as Noto Sans CJK; install them with the host environment.

## Build

```sh
git clone --recurse-submodules https://github.com/NorthBoundWisdom/immivio.git
cd immivio
python3 configs/check_environment.py
python3 configs/source_root_workflow.py --init
python3 configs/source_root_workflow.py --update
python3 configs/android_workflow.py configure --vendor Quest --build-type Debug
python3 configs/android_workflow.py prepare-packages --vendor Quest --build-type Debug
python3 configs/android_workflow.py build --vendor Quest --build-type Debug
python3 configs/android_workflow.py test --vendor Quest --build-type Debug
python3 configs/android_workflow.py package --vendor Quest --build-type Debug
```

Use `Pico` or `OpenXR` for the other targets and `Release` for distributable packages. The same Python commands run in PowerShell.

FreeCM `--init` accesses the network for enabled source roots and assets only. `--update`, diagnostics and materialization remain offline. `prepare-packages` independently prepares ordinary Go/Gradle application package caches using their native manifests; it does not install Go, Gradle, Python or any other host tool. Build/Test/Package consume those caches offline. Go and Gradle respect the host's normal cache locations and environment overrides. A prepared package cache lets subsequent builds skip `prepare-packages`.

Configure is explicit. Build/Test/Package reject missing or stale configuration; Package requires a successful current Build. `run` installs an already packaged APK on the attached device. Generated source roots, projects and outputs stay under ignored build directories. Cleanup preserves dependency seeds and signing material, but removes generated configuration; configure again afterward.

## Playback libraries and formats

Immivio uses the unmodified Android ARM64 mpv/FFmpeg release libraries recorded in `third_party/mpv/manifest.json`. The app embeds libmpv through its public OpenGL render API. Native build targets compile the app's JNI bridges against these prepared libraries.

Ordinary and packed SBS/TB playback use the same pipeline. Frame timestamps observe the playback clock; they do not claim exact decoded-image PTS. Subtitles are exposed as text and rendered in Godot's separate caption layers. Bitmap subtitle tracks are not offered. MV-HEVC dual-view video and Dolby Vision colour correctness are not certified by the current build; container recognition or a filename does not establish playback support. HEIF photo decoding uses the Android photo pipeline.

## Outputs, signing and CI

APKs retain `Immivio-<QUEST|PICO|OpenXR>-<version>-<debug|release>-<YYYYMMDD>.apk`. Each `.build.json` receipt includes source/FreeCM commits, resolved enabled dependencies, asset and native package-lock digests, toolchain, APK checksum and signing certificate. Release requires pinned dependencies.

The application ID remains `com.wapok.thru3d`. Existing `artifacts/signing/thru3d-signing.json` credentials are reused. Complete `GODOT_ANDROID_KEYSTORE_<DEBUG|RELEASE>_*` overrides take priority. Keep keys outside Git.

Windows/macOS CI runs on GitHub-hosted `windows-2025` and `macos-15` machines. The setup action installs Python, Java, Go, Android SDK components, Gradle, matching Godot editor/export templates, gomobile/gobind, and Noto CJK system fonts before checking the environment. `configs/ci_toolchain.json` selects CI host tools and verified download hashes; Go and mobile bindings follow `cloud/openlist/go.mod`. The mpv APK and extracted ARM64 libraries are verified against `third_party/mpv/manifest.json`. No private runner registration or shared environment file is needed. Tool installation is isolated in `configs/setup_hosted_ci.py`; local Configure/Build/Test/Package commands still never install tools. Pull requests, including forks, can use the hosted machines; release signing secrets are only supplied to Release builds outside pull requests.

Existing queued runs retain the workflow from their original commit and will not switch runners when this file changes. Push the updated workflow to trigger new builds; old tag runs must be replaced by a new tag or an explicit workflow dispatch on the updated branch.

Tag pushes create a GitHub Release with the tagged changelog on a GitHub-hosted runner, independently of Android runner availability. Android tag builds use Release and repository signing secrets when supplied. Attaching APKs requires successful builds on both hosts and matching tag/commit; canonical APKs come from macOS. Until APK assets appear, the Release contains source archives only. APK checks cover ARM64, ELF symbol/dependency closure and 16KB alignment, signatures, ZIP alignment and application identity. They do not establish headset playback performance.
