# WARSEED 扩充实施路线图（架构参考）

> 版本：工程提案 v1，2026-08-19
> 适用范围：P6.7 之后，从四关 MVP 候选版演进到第一章战役和后续内容管线
> 当前状态：D-027 已取代本文原 R2-R7 领取顺序；正式队列见 [`GAMEPLAY_REWORK_ROADMAP.md`](GAMEPLAY_REWORK_ROADMAP.md)
> 保留用途：地图、混成卡、存档、补给、战役模块和迁移策略的架构参考

## 1. 总体结论

后续开发的主要工程任务不是继续向 `SimulationWorld` 添加新关卡分支，而是建立四个稳定扩展点：

1. 类型化目标与结果系统；
2. 独立地图、经济和编成数据；
3. 可组合的单位能力、混成部队卡和战法效果；
4. 与战场隔离的战役状态和剧情事件。

目标架构：

```text
CampaignDefinition + CampaignState
                  |
                  v
         BattleLaunchContext
                  |
BattleDefinition（组合根）
 ├─ MapDefinition
 ├─ RosterDefinition
 ├─ EconomyDefinition
 ├─ ObjectiveSetDefinition
 ├─ IntelPackageDefinition
 ├─ EnemyPlanSetDefinition
 └─ NarrativePackageDefinition
                  |
                  v
SimulationWorld（权威顺序与状态所有权）
 ├─ Command / Control systems
 ├─ Movement / Combat systems
 ├─ ObjectiveSystem
 ├─ SupplyNetworkSystem
 ├─ OrganizationSystem
 └─ DoctrineEffectSystem
                  |
                  v
BattleOutcome -> CampaignTransitionResult -> CampaignStateStore
```

## 2. 不能破坏的工程边界

- `SimulationWorld` 仍是战场权威状态；
- 输入、UI、Agent 和剧情不直接改位置、生命、补给、目标或战役结果；
- 命令只在固定 tick 边界应用；
- 快照是值拷贝，旧快照不能随新状态变化；
- 任何 Agent 行为都可通过命令、任务、原因和阵营知识审计；
- 内容使用 typed Resource，不以自由字典取代稳定契约；
- 存档升级先备份，迁移失败不得覆盖原档；
- 测试和运行不依赖网络、LLM 或开发机绝对路径；
- 旧基地 RTS 保留为回归模式，扩充不得无意破坏其经济和胜利链。

## 3. 推荐模块边界

### 3.1 数据层

新增目录建议：

```text
src/data/
  battle/
  campaign/
  combat/
  cards/
  objectives/
  maps/
  narrative/

data/
  battles/
  campaigns/
  maps/
  cards/
  combat/
  narrative/
```

不要求一次移动全部现有文件。先新增命名明确的类型，待引用稳定后再做机械迁移，避免功能改动与目录重排混在同一提交。

### 3.2 权威系统

| 系统 | 拥有状态 | 不负责 |
|---|---|---|
| `ObjectiveSystem` | 目标进度、完成/失败事实、战斗结论 | 战役奖励和 UI |
| `SupplyNetworkSystem` | 节点控制、连通、结算、临时连接 | 战役物资与卡牌补员 |
| `OrganizationSystem` | 卡牌组织、压制、恢复、复杂命令门槛 | 实体生命伤害 |
| `DoctrineEffectSystem` | 战法触发、参数和任务修饰 | 直接改战果或绕过命令 |
| `SensorSystem` | 探测、识别、持续跟踪和特征值 | UI 文本合并 |
| `CampaignTransitionService` | 战后结果到战役状态的纯转换 | 战中 tick 与场景树 |

当前 `CombatSystem`、`EconomySystem`、`EngineeringSystem`、`FormationMovementSystem` 和 `StrategicTaskSystem` 继续保留，按依赖逐步扩展。

### 3.3 表现层

新增表现只消费快照：

- `ObjectivePanel`：主次目标与进度；
- `SupplyNetworkOverlay`：当前选择相关的节点和连线；
- `SensorContactOverlay`：持续观察、干扰和识别状态；
- `CampaignMapScreen`：行动节点、后果和军团可用性；
- `NarrativeCommsPanel`：低频短通信，不遮挡地图；
- `CampaignDebrief`：结果等级、区域后果和下一行动。

不要让 `CampaignMapScreen` 直接读写 JSON。它只调用 `CampaignHost` 提交类型化战役操作。

