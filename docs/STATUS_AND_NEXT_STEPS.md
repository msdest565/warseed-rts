# WARSEED 项目交接与持续开发说明

> 最后更新：2026-07-31
> 本文件是下一位 AI 的首要入口。开始工作前先阅读本文件，再阅读 `TECHNICAL_PLAN.md`、`SYSTEM_DESIGN.md`、`MVP_SCOPE.md` 和 `ROADMAP.md`。

## 1. 用户目标与接手方式

用户希望最终获得一个完整、可运行、可验证的 WARSEED 成品，而不是逐步关注每个实现细节。接手 AI 应持续推进路线图，在合理默认值下自主完成设计、实现、调试、自动测试、实际运行和 Windows 导出验证。

执行约束：

- 不要在每个小步骤后停下来等待用户确认；常规技术决策应依据现有文档和代码自行完成。
- 不要要求用户代为运行 Godot、测试或导出命令；当前会话已经允许 AI 调用 Godot。
- 遇到编译、解析、测试、场景或导出错误时，读取完整输出、定位、修复并重新验证，直到通过或遇到真正需要用户决定的产品分歧。
- 只有不可逆操作、对外发布、付费资源、许可证选择、凭据、范围重大变化等必须由用户决定的事项才暂停询问。
- 每个增量都必须形成可运行实体，并完成 headless 测试、实际程序启动和 Windows debug export；不能只写代码后声明完成。
- 保持 MVP 离线可运行，不接入 LLM；不要提前扩张到联网、多玩家、最终美术管线或大规模 ECS。
- 不要跳过 `GameCommand -> CommandValidator -> CommandQueue -> SimulationWorld -> WorldSnapshot/SimulationEvent -> Presentation` 边界。
- 不要让 Godot 节点、HUD、动画、输入或 Agent 直接修改权威位置、生命、资源、任务和控制权。

## 2. 产品和架构基线

WARSEED 是传统 RTS 直接操作与 AI 指挥链结合的 2D 游戏：玩家可以手动控制单位，也能向主 AI 参谋长下达高层目标；工业主管和战场将领通过合法游戏命令执行任务。玩家始终拥有最高控制权，接管后 Agent 不得自动抢回。

首个 5—8 分钟垂直切片只验证：

1. 发展矿区；
2. 守住区域；
3. 攻击目标；
4. 玩家接管导弹车、完成微操并明确归队；
5. 任务目标、路线、阶段、参与者和受阻原因可观察；
6. 离线、无 LLM、headless 回归和 Windows debug export 均通过。

权威链路：

```text
Input / UI / Agent
        ↓
GameCommand
        ↓
CommandValidator
        ↓
CommandQueue
        ↓
SimulationWorld（固定 10 Hz）
        ↓
SimulationEvent / WorldSnapshot
        ↓
Godot presentation / HUD / DebugLayer
```

详细约束见：

- `docs/MVP_SCOPE.md`
- `docs/SYSTEM_DESIGN.md`
- `docs/TECHNICAL_PLAN.md`
- `docs/ROADMAP.md`
- `docs/DECISIONS.md`

## 3. 引擎与环境

已锁定：

- Godot：`4.6.3.stable.mono.official.7d41c59c4`
- 仓库版本锁：`.godot-version` 中的 `4.6.3-stable`
- 语言：typed GDScript（使用 Mono 编辑器不代表项目采用 C#）
- GUI：`D:/AI/Godot_v4.6.3-stable_mono_win64/Godot_v4.6.3-stable_mono_win64.exe`
- CLI：`D:/AI/Godot_v4.6.3-stable_mono_win64/Godot_v4.6.3-stable_mono_win64_console.exe`
- Export templates：已安装匹配的 `4.6.3.stable.mono`
- 目标平台：Windows 10/11 x86-64
- 渲染：Godot 2D，GL Compatibility，1280×720
- Windows preset：`Windows Desktop`
- 导出目标：`build/windows/warseed-debug.exe`
- Git LFS：未启用，当前也不应启用

不要把上述本机绝对路径写入游戏运行时代码或工程资源；它只用于本地开发和验证命令。

## 4. Git 与工作区状态

交接时状态：

