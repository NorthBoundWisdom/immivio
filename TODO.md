# Immivio 后续任务与开发规划

2026-11-12 · 代码基线：`main` @ `ad9f142`。

本文件取代上一版任务书。上一版的 A 组、C2、C3、C4 已由实现窗口完成（`5df5525`…`ad9f142`），静态 review 的结论见第 0 节。后面各节按优先级排列：第 1 节是 review 发现的必须修正项，第 2 节起是规划。

工作方式不变：实现窗口动手，review 窗口只读 diff、不跑测试。

## 约束

- 不改版本号、不打 tag、不发布。发布要等所有者完成头显验收。推送需要所有者当次授权。
- 只动任务列出的范围；范围外的发现写进回报。
- 需要头显确认的行为写进 `docs/ACCEPTANCE.md` 的待验收列表。
- 依据和本文不符时跳过该项，回报证据（文件:行号）。
- 标了"仍待定"的项，没有答复前不动。
- 每个提交只做一件事，提交信息正文写明验证命令和通过数（上一轮 7 个提交都没有正文，见 R7）。
- 只格式化改过的文件：GDScript 用 `.cache/python-tools/formatting/bin/gdformat`，Python 用 `black`，Kotlin 用 ktfmt `--kotlinlang-style`。

## 0. 上一轮 review 结论（静态，未跑测试）

| 项 | 结论 |
| --- | --- |
| A3 无引用翻译 | 通过。5 条已从三个语言删除，全仓库无引用。 |
| A4 测试图片 | 通过，有一处小残留（R4）。 |
| A5 RVM 字样 | 通过。只剩 `test_library_menu.gd` 里应当保留的 3 处。 |
| A6 `THRU3D_` 变量 | 通过。剩下的 `THRU3D_SIGNING_PASSWORD` 在泄密检查的正则里，应当保留。 |
| A2 DLNA 排序翻译 | **任务书本身写错了**（见 R1）。实现窗口先改后撤，最终状态与改动前一致，没有造成损害。 |
| C2 移除 PowerShell | 通过，有三处要补（R2、R3、R5）。`.ps1`/`.psd1` 已清零，连带的 `uri-fixture` 模块、三个调试入口、四个审计脚本都已删除，`c03_sbs_grid.mp4` 未变且与清单的 sha256 一致。 |
| C3 改名 | 通过。`recent_menu`、`_show_recent_menu` 全仓库清零；提交里混入的非改名行都是 gdformat 重新折行。 |
| C4 解耦 | 通过。`host._` 从 380 降到 51，剩下的正好是 7 个测试注入入口。有两点需要跟进（R6 和第 3 节）。 |
| B1–B4 调查 | **review 窗口没有拿到调查结论**（回报在实现窗口的回复里）。B1 的白名单没有改动，TESTING.md 记录为"等待 review"。见第 2 节。 |
| 测试文件数 | Godot `test_*.gd` 103 个、`render_*.gd` 33 个、JVM 测试 54 个文件，改动前后相同。通过数由实现窗口负责，review 未核实。 |

## 1. Review 修正项（下一轮先做）

### R1：删除无引用的排序翻译键（已完成，`903ced5`）

- 事实：`Folder too large to sort` 这个键一直存在（`translations.json` 三个语言各一条），`DlnaClient.kt:231`、`:282` 的消息本来就能查到译文。上一版任务书说"键对不上"是错的。
- 真正的问题：`Folder too large to sort; use source order` 这个键全仓库只出现在 `translations.json` 里，没有任何来源。
- 做法：确认无来源后从三个语言删除。`test_i18n.gd:39` 新加的断言保留。
- 同步：`docs/ACCEPTANCE.md` 的 "Cleanup follow-up" 第一条描述的是一个不存在的缺陷，改成只验证"清理翻译后界面没有冒出英文"。

### R2：解释或撤销 `verification-metadata.xml` 的两条新增

- `f0387a5` 给 `android/gradle/verification-metadata.xml` 新增了 `androidx.annotation:annotation:1.1.0` 和 `androidx.arch.core:core-common:2.1.0` 两个 pom 条目，而所有锁文件都没有变化。
- 被删的 `uri-fixture` 模块是条件 include（`includeUriFixture=true` 时才加入），删除它不应该引入新依赖。
- 做法：说明这两条由哪个配置解析产生；如果只是重新生成时的副产物且离线构建不需要，撤销。

### R3：`DebugDiagnosticsReceiver.kt` 的格式