## 4. 阶段路线

## R0：真人验收与扩充决策冻结（历史方案）

### 目标

这是 D-026 之前的历史目标。P6.7 现为可选产品研究，不再阻塞任何阶段。

### 工作项

- 按既有协议完成四场陌生玩家 cohort；
- 汇总阻塞、理解、操作、平衡和表现问题；
- 修复 P0/P1 问题并复跑发布门；
- 评审 D-018 至 D-024；
- 冻结第一扩充切片的目标、单位和地图范围。

### 历史退出条件

- 核心卡牌/Agent/情报理解达到既有门槛；
- 未解决问题有明确优先级和所有者；
- 扩充不会依赖已被真人证明难以理解的交互；
- 当前 13 套测试、四关 smoke、发布门和 80 实体门保持通过。

该历史阶段已由 D-026 与 D-027 关闭，不得重新作为当前任务门禁。

## R1：通用目标与结果系统

### 目标

让一场会战可以由总部摧毁之外的权威目标结束，并产生多级结果。

### 新类型

```text
BattleObjectiveDefinition
ObjectiveGroupDefinition
BattleObjectiveSetDefinition
ObjectiveState
ObjectiveSnapshot
BattleOutcome
BattleConclusionEvent
```

### 新系统

`ObjectiveSystem.advance(world_view, events, tick)`：

1. 从本 tick 权威状态计算目标事实；
2. 以稳定 objective ID 更新进度；
3. 收集同 tick 完成与失败；
4. 计算唯一结果；
5. 发布 `BATTLE_CONCLUDED`；
6. 后续 tick 不再接受战场命令。

### 兼容策略

先把现有四关编译为等价目标：

```text
Primary: DESTROY_ENTITY(enemy_command_center)
Defeat: DESTROY_ENTITY(player_command_center)
Defeat: TIME_LIMIT_REACHED
```

确认结果完全一致后，再逐关启用新目标。旧 `_update_victory()` 保留给 Legacy RTS，卡牌会战改由 `ObjectiveSystem` 负责。

### 测试

- 每种目标的纯模拟完成、失败、中断和恢复；
- 同 tick 双方完成/失败与 tie-break；
- 结束后命令拒绝、计时冻结和快照不可变；
- 四关旧结果黄金测试；
- 结算只写一次存档；
- UI 只读 `ObjectiveSnapshot`。

### 退出条件

用一张测试地图完成“护送后胜利”和“撤离后有序撤退”两种非总部结局，且旧四关行为无回归。

## R2：会战定义拆分与正式地图管线

### 目标

把地图、编成、经济、目标、情报和敌方计划从 60+ 字段的 `BattleDefinition` 中分离。

### 实施顺序

1. 新增子 Resource 类型和适配 getter；
2. `BattleDefinition` 同时支持旧字段与新引用；
3. Loader 读取后编译成不可变 `ResolvedBattleDefinition`；
4. 迁移 `grey_ridge.tres`，对比解析后哈希；
5. 依次迁移断桥、雾林、黑井；
6. 所有关卡迁移后删除旧字段兼容路径。

不要让运行系统同时到处判断“旧字段还是新字段”。兼容逻辑只存在于 Loader/Compiler。

### 地图实现

新增：

```text
BattleMapDefinition
TerrainZoneDefinition
NavigationObstacleDefinition
DeploymentZoneDefinition
ObjectiveSiteDefinition
SupplyNodeDefinition
SupplyLinkDefinition
CameraLandmarkDefinition
```

`LogicGrid.create_for_battle()` 改为只接收解析后的地图定义，不再预加载 `test_arena.tres`。`create_test_map()` 只留在测试 fixture。

`Battlefield` 从地图定义绘制灰盒；正式 TileMap 后续通过相同稳定 zone/site ID 对齐，不进入权威状态。

### 工具

新增 headless 地图检查器：

```powershell
<godot> --headless --path . --script res://tests/tools/validate_battle_content.gd
```

输出 JSON：引用、可达性、路线长度、部署容量、节点连接、目标覆盖和地图尺寸。

### 退出条件

- 四关全部使用新子 Resource；
- 旧 `test_arena` 不再影响正式会战；
- 灰盒表现与逻辑地形共享 ID；
- 新建一张 8192x5120 测试图不需要修改 `SimulationWorld`；
- 四关确定性摘要只在预期字段上改变。

