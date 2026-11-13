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
- [ ] **推送后复验 CI**。发布前 Windows、macOS 和 Source checks 均须通过；重点复验 Gradle 缓存夹具的 Unix/Windows 入口修正。推送需要所有者当次授权。
- [ ] **CHANGELOG**。发布时决定是否单列安装包变小、移除无用依赖等变化。
- [ ] **发布**。所有者完成头显验收、目标构建和 CI 确认后执行；此前不改版本号、不打 tag、不发布。

## 2. 发布后调整

### B4：`profile` 参数常量化与保存记录迁移

- [ ] 固定遮罩缓冲尺寸为 `320x320` 常量；不改变视频解码或颜色输出尺寸。
- [ ] 删除 `PROFILES` 列表、按文件保存的 `profile` 字段及调试接收器的 profile 参数。
- [ ] 为 `file_mode_memory.gd` 做版本化迁移，保留既有几何、立体、字幕和时序偏好，不能因缺字段而丢弃旧记录。
- [ ] 下一次发布之后单独提交并验证；发布前不修改运行路径和保存格式。

### T6：移除 Windows CI（已决定，2026-11-12）

决定：去掉 Windows 构建线，只保留 macOS。依据：

- 发布包只取 macOS 构建。`tools/prepare_android_release.py:53` 拒绝非 macOS 的回执，`publish-android-release.yml` 只下载 `Immivio-Android-Release-macOS`。
- Windows 那条线是对同一份源码的重复构建和测试，每次 push 都跑（`on.push.branches: ["**"]`），最长 90 分钟。
- 所有者只在 macOS 上开发，Windows 设备脚本已全部移除。

**排在下一次发布之后做**：发布流程目前要求两条线都成功，不要在下一次发布前改动它。

范围：

- `.github/workflows/android-release.yml`：`matrix.include` 只留 macOS。
- `tools/select_android_release.py:11` 的 `BUILD_JOBS` 和第 38 行的报错改成只要求 macOS；`tools/test_prepare_android_release.py` 里涉及 `Release / Windows` 和 `ci_host == "Windows"` 的用例同步更新（"非 macOS 回执被拒绝"这条断言保留，换一个非 macOS 的值）。
- `tools/prepare_android_release.py:143` 发布说明里 "Both Windows and macOS CI builds passed" 的措辞。
- `configs/setup_hosted_ci.py` 的 Windows 分支、`configs/ci_toolchain.json` 的 `GodotWindows` 资产和对应测试保留；不再由 CI 执行，仍可供手动准备 Windows 环境。
- `docs/BUILD.md:54` 的 PowerShell 说明和第 146 行的 runner 描述；`docs/TESTING.md:28` 保持不动（原生测试本身仍可在三个平台构建）。

不要动：

- `configs/player_build.py`、`check_environment.py` 里的 `os.name == "nt"` 分支和 `android/gradlew.bat`。它们让脚本在 Windows 上仍然可以手动运行，删除它们没有收益，只有风险。文档里把 Windows 从"CI 验证过"降级为"未经验证，可能可用"。

验收：workflow 和发布脚本测试全过；推送后只触发 macOS 一条构建线且成功。

## 3. 架构整理

S1 → S2 → S3 排在下一次发布之后，避免在发布验收前再次改动输入和资料库调用路径。S4、S5 在这三项之后推进；每步单独提交。

### S1：资料库来源状态移进 controller

- 现状：`de4c244` 在 `library_menu.gd` 上加了 18 个 `source_*` 属性和 4 个 `source_*` 函数，逐个转发到菜单的私有变量；`library_source_controller.gd` 改为访问这些入口。耦合换了名字，状态仍在菜单里。
- 副作用：多个入口声明为 `Variant`，而底层是 `String`、`bool`、`Dictionary`，丢了类型。
- 目标：SMB、DLNA、本地卷这三组来源状态由 `library_source_controller.gd` 持有，菜单通过 controller 读取。完成后删除全部 `source_*` 转发。
- 步骤：先按来源分三次迁移（本地卷 → SMB → DLNA），每次迁移后菜单里对应的私有变量清零。
- 约束：菜单的绘制和交互行为不变；直接读这些私有变量的测试（约 8 个文件）同步改为读 controller。

### S2：测试注入入口改成显式接口

