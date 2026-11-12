# Immivio 清理遗留事项

2026-11-12 · 基线：`main` 上包含本文件的那次提交（未推送）。

本文件是给实现窗口的任务书。实现完成后交回 review；review 只读 diff，不跑测试，所以每一项都要在回报里附上你自己执行过的验证命令和结果。

## 约束

- 不改版本号、不打 tag、不发布、不推送。
- 只动任务里列出的范围；范围外发现的问题写进回报，不要顺手修。
- 需要头显才能确认的行为，写进 `docs/ACCEPTANCE.md` 的待验收列表，不要用主机测试代替。
- 依据和本文不符时（例如发现了本文没提到的调用方），跳过该项并在回报里写明证据（文件:行号）。
- C 组是所有者已经做出的决定，按其中写明的范围执行；标了"待所有者确认"的子项先不动。
- 格式化只针对你改过的文件：GDScript 用 `.cache/python-tools/formatting/bin/gdformat`，Python 用 `black`，Kotlin 用 ktfmt（见 `CONTRIBUTING.md`）。

## A 组：已确认有问题，可以直接修

### A1：（已并入 C2）

原本要修 `tools/Test-SmbSubtitlesDevice.ps1` 的 alpha 步骤。所有者决定整体移除 PowerShell 设备脚本，这个脚本随 C2 删除，不再单独修。

### A2：DLNA 排序错误的翻译键对不上

- **现象**：`translations.json` 里的键是 `Folder too large to sort; use source order`，而 `DlnaClient.kt:231` 和 `:282` 抛出的是 `Folder too large to sort`。两者不相等，这条错误在中文和日文界面下显示的是英文原文。
- **做法**：先确认这条消息到达界面的路径（是否经过 `I18n.t`），再让键和消息一致。以 Kotlin 侧实际抛出的文本为准。
- **验收**：加一条 Godot 或 JVM 断言，证明这条消息能查到译文。

### A3：五条没有精确引用的翻译

以下键在 `app/godot/scripts`、`android/player-plugin/src/main` 和 `licenses.json` 里都搜不到完全相同的字符串，上一轮因为有部分匹配而保留：

- `Alpha passthrough FPS limit`（对应的 `alpha_fps` 设置已退休）
- `Unable to load subtitle. Choose an SRT, ASS, SSA or VTT file.`
- `Unable to open account settings.`
- `Unable to read saved servers`
- 含 `movie.mp4 → movie.si.mix.m4a` 的那条说明

**做法**：逐条确认是否由字符串拼接或 Kotlin 错误消息产生；确认无来源的从三个语言里一起删除。删除前用 `git grep -F` 对整个仓库（不只是脚本目录）搜一遍，上一轮就因为只搜了脚本目录而误删过 `licenses.json` 引用的三条。

### A4：两张不再有使用方的测试图片

- `app/godot/media/c04_independent_mask.png` 和 `c04_independent_rgb.png`（及各自的 `.import`）原先只被 `render_c04_alpha.gd` 使用，该测试已随旧显示管线删除。
- 现在只剩 `tests/fixtures/c04_alpha.json` 和 `tools/media/generate_c04_fixtures.py` 提到它们。
- **做法**：删除这两张图和 `.import`，同步清单和生成脚本。`c04_independent_alpha.mp4` 仍被 `MpvDiagnostics.kt` 和 `benchmarks/mpv_gpu_probe.py` 使用，不要动。

### A5：残留的 RVM 字样

`git grep -n -E "RVM|rvm_" -- . ':!CHANGELOG.md' ':!website' ':!docs/ARCHITECTURE.md'` 目前还有约 20 处命中，分布在调试类注释、探针的 `scope` 文字、测试断言文案、fixture 清单和生成脚本的说明里。

- **做法**：改成描述现状的措辞。fixture 清单（`tests/fixtures/*.json`）里的文字要和生成脚本一起改，保持两边一致。
- **不要改**：`test_library_menu.gd:539` 和 `:718` 是"界面里不得出现这些名字"的断言；`test_library_menu.gd:309` 的 `"rvm_model": "fast"` 先确认是不是"旧设置被忽略"的输入，是就保留。

