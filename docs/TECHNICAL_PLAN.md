# WARSEED Godot 技术方案

## 文档状态与适用范围

本方案是 WARSEED 首个 5—8 分钟垂直切片及后续 15—20 分钟完整 MVP 的已接受实现基线。产品范围以 [MVP 范围](MVP_SCOPE.md) 为准，通用职责和控制权原则以 [系统设计](SYSTEM_DESIGN.md) 为准。

本方案不包含完整数值平衡、美术生产规范、多人同步、自然语言命令或最终发布流程。仓库当前仍是文档阶段；Godot 工程将在下一项独立任务中建立。

## 技术栈基线

| 项目 | 决策 |
|---|---|
| Engine | Godot 4.6 stable 系列 |
| Language | typed GDScript |
| Target platform | Windows 10/11 x86-64 first |
| Game form | 2D top-down RTS，键鼠输入 |
| Map | `TileMapLayer` + 独立逻辑格 |
| Initial pathfinding | `AStarGrid2D` |
| Formation | 项目自定义 formation slots |
| Authoritative simulation | 固定 10 Hz `SimulationTick` |
| Data | typed custom `Resource` + 文本 `.tres` |
| Tests | 纯模拟测试 + Godot headless 集成/场景测试 |
| LLM | MVP 不接入 |
| Git LFS | 初期不启用 |

### 版本政策

- 工程 bootstrap 时安装当时可用的最新 `4.6.x-stable`，并记录精确 patch 版本。
- 编辑器、headless runner、CI 和 Windows 导出模板必须使用同一精确版本。
- patch 升级必须独立提交，重新导入工程，并运行全部 headless 测试与 Windows 导出冒烟测试。
- 跨 minor 或 major 升级必须新增 Accepted 决策，不在功能开发中顺带升级。

## 选择 Godot 的理由与限制

Godot 的原生 2D、`Camera2D`、`Control`、`TileMapLayer`、`AStarGrid2D` 和自定义绘制能力适合快速验证 RTS 输入、路线显示、任务状态和控制权交接。typed GDScript 能缩短状态机、任务模板和调试覆盖层的迭代周期；文本场景和资源也便于当前小团队使用 Git 审查。

需要明确以下限制：

- Godot 不直接提供完整 RTS 编队、拥挤处理和战略任务系统；
- 局部 separation、卡住恢复、狭窄通道退化和 formation slots 由项目实现；
- typed GDScript、静态检查和测试是强制工程约束，不能用无结构字典和字符串事件替代稳定类型；
- 若单位规模、寻路负载或平台范围显著超过 MVP，必须重新测量，而不是假定当前方案无限扩展。

## 架构与依赖方向

```text
Input / UI / Agent
        ↓
GameCommand
        ↓
CommandValidator
        ↓
CommandQueue
        ↓
SimulationWorld（固定 tick，权威状态）
        ↓
SimulationEvent / WorldSnapshot
        ↓
Godot presentation / HUD / audio / debug overlays
```

核心规则：

1. `SimulationWorld` 是唯一权威战局状态；Godot `Node`、场景树、动画和 HUD 不是权威状态。
2. 玩家 UI 与 Agent 创建相同的 `GameCommand` 类型，并经过同一个 `CommandValidator`。
3. `CommandValidator` 检查控制权、单位状态、目标、资源、视野与路径前置条件。
4. 验证通过的命令进入 `CommandQueue`，只在 `SimulationTick` 边界应用。
5. 表现层通过 `WorldSnapshot` 和 `SimulationEvent` 更新，不直接修改位置、生命、资源、任务或控制权。
6. 模拟实体使用稳定 `EntityId`；显示节点只是实体 view/proxy，重建显示节点不能创建或删除模拟实体。

## 计划目录结构

以下目录在后续工程 bootstrap 中创建，本次不建立空目录：

```text
project.godot
src/
  app/
  commands/
  simulation/
    core/
    entities/
    systems/
    tasks/
    agents/
    navigation/
  presentation/
  input/
  ui/
  data/
  debug/
scenes/
  game/
  maps/
  units/
  buildings/
  ui/
data/
  units/
  buildings/
  weapons/
  production/
  tasks/
  formations/
  maps/
  balance/
assets/
  art/
  audio/
tests/
  unit/
  integration/
  scenarios/
addons/
tools/
```