- 现状：7 个入口（`_ray`、`_active_menu`、`_input_focused`、`_controller_allowed`、`_controller_ray`、`_head_tracked`、`_recenter`）靠测试继承 `main.gd` 覆写来注入假输入，所以 coordinator 必须继续走 `host._xxx`。
- 目标：把这 7 个入口收进一个可替换的输入来源对象（例如 `InputSource`，生产实现读 XR 控制器，测试实现返回固定值），`main.gd` 持有它，coordinator 直接调用。
- 完成标准：`app/godot/scripts` 里 `host._` 清零；测试不再需要继承 `main.gd` 来改输入。

### S3：消除按字符串访问的私有成员

- `mpv_video_display.gd:2276`、`:2302` 用 `host.has_method("_menu_state")`、`"_canvas_controls_snapshot"`，`playback_coordinator.gd:208` 用 `host.get("_finishing_app")`。这些引用改名时不会被任何工具发现。
- 目标：改成公开方法，由持有者显式传入（Callable 或接口），不再按名字反射。

### S4：测试对私有成员的访问

- 更早的统计是 95 个测试里有 79 个直接访问私有成员。上一轮只同步了被改名的成员。
- 做法：先出一份清单（成员名 · 访问次数 · 所在测试），按访问次数从高到低，给前 20 个成员提供公开的只读快照或测试专用入口。不要求一轮做完。

### S5：拆分过大的脚本

按当前行数：`library_menu.gd` 约 3200 行、`mpv_video_display.gd` 约 2560 行、`player_menu.gd` 约 1940 行、`main.gd` 约 1210 行、两个 coordinator 各约 1000 行。

- `mpv_video_display.gd`：把调试命令处理和调试报告（`_on_debug_command`、`_write_debug_report` 一带，约 400 行）拆到独立脚本，仅 Debug 构建加载。
- `library_menu.gd`：关于页与许可阅读器、来源列表（S1 之后）各自独立。
- `player_menu.gd`：字幕、音轨、画面调整三组弹层已有 `playback_popups.gd`，把仍留在主文件里的绘制函数迁过去。
- 每次拆分只移动代码，不改行为；以 Godot 测试数量和结果不变为准。

## 4. 依赖升级后验收

依赖升级一次只动一个，锁文件和校验元数据一律由 Gradle 生成；升级后检查 `verification-metadata.xml` 的 diff，确认没有意外的传递依赖。

- [ ] **头显验收**：验证 OpenXR loader 1.1.65 的启动、会话恢复、输入与播放；验证 bcprov 1.87 / SLF4J 2.0.20 下的 SMB 登录、浏览、随机读取、签名及加密。详细范围见 `docs/ACCEPTANCE.md`。
- [ ] **GitHub Actions**：推送后观察升级后的固定 commit，确认 Windows、macOS、Source checks 及网站发布流程成功。

## 5. 文档

- [ ] **`docs/ACCEPTANCE.md`**：顶部只放“当前待验收”，历史记录按日期归档到文件后半部分或单独文件。
- [ ] **`docs/ARCHITECTURE.md`**：补充 coordinator 的公开名字（`input_coordinator`、`playback_coordinator`、`settings_controller`、`presentation_coordinator`）和 `library_menu`；S1、S2 完成后再更新一次。
- [ ] **`README.md`**：发布前复查，确认没有再提到已删除的重构计划和 PowerShell 脚本。

## 6. 命名整理

以下三项排在 S1 → S2 → S3 之后，一个提交改一个名字。应用 ID、Kotlin/Java 包名、Godot 插件目录、插件类和单例名保持不变。

- [ ] **Gradle 根工程名**：将 `VRPassthroughPlayerAndroid` 改为 `ImmivioAndroid`。用 `git grep -n VRPassthroughPlayerAndroid` 确认没有脚本按工程名定位构建产物。
- [ ] **调试属性前缀**：将 `debug.vrpp.*` 改为 `debug.immivio.*`；同步 `benchmarks/` 脚本、`docs/TESTING.md` 和 Kotlin 侧读取位置，用 `git grep -n 'debug\.vrpp'` 确认旧前缀清零。
- [ ] **日志标签**：将 `Quest*`（如 `QuestDlna`、`QuestCapabilityProbe`）改为 `Immivio*`。只改 `Log.x(TAG, …)` 的标签字符串，不改类名；同步 `benchmarks/` 和文档里按标签过滤 logcat 的位置。
- [ ] **文档与注释**：遇到把三个平台统称为 Quest 的地方时，改成准确的平台表述。