### A6：`THRU3D_` 前缀的环境变量

`tools/media/generate_mp07_motion_fixture.py:26` 读取 `THRU3D_FFMPEG`。用 `git grep -n "THRU3D_"` 找出全部同类变量，改成 `IMMIVIO_` 前缀。

## B 组：需要先调查，回报结论后再决定是否动手

### B1：调试用的测试素材名单

- `DebugDiagnosticsReceiver.kt` 约 320-340 行的 fixture 白名单里有 `mp05_person_still`、`mp07_motion_4k`、`mp08_8k_low`、`mp08_8k_high`、`mp08_8k_high_30`、`mp08_8k_long`、`mp08_4k`、`depth_2d`、`mpv_performance` 等名字。
- 已确认：`mp05_person_still` 在仓库里没有清单、没有生成脚本、也没有其他使用方。
- 已确认：`mp07_motion_4k` 有生成脚本（需要 `--source` 指定本地原片），但它生成的 `tests/fixtures/mp07_motion_4k.json` 不在仓库里；`Test-MpvSeekHoldDevice.ps1` 和 `Test-MpvSeekTimelineDevice.ps1` 依赖这个清单。
- 已确认：`mp08_8k_high_30` 被 `benchmarks/mpv_seek_strategy_device.py` 和 `mpv_startup_device.py` 当默认素材，仓库里没有清单也没有生成脚本。
- **要回答**：名单里每个名字，谁在用、素材从哪来。整理成表格：名字 · 使用方 · 清单/生成脚本 · 结论。
- **建议做法**：没有任何使用方的名字从白名单删除；有使用方但素材需要本地准备的，在 `docs/TESTING.md` 写清楚准备步骤，并让脚本在缺素材时给出明确的报错。
- **注意**：这项要在 C2 之后做。C2 会删掉一批使用方（例如依赖 `mp07_motion_4k` 的两个 `.ps1`），名单要按删除后的状态重新统计。

### B2：三个调试参数是否还有人用

- `QuestPlayerPlugin.kt:591-593` 在 `open` 指令里读取 `normal_fast`、`frame_cap`、`borrow_color`，对应 `MpvVideoBridge.kt` 的 `debugNormalFramePath`、`debugFrameCap`、`debugBorrowColor`。
- 已确认：`tools/` 和 `benchmarks/` 里没有任何脚本发送这三个参数。
- **要回答**：这三个开关在 `MpvVideoBridge` 里各自控制什么，去掉后生产路径是否完全不变。只报告，不改。

### B3：`media_state.gd` 里的旧管线分支

- `media_state.gd` 现在只被 `mpv_media_state.gd` 继承。它的 `apply()` 里还有 `"frame"`（带 4×4 变换矩阵）和 `"codec"` 分支，以及 `surface_timestamp_ns`、`coalesced_notifications`、`codec_dropped_frames`、`"frame_pairing": "direct_OES_only"` 等字段。
- 对应的 `media_frame`、`media_codec` 等信号已经从插件里删除，这些分支看起来不可能再被触发。
- **要回答**：`apply()` 的每个分支现在由谁调用；哪些字段还被报告、测试或设备探针读取。
- **建议做法**：确认无调用方后删除分支和字段，把剩余内容并进 `mpv_media_state.gd`；有测试断言这些字段的，一并更新并说明理由。

### B4：`profile` 参数现在的含义

- `mpv_video_display.gd:42-43` 的 `AUTOMATIC_PROFILE := "320x320"` 和 `PROFILES` 列表原本是推理输入尺寸；第 137 行的注释还写着 "ROI default"。
- 这个值仍然一路传到 `open_mpv_video`，Kotlin 侧用 `BUFFER_SHAPES` 校验，并在 `MpvVideoBridge.kt:869` 和 `:976` 作为 `session.dims` 使用；`file_mode_memory.gd` 还按文件保存它。
- **要回答**：`session.dims` 现在决定什么（遮罩缓冲尺寸？）；用户还能不能改它；按文件保存它是否还有意义。只报告，不改。

## C 组：所有者已决定（2026-11-12）

### C1：APK 里的"已移除组件"检查——不恢复