## R3：单位能力与混成部队卡

### 目标

让“新兵种”成为底层行为差异，让“新卡牌”成为稳定编制和组织差异。

### 数据类型

```text
TargetProfileDefinition
WeaponDefinition
SensorDefinition
SignatureDefinition
AmmoProfileDefinition
UnitCardCompositionEntry
UnitCardAbilityDefinition
```

现有 `CombatDefinition` 可先扩展引用，不必立即拆除其兼容字段。Loader 负责把旧攻击力/射程转换为默认武器。

### 运行状态

`UnitState` 新增最小字段：

- `target_tags`
- `signature_values`
- `suppression_received`
- `ammo_by_weapon_id`
- `sensor_state`
- `jammed_until_tick`

`UnitCardState` 新增：

- `available_strength_by_entry_id`
- `active_member_ids_by_entry_id`
- `ammo_summary`
- `suppression_summary`

所有快照字段仍为值拷贝。

### 第一批行为

只实现：

1. 无人侦察机：飞行移动层、无占点、光学观察；
2. 机动防空：攻击 air 标签目标、雷达开关与暴露；
3. 电子战：区域干扰传感器/制导，不直接造成伤害；
4. 专业弹药：火炮/防空按齐射消耗，运输节点恢复。

第一批不实现方向装甲、复杂穿深、逐部件损坏、燃油或全单位弹药。

### 存档迁移

存档格式升级到 v4：

- v3 卡牌现员写入 `composition.main.available_strength`；
- v3 授权兵力写入 `composition.main.authorized_strength`；
- 荣誉、装备、组织、累计损失保持不变；
- 保存迁移来源版本和内容版本；
- 迁移前创建 `.backup-<timestamp>.json`；
- 旧同质卡保持同质，不在迁移中自动赠送新分队。

### 退出条件

- 同一张测试卡包含两种单位并能正确部署、接管、归还、受损、撤出和存档；
- 新无人机/电子战行为只使用合法阵营知识；
- 旧十二卡在兼容模式下数值和战损不变；
- 60—80 实体实渲仍通过正式门。

## R4：战法效果注册与补给网络

### 目标

停止继续增加按字符串 ID 的世界类分支，并让地图节点形成可切断的经济关系。

### 战法效果

新增 `DoctrineEffectRegistry`，代码注册允许的效果 kind；数据只提供参数。执行器不能从 Resource 路径动态加载任意脚本。

迁移顺序：

1. 隐蔽搜索、交替掩护、炮火准备、集中突破；
2. 快速架桥、高地监视；
3. 弹性防御、遭遇后脱离、战斗撤退；
4. 预备队投入、相互支援、集结整编。

每迁移一张战法，都用现有测试锁定行为、原因和时序，再删除旧分支。

### 补给网络

新增 `SupplyNetworkSystem`：

- 战略区控制状态由既有系统提供；
- 节点与连接来自地图定义；
- 使用稳定顺序执行图遍历；
- 只结算与总部连通的我方节点；
- 运输卡可提交 `EstablishSupplyLinkCommand` 建立临时连接；
- 连接中断发布结构化事件和快照；
- 基础模式可配置为不使用网络，保持灰脊兼容。

### 退出条件

- 十二战法不再依赖 `SimulationWorld` 中的 doctrine ID match；
- 一张测试地图可以切断/恢复补给连接；
- 经济 UI 可以解释每笔收入与中断原因；
- Agent 不会使用隐藏敌军位置判断线路安全。

## R5：第一章战役纵向切片

### 目标

用现有四关证明战役节点、结果后果和剧情状态能闭环。

### 新模块

```text
CampaignDefinition
CampaignNodeDefinition
CampaignState
CampaignStateSnapshot
BattleLaunchContext
BattleOutcome
CampaignTransitionResult
CampaignStateStore
CampaignHost
```

### 界面流程

```text
CampaignMapScreen
  -> NodeBriefing
  -> PrebattlePlanner
  -> Battle
  -> BattleDebrief
  -> CampaignDebrief
  -> CampaignMapScreen
```

当前 `battle_selector` 可以先适配为 CampaignMapScreen 的列表降级布局，保留五档分辨率和键盘焦点。行动图连线只是表现，解锁真值来自 `CampaignStateSnapshot`。

### 第一章状态

最小只引入：

