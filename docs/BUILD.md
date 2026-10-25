# Building Immivio

Immivio uses ordinary Gradle dependency files and one verified OpenXR addon archive. Project-owned Python scripts implement the Android workflow and workspace locking using the standard library. Tools and large native libraries belong to a prepared development environment. Configure, Build, Test and Package never install tools or download dependencies.

## Dependency ownership

| Input | Managed by |
| --- | --- |
| OpenXR vendor Android addon | Single verified archive recorded in `third_party/openxr-vendors/manifest.json` |
| Android application/plugin packages | Gradle version catalog, lockfiles and verification metadata under `android/` |
| Python, JDK, Gradle, Godot and export templates, Android SDK/NDK/CMake | Preinstalled host environment; compatible host installations; Android project targets in `configs/toolchain.json` |
| Android ARM64 libmpv/FFmpeg libraries | Prepared host SDK directory, checked against `third_party/mpv/manifest.json` |
| Python media tools for fixtures | Preinstalled environment; `requirements-media-tools.txt` |

There is no source-root initialization or materialization step. Edit Gradle files directly and commit their native lock/checksum changes. The OpenXR addon manifest records its version, URL, byte size and SHA-256; its downloaded archive stays under `.cache/openxr-vendors`.

## Prepare the host once

Use compatible installed tools. Python needs the standard-library features available in 3.11+. JDK/Gradle compatibility is checked by the Android build plugin. No exact host tool versions are prescribed. `configs/toolchain.json` records Android application targets, not host versions. Use `JAVA_HOME`, `ANDROID_HOME` / `ANDROID_SDK_ROOT`, and `PATH` for the installed tools. `GODOT_EXE`, `GODOT_TEMPLATES_DIR` and `GRADLE_EXE` can select nonstandard installation paths. Godot's matching Android export templates must already contain `android_source.zip` and `version.txt`.

Large desktop media libraries and ordinary native build tools can be installed with the operating system's package manager, for example:

```sh
# macOS desktop/native development
brew install ffmpeg mpv pkgconf ninja meson
# Debian/Ubuntu desktop/native development
sudo apt install ffmpeg libmpv-dev pkg-config ninja-build meson
```

The desktop libraries installed by these commands cannot be packaged into Android. Prepare the eight Android ARM64 libraries listed in `third_party/mpv/manifest.json` in a separate SDK directory, then set `IMMIVIO_MPV_LIB_DIR` to it. The manifest records the supported upstream mpv-android release, download location and each library's checksum. A maintainer can unpack `lib/arm64-v8a/*.so` from that release APK once, outside the project build. The build verifies all selected library bytes before copying them. It does not download mpv, FFmpeg or their full Git histories.

NDK, CMake and Android Build Tools are selected from complete stable installations under the supplied Android SDK. The latest installed version is the default; `IMMIVIO_NDK_VERSION`, `IMMIVIO_CMAKE_VERSION` and `IMMIVIO_BUILD_TOOLS_VERSION` can select another installed component. Godot's templates must match the installed editor version. These compatibility relationships do not pin the editor or SDK tools to specific releases.

```sh
python3 configs/check_environment.py
```

Optional fixture/benchmark scripts use the active Python environment. If needed, install `requirements-media-tools.txt` there beforehand; this is separate from application builds and CI. Host tests require working CJK system fonts, such as Noto Sans CJK; install them with the host environment.

## Build

```sh
git clone https://github.com/NorthBoundWisdom/immivio.git
cd immivio
python3 configs/check_environment.py
python3 configs/prepare_assets.py --download
python3 configs/android_workflow.py configure --vendor Quest --build-type Debug
python3 configs/android_workflow.py prepare-packages --vendor Quest --build-type Debug
python3 configs/android_workflow.py build --vendor Quest --build-type Debug
python3 configs/android_workflow.py test --vendor Quest --build-type Debug
python3 configs/android_workflow.py package --vendor Quest --build-type Debug
```

Use `Pico` or `OpenXR` for the other targets and `Release` for distributable packages. The same Python commands run in PowerShell.

`prepare_assets.py --download` explicitly downloads the OpenXR archive if its cache is missing or invalid. Run it without `--download` to verify the cache offline. `prepare-packages` prepares ordinary Gradle application package caches using their native manifests; it does not install Gradle, Python or any other host tool. Configure/Build/Test/Package consume prepared inputs offline. Gradle respects the host's normal cache locations and environment overrides. Valid caches let subsequent builds skip these preparation commands.