保持已删除的状态，不需要任何操作。`tools/Check-PublicSource.py` 仍然禁止把模型文件和二进制提交进仓库。

### C2：移除 PowerShell 设备脚本

所有者的决定：Windows 上的设备脚本维护成本大于意义，直接砍掉，不移植。

**删除**

- `tools/` 下全部 11 个 `Test-*.ps1`。
- `tools/environment/Activate-QuestEnvironment.ps1`（只被上述脚本引用）。
- `PSScriptAnalyzerSettings.psd1`，以及 `CONTRIBUTING.md` 里关于 PowerShell 格式化的说明。
- `tools/fixtures/download_panoramas.py` 文档字符串里的 PowerShell 示例改成 shell 写法。

**随之失去使用方的东西：逐个确认后删除**

- 只审计 `.ps1` 产出目录的 Python 脚本。已确认 `benchmarks/external_uri_device.py`、`local_access_device.py`、`local_selection_device.py` 分别只被对应的 `.ps1` 调用；`benchmarks/mpv_seek_hold_device.py` 读取的 `{mode}-before-report.json` 等文件也只有 `Test-MpvSeekHoldDevice.ps1` 会生成。其余 benchmark 逐个确认它们的输入由谁产生。
- 只为这些脚本服务的调试设施：`android/uri-fixture` 模块（含 `android/settings.gradle` 里的 include）、`LocalAccessTestProvider`、调试接收器里的 `DEBUG_LOCAL_ACCESS`、`DEBUG_LOCAL_SELECTION`、`DEBUG_MPV_URI` 等入口。**删除前必须确认没有其他使用方**：`configs/pico_store.py:21` 引用了 `LocalAccessTestProvider`（看起来是商店包的排除检查），`tools/Test-SelectedFeaturesDevice.py` 等 Python 探针也走同一个调试接收器。
- 删除 `uri-fixture` 模块会改变 Gradle 依赖图：按 `docs/BUILD.md` 的做法用 Gradle 重新生成锁文件和校验元数据，不要手改。

**保留并处理**

- `tools/media/Generate-C03Fixtures.ps1` 是 `app/godot/media/c03_sbs_grid.mp4` 的生成脚本，该素材仍被调试诊断和 `benchmarks/mpv_gpu_probe.py` 使用。把生成逻辑移植成 Python（参照 `tools/media/generate_c04_fixtures.py`），输出必须与现有文件逐字节一致或在回报里说明差异；然后删除 `.ps1` 并更新 `tests/fixtures/c03_sbs_grid.json` 的 `source` 字段。
- `tools/Test-SelectedFeaturesDevice.py` 已经是 Python，保留。

**不要动**

- `android/gradlew.bat`：Godot 导出工程会复制它。
- `configs/setup_hosted_ci.py` 里的 `pwsh` 调用和 `.github/workflows` 的 Windows runner：这是 Windows 上的 CI 构建，不是设备脚本。是否连 Windows CI 一起去掉**待所有者确认**，本轮不动。
- `docs/BUILD.md:54` 关于 Python 命令可以在 PowerShell 里运行的说明：与上一条绑定，同样不动。

**验收**

- `git ls-files '*.ps1' '*.psd1'` 没有输出。
- `git grep -n -i -E "\.ps1|PSScriptAnalyzer"` 只剩 `CHANGELOG.md` 里的历史记录（如果有）。
- 完整验证命令全部通过；被删除的 JVM 或 workflow 用例逐条说明理由。
- 在 `docs/TESTING.md` 里如实更新"设备探针"的现状：还剩哪些、各自需要什么素材。

### C3：`recent_menu` 改名为 `library_menu`

- 把 `main.gd` 的 `recent_menu` 改成 `library_menu`，`_show_recent_menu` 改成 `_show_library_menu`，同步所有脚本、测试、设备探针和文档。
- 真正表示"最近播放"的名字不要改：`list_recent`、`recent_scan.gd`、`test_recent_files.gd` 里关于最近文件存储的部分等。逐处判断，不要全局替换 `recent`。
- 单独一个提交，只包含改名，不夹带其他改动；放在 C2 之后、C4 之前做。
- 验收：`git grep -n "recent_menu\|_show_recent_menu"` 没有输出；Godot 测试数量和结果与基线一致。

