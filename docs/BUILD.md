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

The distribution channel is independent of the headset. Local commands default to `--channel appstore --build-type Release`; explicit `--build-type Debug` remains available for development and cannot be uploaded as a store release. Web commands default to Debug unless a build type or CI override is supplied. Appstore builds produce a store-distributed app with no Check for updates or external update-release action. Use `--channel web` consistently for Configure, Build, Test, Package and Run to include the explicit GitHub update checker:

```sh
python3 configs/android_workflow.py configure --vendor Pico --build-type Debug --channel web
python3 configs/android_workflow.py build --vendor Pico --build-type Debug --channel web
python3 configs/android_workflow.py package --vendor Pico --build-type Debug --channel web
```

Channels use mutually exclusive Godot export features (`immivio_appstore` / `immivio_web`), separate configuration/build receipts and APK names. Channel changes require matching Configure and Build stages. Direct Godot exports also default to appstore through the checked-in presets. GitHub branch/PR builds default to appstore; manual CI runs offer a channel selector. Tag refs always force `Release` and `web`, including when a caller requests appstore. GitHub publication rejects non-web or channel-less receipts.

`prepare_assets.py --download` explicitly downloads the OpenXR archive if its cache is missing or invalid. Run it without `--download` to verify the cache offline. `prepare-packages` prepares ordinary Gradle application package caches using their native manifests; it does not install Gradle, Python or any other host tool. Configure/Build/Test/Package consume prepared inputs offline. Gradle respects the host's normal cache locations and environment overrides. Valid caches let subsequent builds skip these preparation commands.

Configure is explicit. Build/Test/Package reject missing or stale configuration; Package requires a successful current Build. `run` installs an already packaged APK on the attached device. Generated projects and outputs stay under ignored build directories. `python3 configs/android_workflow.py clean --dry-run` previews cleanup; `clean` defaults to the build scope, removing `build/` while preserving final packages, archives, addon caches and persistent signing material. Configure again afterward.

The initial Godot editor configuration and asset-import passes each have a 30-minute wall-clock limit. Full-size panorama compression on a hosted macOS runner with an empty import cache can exceed ten minutes. This allowance preserves the reviewed image dimensions and compression quality; import timeouts still fail the build.

## PICO store APKs

The default PICO store workflow uses the existing application identity, project-owned release key, ARM64 and `minSdkVersion=29` for PICO Neo3, PICO 4 and PICO 4 Ultra:

```sh
python3 configs/android_workflow.py configure --vendor Pico
python3 configs/android_workflow.py build --vendor Pico
python3 configs/android_workflow.py package --vendor Pico
```

Package validates the **compiled APK** using [PICO's first-version upload rules](https://developer-cn.picoxr.com/document/distribute/app-publish-first-version/#3af79c21). It checks the APK format and conservative 4,000,000,000-byte limit, package/version consistency, ARM64, SDK values and actual XR metadata, appstore feature, release-only components and one launcher icon. Existing checks still verify signatures, native dependencies, 16-KB alignment and the video application category. It records MD5 (PICO's duplicate-upload comparison), SHA-256 and the signer in `<APK stem>.store-report.json`; the build receipt names this report. Only the APK is uploaded as the installation package.

The store certificate's **public** SHA-256 fingerprint is pinned in `configs/pico_store.py`. The maintainer prepared the first store identity before any PICO store version was on shelf; earlier draft/side-loaded packages used a retired certificate. Store packaging requires the fixed store key through its persistent local signing record or complete `GODOT_ANDROID_KEYSTORE_RELEASE_*` overrides, verifies the APK signer against the configured key and refuses key drift. It never generates a temporary store key. Keep the private keystore and password backed up outside Git. Changing the first store signing identity later needs an explicit migration agreed with PICO.

Manual CI defaults to Release/appstore and uploads the store report alongside its APK. Provision the same fixed key using the existing `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEY_ALIAS` and `ANDROID_KEY_PASSWORD` repository secrets before requesting a CI store package. A missing or different key fails closed; this workflow does not transmit local private keys automatically. Branch/PR CI deliberately specifies Debug for development validation; tag CI remains web/Release. Debug APKs are not store submissions.

If an actual `pvr.app.id` is embedded, set `IMMIVIO_PICO_APP_ID` to the real platform-assigned ID so validation can compare it. An APK without this optional field does not receive a fabricated ID. For an **already uploaded version in the same PICO track/region**, set `IMMIVIO_PICO_STORE_BASELINE` to its store-report JSON: validation then requires the same package/certificate, a nondecreasing versionCode and a different APK MD5. Do not treat an unsubmitted local build as an uploaded baseline. Portal state cannot be inferred from local packages.

The current Godot/OpenXR APK reports its actual SDK metadata. The linked Unity/Unreal SDK thresholds for Swan devices in the US are outside this package's device scope; do not relabel the SDK or claim Swan support. A successful local report does not constitute PICO store approval: platform application/package binding, correct feature declarations, store artwork, developer identity/contact, privacy policy, applicable regional filings and device/content review still belong to submission. Existing public policy pages are [Privacy](https://northboundwisdom.github.io/immivio/zh/privacy/) and [Terms](https://northboundwisdom.github.io/immivio/zh/terms/).

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