- 四节点结果；
- `enemy_momentum`；
- `intel_advantage`；
- `infrastructure_integrity`；
- 不超过五个剧情标记；
- 现有补充点、功勋、战役日和卡牌记录。

黑井启动上下文必须根据前三关结果改变至少两项：初始报告、初始补给、支援冷却或敌预备时机。不能只改变一段简报文字。

### 存档

建议战役存档 v1 独立于军团 v4，但由一个 manifest 关联：

```text
user://campaigns/<slot_id>/campaign.json
user://campaigns/<slot_id>/roster.json
user://campaigns/<slot_id>/settings.json
user://campaigns/<slot_id>/playtests/
```

写入流程使用临时文件 + 原子重命名；读取失败尝试最近备份并向玩家说明，不能静默清空。

### 退出条件

- 四关可从新战役入口连续完成；
- 失败、代价胜利和有序撤离至少各有一条可达链；
- 黑井真实读取前三关后果；
- 重播教程不修改战役结果；
- 重开战役先归档旧槽；
- 第一章结算可说明玩家的两次主要战役后果。

## R6：第一扩充内容包

### 目标

制作章节二的两张分支地图，但只把一张推进到最终表现，另一张保持完整灰盒，以验证内容管线吞吐。

推荐：

- 《白港截流》：标准补给网络、无人机、防空、设施保护；
- 《盐沼盲区》：确认目标、电子战、撤离胜利。

### 内容门

每张地图必须有：

- 独立地图 Resource；
- 3 套敌方锁定计划；
- 至少 3 种可解释玩家方案；
- 完整目标/结果/战役后果；
- 前 200 tick 矩阵和完整结局矩阵；
- 60—80 实体性能；
- 双语文本与教程复习点；
- 可选真人可用性研究，不参与完成判定。

### 退出条件

制作第二张地图时不需要新增通用系统或修改第一张地图的脚本，证明管线可扩展。

## R7：三章内容生产与最终表现

在前六阶段通过后才进入批量生产：

- 12 个主线行动和最多 3 个支线；
- 18—24 张部队卡；
- 12—16 种底层单位；
- 16—20 张战法；
- 20—30 项成长；
- 正式 TileMap、单位轮廓、卡牌头像/徽记、环境音与战斗音效；
- 章节平衡、完整战役时长和多结局测试。

不要求所有内容同时最终化。每章可以独立达到可发布质量，并保留章节版本号。

## 5. 当前代码到目标代码的映射

| 当前模块 | 建议演进 | 迁移原则 |
|---|---|---|
| `src/data/battle_definition.gd` | 组合根 + Resolved compiler | 保留旧字段适配一阶段 |
| `src/data/unit_definition.gd` | 引用武器/传感器/特征配置 | 旧 combat 自动转默认武器 |
| `src/data/unit_card_definition.gd` | 稳定 composition entries | v3 现员迁入 `main` |
| `src/data/doctrine_definition.gd` | effects 数组 | 逐战法迁移并锁行为测试 |
| `src/simulation/core/simulation_world.gd` | 系统协调与 tick 顺序 | 先提取纯函数/系统，不大重写 |
| `_update_victory()` | Legacy RTS 保留；卡牌战用 ObjectiveSystem | 等价目标先行 |
| `_advance_strategic_regions()` | 控制状态保留；结算移入 SupplyNetworkSystem | 控制与经济分离 |
| `_advance_unit_card_organization()` | OrganizationSystem | 黑井参数成为 profile |
| `_advance_limited_withdrawals()` | Objective/Withdrawal system | 撤出状态与胜利目标解耦 |
| `battle_selector.gd` | 战役图列表降级视图 | 先保持现有 UI 可访问性 |
| `army_roster_store.gd` | Roster v4 + 独立 Campaign store | 迁移、备份、失败可见 |
| `battlefield.gd` | 消费地图定义的灰盒/正式表现 | 不拥有逻辑真值 |
| `logic_grid.gd` | 由 ResolvedMap 初始化 | 测试图不再影响正式地图 |

## 6. 内容版本与存档迁移

### 6.1 版本字段

区分三个版本：

- `save_format_version`：JSON 结构；
- `content_version`：卡牌、地图和节点定义版本；
- `simulation_version`：影响确定性结果的规则版本。

不要用一个 `format_version` 同时表达所有变化。

### 6.2 迁移规则

