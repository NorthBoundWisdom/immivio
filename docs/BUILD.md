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

A typical shell setup:

```sh
export GRADLE_USER_HOME="$PWD/.cache/gradle"
export IMMIVIO_MPV_LIB_DIR="$PWD/.cache/verified-mpv/arm64-v8a"
```

Tool selection prefers an explicit `GRADLE_EXE`, then `gradle` on PATH, then a prepared project cache matching the Gradle version in `configs/ci_toolchain.json` under `.cache/gradle/wrapper/dists/`. It never downloads a missing distribution.

Large desktop media libraries and ordinary native build tools can be installed with the operating system's package manager, for example:

```sh
# macOS desktop/native development
brew install ffmpeg mpv pkgconf ninja meson
# Debian/Ubuntu desktop/native development
sudo apt install ffmpeg libmpv-dev pkg-config ninja-build meson
```

The desktop libraries installed by these commands cannot be packaged into Android. Set `IMMIVIO_MPV_LIB_DIR` to a prepared output directory and build all eight Android ARM64 playback libraries from the locked sources:

```sh
python3 tools/build_patched_mpv.py --base "$IMMIVIO_MPV_LIB_DIR" --output "$IMMIVIO_MPV_LIB_DIR" --download --prepare-tools
```

This explicit preparation step uses the exact NDK in `third_party/mpv/source-build.json` (currently 30.0.16248370), the shared host Python, Ninja and pkg-config. Meson and its Python generator dependencies live in `.cache/native-build-tools`; they do not change the global toolchain. Omit `--download --prepare-tools` to rebuild offline from prepared archives and tools. The source build supports macOS and Linux.

The source archives, source patch and tool versions are locked. The build carries AAudio clock/reset fixes, GPU-fenced AImage return, compositor Surface cadence and retryable MediaCodec priority/frame-rate hints, uses the public libmpv API, and statically links its C++ runtime without exporting duplicate STL symbols. The normal configure/build stages verify source-input/output receipts for all eight libraries before staging anything. An old receipt, edited patch or modified library is rejected. Normal builds perform no dependency downloads or source compilation. Script/plugin loading is compiled out of this narrow playback runtime; it retains libass, OpenGL, Android MediaCodec and AAudio. See `third_party/mpv/SOURCE_BUILD.md` for provenance and notices.

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

Use `Pico` or `OpenXR` for the other targets and `Release` for distributable packages. Windows builds are unverified.

The distribution channel is independent of the headset. Local commands default to `--channel appstore --build-type Release`; explicit `--build-type Debug` remains available for development and cannot be uploaded as a store release. Web commands default to Debug unless a build type or CI override is supplied. Appstore builds produce a store-distributed app with no Check for updates or external update-release action. Use `--channel web` consistently for Configure, Build, Test, Package and Run to include the explicit GitHub update checker:

```sh
python3 configs/android_workflow.py configure --vendor Pico --build-type Debug --channel web
python3 configs/android_workflow.py build --vendor Pico --build-type Debug --channel web
python3 configs/android_workflow.py package --vendor Pico --build-type Debug --channel web
```

Channels use mutually exclusive Godot export features (`immivio_appstore` / `immivio_web`), separate configuration/build receipts and APK names. Channel changes require matching Configure and Build stages. Direct Godot exports also default to appstore through the checked-in presets. Tag builds always use `Release` and `web`.

`prepare_assets.py --download` explicitly downloads the OpenXR archive if its cache is missing or invalid. Run it without `--download` to verify the cache offline. `prepare-packages` prepares ordinary Gradle application package caches using their native manifests; it does not install Gradle, Python or any other host tool. Configure/Build/Test/Package consume prepared inputs offline. Gradle respects the host's normal cache locations and environment overrides. Valid caches let subsequent builds skip these preparation commands.

Configure is explicit. Build/Test/Package reject missing or stale configuration. Package requires a successful current Build. `run` installs an APK whose receipt matches the current build. Generated projects and outputs stay under ignored build directories. Preview cleanup with `python3 configs/android_workflow.py clean --dry-run`. The default cleanup removes `build/` and preserves final packages, archives, addon caches and persistent signing material. Configure again afterward.

## PICO store APKs

The default PICO store workflow uses the existing application identity, project-owned release key, ARM64 and `minSdkVersion=29` for PICO Neo3, PICO 4 and PICO 4 Ultra:

```sh
python3 configs/android_workflow.py configure --vendor Pico
python3 configs/android_workflow.py build --vendor Pico
python3 configs/android_workflow.py package --vendor Pico
```