- `f0387a5` 在这个文件里去掉了一部分尾随逗号、改了缩进（忽略空白后仍有 17 增 37 删），与文件其余部分和同目录其他文件的风格不一致，看起来不是项目规定的 ktfmt 输出。
- 做法：用 ktfmt `--kotlinlang-style --do-not-remove-unused-imports` 重新格式化该文件，diff 应当只剩功能改动。

### R4：`generate_c04_fixtures.py` 的残留分支

- `encode()` 里仍然计算 `image_name = ... else "c04_independent_rgb.png"`，但独立素材已经改用临时文件，这个分支的值不再被使用。
- 做法：去掉无用分支，让代码读起来和实际行为一致。

### R5：`pico_store.py` 里已不存在的组件名

- `configs/pico_store.py:21` 的 `DEBUG_COMPONENTS` 仍列着 `LocalAccessTestProvider`，该类已删除。
- 做法：从集合里移除；`tests/workflow/test_pico_store.py` 如有对应用例一并更新。

### R6：公开名字的遮蔽检查

- `ad9f142` 把 `main.gd` 的成员改成了 `eye()`、`viewer()`、`grab`、`library_grab`、`trigger_taps`、`wearer_present` 等通用名字。
- 风险：`main.gd` 及继承它的测试类里如果有同名局部变量或参数，会遮蔽成员（GDScript 只给警告）。
- 做法：在 `main.gd` 和所有 `extends Main` / `extends "res://scripts/main.gd"` 的类里搜这些名字的局部声明，有遮蔽就改局部名。回报搜索命令和结果。

### R7：补提交说明（已完成，`903ced5`）

`903ced5` 的正文补记了上一轮 7 个提交的验证结果：workflow 77、website 4、发布脚本 17、JVM 205（10 项跳过）、Godot 102，Quest Debug 完成构建和打包；Pico/OpenXR 和头显未验证。

- 不改写已有提交。在本轮的第一个提交正文里，补记上一轮 7 个提交的验证结果（workflow、website、JVM、Godot 的通过数，以及构建/打包了哪些目标）。
- 之后每个提交都按"约束"一节写正文。

### R8：C03 生成脚本的小问题

- `tools/media/generate_c03_fixtures.py` 读取清单用的是固定路径，写回用的是 `--manifest`，两者不一致；改成读写同一个路径。
- 脚本要求 `--font` 且输出随 FFmpeg/字体版本变化，这是如实记录的限制，保留现状即可。

## 2. 上一轮遗留的调查项

实现窗口请把 B1–B4 的结论重新贴给 review 窗口（或写进本节），然后按下面的默认处理执行。

### B1：调试素材白名单

- 现状：`DebugDiagnosticsReceiver.kt` 的白名单仍接受 `mp05_person_still`、`mp07_motion_4k`、`mp08_8k_low`、`mp08_8k_high`、`mp08_8k_long`、`mp08_4k`、`depth_2d`；`docs/TESTING.md` 写明这些名字已经没有调用方。
- 默认处理：从白名单和大小限制分支里删除这 7 个名字；保留 `mp03_frame_identity`、`mp06_text_subtitles`、`mp08_8k_high_30`、`mpv_performance`。`tools/media/generate_mp07_motion_fixture.py` 随之失去用途，一并删除。
- 同时恢复 `82eb55e` 撤掉的那条缺素材报错（"Prepare local fixture … before running the probe"）：它只是让失败信息可读，不属于策略变更。
- 更新 `docs/TESTING.md` 里对应的两段。

### B2：三个调试开关（`normal_fast`、`frame_cap`、`borrow_color`）

- 没有任何脚本发送它们。默认处理：如果调查确认去掉后生产路径不变，删除 `QuestPlayerPlugin.kt` 里的读取和 `MpvVideoBridge.kt` 的 `debugNormalFramePath`、`debugFrameCap`、`debugBorrowColor` 及其字段；调试接收器里对应的三个参数一并删除。
- 如果其中某个开关在排查性能问题时仍有价值，保留它并在 `docs/TESTING.md` 写明用法。

### B3：`media_state.gd` 的旧分支

- 默认处理：确认 `"frame"`、`"codec"` 分支和 `surface_timestamp_ns`、`coalesced_notifications`、`codec_dropped_frames`、`frame_pairing`、`effect_revision` 无调用方后删除，把剩余内容并入 `mpv_media_state.gd`，删除基类文件。
- `effect_revision` 仍被 `mpv_video_display.gd` 赋值为 `presentation_revision`：改用后者的名字，或在回报里说明为什么必须保留。