1. 读取旧档后先做内存迁移和完整校验；
2. 校验通过才创建备份并写新档；
3. 迁移失败返回结构化错误，不创建空档；
4. 卡牌 ID 和 composition entry ID 永不复用；
5. 删除内容时把旧记录放入 `retired_cards`，不静默丢失；
6. 数值平衡变化不应重置现员、战损和荣誉；
7. 只有明确内容迁移表可以改变卡牌组成。

### 6.3 回滚

新版本写入后保留最近两个可恢复备份。若玩家回到旧程序，旧程序可以拒绝读取新档并说明版本不兼容，不能尝试猜测字段。

## 7. 测试策略

### 7.1 数据契约

每个 Resource 加载时检查：

- 稳定 ID 唯一；
- 所有引用存在；
- 数值范围合法；
- 地图尺寸、网格和区域匹配；
- composition entry ID 唯一且授权数量为正；
- 战法参数满足 effect kind 需求；
- 目标引用的站点/区域/卡牌存在；
- 战役节点图无非法环、无不可达必需节点；
- 所有本地化 key 在中英资源中存在。

### 7.2 纯模拟测试

- 每种目标的状态机；
- 同 tick 结局；
- 补给图连接与切断；
- 传感器、特征、电子战和防空；
- 混成卡部署/战损/撤出；
- 战法效果与原因；
- 战役结果纯转换；
- v3/v4 存档迁移与损坏文件恢复；
- 固定种子复现。

### 7.3 集成测试

- UI 与 Agent 仍走同一命令验证；
- 目标完成后场景进入唯一结算；
- 战后只提交一次 CampaignTransition；
- 行动图选择与战前编成上下文一致；
- 新快照不泄露隐藏传感器真值；
- 地图表现与逻辑区稳定 ID 对齐；
- 语言切换即时刷新新增 UI。

### 7.4 场景矩阵

现有 72 案例矩阵继续作为早期窗口审计，但新增完整结果矩阵：

| 层 | 运行时长 | 目的 |
|---|---:|---|
| Opening matrix | 200 tick | 命令合法、开局差异、敌方计划来源 |
| Mechanic smoke | 1200—2000 tick | 新机制至少触发一次并保持稳定 |
| Outcome matrix | 直到结局 | 推荐/替代/撤离/故意失败的实际结果 |
| Campaign chain | 4—6 场 | 存档、后果、分支与内容版本 |
| Render benchmark | 30 秒 + 长局 | 60—80 实体、弹丸和 HUD |

“矩阵通过”必须在报告中说明运行窗口和断言内容，避免把开局测试称为完整平衡。

### 7.5 可选真人研究

以下问题适合在条件允许时研究，但不作为工程、阶段或发布硬门：

- 玩家是否看懂主目标与结束条件；
- 是否理解新单位为什么有用/无效；
- 是否能指出一次补给线中断来源；
- 是否能区分压制、损伤、低组织和无弹药；
- 是否理解战役后果来自自己的战斗事实；
- 是否能在不看外部文档时完成一条非总部胜利路径。

## 8. 性能预算

| 指标 | 近期门 |
|---|---:|
| 正式实体 | 60—80 |
| 权威 tick | 10 Hz |
| 模拟 P95 | <= 10 ms，目标留足 100 ms tick 预算 |
| 画面 P95 | <= 16.667 ms |
| 输入到表现 P95 | <= 150 ms |
| 常驻弹丸 | 按正式关卡实测，不以人工 160 峰值替代 |
| 路径失败 | 正常路线 0；故意不可达必须有明确拒绝 |
| 孤儿节点/资源增长 | 长局 0 |

新地图更大不代表所有实体每 tick 全频运行。传感器、Agent、目标和补给系统应按不同频率或事件唤醒，但权威结果仍落在固定 tick。

只有测量证明 `AStarGrid2D` 与共享编队路径不足时，才评估分区路径、流场或其他导航。不要因计划中的大地图提前重写导航。

## 9. 观测与平衡数据

新增记录字段：

- 目标首次显示、首次进展、完成、失败和中断次数；
- 补给收入按来源、损失的潜在收入、溢出；
- 每张卡的部署、接敌、低组织、撤出、弹药耗尽和补给恢复；
- 传感器报告来源、识别时长、错误/过期后仍被操作的次数；
- 战法触发、阻塞、退出原因；
- 战役节点选择、未选行动后果和资源变化；
- 结局等级与触发事实。