`simulation` 不依赖 `presentation`、`ui` 或具体场景；`commands` 是输入、Agent 和模拟共享的边界；测试可以直接构造 `SimulationWorld`，不要求加载主游戏场景。

## 场景组合根

```text
GameRoot
├─ SimulationHost
├─ WorldPresentation
│  ├─ Terrain
│  ├─ Units
│  ├─ Buildings
│  └─ Overlays
├─ InputController
├─ CameraController
├─ HUD
└─ DebugLayer
```

- `SimulationHost` 只负责推进纯模拟、接收命令并发布事件/快照。
- `WorldPresentation` 根据 `EntityId` 创建和更新 `Node2D` 代理。
- `InputController` 负责逐帧采集输入并转换为命令，不直接移动单位。
- `HUD` 不保存第二份资源、任务或控制权真相。
- `DebugLayer` 可视化路径、槽位、控制者、视野与任务状态，但不参与规则结算。

## 统一命令边界

首批命令族：

- `MoveCommand`
- `AttackCommand`
- `AttackMoveCommand`
- `StopCommand`
- `GatherCommand`
- `BuildCommand`
- `RepairCommand`
- `QueueProductionCommand`
- `TakeControlCommand`
- `ReturnControlCommand`
- `CreateStrategicGoalCommand`
- `CancelTaskCommand`

每条命令至少携带：

- `command_id`
- `issuer_id`
- `issuer_kind`
- `issued_tick`
- `target_entity_ids`
- 参数化实体/坐标/区域目标
- 控制权上下文

验证结果使用：

- `Accepted`
- `Rejected`
- `Deferred`

首批机器可读原因：

- `InvalidTarget`
- `NotController`
- `EntityDisabled`
- `InsufficientResources`
- `TargetNotVisible`
- `PathUnavailable`
- `TaskConflict`

玩家直接命令优先于高层命令、Agent 任务和单位默认行为。玩家接管在下一个权威 tick 生效；同一 tick 内低优先级 Agent 命令不得覆盖接管。

## 模拟时间、顺序与可复现性

### 固定步进

- 权威模拟初始使用 10 Hz，即每 100 ms 一个 `SimulationTick`。
- 渲染帧率目标为 60 FPS，与模拟频率解耦；单位显示位置在相邻快照间插值。
- Agent 以 N 个模拟 tick 为间隔更新，不在每个渲染帧重规划。
- 若测试证明 10 Hz 不能满足移动和战斗手感，应统一修改模拟常量和决策记录，禁止各系统自行选择频率。

### Tick 处理顺序

初始顺序统一集中定义：

1. 接收并排序已验证命令；
2. 处理控制权变化；
3. 推进战略目标、任务和单位意图；
4. 处理移动与到达；
5. 处理采集、施工、维修和生产；
6. 处理攻击、伤害与死亡；
7. 判定胜负；
8. 发布事件与快照。

不得依赖 SceneTree 节点遍历顺序决定结算。双方指挥中心在同一 tick 的伤害阶段被摧毁时，在胜负阶段判定平局。

### 随机性

模拟使用项目封装的随机源和已记录种子。表现层粒子、音效变体等随机行为使用独立随机源，不得改变模拟。垂直切片目标是“同一构建、初态、种子和命令序列产生相同关键事件/状态摘要”，暂不承诺跨版本 multiplayer lockstep 级确定性。

## 地图、寻路与编队

### 地图

- `TileMapLayer` 负责地形表现和关卡编辑。
- 地图加载时生成独立逻辑格，记录通行、移动成本、视野阻挡、矿区和战略区域。
- 模拟系统读取逻辑格，不把 TileMap 节点作为战局真相。

### 全局寻路

- 首个切片使用 `AStarGrid2D` 处理静态地形全局路径。
- 建筑落地后以受控方式更新逻辑阻挡和 A* 格；动态单位不逐个永久写入全局阻挡格。
- 路径请求设每 tick 预算并缓存有效路径；单位不在每帧重算。
- 不可达目标产生 `PathUnavailable`，不能无限重复提交移动命令。

### Formation slots

- 编队先计算中心/leader 路径，再按朝向和 `FormationDefinition` 分配稳定 `slot_id`。
- 突击车优先前排，导弹车优先后排；槽位是期望位置，不是强制物理锁定。
- 使用简单 separation、到位容差、掉队和 `UnitStuck` 检测。
- 狭窄通道允许压缩间距或退化为纵队，通过后重新形成队形。
- 玩家接管单位时释放或标记其 slot 为空；归队时选择安全 rejoin point 并重新分配，禁止瞬移。

