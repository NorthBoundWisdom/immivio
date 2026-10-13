# Building Immivio

Immivio has one playback edition. Builds do not prepare, compile or package inference models, MNN or ncnn. The former AI/no-AI build switches and model preparation workflows have been retired.

## Host tools

Use the versions pinned in `tools/environment/base-player.lock.json`: Godot 4.7.2 and matching Android export templates, the locked Android SDK/NDK/CMake, a compatible JDK, Go and Python. Hosted CI provisions these tools on Windows and macOS. Local builds use `JAVA_HOME`, `ANDROID_HOME` / `ANDROID_SDK_ROOT`, and optionally `GODOT_EXE` / `GODOT_TEMPLATES_DIR`.

The builder verifies downloaded dependency hashes, builds the OpenList adapter from its pinned source, stages the Android plugin, runs JVM tests, imports the Godot project and exports the APK. Downloads and generated files are kept in ignored `.cache`, `build` and `artifacts` directories.

```sh
git clone https://github.com/NorthBoundWisdom/immivio.git
cd immivio
python3 tools/build_player.py --vendor Quest --build-type Debug
```

Use `Pico` or `OpenXR` for the other targets and `--build-type Release` for an optimized distributable package. The PowerShell wrapper calls the same builder:

```powershell
./tools/Build-Player.ps1 -XrVendor Pico -BuildType Release
```

`--sdk`, `--java-home`, `--godot` and `--templates` can select explicit host locations. `--prepare-only` prepares dependencies; `--plugin-only` builds/tests the Android plugin without exporting the app.

## Playback backends

| Backend | Preparation and capabilities |
| --- | --- |
| Standard libmpv (default) | Uses the checksum-pinned public Android libraries. Ordinary playback and existing stereo media use render-transaction timing; exact decoded-image PTS and the project-private PGS/spatial APIs are not claimed. |
| Verified project libmpv | Optional independently prepared source-frame backend. Its receipt must match the pinned source revision, patch/header hashes, source lock and every packaged library. Private PGS, Dolby and spatial capabilities still depend on the actual source/device. No inference runtime is involved. |

To import a verified project backend:

```sh
python3 tools/build_player.py --vendor Quest --build-type Release \
  --mpv-dir /path/to/verified/arm64-v8a \
  --mpv-receipt /path/to/source-build.json
```

Source pins, patches and corresponding-source information are under `third_party/mpv` and `native/mpv/patches`; `tools/environment/Prepare-MpvAndroid.ps1` contains the historical source-backend preparation path. Do not substitute arbitrary library bytes or bypass the receipt check.

## Output and identity

Artifacts are named `Immivio-<QUEST|PICO|OpenXR>-<version>-<debug|release>-<YYYYMMDD>.apk`. Each APK has a `.build.json` receipt containing the product, source commit, signing certificate, backend, hashes and toolchain versions. There is no edition suffix.

The visible app name is **Immivio**. The store listing name is **Immivio – VR & Spatial Media Player**. The existing ordinary player's `com.wapok.thru3d` application ID, native package namespace and user-data directory remain stable so compatible signed updates preserve data. These identifiers are compatibility contracts, not the public product name.

Existing local `artifacts/signing/thru3d-signing.json` credentials are reused. New installations of the build tool create an Immivio signing identity. Explicit `GODOT_ANDROID_KEYSTORE_RELEASE_*` or Debug counterparts take priority. Keep credentials and signing material out of Git. Different certificates cannot update one another merely because package names match.

## CI and releases

`.github/workflows/android-release.yml` runs one Windows/macOS matrix. Branch/PR builds default to Debug; tags force Release. Both hosts exercise the same builder. Release signing uses the existing `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEY_ALIAS` and `ANDROID_KEY_PASSWORD` secrets; Debug jobs do not receive them.

The tag publisher requires successful Release jobs on both hosts, verifies the exact tag/commit and copies the three canonical macOS APKs. It checks all receipts and hashes before preparing any publishable assets. Historical pre-Immivio releases remain historical; the new publisher does not relabel old binaries.

APK inspection rejects model assets and removed inference libraries, verifies ARM64 ELF dependencies/symbols and alignment, checks the app label/ID, and verifies signing and ZIP alignment. These checks establish packaging behavior, not headset playback performance.

## Branding and website

The source artwork is `app/godot/branding/immivio-icon.png`. Run `godot --headless --xr-mode off --path app/godot --script ../../tools/prepare_branding.gd` to generate the adaptive foreground and transparent-corner website icon. All export presets share the source and themed monochrome assets.

The bilingual static site is in `website/`. `python3 tools/check_website.py` checks local links, languages, screenshots and any published Immivio download choices. GitHub Pages publishes from `main`; until a branded Release exists, the download selector links to current development workflow artifacts.
