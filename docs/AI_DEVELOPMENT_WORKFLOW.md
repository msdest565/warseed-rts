# WARSEED AI 开发主工作流

> 工作流版本：1.1
> 基线日期：2026-09-07
> 适用范围：从已完成的 R1 工程基线推进到玩法改写、第一章与后续内容生产
> 实时状态：[`AI_DEVELOPMENT_STATE.md`](AI_DEVELOPMENT_STATE.md)
> 目标命令：[`AI_GOAL_COMMANDS.md`](AI_GOAL_COMMANDS.md)
> 当前路线：[`GAMEPLAY_REWORK_ROADMAP.md`](GAMEPLAY_REWORK_ROADMAP.md)
> 架构参考：[`EXPANSION_IMPLEMENTATION_ROADMAP.md`](EXPANSION_IMPLEMENTATION_ROADMAP.md)

## 1. 工作流目的

本文件把产品设计和工程路线转化为 AI 可以反复执行的确定性流程。它解决五个问题：

1. AI 如何判断当前能做什么，不能跳过什么；
2. 一个需求怎样被拆成可验证的工作项；
3. 实现、测试、性能、存档和文档怎样在同一闭环中完成；
4. 失败、阻塞、范围变化和用户已有修改怎样处理；
5. 下一名 AI 如何仅凭仓库文档继续工作，而不依赖聊天上下文。

本工作流不使用虚构日历工期。计划以依赖、工作包和阶段出口管理；实际排期由产品负责人根据团队容量决定。

## 2. 信息源与冲突处理

AI 必须按以下优先级判断事实：

1. 当前代码、`.tres` 数据、场景和自动测试：决定“现在实际怎样运行”；
2. `DECISIONS.md` 中 Accepted 决策：决定不可绕过的产品与技术边界；
3. `PRODUCT_VISION.md`、`GAME_DESIGN_DOCUMENT.md`：决定核心体验；
4. `AI_DEVELOPMENT_STATE.md`：决定当前阶段、门禁和任务状态；
5. 本工作流：决定任务执行方式；
6. 扩充规格、战役圣经和实施路线图：决定目标设计；
7. 历史状态和验收文档：作为证据，不覆盖更晚事实。

出现冲突时，AI 不能静默选择。先记录冲突位置、当前代码事实和受影响工作项；若差异会改变产品行为、存档或阶段范围，则暂停该工作项并请求产品决策。

## 3. 固定工程原则

- 核心玩法是“常驻军团卡牌 + 将领 Agent + 部队卡级直接控制”；
- 卡牌不抽取、不洗牌，不引入随机手牌和卡包稀有度；
- 玩家与 Agent 使用相同命令、资源、视野和战斗规则；
- 玩家接管优先，只有明确归还后 Agent 才恢复控制；2026-09-10 用户明确要求将新的玩家将领执行决策、路线和姿态视为交还该将领部队的授权，后台 Agent 更新仍不得抢回控制；
- 敌方开局计划在读取玩家本局行为前锁定，后续反应只读取合法阵营知识；
- `SimulationWorld` 只保留权威顺序、状态所有权和系统协调，不继续吸收关卡特判；
- 内容使用稳定 ID、typed Resource、加载验证和显式迁移；
- 战中只有 `Supply` 是可消费货币，人口、组织和弹药是约束或状态；
- 近期正式内容以 60-80 个活跃实体为硬门；
- 核心战斗完全离线，不以 LLM 或网络服务作为运行依赖。

## 4. 角色与权限

| 角色 | 负责 | 不能替代 |
|---|---|---|
| 产品负责人 | 接受决策、改变范围、批准阶段出口 | 自动测试结果 |
| 产品研究组织者 | 可选招募玩家、观察并保留原始证据 | 工程验证与产品决策 |
| AI 实现代理 | 审计、设计契约、编码、测试、文档、交接 | 产品范围与主观真人体验结论 |
| 自动化 | 证明确定性、合法性、回归、性能、策略差异和文件完整性 | 主观乐趣、叙事理解和商业质量 |
| 内容设计 | 目标、地图问题、敌方计划、叙事和数值假设 | 权威系统实现 |

自 D-026 起，`human_required` 字段废止。历史工作项中的该字段只作为档案读取，不能阻塞任务；新工作项使用 `external_research: optional`，并始终禁止把模拟结果写成真人体验结论。

## 5. 总体阶段图