仅在 10—15 个单位下仍出现长期拥堵、频繁重算超预算或动态障碍导致大量错误路径时，才评估 `NavigationServer2D`、流场或更复杂局部避障。

## 数据驱动配置

静态定义使用 typed custom `Resource` 和文本 `.tres`：

- `UnitDefinition`
- `BuildingDefinition`
- `WeaponDefinition`
- `ProductionRecipe`
- `TaskTemplate`
- `FormationDefinition`
- `MapDefinition`
- `BalanceProfile`

规则：

- Resource 只保存静态配置，战局中的生命、位置、队列和任务进度属于 `SimulationWorld`；
- 加载时验证 ID 唯一、引用存在、数值范围合法；
- 同一平衡值不得同时定义在脚本、场景和 Resource；
- 测试可加载与正式游戏相同的定义，也可构造最小测试定义。

## Agent 实现

- 参谋长使用结构化目标、`TaskTemplate` 和规则分派；
- 工业主管、战场将领和敌方 AI 使用有限状态机或显式任务图；
- Agent 只能读取按阵营过滤的 `WorldSnapshot` 和敌情记忆；
- Agent 输出候选 `GameCommand`，仍须通过 `CommandValidator`；
- 每次决策附带 `reason_code`、任务阶段和相关事实，供 HUD 与日志解释；
- MVP 不调用语言模型；未来自然语言只能转换为已有的结构化目标。

Agent 运行频率低于模拟 tick，并由事件唤醒关键重评，例如基地受袭、目标摧毁、编队损失达到阈值或资源条件满足。

## 战争迷雾与情报

从工程第一阶段建立三态知识模型：`Unexplored`、`Explored`、`Visible`。视觉雾效可以后置，但 Agent 访问边界不能后置。

- 单位和建筑产生视野源；前线支援站扩大固定区域视野。
- 敌人离开视野后保存最后已知位置、兵力和 `last_seen_tick`。
- 玩家方 Agent 只读玩家已知快照，不读取完整 `SimulationWorld`。
- 敌方脚本袭击可以按阶段和地图区域触发，但不能精确锁定不可见单位实时位置。
- 调试模式可同时显示真实状态和某阵营已知状态，用于验证不作弊。

## UI、输入与调试

### 玩家 UI

- 左键点选和框选；
- 右键上下文移动、攻击、采集与交互；
- 数字键控制组；
- 攻击移动、停止、撤退；
- 结构化高层命令和地图目标选择；
- 接管、返回原编队、留在原地、加入其他编队和持续手动。

### Agent/任务界面

显示负责 Agent、目标、阶段、成员、预算、路线、完成/撤退条件、最近事件和受阻原因，并提供暂停、取消、修改和接管操作。

### DebugLayer

至少可切换显示：

- `EntityId` 与控制状态；
- 当前命令和任务；
- A* 路径、formation slots 和 rejoin point；
- 防守半径、攻击距离与视野；
- 真实状态和阵营已知状态；
- tick 耗时、路径请求/失败、命令拒绝和 Agent 状态变化；
- 结构化事件时间线。

## 测试与 headless 运行

### 纯模拟测试

不加载主游戏场景，覆盖：

- 命令优先级和拒绝原因；
- 接管后 Agent 不覆盖、归队后任务恢复；
- 资源预留、生产和战斗结算；
- 任务状态转换、取消和受阻；
- 固定种子复现；
- Agent 只能读取许可情报。

### Godot 集成测试

覆盖：

- UI 与 Agent 等价动作经过同一 `CommandValidator`；
- `SimulationHost` 以固定 tick 推进；
- `.tres` 加载、ID 和引用验证；
- `TileMapLayer` 到逻辑格/A* 阻挡同步；
- 显示代理正确消费事件和快照；
- headless 进程返回可靠退出码。

### 场景与试玩测试

- 完成 5—8 分钟垂直切片成功路径；
- 离线、无 LLM 时完整运行；
- Windows debug export 在干净环境启动；
- 后续对 15—20 分钟完整 MVP 做回归。

GUT 是优先评估的社区测试框架，但不是当前已采用依赖。工程 bootstrap 先验证其对锁定 Godot 版本、typed GDScript、headless、退出码和 CI 输出的兼容性；通过后再固定插件版本。若不通过，使用项目自有最小 headless runner，不能让核心测试依赖未验证插件。