### B4：`profile` 参数

- 待所有者决定，取决于调查结论。两种可能：
  - 它现在只决定遮罩缓冲尺寸且用户无法修改：固定为常量，删除 `PROFILES` 列表、按文件保存的字段（`file_mode_memory.gd` 走版本化迁移）和调试接收器的 `profile` 参数。
  - 它仍影响画质或性能：保留，但改掉"ROI default"这类过期注释，并在 `docs/ARCHITECTURE.md` 写明含义。

## 3. 架构：把上一轮的"改名"推进到"归属"

上一轮 C4 把私有访问降到了 51 处，但其中两步是换名字而不是换归属。按下面的顺序继续，每步单独提交。

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

## 4. 发布前必须完成的事（所有者）

这些不属于实现窗口。

1. **头显验收**。至少覆盖：
   - 普通播放、SBS/TB、VR180/360、封装 alpha 文件（Media3 已移除，`alpha_ready()` 的判定变了）。
   - 三种语言下浏览资料库、设置、播放菜单，确认没有冒出英文原文（共删除约 70 条翻译）。
   - 手柄光束、抓取、菜单跟随、重新居中（C4 改动了 coordinator 之间的调用路径）。
   - SMB、DLNA、媒体服务器、本地卷的浏览和播放（S1 相关状态的访问方式变了）。
   - `docs/ACCEPTANCE.md` 里既有的待验收列表。
2. **Pico 和 OpenXR 目标**的构建与打包。上一轮和本轮都只验证了 Quest Debug。
3. **推送后看 CI**。锁文件和校验元数据是用本机的 Gradle 9.8.1 离线生成的，`ci_toolchain.json` 指定 9.8.2；Windows 和 macOS runner 都要过。
4. **CHANGELOG**。这 9 个提交对使用者可见的变化很少（安装包变小、移除了无用依赖），发布时决定是否单列一条。

## 5. 工具链与 CI

### T1：把现在靠人工跑的检查接进 CI

以下检查目前只在本机手动执行，任何一项都可能悄悄退化：

- `ruff check .`（现在零报错）。
- `gdformat --check` 覆盖全部 GDScript。
- ktfmt 检查（R3 就是没有这道检查的结果）。
- `tools/Check-PublicSource.py`、`tools/check_website.py`。
- 做法：加一个轻量的 lint job（只需 Python，不需要 Android SDK），PR 和 push 都跑。

### T2：翻译一致性检查

- 这一轮人工清了三次无引用翻译，还误删过一次。写成脚本：
  - 每个键必须能在源码（GDScript、Kotlin、`licenses.json`）里找到完全相同的字符串，或者出现在一份显式的"动态键"清单里。
  - 三个语言的键集合必须相同（现在是相同的）。
  - 源码里传给 `I18n.t` 的字面量必须有译文。
- 放进 `tests/workflow` 或 Godot 测试，随主机测试一起跑。

### T3：`render_*.gd` 的加载检查

- 33 个渲染测试需要真实 GPU，不在无头测试里运行，改名时很容易坏掉而不被发现（C3、C4 改了其中好几个）。
- 做法：在主机测试里加一步，只做脚本加载和编译，不执行。

### T4：`.uid` 与孤立文件检查

- 本轮清理发现过孤立的 `.uid` 和无引用的着色器。加一个检查：每个 `.uid` 必须有对应文件；`app/godot/shaders` 和 `scripts` 下的文件必须能从 `project.godot` 可达，或在测试、工具里被引用。

### T5：本机工具链

- 本机没有 `gradle` 命令，每次都要手动拼 `GRADLE_EXE`。在 `docs/BUILD.md` 里写明推荐的本机设置，或让 `android_workflow.py` 在未设置时自动使用 `.cache/gradle/wrapper/dists` 下与 `ci_toolchain.json` 版本一致的发行版。
- 把本机的 Gradle 对齐到 9.8.2，避免本机和 CI 生成的锁文件出现差异。

### T6：移除 Windows CI（已决定，2026-11-12）

决定：去掉 Windows 构建线，只保留 macOS。依据：

- 发布包只取 macOS 构建。`tools/prepare_android_release.py:53` 拒绝非 macOS 的回执，`publish-android-release.yml` 只下载 `Immivio-Android-Release-macOS`。
- Windows 那条线是对同一份源码的重复构建和测试，每次 push 都跑（`on.push.branches: ["**"]`），最长 90 分钟。
- 所有者只在 macOS 上开发，Windows 设备脚本已全部移除。