- 当前分支：`docs/project-status`
- 当前 HEAD：`910c458`（`docs: record current progress and next steps`）
- `main` / `origin/main` 基线：`baf8d02`
- bootstrap 和首个移动切片仍在工作区，尚未提交
- 修改文件包括 `.gitattributes`、`.gitignore`、`README.md`、`docs/DECISIONS.md` 和本文件
- `project.godot`、`export_presets.cfg`、`.godot-version`、`src/`、`scenes/`、`tests/` 等目前是新增文件
- `.godot/` 和 `build/` 已正确忽略，不得提交
- 不得丢弃或重置现有工作区；不要使用 `git reset --hard` 或 checkout 覆盖文件
- 用户尚未要求 commit、push 或 PR，因此接手 AI 不应擅自发布

此前创建 `feat/godot-bootstrap` 分支曾被权限策略拦截。该问题不影响本地开发，但在准备提交前应先检查远端分支历史，选择一个干净功能分支并保留全部现有改动。

## 5. 已完成实现

### 5.1 Gate A：工程基线

已完成并实际验证：

- Godot 4.6.3 stable Mono 精确版本锁定；
- `project.godot`、目录骨架、`GameRoot` 和 Windows export preset；
- headless 工程初始化和主场景启动；
- 匹配版本 export templates；
- Windows x86-64 debug export；
- 导出程序 headless 启动和正常图形窗口启动；
- `.godot/`、`build/`、export credentials 等生成物忽略；
- 无 Git LFS。

### 5.2 首个权威移动切片

已实现一个可运行、可见、可操作的俯视载具：

- 启动后在空白网格战场显示 `EntityId = 1` 的载具；
- 左键点击载具进行选择；
- 左键点击空地取消选择；
- 右键点击合法战场位置提交 `MoveCommand`；
- 载具以 10 Hz 权威模拟直线移动；
- 表现层在相邻快照之间插值；
- 显示选择环、目标标记、路线以及 tick、队列、位置和命令结果；
- 表现节点不直接修改权威状态。

主要代码：

- `src/commands/game_command.gd`
- `src/commands/move_command.gd`
- `src/commands/command_validation_result.gd`
- `src/commands/command_validator.gd`
- `src/commands/command_queue.gd`
- `src/simulation/entities/unit_state.gd`
- `src/simulation/core/simulation_world.gd`
- `src/simulation/core/unit_snapshot.gd`
- `src/simulation/core/world_snapshot.gd`
- `src/simulation/core/simulation_event.gd`
- `src/app/simulation_host.gd`
- `src/input/input_controller.gd`
- `src/presentation/battlefield.gd`
- `src/presentation/unit_proxy.gd`
- `src/presentation/world_presentation.gd`
- `src/debug/debug_layer.gd`
- `scenes/game/game_root.tscn`

### 5.3 当前自动测试

项目使用自有最小 headless runner，GUT 尚未采用：

- `tests/test_runner.gd`
- `tests/unit/test_command_pipeline.gd`
- `tests/unit/test_simulation_world.gd`

覆盖内容：

- 合法命令只在 tick 边界生效；
- 不存在实体、错误控制者、disabled 实体和越界目标被结构化拒绝；
- 玩家与测试 Agent 使用同一验证器和队列；
- 10 Hz 固定位移；
- 到达目标不越过；
- 历史快照不会随世界继续推进而改变；
- 相同初态和命令序列产生相同位置结果。

最后一次结果：

```text
WARSEED tests passed: 2 suites
```

## 6. 已验证的命令

以下命令已由 AI 自主成功执行。所有命令保持单行，避免 Bash 把参数拆开。

```bash
"D:/AI/Godot_v4.6.3-stable_mono_win64/Godot_v4.6.3-stable_mono_win64_console.exe" --headless --editor --path "D:/AI/红警尝试" --quit
```

```bash
"D:/AI/Godot_v4.6.3-stable_mono_win64/Godot_v4.6.3-stable_mono_win64_console.exe" --headless --path "D:/AI/红警尝试" --script res://tests/test_runner.gd
```

```bash
"D:/AI/Godot_v4.6.3-stable_mono_win64/Godot_v4.6.3-stable_mono_win64_console.exe" --headless --path "D:/AI/红警尝试" --quit-after 3
```

```bash
mkdir -p "D:/AI/红警尝试/build/windows" && "D:/AI/Godot_v4.6.3-stable_mono_win64/Godot_v4.6.3-stable_mono_win64_console.exe" --headless --path "D:/AI/红警尝试" --export-debug "Windows Desktop" "D:/AI/红警尝试/build/windows/warseed-debug.exe"
```