```text
R0 历史候选版与条件放行（已关闭）
 |
 v
R1 类型化目标与结果系统（已完成）
 |
 v
R2 灰脊乐趣基准
 |
 v
R3 卡牌战术语法
 |
 v
R4 我方分层 AI
 |
 v
R5 敌方行动 AI
 |
 v
R6 第一章行动层
 |
 v
R7 内容生产与最终表现
```

该顺序是依赖顺序，不只是建议优先级。任何阶段可以做研究、原型和文档准备，但正式实现不得越过前一阶段出口。

## 6. 主要开发计划

| 阶段 | 核心结果 | 主要交付物 | 必须通过的出口证据 |
|---|---|---|---|
| R0 | 历史候选版与条件放行 | P6.7 工程候选、D-025 | 已由 D-026 关闭未执行真人工作项 |
| R1 | 总部摧毁不再是唯一结局 | 目标定义/状态/快照、`ObjectiveSystem`、`BattleOutcome`、目标 UI | 等价迁移四关；护送胜利和有序撤离可达；同 tick 结算稳定 |
| R2 | 让灰脊成为可比较的玩法基准 | 完整对局观测、战线/威胁提示、异常驱动指挥、因果复盘 | 多策略完整对局矩阵、确定性、80 实体、五档 UI 与产品风险审查通过 |
| R3 | 卡牌提供真实战术动词 | 类型化效果、composition、4-6 张差异卡、存档兼容 | 新动作、代价与反制可解释；旧卡兼容；60-80 实体通过 |
| R4 | 我方 AI 把意图变成方案 | 态势黑板、2-3 个 COA、将领任务图、预备/撤退/重规划 | 计划完成率、纠正负担、公平知识和完整对局门通过 |
| R5 | 敌方 AI 公平且不机械 | Doctrine、Operation Plan、Reaction Rules、Reserve Policy | 多轴与牵制可复盘；无隐藏信息读取；多策略矩阵通过 |
| R6 | 形成第一章行动层 | 行动图、跨关后果、正式地图/补给数据、四关迁移 | 第一章连续存档、结果分支、性能和产品审查通过 |
| R7 | 证明内容可重复生产 | 第二章样板、内容验证器、正式资产与完整发布门 | 第二关不新增通用系统；存档、性能、UI、本地化和导出通过 |

## 7. 工作项状态机

### 7.1 状态定义

| 状态 | 含义 | 允许的下一状态 |
|---|---|---|
| `BLOCKED` | 依赖、决策或权限缺失 | `READY`、`CANCELLED` |
| `READY` | 输入完整，可以领取 | `DISCOVERY` |
| `DISCOVERY` | 正在核对当前实现、测试和风险 | `CONTRACT`、`BLOCKED` |
| `CONTRACT` | 行为契约与验收条件已冻结 | `IMPLEMENTING`、`BLOCKED` |
| `IMPLEMENTING` | 正在修改代码、数据或文档 | `VERIFYING`、`REWORK` |
| `VERIFYING` | 正在运行分层验证 | `REVIEWING`、`REWORK` |
| `REWORK` | 新增行为或验证未满足契约 | `IMPLEMENTING`、`VERIFYING`、`BLOCKED` |
| `REVIEWING` | 检查 diff、兼容、文档和证据 | `DONE`、`REWORK` |
| `DONE` | 验收条件全部满足，状态文件已更新 | 无 |
| `CANCELLED` | 产品决定移除整个工作项，且已记录决策 ID 与原因 | 无 |

任一时刻只能有一个主要工作项处于 `DISCOVERY` 至 `REVIEWING`。多个只读调查可以并行，但不能同时修改相同契约或共享权威状态。

产品负责人通过 Accepted 决策移除整个工作项时，任何非终态都可以直接进入 `CANCELLED`；这不是验证失败，必须在状态记录中保留决策 ID、原因和替代入口。

### 7.2 标准执行循环

#### A. 领取与预检

1. 从 `AI_DEVELOPMENT_STATE.md` 选择第一个 `READY` 且依赖满足的工作项；
2. 读取工作项的 `source_documents`；
3. 检查 `git status --short`，识别并保护用户已有修改；
4. 运行工作项要求的基线测试；
5. 若基线已失败，记录失败是否与任务相关，不得先掩盖失败再实施。

#### B. 发现

1. 从输入/UI 沿命令、校验、队列、权威系统、快照和表现追踪完整调用链；
2. 列出当前行为、目标行为和差异；
3. 找到已有本地模式、测试辅助和数据契约；
4. 评估存档、确定性、公平知识、本地化、性能和五档分辨率影响；
5. 确认范围外事项，避免顺手扩张。