**排在发布之后做**（阶段 6 之前，见第 10 节）：发布流程目前要求两条线都成功，不要在下一次发布前改动它。

范围：

- `.github/workflows/android-release.yml`：`matrix.include` 只留 macOS。
- `tools/select_android_release.py:11` 的 `BUILD_JOBS` 和第 38 行的报错改成只要求 macOS；`tools/test_prepare_android_release.py` 里涉及 `Release / Windows` 和 `ci_host == "Windows"` 的用例同步更新（"非 macOS 回执被拒绝"这条断言保留，换一个非 macOS 的值）。
- `tools/prepare_android_release.py:143` 发布说明里 "Both Windows and macOS CI builds passed" 的措辞。
- `configs/setup_hosted_ci.py`：删除 `windows` 分支（Godot Windows 资产、`gradle.bat`、SDK 路径空格处理、`pwsh` 注册字体）；`configs/ci_toolchain.json` 删除 `GodotWindows`；对应的 `tests/workflow/test_hosted_ci.py` 用例更新。
- `docs/BUILD.md:54` 的 PowerShell 说明和第 146 行的 runner 描述；`docs/TESTING.md:28` 保持不动（原生测试本身仍可在三个平台构建）。

不要动：

- `configs/player_build.py`、`check_environment.py` 里的 `os.name == "nt"` 分支和 `android/gradlew.bat`。它们让脚本在 Windows 上仍然可以手动运行，删除它们没有收益，只有风险。文档里把 Windows 从"CI 验证过"降级为"未经验证，可能可用"。

验收：workflow 和发布脚本测试全过；推送后只触发 macOS 一条构建线且成功。

## 6. 设备探针

### D1：一个统一的设备探针入口

- 现状：`tools/Test-SelectedFeaturesDevice.py` 和 `benchmarks/` 下的几个设备脚本各自实现了 adb 调用、调试广播、等待报告、拉取文件。`docs/TESTING.md` 承认 GPU、core、audio 三类报告"没有端到端的驱动"，只能手动发广播再手动拉 JSON。
- 目标：抽出一个共用的 Python 模块（设备选择、APK 一致性校验、发送请求、等待带 request key 的报告、保存证据），现有脚本改为调用它；再补上 GPU、core、audio 三类报告的驱动。
- 输出统一放在 `artifacts/captures/device/`。

### D2：只重建外部 URI 授权的自动化（已决定，2026-11-12）

随 PowerShell 一起删除的四类设备自动化，处理如下：

| 类别 | 决定 | 理由 |
| --- | --- | --- |
| 外部 URI 授权与撤销 | **用 Python 重建** | 跨应用、跨 UID 的权限行为，Android 或头显系统升级后最容易变；手动验收难以覆盖撤销和进程重启后的状态 |
| 本地文件访问预检 | 不重建 | 逻辑由 JVM 测试覆盖（`LocalStorageVolumesTest` 等），设备上的差异在日常使用中立刻可见 |
| 文档选择 | 不重建 | 依赖系统选择器界面，自动化本来就绕过了它；手动验收更真实 |
| seek 冻结帧像素对比 | 不重建 | Godot 侧已有 `test_mpv_seek_hold.gd` 和渲染测试；设备上的像素对比维护成本高 |

外部 URI 的重建范围（在 D1 完成后做）：

- 恢复一个独立 UID 的测试 APK（原 `android/uri-fixture`，可从 `f0387a5^` 取回并改用当前应用 ID），仍然用条件 include，默认构建不包含它。
- 恢复 `DEBUG_MPV_URI` 入口和 `MpvDiagnostics.requestExternal`。
- 用 D1 的共用模块写驱动：安装 fixture → 授权 → 播放器经 FD 解码 → 撤销 → 确认访问失败 → 重启进程后确认不残留授权。
- 恢复模块会再次改变 Gradle 依赖图，锁文件和校验元数据由 Gradle 重新生成。
- `docs/ACCEPTANCE.md` 里"外部 URI 授权需手动验收"那条，在驱动可用后改为引用该驱动。

其余三类保持手动验收，在 `docs/ACCEPTANCE.md` 的待验收列表里各留一条。

### D3：素材准备

- `mp08_8k_high_30` 是两个性能探针的默认素材，但仓库里没有生成方式，只能自备。要么提供一个从合成源生成同规格素材的脚本，要么把探针的默认值改成必填参数，避免"默认值指向一个不存在的文件"。

## 7. 依赖