## 性能预算与观测

| 指标 | 首个切片基线 |
|---|---|
| 显示目标 | 60 FPS |
| 权威模拟 | 10 Hz |
| 对局时长 | 5—8 分钟 |
| 玩家单位 | 5 个左右 |
| 完整 MVP 玩家单位 | 常见 10—15 个 |
| Agent 更新 | 低于模拟频率，事件触发关键重评 |
| 导航 | 有每 tick 请求预算，不逐帧重算 |
| 测试 | 支持无渲染加速运行 |

必须记录每 tick 模拟耗时、路径请求和失败、命令接受/拒绝、任务状态变化与 Agent 决策次数。只有测量证明现有实现无法达到预算时，才考虑更复杂数据结构、流场、C# 或 GDExtension。

## Windows 构建与 CI

- 首发开发目标为 Windows 10/11 x86-64，键鼠是 MVP 输入基线。
- 工程、headless 测试和 export templates 使用相同精确 Godot 版本。
- 工程 bootstrap 创建 Windows debug export preset。
- 后续 CI 至少执行 headless tests 和 Windows export smoke test。
- 其他平台不是 MVP 验收条件，但代码不得硬编码开发机绝对路径或 Windows 路径分隔符。

## Git 与资产策略

后续创建工程时：

- 忽略 `.godot/`、导入缓存、导出目录和本地编辑器状态；
- 提交 `project.godot`、源 `.gd`、`.tscn`、`.tres`、源资产与必要插件元数据；
- 导出包由构建流程产生，不提交到源码历史；
- 初期不启用 Git LFS，也不预先把全部 PNG/WAV 加入 LFS；
- 当真实二进制源资产显著增加、普通 Git 克隆或历史体积不可接受时，再独立决定 LFS 类型和迁移方案。

Godot 专用 `.gitignore` 随真实工程一起加入，避免文档目录与实际导出目录不一致。

## 实施顺序与验收门

### Gate A：引擎基线

1. 锁定精确 `4.6.x-stable` 并创建工程；
2. 建立目录和 `GameRoot`；
3. headless 命令能运行并返回正确退出码；
4. Windows debug export 能启动；
5. Git 中没有生成缓存和导出产物。

### Gate B：手动 RTS

1. 相机平移/缩放、点选、框选和右键移动可用；
2. 单位能绕过静态障碍；
3. 移动、攻击、停止等直接操作都生成 `GameCommand`；
4. 手动路径在没有 Agent 时可玩、可测试。

### Gate C：权威模拟边界

1. UI 和测试 Agent 通过同一验证器提交命令；
2. 没有 Agent 或表现节点直接修改位置、生命、资源或战斗结果；
3. 事件日志记录命令接受/拒绝与关键状态转换；
4. 同初态、种子和命令序列复现相同关键摘要。

### Gate D：任务与控制权

1. 测试 Agent 能管理一支编队；
2. 玩家直接命令使单位进入 `TemporarilyOverridden`；
3. Agent 在玩家接管期间不覆盖该单位；
4. 玩家明确归队后，单位移动到安全 rejoin point 并恢复任务。

### Gate E：三个高层命令

1. “发展矿区”完成采集和必要生产或明确受阻；
2. “守住区域”不追击超过防守半径；
3. “攻击目标”完成集结、沿路线推进、交战和撤退/完成；
4. 三项任务都显示目标、参与者、阶段、路线和受阻原因。

### Gate F：情报完整性

1. 玩家 Agent 只使用许可信息；
2. 敌方 AI 不精确追踪不可见单位；
3. 最后已知位置带有 `last_seen_tick`；
4. 调试层可以验证真实状态与阵营知识的差异。

### Gate G：切片交付

1. 完成 5—8 分钟成功路径；
2. 玩家能接管导弹车并稳定归队；
3. 离线、无 LLM 环境可完整运行；
4. headless 回归和 Windows 导出冒烟测试通过。

Gate G 通过后，才扩展到 15—20 分钟完整 MVP。

## 明确延期

首个切片不实现：

- 完整存档和跨版本读取；
- 严格确定性回放；
- multiplayer lockstep 或网络同步；
- 自然语言与云端模型；
- 流场、大规模 ECS、复杂动态避障；
- 最终美术资产管线和 Git LFS；
- 大规模单位性能优化。

固定 tick、命令队列和事件日志只为测试、诊断和未来演进保留边界，不构成多人或回放承诺。
