# 更新说明 / Changelog

[中文官网更新说明](https://northboundwisdom.github.io/immivio/zh/updates/) · [English release notes](https://northboundwisdom.github.io/immivio/updates/)

按版本由新到旧排列，只记录与使用体验有关的主要变化。“待发布”不代表已经上线。0.6.0 及更早版本属于原项目历史；文中提到的照片浏览、网盘、AI 转 3D 等功能已在后续版本移除，当前功能以 [README](README.md) 为准。

Newest first, with the main changes that affect everyday use. Unreleased items are not yet part of a public release. Versions 0.6.0 and earlier belong to the original project. Photo viewing, cloud drives and AI 3D conversion appear only as historical features and were removed later; see the [README](README.md) for current capabilities.

## 1.0.0 — 2026-11-14

**中文**

- 清理停用的播放依赖与调试内容，减少安装包内的冗余，并更新基础依赖。
- 保存格式升级时保留已有的逐视频画面、立体、字幕和时序偏好，清除废弃字段。

**English**

- Remove inactive playback dependencies and diagnostic content to reduce redundant package contents, and update core libraries.
- Preserve existing per-video picture, stereo, subtitle and timing preferences while migrating saved records and removing retired fields.

## 0.9.11 — 2026-11-10

**中文**

- 优化星空背景的渲染负载，保留星点、银河、清晰山脊与方向／亮度调节，改善转头时的流畅度。
- 恢复主场景中的立体手柄光束，保留细线、柔边与渐淡效果，减少额外合成开销。
- 避免静止菜单重复提交同一画面，降低主页面的 GPU 负载。

**English**

- Reduce starry-sky rendering cost while retaining stars, the Milky Way, sharp hills and direction/brightness controls, improving smoothness when looking around.
- Render stereoscopic controller beams in the main scene, retaining thin lines, soft edges and fading while reducing composition overhead.
- Stop resubmitting unchanged menu captures to reduce home-page GPU load.

## 0.9.10 — 2026-11-10

**中文**

- 播放清单新增“列表循环”，支持单片重复，保存开关；关闭时仍在播完后返回媒体库。
- 本地媒体库为可见的未播放影片逐一生成缩图，按文件名及尺寸裁切立体／全景画面；播放期间停止生成，沿用统一缓存与清理入口。
- 接入 OpenXR 佩戴事件及 Android 距离感测／熄屏回退，摘下头显时暂停音画，戴回继续原位置；手动暂停、打开／关闭状态与清单保持原意图。实际检测能力与延迟取决于设备。
- 修复休眠／摘戴后缩图工作等待旧回覆、文件替换后误用旧预览，以及预览阻止播放截图更新的问题。

**English**

- Add a saved Repeat queue switch, including single-video repeat; keep the return-to-library behavior when off.
- Generate visible unplayed local-video thumbnails sequentially, crop named stereo/panoramic layouts, suspend generation during playback, and use the existing shared cache and clear action.
- Suspend audio/video on OpenXR wearer absence or Android proximity/display-off events. Wearing again continues in place without overriding manual pause or reviving closed media. Detection availability and delay depend on the device.
- Retry canceled preview work on return, discard previews for changed files, and replace lightweight previews with displayed-frame captures during playback.

## 0.9.9 — 2026-11-08

**中文**

- 新安装默认使用星空背景，保留已保存的选择；将夕阳背景名称简化为“夕阳”。
- 海边改用 8K 实景全景，保留方向与亮度调节，让海浪、沙滩与天空更自然。
- 统一深色面板、分组标题与控件样式，封面使用圆角裁切；已开始且时长已知的视频显示观看进度。
- 修复播放、媒体库和信息页面切换时控制栏轻微位移，以及首次打开媒体库时整窗闪烁。
- 修复部分按钮点击后激光短暂穿透的问题，等待新画面时仍跟随手柄并停在可见面板或浮动按钮上。

**English**

- Start new installations with Starry night while preserving saved choices, and shorten the sunset background name to Sunset.
- Replace Beach with an 8K photographic panorama, retaining direction and brightness controls for more natural surf, sand and sky.
- Unify dark panels, grouped headings and controls, with rounded covers and watch-progress bars for started videos with a known duration.
- Fix small control-bar shifts when switching between Playback, Library and Info, and the window flash on the first Library opening.
- Fix the laser briefly passing through some buttons after a click. While the next page appears, it continues to follow the hand and stop on visible panels or floating buttons.

## 0.9.8 — 2026-11-07

**中文**

- 自动识别没有格式标记的左右／上下立体视频；保留手动选择，并可在“视频模式 → 自动识别”中重新判断。VR 投影和镜头角度仍沿用文件标记或已有设置。
- 重新整理通用、显示、播放、外观与关于设置，用分组和统一控件布局减少查找。
- 播放时使用控制栏上方的紧凑换片窗口；关闭视频后回到完整媒体库与设置，移除独立的控制栏位置锁定。
- 网络媒体分组显示已保存来源和局域网发现的设备，改善空列表提示与长列表滚动。
- 新增程序生成的星空、海边和云海背景，可调整方向与亮度。
- 优化立体手柄光束：线条更细、边缘抗锯齿并逐渐淡出；面板纹理只保留命中光点。

**English**

- Recognize unmarked side-by-side and top-bottom stereo video while preserving manual choices. Recheck a saved format under Video mode → Auto detect. VR projection and lens angle still follow file markers or existing settings.
- Regroup General, Display, Playback, Appearance and About settings, with clearer headings and aligned controls.
- Use a compact video switcher above the playback controls. Closing video returns to the full library and Settings; remove the separate control-bar position lock.
- Group saved Network media sources and devices found on the local network, with clearer empty states and smoother long-list scrolling.
- Add procedural starry-sky, beach and cloud scenery with direction and brightness controls.
- Refine stereoscopic controller beams with thinner lines, antialiased edges and a transparent fade. Keep only the hit reticle in the panel texture.

## 0.9.7 — 2026-11-06

**中文**

- 更换应用图标，更新宣传图和分享预览。
- 全新设计中英文官网，换上当前版本的实际界面截图，并重写使用指南、更新说明和 README。
- 新增中英文 PICO 商店详情图，展示示例视频播放与主要功能，并统一上传海报的尺寸和格式。
- 完善 PICO 商店安装包的发布前检查。

**English**

- Refresh the app icon, artwork and sharing previews.
- Redesign the English and Chinese website with current interface screenshots, and rewrite the user guide, release notes and README.
- Add Chinese and English PICO Store detail images showing sample-video playback and key features, with consistent upload-poster dimensions and formats.
- Improve pre-release checks for PICO Store packages.

## 0.9.6 — 2026-11-06

**中文**

- 将共享文件夹、家庭媒体库和媒体服务器合并到“网络媒体”，添加来源更直观，修复添加页面意外返回的问题。
- 修复播放小窗、设置与网络媒体切换时的闪烁，改善轻微头部移动时播放条的稳定性。
- 统一文件管理页四周的留白，让列表和网格更整齐。
- 窗口默认下移 12 厘米；可在“设置 → 显示 → 窗口高度”中调整到舒服的位置。
- 专注视频播放，移除照片浏览及相关功能；本地文件只显示视频和文件夹，原始照片文件不会被删除。
- 区分商店版和官网版：商店版不显示“检查更新”，官网版保留手动检查。
- 官网新增中英文隐私政策和用户协议。

**English**

- Bring shared folders, home media libraries and media servers into one Network media entry. Make source setup clearer and stop it from unexpectedly returning to the main page.
- Fix flashes when opening playback popups or switching between Settings and Network media, and improve control-bar stability during small head movements.
- Use even spacing around file-browser content for tidier lists and grids.
- Lower windows by 12 cm by default. Adjust their position under Settings → Display → Window height.
- Focus on video playback and remove photo viewing. Local files now show videos and folders; original photo files are not deleted.
- Separate store and website editions: store builds hide Check for updates, while website builds retain the manual check.
- Add English and Chinese Privacy Policy and Terms of Use pages to the website.

## 0.9.5 — 2026-11-05

**中文**

- 新增双语字幕，可同时显示两条文字字幕，并按视频记住选择；平面视频的字幕也可放在画面下方。
- 自动识别常见外挂字幕的文字编码，减少乱码；可按文件名查找和选择字幕，不改动原字幕文件。
- Emby、Jellyfin 支持选择可直接播放的影片版本，并分别记住进度和设置；改进媒体库文件夹与 Plex 分类浏览。
- 支持从系统文件管理器打开或分享兼容的视频，改进 U 盘访问和错误提示。
- 优化中文显示、下拉框、手柄射线和窗口切换；播放控件等画面准备好后再显示，减少位置跳动和误触。
- 扩大平面画面的尺寸与距离调整范围，新增更方便的沉浸式画面移动和缩放；可选择左手、右手或双手捏合操作。
- 默认优先使用 72 Hz，并只列出设备支持的刷新率；新增播放顺序／随机切换，以及未识别视频沿用上次观看模式的选项。
- 新增手动检查更新和本地问题记录导出；取消应用内的重启、退出按钮，改用头显系统管理。

**English**

- Add bilingual subtitles with two text tracks and per-video choices. Captions can also sit below a flat video screen.
- Detect common external-subtitle text encodings to reduce garbled text. Find subtitles by filename without changing the original files.
- Choose directly playable Emby/Jellyfin video versions with separate progress and settings. Improve media folders and Plex library browsing.
- Open compatible videos from the system file manager or sharing menu, with clearer USB access and error feedback.
- Improve Chinese text, dropdowns, controller rays and window transitions. Show playback controls after the picture is ready to reduce jumps and accidental input.
- Expand flat-screen size and distance adjustments, make immersive video easier to move and zoom, and offer left-, right- or both-hand pinch preferences.
- Prefer 72 Hz when available and list only supported refresh rates. Add a sequence/shuffle switch and optional reuse of the last viewing mode for unrecognized videos.
- Add manual update checks and local problem-log export. Remove in-app Restart and Exit buttons; use the headset’s system controls instead.

## 0.9.4 — 2026-10-24

**中文**

- 支持 STRM 视频快捷方式，可从本地、共享文件夹或兼容的视频链接打开。
- 记住文件夹位置和排序，新增列表／图标浏览，以及紧凑／完整窗口切换。
- 新增电视与影院屏幕预设，更方便地调整距离、大小和弯曲程度；可锁定播放控件位置并调整底板透明度。
- 显示加载状态、等待时间和读取速度；闲置手柄会自动隐藏，减少观影干扰。
- 改善 PICO 启动稳定性，修复文件浏览与播放控件同时显示时的点击问题；新版与旧版分别安装，旧数据不会自动迁移。
- 移除网盘和 WebDAV 功能，保留本地文件、局域网共享和支持的媒体服务器。

**English**

- Play STRM video shortcuts from local files, shared folders and compatible video links.
- Remember folder positions and sorting. Add list/icon browsing and compact/full browser windows.
- Add TV and cinema screen presets with easier distance, size and curvature adjustments. Lock playback controls in place and adjust their background opacity.
- Show loading stages, waiting time and input speed. Hide idle controllers to reduce viewing distractions.
- Improve PICO startup and fix input when browsing files alongside playback controls. Install separately from legacy versions without automatically migrating their data.
- Remove cloud-drive and WebDAV features while retaining local files, LAN shares and supported media servers.

## 0.9.3 — 2026-10-14

**中文**

- 为字幕、画面调色、声音同步和双眼对齐等调节项增加独立重置，方便只恢复当前设置。
- 调色预设简化为原始、暖色、冷色和自定义；旧的日光预设按原始显示，同时保留自定义参数。

**English**

- Add individual resets for subtitle, color, timing and eye-alignment adjustments so you can restore one setting at a time.
- Simplify color presets to Original, Warm, Cool and Custom. Display the old Daylight preset as Original while keeping custom values.

## 0.9.2 — 2026-10-14

**中文**

- 将字幕、倍速、调色、同步和队列等操作收进一条紧凑播放栏，通过小窗调整。
- 重新整理文件名、电量、时间和播放按钮的位置，控件更靠近、更容易操作。
- 影片结束后自动播放队列下一条，全部播完后回到原文件夹；取消循环播放和新增书签入口，已有书签保留。
- 音量统一交给头显系统控制，改善重新居中后的画面与菜单位置。

**English**

- Bring subtitles, speed, color, timing and queue controls into a compact toolbar with popups.
- Rearrange the filename, battery, clock and playback buttons to make controls closer and easier to use.
- Advance to the next queued video when playback ends, then return to the original folder. Remove repeat playback and new-bookmark creation while retaining existing bookmarks.
- Use the headset’s system volume controls and improve picture/menu placement after recentering.

## 0.9.1 — 2026-10-13

**中文**

- 优化 PICO 4 菜单显示与文件浏览窗口的位置。
- 修复系统自动重新定位时画面和窗口意外移动的问题，保留应用内手动重新居中。
- 改善播放帧率较低时的菜单显示稳定性。

**English**

- Improve PICO 4 menu display and file-browser placement.
- Prevent automatic tracking resets from unexpectedly moving the picture and windows, while retaining manual recentering.
- Improve menu stability when playback frame rates are low.

## 0.9.0 — 2026-10-13

**中文**

- 项目更名为 Immivio，开始独立维护，继续保持免费开源。
- 专注播放已有的立体和全景内容，移除 AI 转 3D、人像抠图及 AI／非 AI 版本选择。
- 新增播放队列与顺序／随机播放，支持逐视频记住音轨、字幕和时间微调。
- 新增躺卧模式、画面跟随和更方便移动的曲面菜单，改善窗口与提示文字的位置稳定性。
- 提供五种字幕配色、双眼画面对齐设置和更完整的文件名提示；改进局域网字幕匹配。

**English**

- Rename the project to Immivio and begin independent development while remaining free and open source.
- Focus on existing stereo and panoramic content. Remove AI 3D conversion, person cutouts and the AI/non-AI edition selector.
- Add playback queues with sequence/shuffle behavior and per-video audio, subtitle and timing preferences.
- Add Reclining mode, picture following and easier-to-move curved menus. Improve window and tooltip stability.
- Offer five subtitle color palettes, eye-alignment settings and fuller filename tips, with better LAN subtitle matching.

## 0.6.0 — 2026-10-11

**中文**

- 支持立体 HEIC／HEIF 空间照片，加入照片墙、缩略图分组和随机浏览。
- 改善大图加载提示、照片切换和画面位置稳定性；部分普通照片可准备 3D 效果并调节强弱。
- 新增画面跟随和临时透视，以及视频单眼／双眼查看与对齐记忆。

**English**

- Add stereo HEIC/HEIF spatial photos, photo walls, grouped thumbnails and randomized browsing.
- Improve large-photo loading feedback, switching and placement. Prepare adjustable 3D effects for selected ordinary photos.
- Add picture following, temporary passthrough, and remembered video eye views/alignment.

## 0.5.2 — 2026-10-11

**中文**

- 改进人像和照片 3D 效果的调节与处理状态提示。
- 根据设备选择默认画质，并可查看播放帧率。
- 修复部分 H.264 视频启动卡住或退出，以及部分网络目录、同名文件夹无法打开的问题。

**English**

- Improve person/photo 3D effect controls and processing feedback.
- Choose default quality for the device and offer a playback frame-rate display.
- Fix startup stalls or exits for some H.264 videos, plus issues opening certain network directories and same-named folders.

## 0.5.1 — 2026-10-11

**中文**

- 支持通过手机或电脑配对 Plex，浏览媒体库并播放原文件。
- 新增 0.25～3 倍速，并可一键恢复正常速度。
- 增加画面距离、大小、弯曲和旋转调节，扩展字幕大小与位置设置。
- 改善文件排序和控件数值显示。

**English**

- Pair Plex through a phone or computer, browse libraries and play original files.
- Add 0.25×–3× playback speed with a one-step return to normal speed.
- Add screen distance, size, curvature and rotation adjustments, plus more subtitle size/position options.
- Improve file sorting and displayed control values.

## 0.5.0 — 2026-10-10

**中文**

- 完善媒体服务器中的继续观看、最近添加、分类和详情浏览，并在来源支持时提供收藏。
- 新增阿里云盘、夸克与 WebDAV 连接，支持手动添加局域网媒体地址。
- 新增照片调节与局部放大；修复画面朝向、透视显示和账号过期后的重新登录体验。

**English**

- Improve Continue Watching, Recently Added, categories and details in media-server browsing, with favorites where supported.
- Add Aliyun Drive, Quark and WebDAV connections, plus manually entered LAN media addresses.
- Add photo adjustments and a magnifier. Improve picture orientation, passthrough display and sign-in after account expiry.

## 0.4.2 — 2026-10-10

**中文**

- 沉浸式字幕支持横排与竖排，改善多行、双语和首字符位置。
- 可更自由地调整字幕方向、位置与距离。
- 改进网盘外挂字幕和配音匹配，支持读取部分媒体服务器提供的文字字幕。

**English**

- Add horizontal and vertical immersive subtitles, with better multiline, bilingual and first-character placement.
- Offer more flexible subtitle direction, position and distance controls.
- Improve cloud-drive subtitle/dubbing matching and read text subtitles supplied by supported media servers.

## 0.4.1 — 2026-10-09

**中文**

- 更新 Quest 安装包，保留 0.4 版本的功能，没有新增使用功能。

**English**

- Update the Quest package while retaining the 0.4 feature set, with no new user-facing features.

## 0.4 — 2026-10-09

安装包版本显示为 `0.4`，也称 `0.4.0`。 / The package version is `0.4`, also known as `0.4.0`.

**中文**

- 改善照片 3D 处理、横竖图显示和缩放后的画面位置。
- 扩展左右／上下立体视频格式，修复部分鱼眼画面的比例。
- 新增 115 和 OneDrive 连接；旧百度账号需要重新授权。
- 新增默认关闭的文件管理，可在支持的来源中排序、重命名和删除文件；增加 U 盘快捷入口。

**English**

- Improve photo 3D processing, landscape/portrait display and placement after zooming.
- Expand side-by-side/top-bottom video support and correct proportions for some fisheye videos.
- Add 115 and OneDrive connections. Existing Baidu accounts require authorization again.
- Add optional file management, off by default, for sorting, renaming and deleting files on supported sources, plus USB shortcuts.

## 0.3.1 — 2026-10-09

**中文**

- 改善 VR 字幕的稳定性与 PICO 手柄兼容性。
- 优化旧版 Android 的存储授权，以及权限变化后的文件刷新。
- 电量显示可区分充电与接入电源，低电量时变红；改善登录按钮和应用图标显示。

**English**

- Improve VR subtitle stability and PICO controller compatibility.
- Improve storage access on older Android versions and refresh files after permission changes.
- Distinguish charging from connected power, show low battery in red, and improve sign-in buttons and app-icon display.

## 0.3.0 — 2026-10-09

**中文**

- 新增播放书签，可从时间轴或列表跳转，并支持删除和撤销。
- 改善照片沉浸式展示，支持单手拖动和双手缩放。
- 可在头显内完成网络来源和账号设置；改善进度拖动、音轨选择、字幕位置和 Jellyfin 连接。

**English**

- Add playback bookmarks with timeline/list navigation, deletion and undo.
- Improve immersive photo viewing with one-hand dragging and two-hand zoom.
- Set up network sources/accounts inside the headset. Improve seeking, audio-track selection, subtitle placement and Jellyfin connections.

## 0.2.1 — 2026-10-08

**中文**

- 拖动进度时保留画面，修复进度条提前跳回的问题。
- 最近播放加入预览图、海报和分页浏览，手柄与手部模型让操作更直观。
- 提供分别适配 Quest、PICO 的安装包，以及实验性的通用 OpenXR 版本。

**English**

- Keep the picture visible while seeking and fix the timeline jumping back too early.
- Add previews, posters and paging to recent playback, with controller/hand models for clearer interaction.
- Provide separate Quest and PICO packages and an experimental generic OpenXR build.

## 0.2 — 2026-10-07

**中文**

- 改善家庭共享文件夹的连接兼容性与加密支持。
- 新增画质档位和清晰度调节，重新整理设置，并提供重启与退出入口。
- 优化 PICO 窗口和手柄操作，保留已有账号与媒体链接的兼容性。

**English**

- Improve home file-share compatibility and encryption support.
- Add quality presets and sharpness controls, reorganize settings, and offer Restart and Exit actions.
- Improve PICO windows and controller input while retaining existing account and media-link compatibility.

## 0.1.0 — 2026-10-07

**中文**

- 首个独立头显视频／照片测试版，支持平面、180°、360°和立体观看。
- 提供本地、家庭网络与媒体库访问，可选择音轨和字幕，并使用手柄或手势操作。
- 包含实验性的 2D 转 3D 与人像透视效果，提供 Quest、PICO 多语言安装包。

**English**

- First standalone-headset video/photo test release with flat, 180°, 360° and stereo viewing.
- Access local files, home networks and media libraries, choose audio/subtitles, and use controllers or hands.
- Include experimental 2D-to-3D and person-passthrough effects, with multilingual Quest and PICO packages.
