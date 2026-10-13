<p align="center"><img src="website/assets/icon.png" width="88" alt="Thru3D icon"></p>

# Thru3D Media Player

**Your videos and photos, with room to look around.**

Thru3D is an open-source VR/MR media player for **Meta Quest and PICO**. Watch videos on a virtual screen, step into 180° and 360° scenes, browse stereo photos, and play media from your headset or network library.

[Website](https://northboundwisdom.github.io/Thru3D-Media-Player/) · [Download APKs](https://github.com/NorthBoundWisdom/Thru3D-Media-Player/releases/latest) · [Getting started](https://northboundwisdom.github.io/Thru3D-Media-Player/guide/) · [简体中文](README.zh-CN.md)

This repository continues development of [zerochocobo/Thru3D-Media-Player](https://github.com/zerochocobo/Thru3D-Media-Player). **Version 0.6.0 is our last shared development baseline. From that point, this edition follows its own development and release path and is independently maintained by NorthBoundWisdom.** The GitHub fork relationship has been removed; the original source history, attribution and GPL-3.0 license are preserved.

## See it in action

![Thru3D playing the supplied 8K stereo video with its playback controls visible](website/assets/screenshots/playback.png)

*Actual Android emulator capture using `blandscape-60mbps.mp4`. Screenshots show the current development build through its 2D diagnostic entry; headset stereoscopy, tracking and passthrough are experienced on a supported device.*

| Playback settings | Display preferences |
| --- | --- |
| ![Playback settings in Thru3D](website/assets/screenshots/settings.png) | ![Display preferences in Thru3D](website/assets/screenshots/display.png) |

## What you can do

- **Watch your way.** Flat screens, 180° and 360° projections, fisheye video, and side-by-side or top-bottom stereo layouts. Adjust the screen's size, distance and curvature where supported.
- **Bring your library.** Open local files or connect SMB, WebDAV, DLNA and supported media servers. Cloud connections are also available, subject to the service and your account permissions.
- **Keep a comfortable setup.** Move panels with a controller grip, adjust viewing distance, and use optional reclining mode. Per-video viewing preferences help you return to a familiar setup.
- **Take control of playback.** Choose audio and subtitles, adjust speed, save timestamp bookmarks, correct audio/subtitle timing, and build a persistent playback queue.
- **Explore photographs.** View single photos, side previews, a photo wall or memory fragments. Supported spatial-photo and spatial-video formats retain their stereo views.
- **Try optional AI effects.** The AI edition adds depth-based 2D-to-3D viewing for supported flat mono media and person matting for supported content. Ordinary playback is also available in an edition without AI models.

The current development branch additionally includes remembered per-video track choices, persistent volume/mute, five text-subtitle palettes, 1–3-row photo walls and double-tap 3D/mute shortcuts. **Published APKs may lag behind `main`; check the release notes for the features in your download.**

## Download the right edition

Open [GitHub Releases](https://github.com/NorthBoundWisdom/Thru3D-Media-Player/releases/latest), expand **Assets**, and choose an **`.apk`** matching your headset and preferred edition. The source ZIP/TAR archives are for developers.

| Headset | Filename to look for |
| --- | --- |
| Meta Quest | `Thru3D-QUEST-…apk` |
| PICO | `Thru3D-PICO-…apk` |
| Other compatible Android OpenXR runtimes | `Thru3D-OpenXR-…apk` — experimental |

| Edition | Choose it when… |
| --- | --- |
| **No AI** (`noai`) | You want ordinary video/photo playback and existing stereo media with a smaller installation. Live AI conversion is unavailable. |
| **AI** (`ai`) | You want the optional depth and person-matting features. Downloads are larger, and results depend on your device and media. |

Quest 2 and PICO Neo3 are compatibility targets. Support and performance vary by device, codec and video resolution; successful packaging or emulator playback does not establish performance on every headset. Standard OpenXR builds require a compatible Android runtime.

### Your first session

1. **Install.** Enable developer mode on your headset, connect it to your computer, approve USB debugging, and install the selected APK with your preferred sideloading tool.
2. **Open.** Launch Thru3D from your headset's sideloaded-app library. Allow the file or folder access you want to use.
3. **Choose media.** Open a local video/photo or add a network source in the library.
4. **Match the picture.** If the image looks split or distorted, select its projection and stereo layout. For a VR180 SBS fisheye source, use **Fisheye + SBS**.
5. **Make it comfortable.** Recenter the view, set the screen placement, and choose audio/subtitles from the playback controls.

For step-by-step help, see the [user guide](https://northboundwisdom.github.io/Thru3D-Media-Player/guide/).

## Everyday controls

| Action | How |
| --- | --- |
| Show or hide playback controls | Left Menu button, or tap the picture with the trigger |
| Select a control | Point with the controller ray and press its trigger; supported hand pointing/pinching is also available |
| Move the picture or library window | Hold the grip; use the same hand's thumbstick to adjust distance where available |
| Seek or change volume | Use the playback controls; thumbsticks provide shortcuts while lists and captured sliders are inactive |
| Scroll a library or settings list | Use the thumbstick while that list is open |
| Return to the library | Use **Close video** on the playback controls |
| Watch while reclined | Enable **Settings → General → Reclining mode**; Follow is a separate setting |

In the current development build, double-tap the video **3D** icon to toggle the effect and the **volume** icon to mute/restore sound. The UI supports English, Simplified Chinese, Traditional Chinese and Japanese.

## A few useful answers

**Can I use it without AI?** Yes. Choose the No AI APK for ordinary playback and pre-existing stereo media. It uses a different playback backend; PGS bitmap subtitles and some specialized spatial/Dolby features differ from the AI build. See the [build capability table](docs/BUILD.md#build-modes-and-compatibility) if you need those formats.

**Why won't an APK update my existing installation?** Android requires matching application IDs and signing keys. Builds from different distributors, or some CI builds, may not update one another. Keep your existing installation and saved data until you have checked the release's installation notes. Current development builds give AI and No AI editions separate app identities; check the particular release before installing both.

**Will any 8K or 3D video play smoothly?** Resolution alone is not enough to tell. Codec, bitrate, projection, effects and headset hardware all matter. AI effects add processing work. The screenshots are examples of the interface, not a headset performance benchmark.

**Does the screenshot video come with the app?** No. The supplied sample was used to capture the interface; the original video is not included in the repository or downloads.

**Where should I report a problem?** Open an [issue in this repository](https://github.com/NorthBoundWisdom/Thru3D-Media-Player/issues). Include the headset, app version/edition, media format and steps to reproduce. Share a short sample only if you are allowed to distribute it; keep account credentials and private media out of public reports.

## Development, history and license

- [English changelog](CHANGELOG.md) · [中文更新日志](CHANGELOG.zh-CN.md)
- [Build from source](docs/BUILD.md) · [Model requirements](docs/MODELS.md)
- [Architecture](docs/ARCHITECTURE.md) · [Testing](docs/TESTING.md) · [Contributing](CONTRIBUTING.md)
- Project source: [GPL-3.0-only](LICENSE). Third-party components retain their licenses, including the embedded OpenList component's AGPL-3.0 obligations. See [licensing details](docs/LICENSING.md).

## More from NorthBoundWisdom

[**Ravo Studio**](https://northboundwisdom.github.io/Ravo/) — organize, review and develop your photographs.

[**SonaFolio**](https://northboundwisdom.github.io/sonafolio/) — turn podcasts and media into transcripts and a local knowledge library.
