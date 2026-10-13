<p align="center"><img src="website/assets/icon.png" width="88" alt="Immivio 图标"></p>

# Immivio

### Open Spatial Media Player

**VR180 · VR360 · 3D · Spatial Video · Photos**

面向独立 XR 头显的开源空间媒体播放器。

在 Meta Quest、PICO 或兼容的 Android OpenXR 头显中观看自己的视频与照片。选择虚拟屏幕或沉浸投影，连接自己的资料库，把播放控件放在顺手的位置。

[官网](https://northboundwisdom.github.io/immivio/zh/) · [发布版本](https://github.com/NorthBoundWisdom/immivio/releases) · [开发版构建](https://github.com/NorthBoundWisdom/immivio/actions/workflows/android-release.yml) · [使用指南](https://northboundwisdom.github.io/immivio/zh/guide/) · [English](README.md)

Immivio 在 [zerochocobo/Thru3D-Media-Player](https://github.com/zerochocobo/Thru3D-Media-Player) 的基础上继续开发。**0.6.0 是最后共同采用的基线；从这个版本起，本项目走独立的开发与发布路线，由 NorthBoundWisdom 独立维护。** 原有源码历史、来源署名及 GPL-3.0 许可继续保留。

## 你的影像，就在身边

![使用指定 VR180 立体视频拍摄的播放界面](website/assets/screenshots/playback.png)

*使用 `blandscape-60mbps.mp4` 在 Android 虚拟机中实拍，拍摄时间早于 Immivio 更名。二维调试视图展示界面，不代表头显双眼立体、透视效果或帧率；原始视频未随应用提供。*

| 播放设置 | 显示设置 |
| --- | --- |
| ![播放设置](website/assets/screenshots/settings.png) | ![显示设置](website/assets/screenshots/display.png) |

- **平面与沉浸观看。** 支持平面、VR180、VR360、鱼眼投影，以及 SBS／TB 左右／上下立体布局和半宽／半高格式。
- **连接自己的资料库。** 本地文件、SMB、WebDAV、DLNA、支持的媒体服务器与云盘来源。可用操作取决于服务及账号权限。
- **调整到舒适的位置。** 移动画面和窗口，调整支持模式下的大小、距离与曲率，按需开启躺卧或跟随。
- **控制播放细节。** 音轨与字幕、倍速、时间点书签、逐视频音频／字幕校时、持久化队列、循环与随机播放。
- **记住观看习惯。** 逐视频保存轨道选择和双眼对齐，保存音量／静音状态，悬浮查看完整文件名。
- **浏览照片。** 单图、侧边预览、1～3 行照片墙与记忆碎片。空间格式的解码能力取决于播放后端和片源。

Immivio 现在只有 **一个播放版本**，播放已有立体／空间媒体，不把普通 2D 内容生成为 3D。此前的实时 AI 深度、人物抠像、模型准备及推理功能均已移除。

## 下载与安装

正式 APK 位于[发布版本](https://github.com/NorthBoundWisdom/immivio/releases)。最新开发包位于成功的 [Android 工作流运行](https://github.com/NorthBoundWisdom/immivio/actions/workflows/android-release.yml) → **Artifacts**，下载此类构建产物需要登录 GitHub。更名前的历史版本保留原名称和当时的功能。

| 设备 | 产物名称 |
| --- | --- |
| Meta Quest | `Immivio-QUEST-<版本>-<debug或release>-<日期>.apk` |
| PICO | `Immivio-PICO-<版本>-<debug或release>-<日期>.apk` |
| 兼容的 Android OpenXR 运行时 | `Immivio-OpenXR-<版本>-<debug或release>-<日期>.apk`，实验性支持 |

1. 开启头显开发者模式，连接电脑并允许 USB 调试。
2. 使用侧载工具安装对应 APK；源码 ZIP／TAR 不能直接安装。
3. 从头显侧载应用列表启动 **Immivio**。
4. 打开本地文件或添加网络来源，按需授权访问。
5. 匹配投影与立体布局。例如 VR180 SBS 鱼眼片源选择 **鱼眼 + SBS**。

Quest 2、PICO Neo3 是兼容目标。设备、编码、码率和分辨率都会影响实际表现；通用 OpenXR 版需要兼容的 Android 运行时。

## 常用操作

| 操作 | 方式 |
| --- | --- |
| 显示／隐藏播放控件 | 左手 Menu 键，或用扳机点按画面 |
| 选择控件 | 手柄射线 + 扳机；支持的设备也可使用手部指向／捏合 |
| 移动画面或资料库窗口 | 按住抓握键；支持的位置可用同手摇杆调整远近 |
| 跳转／调整音量 | 播放控件，或未打开列表、未捕获滑块时的摇杆快捷操作 |
| 静音／恢复 | 双击音量图标 |
| 滚动列表 | 列表打开时使用摇杆 |
| 返回资料库 | 选择“关闭视频” |
| 躺卧观看 | 设置 → 常规 → 躺卧模式；跟随仍为独立开关 |

界面支持英文、简体中文、繁体中文和日文；文字字幕提供五种配色。更多来源、布局、校时和队列说明见[使用指南](https://northboundwisdom.github.io/immivio/zh/guide/)。

## 常见问题

**AI／No AI 版本去哪了？** 已统一为不含模型转换和人物抠像的播放器。已有立体视频与原生空间格式并不依赖这些被删除的功能。

**可以覆盖已有应用吗？** 保留普通版的应用 ID 和签名身份，以便延续原数据。Android 仍要求签名一致；其他发布者或临时 CI 签名的包可能不能覆盖，请先核对安装说明。

**每个构建都支持空间格式和 PGS 字幕吗？** 不完全相同。标准 libmpv 构建与可选导入的、经过验证的项目 mpv 后端存在能力差异，见[播放后端与格式](docs/BUILD.md#playback-backends)。不能仅从文件名推断格式支持。

**所有 8K 视频都能流畅播放吗？** 编码、码率、投影和硬件都会影响结果。模拟器截图不是头显性能基准。

**在哪里反馈问题？** 请在[本仓库 Issues](https://github.com/NorthBoundWisdom/immivio/issues)中提供设备、构建版本、格式与复现步骤。只提供可分发的样片，不上传账号凭据或私人媒体。

## 项目与开发

- 应用商店名称：**Immivio – VR & Spatial Media Player**
- [中文更新日志](CHANGELOG.zh-CN.md) · [Changelog](CHANGELOG.md)
- [源码构建](docs/BUILD.md) · [架构](docs/ARCHITECTURE.md) · [测试](docs/TESTING.md) · [贡献](CONTRIBUTING.md)
- 源码采用 [GPL-3.0-only](LICENSE)。第三方组件保留各自许可，包含内嵌 OpenList 的 AGPL-3.0 义务，详见[许可说明](docs/LICENSING.md)。

[**Ravo Studio**](https://northboundwisdom.github.io/Ravo/) — 整理、浏览与处理照片。

[**SonaFolio**](https://northboundwisdom.github.io/sonafolio/) — 将播客和媒体转为转写文本及本地知识库。