### C4：继续收缩 coordinator 对 `main.gd` 私有成员的依赖

现状：`app/godot/scripts` 里 `host._xxx` 共 380 处。按下面的顺序分步做，每一步单独提交、单独验证；任何一步需要改变行为或测试注入方式就停下回报。

1. **`library_source_controller.gd` 的 81 处**：它访问的是资料库菜单（`LibraryMenu`）的私有状态，如 `_pending`、`_dlna_stack`、`_local_stack`。把这些状态的归属定下来：要么移进 controller 自己持有，菜单通过它读取；要么在菜单上提供不带下划线的访问入口。选改动更小的一种，并在回报里说明理由。
2. **跨 coordinator 的调用**：一个 coordinator 通过 `host._xxx()` 调用另一个 coordinator 的方法时，`main.gd` 只是转发。给 `main.gd` 的四个 coordinator 字段提供公开名字，让调用方直接调用目标 coordinator；之后删除 `main.gd` 里不再有调用方的转发函数。
3. **`main.gd` 真正持有的状态和方法**（如 `_viewer()`、`_eye()`、`_head_pose()`）：被外部使用的改成不带下划线的公开名字。

约束：

- 以下 7 个入口被测试通过继承 `main.gd` 覆写来注入假输入，必须继续经由 `host` 调用，不能改成直接调用：`_ray`、`_active_menu`、`_input_focused`、`_controller_allowed`、`_controller_ray`、`_head_tracked`、`_recenter`。开工前重新扫一遍测试里继承 `main.gd` 的类，名单以实际为准。
- 测试对私有成员的直接访问（更早的统计是 95 个测试中的 79 个）只在被改名的成员上同步更新，不做额外的测试重构。
- 不新增全局事件总线或服务容器。
- 验收：回报每一步前后的 `host._` 计数；Godot 测试数量和结果与基线一致。

## 待设备验收（不属于实现窗口的工作，记录在此）

- 外部 URI 授权测试：`android/uri-fixture` 的目标包名已改为 `com.northboundwisdom.immivio`。
- 普通播放与封装 alpha 文件播放：已移除 Media3 依赖；`alpha_ready()` 不再依赖 `inference_ran`。
- 菜单文案：删除了 65 条翻译，确认界面里没有冒出英文原文。
- Pico 和 OpenXR 目标：上一轮只构建并打包了 Quest Debug。
- CI：锁文件是用 Gradle 9.8.1 离线生成的，`configs/ci_toolchain.json` 指定的是 9.8.2；推送后留意依赖校验是否通过。

## 验证命令

在仓库根目录执行。本机 PATH 上没有 `gradle`，Android 相关步骤需要先设置：

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

涉及 Godot、Kotlin 或构建脚本的改动，再执行（改过 GDScript 后必须重新 configure）：

```sh
python3 configs/android_workflow.py configure --vendor Quest --build-type Debug
python3 configs/android_workflow.py build --vendor Quest --build-type Debug
python3 configs/android_workflow.py test --vendor Quest --build-type Debug --level all
python3 configs/android_workflow.py package --vendor Quest --build-type Debug
```

基线结果（2026-11-12）：workflow 77 项、website 4 项、JVM 205 项（10 项跳过）、Godot 102 项全部通过，ruff 零报错。结果低于这个基线必须在回报里解释。

## 回报格式

写在最终回复里，不要写进仓库：

1. 任务状态表：任务 · 状态（完成／部分／跳过／未执行）· 改动的文件 · 执行过的验证命令及通过数／失败数。
2. B 组每一项的调查结论，附证据（文件:行号）。
3. 删除的每条断言、翻译或文件，以及删除依据。
4. 新增到 `docs/ACCEPTANCE.md` 的待设备验收项。
5. 范围外发现，只列出不修改。
6. `git status --short` 和 `git diff --stat` 的完整输出。

## 执行顺序

A 组 → C2 → B 组（B1 依赖 C2 的结果）→ C3 → C4。B 组只回报结论的项不阻塞后面的步骤。