```bash
"D:/AI/红警尝试/build/windows/warseed-debug.exe" --headless --quit-after 3
```

正常图形启动也已成功：

```bash
"D:/AI/红警尝试/build/windows/warseed-debug.exe"
```

最后一次图形运行环境输出：

```text
OpenGL API 3.3.0 NVIDIA 610.88 - Compatibility
Using Device: NVIDIA GeForce RTX 4070 Ti SUPER
```

## 7. 当前真实完成度

已通过：

- Gate A：引擎基线；
- Gate C 的核心雏形：统一命令入口、权威状态边界、基本事件和确定性移动；
- 一个可运行的单单位交互切片。

尚未通过：

- Gate B：缺少相机、框选、停止/攻击命令和静态障碍导航；
- Gate C 完整验收：事件摘要和集成测试仍需扩大；
- Gate D：任务与控制权；
- Gate E：三个高层命令；
- Gate F：情报完整性；
- Gate G：5—8 分钟完整切片。

当前产物不是完整 MVP，也不是完整 RTS，只是经过验证的权威移动基础。不要把它描述为最终成品。

## 8. 下一步执行顺序

接手 AI 应按下列顺序持续推进。每项完成后立即运行自动测试、实际程序和 Windows export 验证；通过后直接进入下一项，不等待用户逐项批准。

### P0：完成阶段 1 技术基线

1. 为当前 `SimulationHost`、`WorldPresentation` 和输入链路补充 headless 集成测试。
2. 建立最小 `TileMapLayer` 测试地图与独立逻辑格。
3. 使用 `AStarGrid2D` 实现静态障碍寻路；不可达目标返回 `PathUnavailable`。
4. 扩展到约 5 个单位，加入稳定 formation slots。
5. 加入简单 separation、卡住检测和狭窄通道纵队降级。
6. 记录每 tick 耗时、路径请求/失败、命令接受/拒绝和任务状态变化。
7. 添加一个 typed custom `Resource` 和 `.tres` 加载/引用验证 spike。
8. 评估 GUT；若没有明确收益，继续使用并完善项目自有 runner，不为换框架阻塞开发。

完成标准：`ROADMAP.md` 阶段 1 退出条件全部满足。

### P1：完成纯手动 RTS 原型

1. 相机平移/缩放、点选、框选、右键上下文命令和数字控制组。
2. `StopCommand`、`AttackCommand`、`AttackMoveCommand` 等直接命令均走统一链路。
3. 五类基础单位的数据和表现：矿车、工程车、侦察车、突击车、导弹车。
4. 三类建筑：指挥中心、无人兵工厂、前线支援站。
5. 一种矿石资源、采集/返仓、消费、建造、生产、维修。
6. 攻击、伤害、死亡和指挥中心胜负条件。
7. 战争迷雾、最后已知位置和基础事件日志。

完成标准：没有 Agent 时，玩家可以完整手动完成一场短局，且核心模拟可加速、复现和自动测试。

### P2：完成任务和控制权

1. 战略目标、Agent 任务、单位动作三层状态结构。
2. `PlayerControlled`、`AgentControlled`、`TemporarilyOverridden` 等明确控制权状态。
3. 玩家命令优先，接管期间 Agent 不得覆盖。
4. 返回原编队、留在原地、加入其他编队和持续手动。
5. rejoin point、无瞬移归队、缺员处理和任务恢复。
6. 目标、路线、阶段、参与者和受阻原因可视化。

完成标准：测试 Agent 带队时，玩家能接管导弹车、完成操作并稳定归队。

### P3：完成三个高层命令和角色 Agent

1. 工业主管完成“发展矿区”：采集、第二矿车、指定建筑/生产，或明确受阻。
2. 战场将领完成“守住区域”：防守半径、禁止过度追击、损失阈值撤退。
3. 战场将领完成“攻击目标”：分配、集结、沿路线推进、交战和撤退/完成。
4. 主 AI 参谋长完成结构化目标校验、拆分、分派、冲突检测和摘要。
5. 玩家可检查、暂停、取消、修改任务，不被普通执行弹窗打断。

### P4：完成情报边界、敌方 AI 和垂直切片