| 项 | 现状 | 建议 |
| --- | --- | --- |
| OpenXR loader | 1.1.54，上一轮因需与 Godot OpenXR Vendors 5.1.0 对齐而未升 | 确认 Vendors 5.1.0 自带的 loader 版本；能升则升，需头显验收 |
| Gradle | CI 9.8.2，本机 9.8.1 | 本机对齐（见 T5） |
| Pillow | 12.3 | 13.0 是大版本，只影响素材工具；升级后重跑 C04 生成并比对输出 |
| bcprov / slf4j | 与 jcifs 3.0.4 的 pom 对齐 | 保持；bcprov 有安全更新时再评估是否脱离对齐 |
| GitHub Actions | 固定在 commit | 推送后统一升级一次并观察 |
| Media3 | 已移除 | — |

依赖升级一次只动一个，锁文件和校验元数据一律由 Gradle 生成，升级后看 `verification-metadata.xml` 的 diff 里有没有意外的传递依赖（参见 R2）。

## 8. 文档

- **`docs/ACCEPTANCE.md`**：文件里混着当前待验收项和多轮历史记录。拆成两部分：顶部只放"当前待验收"，历史记录按日期归档到文件后半部分或单独文件。
- **`docs/ARCHITECTURE.md`**：C3、C4 之后，coordinator 的公开名字（`input_coordinator`、`playback_coordinator`、`settings_controller`、`presentation_coordinator`）和 `library_menu` 应当出现在文档里；S1、S2 完成后再更新一次。
- **`docs/SELECTED_UPSTREAM_PORTS.md`**：第 183 行引用了上游的 `file_subtitle_layout_memory.gd`、`test_subtitle_layout_memory.gd`，读起来像本仓库的文件，标明它们是上游路径。
- **`docs/TESTING.md`**：新加的 "Device probes and local media" 一节信息准确但很密，B1 处理完后重写成表格：脚本 · 是否需要设备 · 需要的素材 · 素材来源。
- **`README.md`**：确认没有再提到已删除的重构计划和 PowerShell 脚本（上一轮已处理链接，发布前再读一遍）。

## 9. 命名遗留（已决定，2026-11-12）

这些名字来自原项目，不影响功能。逐项决定如下：

| 名字 | 决定 | 理由 |
| --- | --- | --- |
| 应用 ID `com.northboundwisdom.immivio` | **永不改动** | 改了就无法覆盖安装，用户数据丢失 |
| Kotlin/Java 包名 `org.vrpassthroughplayer.plugin` | **不改** | 见下 |
| Godot 插件目录与单例 `quest_player`、`QuestPlayerPlugin` | **不改** | 见下 |
| Gradle 根工程名 `VRPassthroughPlayerAndroid` | **改为 `ImmivioAndroid`** | 只出现在 `android/settings.gradle`，不进入产物 |
| 调试属性前缀 `debug.vrpp.*` | **改为 `debug.immivio.*`** | 只有调试构建和几个 Python 探针读写，改动面小 |
| 日志标签 `Quest*`（如 `QuestDlna`、`QuestCapabilityProbe`） | **改为 `Immivio*`** | 三个头显平台共用，带 Quest 会误导排查 |
| 文档和注释里把三个平台统称为 Quest 的地方 | **随手改** | 遇到就改，不单独立项 |

包名和插件名不改的理由：

- 改动面覆盖全部 Kotlin 源码、C++ 侧的 JNI 函数名（`Java_org_vrpassthroughplayer_…`）、GDScript 里 `JavaClassWrapper.wrap` 的字符串、ProGuard 规则、`pico_store.py` 的组件名检查和导出预设。任何一处漏改都是运行时才暴露的崩溃，主机测试发现不了。
- 这些名字用户看不到，也不出现在商店或文档的对外部分。
- 收益只是读代码时少一点困惑；在 `docs/ARCHITECTURE.md` 里用一段话说明"包名和插件名沿用原项目，不代表只支持 Quest"就能达到同样效果。**这段说明本轮就加**。
- 如果将来因为别的原因必须动 JNI 层（例如拆分插件），再顺带改名。

三个要改的名字的做法：

- 排在阶段 9。一个提交改一个名字。
- `debug.vrpp.*`：同步 `benchmarks/` 里设置属性的脚本、`docs/TESTING.md`，以及 Kotlin 侧读取的位置；用 `git grep -n "debug\.vrpp"` 确认清零。
- 日志标签：只改 `Log.x(TAG, …)` 的标签字符串，不改类名；`benchmarks/` 和文档里按标签过滤 logcat 的地方同步。
- 根工程名：确认没有脚本按工程名定位构建产物（`git grep -n VRPassthroughPlayerAndroid`）。