Package validates the **compiled APK** using [PICO's first-version upload rules](https://developer-cn.picoxr.com/document/distribute/app-publish-first-version/#3af79c21). It checks the APK format and conservative 4,000,000,000-byte limit, package/version consistency, ARM64, SDK values and actual XR metadata, appstore feature, release-only components and one launcher icon. Existing checks still verify signatures, native dependencies, 16-KB alignment and the video application category. It records MD5 (PICO's duplicate-upload comparison), SHA-256 and the signer in `<APK stem>.store-report.json`; the build receipt names this report. Only the APK is uploaded as the installation package.

All Release APKs (Quest, PICO and OpenXR, `web` and `appstore`) are signed with one release key whose **public** certificate SHA-256 is pinned in `configs/pico_store.py`. Release packaging requires that key through the persistent local signing record or complete `GODOT_ANDROID_KEYSTORE_RELEASE_*` overrides, checks the exported APK's certificate with `apksigner`, and never generates a replacement key. Keep the keystore and password backed up outside Git.

If an actual `pvr.app.id` is embedded, set `IMMIVIO_PICO_APP_ID` to the real platform-assigned ID so validation can compare it. An APK without this optional field does not receive a fabricated ID. For an **already uploaded version in the same PICO track/region**, set `IMMIVIO_PICO_STORE_BASELINE` to its store-report JSON: validation then requires the same package/certificate, a nondecreasing versionCode and a different APK MD5. Do not treat an unsubmitted local build as an uploaded baseline. Portal state cannot be inferred from local packages.

The current Godot/OpenXR APK reports its actual SDK metadata. The linked Unity/Unreal SDK thresholds for Swan devices in the US are outside this package's device scope; do not relabel the SDK or claim Swan support. A passing local report does not mean store approval.

## Generated files and cleanup

Generated files use one layout, shared by local builds, device/render tools and CI:

| Directory | Contents | Cleanup |
| --- | --- | --- |
| `artifacts/packages/<PICO\|QUEST\|OpenXR>/<appstore\|web>/<release\|debug>/` | Installable APKs and their build/store reports | Kept by every automatic cleanup command |
| `artifacts/packages/releases/<tag>/` | Verified three-platform publication bundle | Kept by every automatic cleanup command |
| `artifacts/reports/` | CI summaries, release checks and move journals | Kept by default |
| `artifacts/tests/` | Godot, JVM, workflow and native test results | `clean --scope tests` |
| `artifacts/captures/` | UI, headset and branding verification images/reports | `clean --scope captures` |
| `artifacts/logs/` | Build logs by platform/channel/type, manual/tool logs | `clean --scope logs` |
| `artifacts/archive/` | Preserved historical output and old build experiments/dependencies | `clean --scope archive` only when no longer needed |
| `build/android/` | Configuration state, generated Gradle properties and Godot API | `clean --scope build` |
| `build/staging/` | Verified addon expansion and CI download staging | `clean --scope build` |
| `build/intermediates/` | Editor helper scripts and temporary APK inspection | `clean --scope intermediates` (preserves configuration) |
| `build/tests/`, `build/native/` | Temporary test inputs and native host builds | `clean --scope build` |

Each output root has a generated `00-目录说明.txt`. Signing identities remain outside the repository in the persistent private configuration directory. Neither cleanup nor organization follows output-root symlinks or moves/deletes detected signing material. Dependency acquisition caches under `.cache/` also remain separate.

```sh
# These commands do not require an installed Android/Godot toolchain.
python3 configs/android_workflow.py outputs
python3 configs/android_workflow.py locate --vendor Pico
python3 configs/android_workflow.py organize --dry-run
python3 configs/android_workflow.py organize
python3 configs/android_workflow.py clean --scope build --dry-run
python3 configs/android_workflow.py clean --scope build
python3 configs/android_workflow.py clean --scope logs
python3 configs/android_workflow.py clean --scope intermediates
```

`locate` prints the latest existing verified package path for the requested profile; add `--channel web --build-type Debug` as needed. Its APK, `.build.json` and optional `.store-report.json` stay together. Package filenames do not change. `organize` moves loose outputs into this layout without overwriting data and records each move under `artifacts/reports/organization/`.

CI uploads the nested `packages/` and `reports/ci/` trees. The tag publisher verifies all three nested package/receipt pairs, rejects duplicates or unrelated APKs, and flattens the verified set into the public release bundle. CI hash lists use paths relative to `artifacts/`; public release hash lists use APK basenames.

## Playback libraries and formats

Immivio builds all eight Android ARM64 mpv/FFmpeg libraries from the sources and patches locked in `third_party/mpv/source-build.json`. The generated build receipt verifies their bytes. Native targets compile the app's JNI bridges against these prepared outputs. See [runtime source build](../third_party/mpv/SOURCE_BUILD.md).