Configure is explicit. Build/Test/Package reject missing or stale configuration; Package requires a successful current Build. `run` installs an already packaged APK on the attached device. Generated projects and outputs stay under ignored build directories. `python3 configs/android_workflow.py clean --dry-run` previews cleanup; `clean` removes `build/` while preserving the addon cache and signing material. Configure again afterward.

## Playback libraries and formats

Immivio uses the unmodified Android ARM64 mpv/FFmpeg release libraries recorded in `third_party/mpv/manifest.json`. The app embeds libmpv through its public OpenGL render API. Native build targets compile the app's JNI bridges against these prepared libraries.

Ordinary and packed SBS/TB playback use the same pipeline. Frame timestamps observe the playback clock; they do not claim exact decoded-image PTS. Subtitles are exposed as text and rendered in Godot's separate caption layers. Bitmap subtitle tracks are not offered. MV-HEVC dual-view video and Dolby Vision colour correctness are not certified by the current build; container recognition or a filename does not establish playback support. HEIF photo decoding uses the Android photo pipeline.

## Outputs, signing and CI

APKs retain `Immivio-<QUEST|PICO|OpenXR>-<version>-<debug|release>-<YYYYMMDD>.apk`. Each schema-version-5 `.build.json` receipt includes the source commit, verified OpenXR addon version/checksum, Gradle locks, manifest digests, toolchain, APK checksum and signing certificate. Changes to build scripts or the addon manifest invalidate previous build configurations. The current release publisher requires version-5 receipts; rebuild older packages before publishing them with this workflow.

The exported application is categorized as video (`package/app_category=8` in Godot, `appCategory=2` and `isGame=false` in Android); package verification rejects a game-classified APK.

Signing is project-local and independent of any employer or company product. Use only Immivio's project-local key; no company certificate or organization identity is used. The retained legacy certificate has subject `CN=Thru3D`; newly prepared keys use `CN=Immivio`.

For PICO, the project exporter supplies a concrete `ImmivioLauncherActivity`; the engine alias is hidden from the launcher to avoid duplicate entries. The activity forwards to the normal immersive alias and reuses an existing player instance. Other vendors retain their normal Godot entry. PICO may list sideloaded immersive SDK applications under Library → Unknown sources even when the Android category is video.

The application ID is `com.northboundwisdom.immivio`. It installs separately from legacy `com.wapok.thru3d`; existing legacy data is not automatically migrated. PICO may reject the legacy identity through its store entitlement service. Set `IMMIVIO_DEVELOPMENT_PACKAGE=1` for a separate Debug-only `com.northboundwisdom.immivio.dev` build; configuration and receipts include the selected identity. Existing `artifacts/signing/thru3d-signing.json` credentials are reused. Complete `GODOT_ANDROID_KEYSTORE_<DEBUG|RELEASE>_*` overrides take priority. Keep keys outside Git.

Windows/macOS CI runs on GitHub-hosted `windows-2025` and `macos-15` machines. The setup action installs Python, Java, Android SDK components, Gradle, matching Godot editor/export templates, and Noto CJK system fonts before checking the environment. `configs/ci_toolchain.json` selects CI host tools and verified download hashes. The mpv APK and extracted ARM64 libraries are verified against `third_party/mpv/manifest.json`. No private runner registration or shared environment file is needed. Tool installation is isolated in `configs/setup_hosted_ci.py`; local Configure/Build/Test/Package commands still never install tools. Pull requests, including forks, can use the hosted machines; release signing secrets are only supplied to Release builds outside pull requests.

Existing queued runs retain the workflow from their original commit and will not switch runners when this file changes. Push the updated workflow to trigger new builds; old tag runs must be replaced by a new tag or an explicit workflow dispatch on the updated branch.

Tag pushes create a GitHub Release with the tagged changelog on a GitHub-hosted runner, independently of Android runner availability. Android tag builds use Release and repository signing secrets when supplied. Attaching APKs requires successful builds on both hosts and matching tag/commit; canonical APKs come from macOS. Until APK assets appear, the Release contains source archives only. APK checks cover ARM64, ELF symbol/dependency closure and 16KB alignment, signatures, ZIP alignment and application identity. They do not establish headset playback performance.