观测数据不进入 Agent 决策或权威战斗输入。隐私与试玩隔离继续沿用现有会话机制。

## 10. 历史首批提交序列

本节只记录旧路线，不再授权任务领取。当前工作项顺序见 `GAMEPLAY_REWORK_ROADMAP.md`。

每项应保持可独立审查，不把大规模目录移动与规则改动混在一起：

1. 新增目标数据类型、状态和纯单元测试；
2. 新增 `ObjectiveSystem`，用等价总部目标接管卡牌会战胜负；
3. 新增 `BattleOutcome` 与结算一次性保护；
4. 拆出 `BattleMapDefinition`，让灰脊通过新 Loader 运行；
5. 迁移其余三关并移除正式会战对 `test_arena` 的回落；
6. 新增地图/内容 headless validator 和 JSON 报告；
7. 新增 composition entry，保持旧十二卡单条 `main` 兼容；
8. 升级军团存档 v4 与备份/迁移测试；
9. 实现无人机 + 防空纵向切片；
10. 实现电子战 + 传感器/特征纵向切片；
11. 迁移四张基础战法到效果注册表；
12. 建立补给连接图并在测试地图验证切断/恢复；
13. 建立第一章 CampaignState 和四节点线性入口；
14. 逐关重构目标与结果后果；
15. 完成黑井读取前三关结果的第一章闭环。

每完成 3—5 个提交进行一次 Windows 实渲和完整发布门，避免到阶段末才发现性能或存档回归。

## 11. 优先级

### P0：历史阻塞扩充项

- 通用目标/结局系统；
- 正式地图定义与 `test_arena` 解耦；
- 混成卡稳定条目与存档 v4；
- 80 实体性能回归；
- 内容验证器。

### P1：形成第一章

- 四关新目标；
- 结果等级与战役后果；
- 第一章行动图；
- 叙事通信/档案；
- 战法效果注册；
- 补给网络基础；
- 两种新底层单位纵向切片。

### P2：章节二内容

- 8192x5120 标准地图；
- 无人机、防空、电子战、专业弹药；
- 白港/盐沼分支；
- 物资与情报优势；
- 新增四张卡。

### P3：大型行动与最终资产

- 80—100 实体大型关卡；
- 三章完整内容；
- 正式地图和单位资产；
- 更丰富成长和结局；
- 120 实体重新优化与评估，但不自动进入正式范围。

## 12. 主要风险与控制

| 风险 | 早期信号 | 控制方式 |
|---|---|---|
| 系统拆分引发大回归 | 四关哈希广泛变化 | 等价适配先行，一系统一迁移 |
| 单位维度过多 | 玩家无法说出单位为何失败 | 第一批只加六维，卡面分层反馈 |
| 混成卡存档损坏 | v3 现员无法稳定映射 | 单条 `main` 保守迁移，重编另做版本表 |
| 目标系统变成脚本语言 | 每关要求特殊表达式 | 限定 objective kinds + 两层 ALL/ANY |
| 战役层抢走核心玩法 | 玩家在地图页花时超过战场 | 轻量行动图，每阶段 2+1 选择 |
| 补给线增加微操 | 玩家反复点击运输单位 | 默认抽象连接，只在特定目标物理护送 |
| 新叙事泄露隐藏真值 | 台词提前说出敌计划 | 触发器只读可见快照/公开目标 |
| 内容规模超过性能 | 120 实体成为默认要求 | 近期硬门 60—80，按实测升级 |
| 自动平衡被误读 | 开局矩阵被称为通关率 | 报告强制标注 tick 窗口与结局断言 |

## 13. 阶段完成定义

一个阶段只有在以下条件全部满足时才完成：

- 设计规格、数据契约和错误语义已更新；
- 新数据可以被加载、验证和本地化；
- 玩家与 Agent 都通过统一命令边界使用新能力；
- 旧四关和 Legacy RTS 没有非预期回归；
- 新存档可迁移、备份和恢复；
- 纯模拟、集成、场景、结局矩阵和性能证据与风险匹配；
- 新 UI 在五档分辨率下可用；
- 可选产品研究若已执行，必须保留真实来源与结论边界；未执行不阻塞完成；
- `git diff --check`、统一发布门和 Windows 导出通过；
- 文档明确区分当前实现、已验证结果和后续提案。
