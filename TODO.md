# Immivio 未完成任务

## 1. 发布前验收与发布（所有者）

- [ ] **头显验收**，至少覆盖：
  - 普通播放、SBS/TB、VR180/360、封装 alpha 文件（Media3 移除后，`alpha_ready()` 的判定有变化）。
  - 三种语言下浏览资料库、设置、播放菜单，确认没有冒出英文原文。
  - 手柄光束、抓取、菜单跟随、重新居中。
  - SMB、DLNA、媒体服务器、本地卷的浏览和播放。
  - `docs/ACCEPTANCE.md` 中的其余待验收项。
- [ ] **D1：统一设备探针的真机验收**。验证设备选择、APK 一致性校验、发送请求、等待带 request key 的报告、保存证据，以及 GPU、core、audio 三类报告的驱动；确认输出位于 `artifacts/captures/device/`。实现已具备，目前只用假 ADB 验证过。
- [ ] **D2：外部 URI 授权自动化的真机验收**。验证独立 UID fixture APK 的安装、授权、播放器经 FD 解码、撤销后访问失败，以及重启进程后不残留授权。实现已具备，目前只用假 ADB 验证过。
- [ ] **推送后复验 CI**。确认 Android workflow 仅触发 macOS 一条构建线且成功，Source checks 通过。推送需要所有者当次授权。
- [ ] **CHANGELOG**。发布时决定是否单列安装包变小、移除无用依赖等变化。
- [ ] **发布**。所有者完成头显验收、目标构建和 CI 确认后执行；此前不改版本号、不打 tag、不发布。

## 3. 依赖升级后验收

依赖升级一次只动一个，锁文件和校验元数据一律由 Gradle 生成；升级后检查 `verification-metadata.xml` 的 diff，确认没有意外的传递依赖。

- [ ] **头显验收**：验证 OpenXR loader 1.1.65 的启动、会话恢复、输入与播放；验证 bcprov 1.87 / SLF4J 2.0.20 下的 SMB 登录、浏览、随机读取、签名及加密。详细范围见 `docs/ACCEPTANCE.md`。
- [ ] **GitHub Actions**：推送后观察升级后的固定 commit，确认 macOS Android 构建、Source checks 及网站发布流程成功。

## 4. 文档

- [ ] **`docs/ACCEPTANCE.md`**：顶部只放“当前待验收”，历史记录按日期归档到文件后半部分或单独文件。
- [ ] **`README.md`**：发布前复查，确认没有再提到已删除的重构计划和 PowerShell 脚本。