`locate` prints the latest existing verified package path for the requested profile; add `--channel web --build-type Debug` as needed. Its APK, `.build.json` and optional `.store-report.json` stay together. Package filenames do not change. `organize` moves old loose outputs without overwriting or deleting file data, keeps original names in historical archives, and records source/destination pairs in `artifacts/reports/organization/`. Unrecognized old build trees are archived under `artifacts/archive/legacy-build/`; their embedded absolute-path configurations are historical, not active configurations. Run Configure after migrating the layout. New APK inspection uses a temporary directory removed on success or failure, so repeated packaging no longer retains expanded copies of every native library.

CI uploads the nested `packages/` and `reports/ci/` trees. The tag publisher verifies all three nested package/receipt pairs, rejects duplicates or unrelated APKs, and flattens the verified set into the public release bundle. CI hash lists use paths relative to `artifacts/`; public release hash lists use APK basenames.

## Playback libraries and formats

Immivio uses the unmodified Android ARM64 mpv/FFmpeg release libraries recorded in `third_party/mpv/manifest.json`. The app embeds libmpv through its public OpenGL render API. Native build targets compile the app's JNI bridges against these prepared libraries.

Ordinary and packed SBS/TB playback use the same pipeline. Frame timestamps observe the playback clock; they do not claim exact decoded-image PTS. Subtitles are exposed as text and rendered in Godot's separate caption layers. Bitmap subtitle tracks are not offered. MV-HEVC dual-view video and Dolby Vision colour correctness are not certified by the current build; container recognition or a filename does not establish playback support.

## Outputs, signing and CI

APKs use `Immivio-<QUEST|PICO|OpenXR>-<version>-<appstore|web>-<debug|release>-<YYYYMMDD>.apk`. Each schema-version-5 `.build.json` receipt includes the distribution channel, source commit, verified OpenXR addon version/checksum, Gradle locks, manifest digests, toolchain, APK checksum and signing certificate. Packaging verifies the channel feature in the exported project. Changes to build scripts or the addon manifest invalidate previous build configurations. The current release publisher requires version-5 web-channel receipts; rebuild older packages before publishing them with this workflow.

The exported application is categorized as video (`package/app_category=8` in Godot, `appCategory=2` and `isGame=false` in Android); package verification rejects a game-classified APK.

Signing is project-local and independent of any employer or company product. Use only Immivio's project-local key; no company certificate or organization identity is used. The retained legacy certificate has subject `CN=Thru3D`; newly prepared keys use `CN=Immivio`.

For PICO, the project exporter supplies a concrete `ImmivioLauncherActivity`; the engine alias is hidden from the launcher to avoid duplicate entries. The activity forwards to the normal immersive alias and reuses an existing player instance. Other vendors retain their normal Godot entry. PICO may list sideloaded immersive SDK applications under Library → Unknown sources even when the Android category is video.

The application ID is `com.northboundwisdom.immivio`. It installs separately from legacy `com.wapok.thru3d`; existing legacy data is not automatically migrated. PICO may reject the legacy identity through its store entitlement service. Set `IMMIVIO_DEVELOPMENT_PACKAGE=1` for a separate Debug-only `com.northboundwisdom.immivio.dev` build; configuration and receipts include the selected identity. Keys and credentials now live outside disposable outputs: `~/.config/immivio/signing/` on macOS/Linux (`XDG_CONFIG_HOME` is respected), or `%APPDATA%/Immivio/signing/` on Windows. `IMMIVIO_SIGNING_DIR` can select another durable private directory. Back up that directory securely. Existing project-local `artifacts/signing/` identities, when still present, are copied into the persistent directory without replacing a different key; subsequent builds use the persistent copy. Never keep the only signing-key copy in `artifacts/`. Complete `GODOT_ANDROID_KEYSTORE_<DEBUG|RELEASE>_*` overrides take priority. Keep keys outside Git.

Windows/macOS CI runs on GitHub-hosted `windows-2025` and `macos-15` machines. The setup action installs Python, Java, Android SDK components, Gradle, matching Godot editor/export templates, and Noto CJK system fonts before checking the environment. `configs/ci_toolchain.json` selects CI host tools and verified download hashes. The mpv APK and extracted ARM64 libraries are verified against `third_party/mpv/manifest.json`. No private runner registration or shared environment file is needed. Tool installation is isolated in `configs/setup_hosted_ci.py`; local Configure/Build/Test/Package commands still never install tools. Pull requests, including forks, can use the hosted machines; release signing secrets are only supplied to Release builds outside pull requests.

Existing queued runs retain the workflow from their original commit and will not switch runners when this file changes. Push the updated workflow to trigger new builds; old tag runs must be replaced by a new tag or an explicit workflow dispatch on the updated branch.

Tag pushes create a GitHub Release with the tagged changelog on a GitHub-hosted runner, independently of Android runner availability. Android tag builds use Release and repository signing secrets when supplied. Attaching APKs requires successful builds on both hosts and matching tag/commit; canonical APKs come from macOS. Until APK assets appear, the Release contains source archives only. APK checks cover ARM64, ELF symbol/dependency closure and 16KB alignment, signatures, ZIP alignment and application identity. They do not establish headset playback performance.