#### C. 契约冻结

开始编辑前必须写清：

- 输入和合法前置条件；
- 权威状态变化；
- 拒绝原因和失败语义；
- 产生的事件与快照字段；
- UI/Agent 能看到什么，不能看到什么；
- 稳定 ID、数据验证和迁移规则；
- 确定性顺序和同 tick 处理；
- 自动测试、性能、实渲和可选产品研究边界。

若契约需要新增产品决定，工作项返回 `BLOCKED`，不能在实现中偷偷决定。

#### D. 最小纵向实现

按以下顺序完成同一条行为：

```text
typed data contract
 -> loader/compiler validation
 -> authoritative state/system
 -> command and rejection semantics
 -> snapshot/event
 -> Agent/UI consumer
 -> persistence/migration when applicable
 -> tests and observability
 -> documentation
```

先完成一条可工作的端到端路径，再扩展同类枚举或批量迁移内容。不得先创建大量空类、占位字段和未接线配置来宣称系统完成。

#### E. 分层验证

验证按成本从低到高运行：

1. 解析、静态检查和内容校验；
2. 受影响单元/纯模拟测试；
3. 14 套回归；
4. 受影响关卡 smoke；
5. 开局矩阵、机制 smoke 或完整结局矩阵；
6. 五档 UI、Windows 实渲和性能；
7. 完整发布门；
8. 可选产品研究，不影响工程完成状态。

低层失败时先停止，不通过重复运行碰运气。固定种子结果发生变化时，必须说明是预期契约变化还是回归。

#### F. 审查与交接

1. 阅读最终 diff，而不是只看测试结果；
2. 检查是否修改无关文件、引入绝对路径、自由字典、隐藏真值或字符串特判；
3. 核对中英文文本、错误语义、存档版本和观测字段；
4. 更新状态文件、相关设计文档和证据路径；
5. 运行 `git diff --check`；
6. 汇报结果、验证、残余风险和唯一下一工作项。

## 8. 标准工作项契约

新工作项使用以下 YAML 结构。字段不适用时填写 `none`，不得删除关键字段：

```yaml
work_item_id: WS-R1-001
title: Define typed battle objectives
phase: R1
type: system
status: READY
owner: ai
external_research: optional
objective: >-
  One observable behavior this work item must deliver.
why_now: >-
  Dependency or player problem that makes it the next task.
depends_on:
  - WS-R0-006
source_documents:
  - docs/EXPANSION_SYSTEMS_AND_CONTENT_SPEC.md
  - docs/EXPANSION_IMPLEMENTATION_ROADMAP.md
current_evidence:
  - path and exact fact proving current behavior
in_scope:
  - concrete code/data/test changes
out_of_scope:
  - explicitly deferred behavior
invariants:
  - 10 Hz authoritative simulation
  - no hidden-knowledge reads
behavior_contract:
  inputs: []
  authoritative_changes: []
  rejection_reasons: []
  events_and_snapshots: []
data_contracts: []
persistence:
  format_change: false
  migration: none
observability: []
acceptance_criteria:
  - externally observable pass condition
verification:
  baseline: []
  focused: []
  full_gate: false
  optional_research: []
expected_files: []
risks: []
rollback: >-
  Compatibility path or recovery method.
handoff_outputs:
  - state update
  - evidence paths
```

工作项必须只有一个主要行为目标。若 `acceptance_criteria` 需要“以及另一个不相关系统”，应拆成两个有依赖的工作项。

## 9. 任务拆分规则

- 数据类型、运行系统、迁移和内容批量迁移分别提交，但每一步都保持可运行；
- 先兼容读取，再迁移内容，最后删除旧路径；
- 兼容判断集中在 Loader/Compiler，不散落在运行系统；
- 先锁定旧行为黄金测试，再提取系统；
- 先迁移一张地图、一张卡或一张战法，再批量迁移同类内容；
- 目录移动与行为改动分开；
- 新 UI 必须消费快照，不直接读取世界内部状态或 JSON；
- 新 Agent 行为必须输出命令、任务、reason key 和退出条件；
- 新观测字段不能成为权威输入；
- 每完成 3-5 个小工作项，或任何共享系统/阶段出口改变后，运行一次完整发布门。

## 10. 变更类型与验证矩阵

