<p align="center"><img src="website/assets/icon.png" width="88" alt="Thru3D 图标"></p>

# Thru3D Media Player

**让你的影片与照片，拥有更大的观看空间。**

Thru3D 是面向 **Meta Quest 和 PICO** 的开源 VR/MR 媒体播放器。你可以在虚拟屏幕上看视频、进入 180°／360° 场景、浏览立体照片，也可以直接播放头显或网络媒体库里的内容。

[官方网站](https://northboundwisdom.github.io/Thru3D-Media-Player/zh/) · [下载 APK](https://github.com/NorthBoundWisdom/Thru3D-Media-Player/releases/latest) · [使用指南](https://northboundwisdom.github.io/Thru3D-Media-Player/zh/guide/) · [English](README.md)

本仓库在 [zerochocobo/Thru3D-Media-Player](https://github.com/zerochocobo/Thru3D-Media-Player) 的基础上继续开发。**0.6.0 是双方最后共同采用的开发基线；从这个版本起，本项目走独立的开发与发布路线，由 NorthBoundWisdom 独立维护。** GitHub fork 关系现已解除，原有源码历史、来源署名及 GPL-3.0 许可继续保留。

## 实际运行画面

![Thru3D 播放指定 8K 立体视频时的实际控制界面](website/assets/screenshots/playback.png)

*使用 `blandscape-60mbps.mp4` 在 Android 虚拟机中截取，展示当前开发版本的二维调试入口。双眼立体、头部追踪和透视效果需在支持的头显上体验。*

| 播放设置 | 显示设置 |
| --- | --- |
| ![Thru3D 播放设置](website/assets/screenshots/settings.png) | ![Thru3D 显示设置](website/assets/screenshots/display.png) |

## 你可以用它做什么

- **选择适合内容的观看方式。** 支持平面、180°、360°、鱼眼视频，以及左右／上下立体格式。支持的模式可以调整屏幕大小、距离与曲率。
- **连接自己的媒体库。** 打开本地文件，或连接 SMB、WebDAV、DLNA 和支持的媒体服务器；也可使用云盘连接，具体能力取决于服务和账号权限。
- **调整到舒适的位置。** 用手柄抓握键移动画面和窗口，调整观看距离，按需开启躺卧模式，并记住每个视频的观看偏好。
- **更方便地控制播放。** 切换音轨和字幕、调整倍速、保存时间点书签、校准音画／字幕时间，或建立可保存的播放队列。
- **浏览照片和空间媒体。** 在单图、侧边预览、照片墙和记忆碎片之间切换；支持范围内的空间照片和空间视频可保留立体视图。
- **按需使用 AI。** AI 版为支持的平面单目内容提供深度 2D 转 3D，并为支持的内容提供人物抠像。普通播放也可以使用不含 AI 模型的版本。

当前开发分支还加入了逐视频字幕／音轨选择记忆、音量／静音持久化、五种文字字幕配色、1～3 行照片墙，以及 3D／静音双击快捷开关。**已发布 APK 可能晚于 `main` 的进度，请以具体版本的发布说明为准。**

## 下载适合你的版本

打开 [GitHub Releases](https://github.com/NorthBoundWisdom/Thru3D-Media-Player/releases/latest)，展开 **Assets**，下载与你的头显和功能需求对应的 **`.apk`**。源码 ZIP／TAR 压缩包用于开发，不是安装包。

| 设备 | 选择的文件名 |
| --- | --- |
| Meta Quest | `Thru3D-QUEST-…apk` |
| PICO | `Thru3D-PICO-…apk` |
| 其他兼容的 Android OpenXR 运行时 | `Thru3D-OpenXR-…apk`，实验性支持 |

| 版本 | 适合的需求 |
| --- | --- |
| **No AI**（`noai`） | 主要播放普通视频、照片和已有立体内容，希望安装体积更小；不提供实时 AI 转换。 |
| **AI**（`ai`） | 希望使用可选的深度和人物抠像功能；安装包更大，效果与性能取决于设备和片源。 |

Quest 2、PICO Neo3 是兼容目标。不同设备、编码和分辨率的表现可能不同；打包成功或模拟器可播放，不代表所有头显都已完成实机验证。通用 OpenXR 版需要兼容的 Android 运行时。

### 第一次使用

1. **安装。** 开启头显开发者模式，连接电脑并允许 USB 调试，用你常用的侧载工具安装对应 APK。
2. **启动。** 从头显的侧载应用列表打开 Thru3D，允许访问你准备使用的文件或目录。
3. **选择内容。** 打开本地视频／照片，或在资料库中添加网络来源。
4. **匹配画面格式。** 如果画面分成两半或发生变形，请选择正确的投影和立体布局。例如 VR180 SBS 鱼眼片源使用 **鱼眼 + SBS**。
5. **调整观看体验。** 居中画面、调整屏幕位置，再从播放控件选择音轨和字幕。

详细步骤见[使用指南](https://northboundwisdom.github.io/Thru3D-Media-Player/zh/guide/)。

## 常用操作

| 想做什么 | 如何操作 |
| --- | --- |
| 显示／隐藏播放控件 | 左手 Menu 键，或用扳机点按画面 |
| 选择控件 | 用手柄射线指向并按扳机；支持的设备也可使用手部指向／捏合 |
| 移动画面或资料库窗口 | 按住抓握键；支持的位置可用同手摇杆调整远近 |
| 跳转或调整音量 | 使用播放控件；未打开列表、未捕获滑块时也可用摇杆快捷操作 |
| 滚动资料库或设置列表 | 打开对应列表后使用摇杆 |
| 回到资料库 | 选择播放控件中的“关闭视频” |
| 躺着观看 | 开启“设置 → 常规 → 躺卧模式”；“跟随”仍为独立开关 |

当前开发版本还支持双击视频 **3D** 图标开关立体效果、双击 **音量** 图标静音／恢复。界面支持英文、简体中文、繁体中文和日文。

## 常见问题

**不需要 AI，可以用吗？** 可以。No AI APK 可播放普通媒体和已有立体内容。它使用不同的播放后端，PGS 位图字幕及部分空间／杜比能力与 AI 版存在差异；有这些需求时，请查看[构建能力对照](docs/BUILD.md#build-modes-and-compatibility)。

**为什么 APK 不能覆盖已安装的版本？** Android 要求应用 ID 和签名密钥一致。不同发布者或部分 CI 构建之间可能无法直接覆盖。先核对发布说明，并保留原安装和数据。当前开发版本为 AI／No AI 使用独立应用身份；具体发布包能否共存请以该版本说明为准。

**所有 8K 或 3D 视频都能流畅播放吗？** 不能仅根据分辨率判断。编码、码率、投影、效果及设备硬件都会影响播放，AI 也会增加处理负担。这里的截图展示界面，不代表头显性能基准。

**截图中的视频会随应用提供吗？** 不会。它仅用于拍摄展示画面，原始视频未包含在仓库或下载包中。

**在哪里反馈问题？** 请在[本仓库 Issues](https://github.com/NorthBoundWisdom/Thru3D-Media-Player/issues)中说明头显型号、应用版本／版本类型、媒体格式及复现步骤。只分享你有权分发的样片，不要上传账号凭据或私人媒体。

## 开发、历史和许可

- [中文更新日志](CHANGELOG.zh-CN.md) · [English changelog](CHANGELOG.md)
- [源码构建](docs/BUILD.md) · [模型要求](docs/MODELS.md)
- [架构](docs/ARCHITECTURE.md) · [测试](docs/TESTING.md) · [贡献](CONTRIBUTING.md)
- 项目源码采用 [GPL-3.0-only](LICENSE)。第三方组件保留各自许可，包含内嵌 OpenList 的 AGPL-3.0 义务，详见[许可说明](docs/LICENSING.md)。

## 兄弟项目

[**Ravo Studio**](https://northboundwisdom.github.io/Ravo/) — 整理、浏览并处理你的照片。

[**SonaFolio**](https://northboundwisdom.github.io/sonafolio/) — 将播客和媒体转为转写文本与本地知识库。