## 10. 建议的执行顺序

| 阶段 | 内容 | 谁 | 前置 |
| --- | --- | --- | --- |
| 1 | R2–R6、R8（R1、R7 已完成）；`ARCHITECTURE.md` 加包名说明（第 9 节） | 实现窗口 | — |
| 2 | B1–B3 按默认处理执行；B4 等调查结论 | 实现窗口 | B 组结论交给 review |
| 3 | T1–T5（把检查接进 CI 和主机测试） | 实现窗口 | 阶段 1 |
| 4 | 头显验收、Pico/OpenXR 构建、确认 CI 两条线都过 | 所有者 | 阶段 1–2 |
| 5 | 发布 | 所有者 | 阶段 4 |
| 6 | T6 移除 Windows CI | 实现窗口 | 阶段 5 |
| 7 | S1 → S2 → S3 | 实现窗口 | 阶段 5（避免发布前再动交互路径） |
| 8 | D1，随后 D2（外部 URI）、D3 | 实现窗口 | 阶段 2 |
| 9 | S4、S5、文档整理；第 9 节的三个改名；依赖升级 | 实现窗口 | 阶段 7 |

阶段 3 排在验收之前是有意的：这些检查不改变应用行为，却能防止后面每一轮清理再出现"误删翻译""格式跑偏"这类问题。阶段 6 排在发布之后，是因为发布流程目前要求 Windows 和 macOS 两条线都成功，发布前不动它。阶段 7 排在发布之后，是因为 S1、S2 会再次改动输入和资料库的调用路径，放在验收之前等于让验收作废。

## 决定记录

| 事项 | 状态 |
| --- | --- |
| APK "已移除组件"检查 | 不恢复（所有者，2026-11-12） |
| PowerShell 设备脚本 | 全部移除，已完成（所有者，2026-11-12） |
| 推送 | 已推送 `main`（所有者授权，2026-11-12） |
| Windows CI | 移除，排在下次发布之后（T6） |
| 设备自动化重建 | 只重建外部 URI 授权（D2） |
| 命名遗留 | 包名、插件名不改；工程名、调试属性前缀、日志标签改（第 9 节） |
| B4 `profile` 参数 | **仍待定**：需要先看到调查结论 |

后三项由 review 窗口受所有者委托决定；不同意任何一项，直接改本表和对应章节即可。

## 验证命令

在仓库根目录执行。本机 PATH 上没有 `gradle`：

```sh
source "$HOME/.config/dev-environment/environment.sh"
export GRADLE_EXE="$(ls -d "$PWD"/.cache/gradle/wrapper/dists/gradle-9.8.1-bin/*/gradle-9.8.1/bin/gradle)"
export GRADLE_USER_HOME="$PWD/.cache/gradle"
export IMMIVIO_MPV_LIB_DIR="$PWD/.cache/verified-mpv/arm64-v8a"
```

每组做完后：

```sh
python3 -m unittest discover -s tests/workflow
python3 -m unittest discover -s tests/website
python3 tools/test_prepare_android_release.py
python3 tools/Check-PublicSource.py
python3 tools/check_website.py
ruff check .
git diff --check
```

涉及 Godot、Kotlin 或构建脚本的改动（改过 GDScript 后必须重新 configure）：

```sh
python3 configs/android_workflow.py configure --vendor Quest --build-type Debug
python3 configs/android_workflow.py build --vendor Quest --build-type Debug
python3 configs/android_workflow.py test --vendor Quest --build-type Debug --level all
python3 configs/android_workflow.py package --vendor Quest --build-type Debug
```

基线（2026-11-12，`c00dc4d` 时由 review 窗口实测）：workflow 77 项、website 4 项、JVM 205 项（10 项跳过）、Godot 102 项全部通过，ruff 零报错。`ad9f142` 的结果由实现窗口负责提供；低于基线必须解释。

## 回报格式

写在最终回复里，不要写进仓库：

1. 任务状态表：任务 · 状态（完成／部分／跳过／未执行）· 提交 · 执行过的验证命令及通过数／失败数。
2. 调查项的结论，附证据（文件:行号）。
3. 删除的每条断言、翻译或文件，以及依据。
4. 新增到 `docs/ACCEPTANCE.md` 的待设备验收项。
5. 范围外发现，只列出不修改。
6. `git log --oneline` 的新增提交和 `git status --short`。