| 变更类型 | 最低自动验证 | 额外门 |
|---|---|---|
| 纯文档 | 链接/围栏/表格检查，`git diff --check` | 数字必须回查代码或证据 |
| typed Resource/Loader | 数据单测、引用/范围/重复 ID 校验、14 套回归 | 受影响内容全部重新加载 |
| 命令/校验 | 合法与拒绝路径、队列时序、快照不可变 | UI 与 Agent 使用同一命令的集成测试 |
| 权威系统/tick 顺序 | 纯模拟、固定种子、同 tick 边界、14 套回归 | 四关 smoke；必要时完整结局矩阵 |
| 地图/导航 | 可达性、部署容量、稳定路径、地图校验器 | 受影响关卡 smoke、实渲和性能 |
| UI/输入/本地化 | 输入集成、中英刷新、五档分辨率 | 真实键鼠截图检查 |
| 存档/战役状态 | 旧版本迁移、损坏恢复、原子写入、重复结算 | 四至六关链式测试和隔离档检查 |
| 单位/战斗/卡牌 | 对照场景、战损回写、Agent 使用、确定性 | 60-80 实体实渲、reason 覆盖和完整策略矩阵 |
| 经济/补给 | 收入来源、切断/恢复、溢出和 UI 说明 | Agent 无隐藏路线安全判断 |
| 阶段出口/发布候选 | 上述所有相关层 | 完整发布门、Windows 导出、完整对局指标和产品风险审查 |

标准完整门：

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\verify_grey_ridge_release.ps1 `
  -GodotConsolePath <godot-console>
```

常用定位命令：

```powershell
& <godot-console> --headless --editor --path . --quit
& <godot-console> --headless --path . --script res://tests/test_runner.gd
& <godot-console> --headless --path . --script res://tests/grey_ridge_smoke.gd
& <godot-console> --headless --path . --script res://tests/scenarios/grey_ridge_decision_matrix.gd
git diff --check
```

## 11. 历史队列与当前入口

这是阶段门通过后的实际领取顺序，不代表这些任务现在都为 `READY`。实时状态以状态文件为准。

| ID | 工作项 | 类型 | 依赖 | 完成信号 |
|---|---|---|---|---|
| WS-R0-001 | 执行 P6.7 陌生玩家 cohort | human | 当前候选包 | 覆盖数、原始记录和人工评估满足预注册 |
| WS-R0-002 | 汇总 cohort 并生成缺陷清单 | analysis | R0-001 | 阻塞/理解/操作/平衡/表现分级且可追溯 |
| WS-R0-003 | 闭环 P0/P1 与重复 P2 | mixed | R0-002 | 每个问题有复现、修复、回归和必要复测 |
| WS-R0-004 | 评审 D-018 至 D-024 | decision | R0-002 | Accepted/Rejected/Deferred 均有理由和影响 |
| WS-R0-005 | 冻结第一扩充切片 | design | R0-003、R0-004 | 目标、范围外、单位、地图和性能预算明确 |
| WS-R0-006 | 运行阶段出口发布门 | verification | R0-005 | 完整门、80 实体、P6.7 全部通过 |
| WS-R1-001 | 建立目标定义契约与数据校验 | system | R0-006 | stable objective ID、kind、参数和错误语义有测试 |
| WS-R1-002 | 建立目标状态、快照和事件 | system | R1-001 | 进度值拷贝、完成/失败事实可观察 |
| WS-R1-003 | 实现确定性 `ObjectiveSystem` | system | R1-002 | 同 tick 收集、tie-break、唯一结算通过 |
| WS-R1-004 | 用等价目标迁移现有四关 | migration | R1-003 | 四关结果与迁移前黄金证据一致 |
| WS-R1-005 | 接入 `BattleOutcome`、结算保护和 UI | vertical_slice | R1-004 | 目标、结果和一次性存档形成完整路径 |
| WS-R1-006 | 建立护送胜利测试场景 | content_test | R1-005 | 不摧毁总部也能权威胜利 |
| WS-R1-007 | 建立撤离结果测试场景 | content_test | R1-005 | 有序撤离与失败能稳定区分 |
| WS-R1-008 | 运行 R1 阶段出口 | verification | R1-006、R1-007 | 四关无回归、非总部结局、发布门全部通过 |

R0 真人工作项已经由 D-026 取消，R1 已完成，R2 工程出口已于 2026-09-10 按用户“维护自检后完成 R3、R4、R5”的明确继续授权接受。R2 以后按 `GAMEPLAY_REWORK_ROADMAP.md` 的队列生成相同格式工作项，不能一次创建覆盖整个阶段的巨型任务。当前进入 R3，使用 `/goal continue` 继续活动目标；任务状态仍以 `AI_DEVELOPMENT_STATE.md` 为准。D-021/D-022 必须在对应依赖工作项前冻结，不能由继续授权推导为全部产品推荐值已经接受。