USB improvements use Android's verified system-mounted volumes. Android 11+ may fall back to a verified public/app-storage mount path when its preferred directory is unavailable and permission permits reading; this is reevaluated rather than persisted. Some PICO system/provider paths may still fail even when a drive appears mounted. Check system storage permissions/mount state and reconnect before retrying. “Stop app access” closes Immivio readers only; system removal/ejection belongs to Android. A raw USB mass-storage, partition or filesystem driver is not included.

## Branding assets

This set was supplied by the maintainer on 2026-11-06. `source-manifest.json` records the original filenames, sizes and SHA-256 values. The six original PNGs are preserved byte-for-byte: the primary app tile lives at `app/godot/branding/immivio-icon.png`, and the three transparent layers plus two posters live in `branding/source/`.

Run the deterministic preparation command from the repository root:

```sh
godot --headless --xr-mode off --path app/godot --script ../../tools/prepare_branding.gd
```

It produces the Android 432px adaptive foreground/background and white-alpha monochrome mask, the 256px site icon, responsive WebP posters, a 1200×675 JPEG sharing image, and the 1024px icon/layers plus 2560×1440 and 1024×1024 JPEG posters in `branding/pico/`. The independent play layer is centred at half scale when composing layered icons so its proportions match the supplied posters. Original sources are never modified.

The Android foreground keeps the complete surround/play mark inside the adaptive safe area; the background fills the system mask without a second opaque icon tile. Source layers and posters stay outside the Godot resource tree so the application does not bundle unused marketing originals.

The homepage and social preview use promotional illustrations, labelled as artwork. Actual application screenshots remain under `website/assets/screenshots/` with their original capture manifest and captions.

### PICO 宣传海报 / PICO promotional posters

Upload the JPEG files below from `branding/pico/`, rather than the original PNGs in `branding/source/` or the website WebP images. The preparation script resizes directly from each original and checks the encoded format, dimensions and 5,000,000-byte limit.

| 用途 / Use | 上传文件 / Upload file | 尺寸 / Dimensions | 格式及大小 / Format and limit |
| --- | --- | --- | --- |
| 宽幅海报 / Wide poster | `branding/pico/poster-wide-2560x1440.jpg` | 2560 × 1440 | JPG/JPEG, ≤5 MB |
| 方形海报 / Square poster | `branding/pico/poster-square-1024.jpg` | 1024 × 1024 | JPG/JPEG, ≤5 MB |

上传时请使用上表中的 JPG 文件；原始 PNG 和官网 WebP 用途不同。运行素材准备命令会直接从原图生成海报，并检查格式、尺寸和大小，避免反复缩放降低清晰度。

### PICO 详情页图片 / PICO detail-page images

Upload the four numbered JPEGs in `branding/pico/details/zh-CN/` for Simplified Chinese, or the four in `branding/pico/details/en/` for English. Each is 2560 × 1440, below 5 MB. The order is playback, network media, VR subtitles and display settings. Keep languages separate in the store’s localized image fields.

中文请上传 `branding/pico/details/zh-CN/` 中的 4 张编号 JPG；英文请使用 `branding/pico/details/en/`，依次展示播放、网络媒体、字幕设置和显示设置。每张均为 2560 × 1440、小于 5 MB。`source/` 是原始截图，不是待上传成品。

The images use actual Android ARM64 emulator captures of the current 0.9.6 production interface in an isolated development application. Cropping and uniform scaling make the menus readable; separate headings and feature copy are added around them. Controls are not redrawn. The playback cards show the maintainer-provided `blandscape` VR180 side-by-side video actually playing in Immivio (a 16-second excerpt from 01:28). The other cards use the bundled CC0 Belfast Sunset sky sample. The example video is not included in the branding assets; no account or private library appears. `branding/pico/details/capture.json` records application/APK identity, source checksums, capture method and crop rectangles. These images do not certify headset stereoscopy or performance.

中英文图均基于隔离开发包的真实虚拟机截图。播放图展示用户提供的 `blandscape` VR180 左右立体示例视频在 Immivio 中实际播放的画面（从 01:28 起截取 16 秒），其他三类图使用项目自带的 CC0 天空素材演示。素材目录不包含示例视频。原截图保存在 `source/`，校验值与来源记录在 `capture.json`。排版仅裁切缩放截图并添加独立文案，没有重绘控件，也不用于证明头显立体或性能表现。

Regenerate the editable layouts with Godot and a real renderer (the command verifies source hashes and output format, dimensions and size):

```sh
godot --xr-mode off --rendering-method gl_compatibility --rendering-driver opengl3 --path app/godot --script ../../tools/prepare_store_details.gd
```

Edit the bilingual text and layout in `tools/prepare_store_details.gd`. Local review contact sheets are written under `artifacts/captures/branding/store-details/`, separate from upload files. 修改中英文文案和位置可直接编辑该脚本，重新运行后会生成全部 8 张；预览拼图放在截图输出目录，不会混入上传文件夹。
