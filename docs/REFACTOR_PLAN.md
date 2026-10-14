# Immivio 重构计划

基线：`41f48d5`，2026-10-13。本文取代 [旧架构评估 issue #1](https://github.com/NorthBoundWisdom/immivio/issues/1)；该 issue 已关闭，原因是其 AI 交付与降级任务已失去适用范围。模块边界、资源所有权和设备验证的建议仍然保留。

## 最新代码的判断

继续使用 Godot/OpenXR → Kotlin → libmpv/FFmpeg/C++，以及 Go/OpenList 的整体分层。重构集中在职责、接口和生命周期，逐批替换实现，每批保持可构建。

| 部位 | 当前证据 | 实际问题 |
| --- | --- | --- |
| Godot 主入口 | `main.gd` 2,377 行；照片、视频、输入、菜单、持久化和诊断混合 | 主入口既组装对象，又直接维护多个业务状态机；迁移和持久化规则散在事件处理里 |
| Godot 展示与菜单 | `library_menu.gd` 1,793 行、`mpv_video_display.gd` 1,744 行、`player_menu.gd` 1,560 行、`photo_display.gd` 1,228 行 | 页面、媒体状态和平台调用交织；已删除的模型预热和效果选择仍有空壳方法 |
| Kotlin 播放编排 | `MpvVideoBridge.kt` 820 行；已有 `MediaSessionGate`、`DecodedFrameGate`、`FramePairGate`、`PairDisplayGate` 等独立状态机 | URI/FD 所有权、播放宿主、GPU 捕获、显示租约和诊断仍集中在桥接类；不能忽略已有 gate 再造一套状态机 |
| 原生 GPU 桥 | `render_bridge.cpp` 1,408 行；Kotlin 声明了无调用者的 ROI、scout、模型输入读回和 MNN 零拷贝入口 | 推理运行时已经移除，接口和内部处理链尚未完全退休；存在额外 shader、缓冲和维护负担 |
| 跨层帧描述 | JSON 中仍有 `model_generation`、`effect_revision`、`alpha_requested` 等历史字段 | 一部分仍参与帧身份和拒绝旧帧的验证；直接删字段会破坏现有显示契约，必须统一迁移 |
| 构建回执 | `input_signature()` 原先未记录 Kotlin/C++/Godot 生产源码 | JNI 或展示代码变化后，旧 AAR 可能仍被判为当前产物；重构前需补上源码失效检查 |
| 构建与依赖 | FreeCM 1 项必需源码、20 项默认关闭源码和 OpenXR 插件；Gradle/Go 已恢复原生锁文件 | 已收缩到合理边界，不再将 Python、SDK、大型媒体库或包管理器元数据塞进 FreeCM |
| 发布与文档 | 单一播放版本、3 个 Android 目标、6 个中英文网站页面；旧工具与机器回执已退休 | 后续改动需要同步当前构建入口、契约测试和用户兼容说明，不再恢复 AI/No-AI 双版本 |

上述为静态代码检查和已有主机/打包验证，不能替代头显上的资源、画面和持续性能验收。

## 重构约束

- 保留用户数据和升级能力：应用 ID、签名身份、存储授权、账号、队列、历史、音轨/字幕选择和模式文件的迁移必须有验证。
- 每个显示帧保持可核对的会话、代次、源 epoch、frame ID、PTS、slot token 和 fence；Godot 完成最后一次绘制后才能释放生产者与消费者租约。
- 区分 UI 主线程、播放工作线程、Godot GL 线程和 native 所有者 EGL context。context 重建不能在新 context 删除旧 GL 名称。
- 普通与打包立体播放使用标准 libmpv；媒体兼容性需要单独进行设备验收。
- 可以删除失去调用者的内部 API，不保留永久空实现。持久化数据和仍被消费者读取的消息字段采用明确迁移。
- 不新增通用服务容器、全局事件总线或跨语言代码生成系统。优先复用现有 gate 和明确的模块接口。
- 主机工具、大型库预配置；FreeCM 的可选依赖继续默认关闭。配置/编译/测试不安装工具。

## 批次与完成标准

| 批次 | 实施内容 | 验证及交付 |
| --- | --- | --- |
| R1：收紧已退休能力的接口 | 抽出设置迁移；删除 Godot 模型预热、无调用者的 profile 切换与 Alpha FPS 分发；删除无调用者的 `FrameTimeline` 和 RenderBridge 推理 JNI 入口；移除 `captureTexture` 的推理输入开关；构建回执记录生产源码变化 | 旧配置只清除已退休字段，普通设置保留，重复迁移无副作用；旧控制事件不能重建设置；源码增删改后旧构建不能打包；Godot、JVM、Android native 编译及 APK 校验通过 |
| R2：缩小原生渲染核心 | 在 R1 的封闭 API 基础上删除内部 scout/ROI、推理 PBO/AHardwareBuffer、深度 warp 链；拆分 GL 状态保护、slot/租约、冻结帧与 JNI 适配 | GPU copy、借用颜色、opaque mask、冻结/seek、context 重建和释放行为保持；补充实际 GLES 与设备对比证据后再宣称 GPU 行为验收 |
| R3：集中播放契约 | 以现有 gate 和 `pair_texture_binding.gd` 为基础定义普通播放帧契约；明确能力、错误和整数/指针编码；同步 Kotlin/Godot/native；版本化迁移历史模型字段 | 拒绝缺失、非法、过期和跨会话消息；保留暂停 redraw、seek、EOF、字幕和纹理所有权用例；不允许不匹配帧混合 |
| R4：拆分应用编排 | 按责任提取播放会话协调、照片流程、输入路由和设置持久化；`main.gd` 保留组装、生命周期和模块连接；显式处理视频/照片/列表间的转换 | 原有射线/扳机、摇杆滚动、capture 后回中、recenter、reclining、follow、队列和恢复行为通过回归；模块有单独的状态与释放责任 |
| R5：拆分平台和菜单边界 | 将 URI/FD/network lease、宿主播放、GPU 显示租约从 `MpvVideoBridge` 分离；插件保持薄适配；菜单读取展示状态并发送明确动作；整理图文加载与缓存 | 取消、重开、后台/恢复、storage 移除、账号撤销、异步回调不再串会话；测试使用真实责任边界，避免依赖巨型类私有字段 |
| R6：收尾与设备验收 | 删除迁移完成后的空壳和旧契约；更新架构、构建、测试及中英官网；固定合法媒体、设备和 APK 清单 | Pico/Quest/OpenXR 包可构建；记录持续播放、seek、暂停 redraw、EOF、休眠恢复、字幕、原生立体、资源泄漏和温度/帧表现；没有实测的项目保持未验收 |

顺序：R1 → R2 → R3，再实施 R4/R5，最后 R6。每批先核对调用者和失败路径，再修改接口与生产实现，最后更新测试及文档。一次提交只覆盖一个可以独立验证的行为边界。

## 当前实施范围

R1 已提交为 `ed190d3`。本轮继续完成 R2–R5 的代码迁移及 R6 文档收尾。根据所有者最新要求，本机只做编译和轻量静态检查，不运行测试矩阵或 APK 打包测试；集中验收单独记录在 [ACCEPTANCE.md](ACCEPTANCE.md)。代码迁移完成与运行时验收通过是不同状态。

当前主入口保留场景组装、生命周期、事件连接以及兼容的字段/方法适配；状态由输入、照片、播放动作、设置、XR 布局和资料库请求控制器拥有。适配层让已有场景、诊断和回归用例继续通过原来的入口访问真实状态，不复制状态、不创建全局事件总线。模块通过弱引用访问场景宿主，失效宿主不会被保活。

不会用文件行数作为验收目标。主要指标是无调用者入口减少、状态/资源责任明确、原有正确性约束和可构建性得到验证。

## 验证方式

- 快速检查：工作流/发布/网站测试、FreeCM 命令清单、公共源码边界和 `git diff --check`。
- Godot：执行全部 `test_*.gd`，新增旧配置迁移与退休动作不能恢复旧设置的行为用例。
- Android：JVM 集成测试、JNI/native ARM64 编译；Debug 包检查 ELF、符号、依赖闭包、16KB、签名、ZIP alignment 与应用身份。
- Go：修改涉及来源、账号或网络租约时执行 `cloudcore` 测试。
- 设备：复用保留的独立探针。实际头显不可用时报告该限制；静态阅读、主机测试和 APK 通过不能代替设备验收。

## 进度

- [x] 重新读取并关闭过时 issue #1。
- [x] 依据 `41f48d5` 的实际代码制定上述范围与次序。
- [x] R1 实现及本地验证完成，与本计划一并提交。
- [x] R2 原生内部管线退休；运行时验收待集中执行。
- [x] R3 version-2 播放消息契约迁移；回归验收待执行。
- [x] R4/R5 应用编排、资料库请求、宿主/源 IO/显示租约职责拆分。
- [x] R6 文档及旧推理验收工具清理。
- [x] 本机集中回归及六个 Android 安装包校验完成；基础工具精确版本固定已移除。
- [ ] 其他平台交给 CI；实际头显、长期性能和账号实测仍待对应环境验收。

### R1 验证记录

- 29 项工作流测试、13 项发布测试、4 项网站测试通过。
- 245 项 JVM 测试、74 项 Godot 测试与 Go `cloudcore` 测试通过。
- Kotlin 和 Android ARM64 native 编译通过；检查实际 AAR 中的 `.so`，18 个 RenderBridge JNI 导出与当前 Kotlin 声明完全一致。
- Quest Debug APK 打包通过现有 ELF、依赖、16KB、签名、ZIP alignment 和应用身份校验。
- 新增生产源码增删改的失效测试；生成输出和测试报告不会造成配置失效。
- 未执行头显测试或 Windows 构建。该记录仅描述 R1，不能用于证明后续代码已经验收。

### R2–R5 代码交付

- 原生渲染拆成 GL 状态保护、纹理工具、slot、冻结帧、渲染核心和 JNI；删除 ROI/scout、推理 PBO/AHardwareBuffer、深度 warp、CPU float mask 上传及不可达的 decoder-image 导入。
- version-2 帧契约由 Kotlin/Godot 两侧集中处理；显示 revision 取代模型代次，shader/fixture 与 EOF/gate 消费者已同步迁移。
- `main.gd` 从本轮基线 2,344 行缩到约 980 行；领域控制器接管输入/拖动、照片/图库、播放/队列、设置持久化和 XR 布局状态。
- `library_source_controller.gd` 管理异步请求、取消和云分页；菜单保留展示与交互，并暴露原有调用入口。
- `PlaybackHost`、`PlaybackSourceResources`、`PlaybackDisplayLeases` 分别拥有解码宿主、FD/网络租约和消费者 GL 状态；关闭后的迟到解析结果不再取得新资源所有权。
- 旧推理专用 motion/modes/XR-Alpha/pixels/subtitles 验证矩阵退出当前工具集。剩余设备验证迁移及集中运行要求见验收清单。

### 本轮轻量编译记录

- Android NDK 对拆分后的 C++ 渲染桥执行 ARM64 `-Wall -Wextra -Werror` 语法编译，通过。
- 单个 Gradle worker 编译 Debug Kotlin 生产源码和 JVM 测试源码，通过；没有执行测试任务。
- 对改动 GDScript 及 fixture 执行资源加载/编译；没有实例化或运行测试脚本。
- 16 个 RenderBridge JNI 声明与 C++ 实现名称匹配，公共源码、FreeCM 命令、网站链接和 workflow 静态检查通过。
- 版本 2 契约的拒绝/时钟 provenance 用例已添加，留待集中执行。本轮未进行打包、矩阵测试或设备验收。
- 重构检查点使用 `[skip ci]`，避免推送触发自动矩阵和打包；集中验收时手动执行工作流。

### 本机集中验收

所有者后续授权执行完整本机校验，并将完成标准收缩为本机能够生成安装包；无需准备 Windows 环境。75 项 Godot、234 项 JVM、48 项 Python 测试与 Go 测试通过；11 项依赖账号的 JVM 用例跳过。Quest/Pico/OpenXR 的 Debug/Release 六个安装包均完成校验。验收范围、产物和限制见 [ACCEPTANCE.md](ACCEPTANCE.md)。

基础工具不再要求固定 Python/JDK/Go/Gradle/Godot/gomobile/NDK/CMake 版本。脚本检查可用性和必要兼容条件：Python 所需标准库、模块语言版本、编辑器/模板匹配及项目 Android target。SDK 工具默认选择完整的已安装版本，可由环境变量指定另一个已安装组件；不下载工具。