## 12. 阶段出口判定

一个阶段只有在以下条件全部满足时才能完成：

1. 所有必需工作项为 `DONE`，没有被忽略的 P0/P1；
2. 设计规格、数据契约和错误语义已同步；
3. 旧四关与 Legacy RTS 没有非预期回归；
4. 新存档可迁移、备份、恢复，或明确证明阶段不改变存档；
5. 相关纯模拟、集成、smoke、矩阵、性能和 UI 证据存在；
6. 完整发布门和 Windows 导出通过；
7. 完整对局代理指标、因果 reason 覆盖和证据边界已经记录；可选真人研究无论是否执行都不改变工程状态；
8. 产品负责人接受阶段决策和残余风险；
9. `AI_DEVELOPMENT_STATE.md` 已推进到下一阶段并记录证据。

“类已创建”“测试文件存在”“自动策略获胜”或“开发者能玩”均不能单独作为阶段完成证据。

## 13. 失败与阻塞处理

### 13.1 基线失败

- 先保存命令、环境、失败输出和受影响测试；
- 判断失败是否在修改前存在；
- 与任务无关时不擅自扩大范围，记录残余风险；
- 直接阻止验证时，将工作项置为 `BLOCKED` 并明确解除条件。

### 13.2 实现回归

- 进入 `REWORK`；
- 优先恢复行为契约，不通过放宽测试隐藏回归；
- 若契约本身错误，返回 `CONTRACT` 并记录为何改变；
- 不删除玩家数据、测试或验证步骤来获得绿色结果。

### 13.3 性能回归

- 保留相同地图、实体数、分辨率、采样时间和硬件口径；
- 区分模拟 P95、画面 P95 和峰值弹丸压力；
- 80 实体超过门时阻止阶段出口；
- 120 实体失败保持为扩展证据，不自动触发架构重写。

### 13.4 存档迁移失败

- 不覆盖原档，不返回空档继续运行；
- 报告源版本、内容版本、失败字段和备份位置；
- 修复迁移器并用原始副本复测；
- 只有完整校验后才原子替换目标文件。

### 13.5 可选产品研究发现问题

- 真人研究不是门禁，但发现的崩溃、存档破坏、错误结算或可复现严重操作问题必须按普通 P0/P1 缺陷处理；
- 不修改原始记录或降低预注册阈值来美化结论；
- 研究证据不足时只标记 `INCOMPLETE`，不影响已独立满足的工程状态；
- 是否把主观意见转为工作项由产品负责人决定，并写明范围和验收方式。

### 13.6 证据来源与结论边界

- 自动策略、headless 测试、自主试玩和开发者脚本统一标记为 `SIMULATED`；
- 真人参与者的原始记录可以标记为 `HUMAN`，但该标签不自动提高优先级或改变阶段状态；
- `SIMULATED` 可以证明确定性、合法性、策略差异、性能和因果完整性，不能证明主观乐趣、学习成本、疲劳或商业质量；
- 取消真人门不允许放宽任何自动测试、完整对局、公平知识、存档、性能、UI 或产品决策门。

## 14. 状态更新与交接格式

每个完成或阻塞的工作项必须在 `AI_DEVELOPMENT_STATE.md` 记录：

- `work_item_id` 与最终状态；
- 实际改变的行为，不只列文件；
- 验收条件逐项结果；
- 执行过的命令与证据路径；
- 未运行的验证及原因；
- 存档、性能、知识公平和本地化影响；
- 残余风险；
- 唯一推荐下一工作项。

对用户的交接使用以下顺序：

```text
结果
改变的玩家/系统行为
验证证据
尚未验证或可选产品研究
下一工作项
```

不得用“基本完成”“应该可用”替代明确状态。无法完成时，说明已经排除什么、确切阻塞条件和恢复入口。

## 15. AI 启动指令模板

后续可以用以下任务描述启动新的 AI 工作回合：

```text
请按照 AGENTS.md 和 docs/AI_DEVELOPMENT_WORKFLOW.md 执行。
先读取 docs/AI_DEVELOPMENT_STATE.md，领取第一个依赖已满足的 READY 工作项。
完成发现、契约、最小纵向实现、分层验证、diff 审查和状态更新。
不得跳过当前阶段门，不得覆盖工作区已有修改，不得把自动化描述成真人体验结论。
如果没有 READY 工作项，请报告阻塞条件和解除阻塞所需的最小行动，不要自行扩大范围。
```
