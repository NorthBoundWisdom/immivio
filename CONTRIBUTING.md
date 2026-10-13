# Contributing

Use [NorthBoundWisdom/immivio](https://github.com/NorthBoundWisdom/immivio) for this independently maintained edition. Open an issue or pull request with a concrete problem, the affected source path and a reproducible example. Keep one change focused on one behavior. Contributions to project-owned source are submitted under GPL-3.0-only; preserve existing third-party notices and identify any imported code's origin/license.

Run the source boundary and applicable host tests described in [TESTING.md](docs/TESTING.md). Android changes also need JVM/build checks; headset-specific claims need device evidence with matching versions. State what you have and have not verified.

Do not commit model weights, generated APKs/libraries, signing material, credentials, personal media or device logs containing user data. Provide synthetic reproduction fixtures or generation instructions. Do not send account tokens in public issues.

VR menus use controller ray/trigger selection or hand interaction, never thumbstick selection. Libraries, settings, list popups and photo menus reserve thumbsticks for scrolling and suppress playback shortcuts. The ordinary video control bar allows the same seek, volume and immersive zoom shortcuts as hidden controls. Pointer capture suppresses shortcuts; after leaving a list or ending capture, the stick must return to center before reactivation. Keep visible UI text concise and place implementation notes in technical documentation.

Distribution APK filenames use platform names `QUEST`, `PICO` and `OpenXR`, with the requested software version and build date. Do not use specific headset models in distribution filenames.

For every version update, maintain `CHANGELOG.md` and the matching English/Chinese release notes in `website/updates/` and `website/zh/updates/`. The bilingual website owns translated user documentation; the repository keeps one README and one technical changelog. Review the README feature overview: add important durable capabilities, while keeping fixes and detailed history in the changelog. Preserve media/device limitations and use English commit messages.

The user website lives in `website/`, with an English home, guide and release notes, and matching pages under `website/zh/`. Run `python3 tools/check_website.py` and `node --check website/assets/site.js` after editing it. The Pages workflow publishes this directory from `main` and refreshes the APK selector when a GitHub Release is published. Keep actual screenshots and their capture manifest together; do not commit the source video or device diagnostics.

Keep search titles, descriptions, social previews and JSON-LD consistent with each page's visible content in both languages. Update sitemap modification dates only for pages whose content changed. Performance claims need evidence; describe supported hardware decoding and GPU rendering without inventing benchmarks, ratings or format guarantees. Keep the repository description and topics aligned with the README's current product scope.

The supplied application artwork is `app/godot/branding/immivio-icon.png`. After replacing it, run `godot --headless --xr-mode off --path app/godot --script ../../tools/prepare_branding.gd` for adaptive safe-area sizing and the website icon. Keep the separate Android monochrome mask consistent with the mark. All three Android export presets share these assets.