Compatible ordinary video can use a decoder Surface in an OpenXR compositor layer. Processed video uses the public libmpv OpenGL/RGBA path; compatible RGBA and fisheye frames can be copied/remapped into image layers once per video frame. Unsupported capabilities or effects retain shader rendering. RGBA frame timestamps observe the playback clock; the direct Surface exposes a separate timeline/format context and creates no RGBA frame ticket. Neither route claims exact decoded-image PTS. Subtitles are exposed as text and rendered in Godot's separate caption layers. Bitmap subtitle tracks are not offered. MV-HEVC dual-view video and Dolby Vision colour correctness are not certified by the current build; container recognition or a filename does not establish playback support.

## Outputs, signing and CI

APKs use `Immivio-<QUEST|PICO|OpenXR>-<version>-<appstore|web>-<debug|release>-<YYYYMMDD>.apk`. Each schema-version-5 `.build.json` receipt includes the distribution channel, source commit, verified OpenXR addon version/checksum, Gradle locks, manifest digests, toolchain, APK checksum and signing certificate. Packaging verifies the channel feature in the exported project. Changes to build scripts or the addon manifest invalidate previous build configurations.

The exported application is categorized as video (`package/app_category=8` in Godot, `appCategory=2` and `isGame=false` in Android); package verification rejects a game-classified APK.

For PICO, the project exporter supplies a concrete `ImmivioLauncherActivity`; the engine alias is hidden from the launcher to avoid duplicate entries. The activity forwards to the normal immersive alias and reuses an existing player instance. Other vendors retain their normal Godot entry. PICO may list sideloaded immersive SDK applications under Library → Unknown sources even when the Android category is video.

The application ID is `com.northboundwisdom.immivio`. It installs separately from legacy `com.wapok.thru3d`; existing legacy data is not automatically migrated. PICO may reject the legacy identity through its store entitlement service. Set `IMMIVIO_DEVELOPMENT_PACKAGE=1` for a separate Debug-only `com.northboundwisdom.immivio.dev` build; configuration and receipts include the selected identity. Keys and credentials now live outside disposable outputs: `~/.config/immivio/signing/` on macOS/Linux (`XDG_CONFIG_HOME` is respected), or `%APPDATA%/Immivio/signing/` on Windows. `IMMIVIO_SIGNING_DIR` can select another durable private directory. Back up that directory securely. Complete `GODOT_ANDROID_KEYSTORE_<DEBUG|RELEASE>_*` overrides take priority. Keep keys outside Git.

### CI

| Workflow | Runs on | Purpose |
| --- | --- | --- |
| `lint.yml` | Pushes to `main`, pull requests | Formatting, source boundary, translations, resources, workflow and website tests |
| `android-release.yml` | `v*` tags, pull requests, manual dispatch | Builds, tests and packages all three targets on `macos-15-intel`; on a tag, publishes the APKs to the GitHub Release |
| `website-pages.yml` | Website changes on `main`, dispatch after a release | Refreshes download links and deploys GitHub Pages |

`.github/actions/android-setup` installs the CI host tools recorded in `configs/ci_toolchain.json` and caches two verified inputs: host tools (`.cache/ci-tools`) and the compiled playback runtime (`.cache/ci-playback/arm64-v8a`). Restored caches are verified before use; local Configure/Build/Test/Package never install tools.

Tag builds need three repository secrets (**Settings → Secrets and variables → Actions**): `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEY_ALIAS` and `ANDROID_KEY_PASSWORD`, for the key matching the pinned certificate. A tag build fails without them. Non-tag CI builds use a temporary key and cannot be published. Publication verifies every receipt's signer and hash, and never replaces an APK already attached to the tag; publish a new patch version instead. APK checks cover ARM64, ELF dependencies, 16 KB alignment, signatures and application identity, not headset performance.

## Branding assets

`branding/source-manifest.json` records the original artwork filenames, sizes and SHA-256 values. The primary app tile is `app/godot/branding/immivio-icon.png`; the transparent layers and posters live in `branding/source/`.

Regenerate all derived icons, website images and PICO store images from the repository root:

```sh
godot --headless --xr-mode off --path app/godot --script ../../tools/prepare_branding.gd
godot --xr-mode off --rendering-method gl_compatibility --rendering-driver opengl3 --path app/godot --script ../../tools/prepare_store_details.gd
```

The first command produces Android adaptive/monochrome icons, the website icon and posters, and the PICO store posters in `branding/pico/`. The second renders the localized PICO detail-page images in `branding/pico/details/`; edit their copy and layout in `tools/prepare_store_details.gd`. Both verify source hashes and output format, size and dimensions. Original sources are never modified. Application screenshots for the website live in `website/assets/screenshots/` with their capture manifest.