1. 阵营知识视图、战争迷雾、`last_seen_tick` 和不作弊自动测试。
2. 规则驱动敌方 AI：发展、侦察、骚扰、争矿、扩军、进攻和回防。
3. 调整为稳定 5—8 分钟成功路径。
4. 验证发展矿区、守住区域、攻击目标和导弹车接管/归队完整流程。
5. 完成 headless 回归、正常图形试玩和 Windows debug export 冒烟测试。

完成标准：`TECHNICAL_PLAN.md` Gate G 全部通过，然后才扩展到 15—20 分钟完整 MVP。

### P5：完整 MVP 与交付质量

1. 扩展到 15—20 分钟完整对局。
2. 完成全权副官模式、教学和基础难度参数。
3. 进行数值、性能、可理解性和任务透明度调优。
4. 增加 CI：headless tests 和 Windows export smoke test。
5. 整理第三方资产/依赖许可证、发布说明和最终可执行包。
6. 最终交付前执行完整测试矩阵和实际端到端试玩。

## 9. 每个增量的强制验证闭环

接手 AI 每次修改后必须自行完成：

1. Godot headless editor import，捕获 typed GDScript 和场景解析错误；
2. 项目自有 runner（或后续确定的 runner）全部测试；
3. 主场景 headless 启动；
4. 正常图形程序实际运行并操作到新增功能；
5. 对失败/拒绝/不可达等相邻异常路径至少做一次运行时探测；
6. Windows debug export；
7. 导出 exe headless 启动和正常图形启动；
8. `git diff --check`；
9. 检查 `.godot/`、`build/`、凭据和临时文件未进入 Git；
10. 更新本交接文档中的完成度、证据、下一步和已知问题。

测试通过不等于功能完成；必须运行真实游戏界面并观察新增行为。正常打开窗口也不等于交互通过；需要实际操作到功能路径。

## 10. 自主决策规则

可以自行决定：

- typed GDScript 内部类型拆分、文件组织和测试用例；
- 临时程序员美术的几何形状和配色；
- 不改变产品规则的 UI 布局；
- 合理初始数值，前提是集中在 typed Resource/平衡数据中并有测试；
- 修复解析、运行、测试、性能和导出错误；
- 在现有技术方案内选择最简单可验证实现。

必须询问用户：

- 改变产品核心、MVP 范围或胜负条件；
- 改变 Godot/typed GDScript/Windows-first/10 Hz 等 Accepted 决策；
- 引入付费、来源不明或许可证不兼容的资产；
- 接入云端服务、LLM、账号、遥测或联网功能；
- 发布公开仓库、提交商店、创建付费资源或使用用户凭据；
- 需要破坏性 Git 操作或丢弃现有工作。

## 11. 当前已知限制与注意事项

- 当前载具移动是空白战场直线移动，没有路径规划或碰撞。
- 当前选择使用最新权威快照做命中测试；后续相机和插值引入后应统一屏幕/世界坐标转换。
- 当前 `EntityId` 是稳定整数，尚未封装独立 ID 类型。
- 当前事件系统只覆盖命令接受/拒绝和到达，后续需要机器可读的完整事件摘要。
- 当前 runner 只有 2 个套件，缺少主场景、输入、表现、导出和导航集成测试。
- 当前图形载具是 Godot 绘图原语，不是最终美术；在核心体验验证前不要启动最终资产生产。
- `project.godot` 含 Godot Mono 编辑器生成的 `[dotnet] project/assembly_name="WARSEED"`，这是已知且应保留的编辑器改动。
- 当前文档和代码在同一未提交工作区；开始大规模后续工作前应整理功能分支，但不能丢失现有修改。

## 12. 接手后的第一轮动作

下一位 AI 应直接执行：

1. `git status --short --branch`，确认并保护现有工作区；
2. 阅读本文件以及 `TECHNICAL_PLAN.md:376` 起的 Gate A—G；
3. 运行第 6 节列出的 import、tests、headless、export 和 exported-exe smoke 命令，确认基线仍然通过；
4. 检查并补充 `SimulationHost` / `WorldPresentation` 集成测试；
5. 开始 P0 的 `TileMapLayer + 逻辑格 + AStarGrid2D` 导航 spike；
6. 持续执行第 8 节路线，不在常规阶段停下来等待用户逐项指挥。

最终目标是交付可运行、可验证的完整 MVP，而不是只输出计划、代码片段或未经运行的阶段性实现。
