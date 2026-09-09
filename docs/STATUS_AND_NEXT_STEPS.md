# WARSEED 项目状态与交接

> 最后更新：2026-08-18
> 历史说明：本文保留 P6.7 候选版交接快照；权威实时入口是 `AI_DEVELOPMENT_STATE.md`。D-026 已取消真人证据硬门，D-027 已启用 `GAMEPLAY_REWORK_ROADMAP.md`。
> 产品目标与验收门见 `GAME_DESIGN_DOCUMENT.md`、`CONTENT_AND_ONBOARDING_DEVELOPMENT_PLAN.md`、`TECHNICAL_PLAN.md` 和 `ROADMAP.md`。

## 1. 当前结论

WARSEED 是 Godot 4.6.3、typed GDScript、Windows-first 的离线 2D 即时战术游戏。D-017 已将产品基线迁移为“常驻军团卡牌 + 具名将领 Agent + 部队卡级直接控制”；当前仓库的基地 RTS 指挥链切片继续作为可复用技术底座，但不再等同于新 MVP。

《灰脊矿区》首个工程可玩切片已经落地：

- typed `CommanderDefinition`、`UnitCardDefinition`；
- typed `ArmyPlan`、权威容量/战法/姿态/首发校验，以及与 `SimulationWorld` 初始化贯通的可变部队隶属；
- 主场景先进入 tick 0 双语战前军团板：三名将领与四张部队卡全部可见，可调整隶属、战法、姿态和准确两张首发卡；非法组合禁用开始，会战前战场命令被宿主拒绝；
- 权威 `CommanderState`、`UnitCardState`、`CommanderSnapshot`、`UnitCardSnapshot`；
- 白久漾、涤天、林默三名具名将领，游隼、铁壁、装甲矛头、雷鸣火力群四张稳定部队卡；
- 卡面现员由真实存活实体计算，旧快照不随新战损改变；
- 1280x720 常驻军团板；将领卡可直接拖向战区，既有将领任务箭头与目标环可继续拖动重定向；点击将领整选部曲，点击部队卡整选绑定实体；
- 首局六步情境教程已进入正式场景：战前可启用/关闭，战中固定在地图外的底部指挥栏，并以已接受的将领目标、空中侦察、预备部署、整卡路线、归还命令和战局结算推进；拒绝命令不会推进，乱序事实会保留，完成/跳过偏好独立于军团战损存档；
- 1280×720 桌面布局保留完整支援、枢机情报和地图视野；480×800 窄屏由教程临时占用完整操作栏，支援/情报栏具备独立滚动，不会把滚轮传给地图缩放；
- 总部预备卡可拖给其战前所属将领快速投入，军团板会预览合法目标或隶属冲突；也可沿用点击卡牌后在地图精确选择部署点；
- 卡牌选择后继续通过现有 `GameCommand -> Validator -> Queue` 下达地图命令；
- 整卡接管/归还、最多八段航路、最终阵线、已提交路线编辑/节点拖动/撤销/清除、阵线端点拖动、正面/预测射界反馈、五种姿态和四张战法均进入权威链；
- 将领行为反馈已结构化进入权威状态与值拷贝快照，军团板以中英双语显示当前行动和合法原因；反馈覆盖姿态差异、战法准备、接敌/规避、任务受阻、整卡接管和归队，不读取隐藏敌情；
- 将领任务展望已补齐 ETA 区间、风险等级/依据和退出条件；ETA 使用真实剩余路线与编队锚点速度，风险只读取阵营接触缓存和 30 秒内未过期的结构化报告，tooltip 同时列出目标与实际参与部队；
- 交替掩护的出发序位只计算已部署部队卡；脱离姿态会在总部方向确定性搜索可达且能容纳整卡展开的集结地域；
- 预备卡快速投入会在总部朝将领当前目标方向确定合法展开点；跨将领投放返回 `COMMANDER_MISMATCH`，不入队、不扣补给，战前 `ArmyPlan` 隶属保持冻结；
- 三资源区、补给/人口、两项支援、情报合并、地形克制和开局锁定敌方反应表可运行；
- 西部矿地、中央废墟与东部林地具有不同的程序化纹理和双语地形标签；合法命令、拒绝命令与新敌情分别触发可区分的程序化短提示音；
- 战后现员与累计损失按稳定卡牌 ID 写回；补充点、功勋、战役日、集体嘉奖、强化侧裙、战后结算与返回编成后再战已闭环；
- “中央突击”“西线钩击”和“西部佯攻”三套敌方开局在玩家行动前确定并锁定；12 人主力与 2 辆独立装甲先遣分工，佯攻按锁定时间表转向，后续四条反应规则只读取合法阵营知识；
- 每局试玩会保存版本化 JSON：战前墙钟耗时、计划变更/非法状态次数与会战中的有效/拒绝命令、首次将领/部队卡命令、改令率、情报响应、直接控制比例、接管/归还、战损和单兵诊断尝试均被记录；`tools/start_isolated_playtest.ps1` 通过 `--playtest-session` 为每名玩家隔离成长档和日志，不触碰普通存档；战后面板显示三行量化摘要，`PLAYTEST_PROTOCOL.md` 与 `tools/complete_playtest_report.ps1` 可将四项人工观察和自动指标合并为不覆盖原始日志的单局判定；所有试玩指标只进入观测记录，不进入权威快照；
- 40/80/120 实体基准、13 套测试、旧切片与灰脊 smoke 均已通过。
- P6.1 教程中心已完成：教程存档升级为 v2，四场会战分别保存未开始/进行中/已完成/已跳过；作战区显示所选会战状态并提供“从头重播”，战前开关只影响当前会战。v1 迁移、逐关隔离和重播不修改军团记录由单元测试覆盖，1280×720 与 640×800 的真实鼠标往返和截图检查通过。
- P6.2 上下文回执已完成：所有 28 个 `CommandValidationResult.Reason` 都显示双语原因与合法下一步；11 种目标模式在状态变化和拒绝后继续显示左/右键、Enter、Backspace、Delete 与 `C` 中当前有效的操作。真实《断桥回声》流程提交不可达路线后保留规划模式、显示“没有可用路径/调整路线/`C` 取消”，随后完成取消、将领命令与整局结算。
- P6.3 四关串联自主试玩已完成：`four_operation_campaign_selfplay.gd` 从作战区用真实鼠标和键盘完成四场战前、会战、结算、成长、补员与返回；测试持久化必须同时带隔离会话和显式自测开关，不会写入普通玩家档。两个全新会话均得到相同的四套锁定计划、四次失败、`battle_count=4`、`rescue_citation` 和累计 13 点补员；黑井正确继承前三关共享卡牌状态。结构化报告和四张关键截图保存在 `artifacts/`。
- P6.4 分辨率与可访问性矩阵已完成：`accessibility_resolution_matrix.gd` 以独立进程和真实输入覆盖 `1280×720`、`1920×1080`、`2560×1600`、`640×800`、`480×800` 的作战区、战前、战场、暂停与十二卡结算。边界、焦点、点击尺寸、横向滚动、地图/面板分隔和滚轮作用域均通过；窄屏战前卡片改为纵向布局，可见友军/敌军使用圆环/三角形辅助颜色识别。报告与 25 张截图保存在 `artifacts/accessibility_resolution_matrix.json` 和 `artifacts/accessibility/`。
- P6.5 音频层级与战斗可读性已完成：`BattleFeedbackDirector` 从权威事件历史聚合接敌、齐射、命中、集火、整卡受压、增援、侦察、总部危机和胜负；最多三条非空间声音并发，关键提示可抢占，静音仍保留文本与地图效果。真实《灰脊矿区》自测在四个不同 tick 捕获接敌、集火、战损和总部告急，峰值 `3/3`；普通接触不再覆盖战斗警告。十个 WAV、报告和截图保存在 `artifacts/battle-feedback/`，新增音频开关通过五档分辨率回归。

固定架构边界：

```text
Input / UI / Agent
        -> GameCommand
        -> CommandValidator
        -> CommandQueue
        -> SimulationWorld (10 Hz authoritative state)
        -> WorldSnapshot / SimulationEvent
        -> Presentation / HUD
```

Godot 节点、HUD、动画和 Agent 不得绕过该边界修改位置、生命、资源、任务或控制权。玩家直接命令优先于 Agent；被接管单位只会在玩家明确选择 RETURN 后归队。

## 2. 已完成能力

### 工程与手动 RTS

- Godot `4.6.3-stable` 锁定，GL Compatibility，1280x720 设计视口和全屏启动；
- Windows Desktop debug export preset；
- 普通点击精确单选、拖框选择框内多个单位、Shift 追加/切换、Alt 点击整组选中当前编队、数字控制组；
- 局部选择下发单体命令并脱离编队跟随；只有完整选中编队时才合并为一条编队命令；
- 新生产单位部署在建筑外侧可通行且不重叠的格子，可立即点选、框选和下达命令；
- 相机平移/缩放、小地图导航；
- Move、Stop、Attack、AttackMove 全部经过统一命令管线；单体和编队锁定射程外目标时会追击，目标换格后重新寻路，并在进入各自射程后停下开火；
- `Q` 进入统一攻击模式：左键可见敌军为集火，左键地面为移动攻击，`T` 保留为兼容别名；模式中显示所有已选作战单位的真实攻击范围、目标标记和指向线；
- 普通点击可选择己方建筑并显示选择框；选中可运行的兵工厂后，可从底部生产栏主动生产全部五类单位；
- 单位能力由数据明确声明：矿车不接受主动攻击命令，只在作业中反击射程内、可见且正在攻击自己的敌方单位；工程车只施工/维修，只有侦察车、突击车和导弹车响应主动攻击、防守与移动攻击；混合选择下达战斗命令不会中断工人任务；
- 防守命令以当前选中的作战单位创建任务编队，再进入地图目标模式指定防守中心与固定半径；单独选择新生产的突击车不会再牵动默认全军；采矿命令可点击指定已知矿区；
- 单独选择一辆我方矿车时，点击采矿按钮或按 `H` 会直接分配唯一已知矿区；存在多个已知矿区时才进入目标选择；
- 相机允许左右各 96、顶部 72、底部 260 屏幕像素的地图外平移，地图底边可移到指挥栏上方；
- 192x128 逻辑格（6144x4096、为上一版 4 倍面积）、支持安全对角移动的 AStarGrid2D、Octile 启发式、可见直线段精简、路径缓存、稳定编队槽位、窄通道纵队和卡住恢复；
- typed 单位/战斗/建筑 Resource catalog 与数据校验；
- 权威弹丸、护甲伤害、追击、AttackMove 自动接敌和死亡 tombstone；单位残骸保留 7 秒后从权威状态、编队和阵营接触记录中清理；
- 单位与建筑共用攻击目标、弹丸和伤害链，玩家可手动摧毁可见敌方建筑；
- 最后一座敌方指挥中心被摧毁后，权威胜负状态立即闭合；
- 玩家基地固定在地图左上区域 `(15, 10)`，敌方基地固定在右下区域 `(86, 54)`。

### 经济与场景状态

- 五类单位数据：矿车、工程车、侦察车、突击车、导弹车；
- 三类建筑数据：指挥中心、无人兵工厂、前线支援站；
- 阵营、建筑、矿点及 immutable snapshots；
- HarvestCommand、ProduceUnitCommand、CancelProductionCommand、SetRallyPointCommand、BuildBuildingCommand、RepairBuildingCommand；
- 矿车实际前往矿区、装载货物、返回指挥中心并卸载后，阵营矿石才增加；
- 玩家和敌方各有 10000 矿石主矿与 8000 矿石扩展矿，矿车均遵守同一往返采集链；主矿耗尽后敌方矿车会转向本方扩展矿；双方矿车在采矿中仅反击实际攻击者，不会因点击或附近出现被动敌军而主动开火，也不会加入袭击编队或取消采矿任务；
- 敌方战斗单位与矿车自卫投射物会实际命中并扣除玩家单位生命；
- 工程车按目标位置施工，建筑经历未完工到可运行状态的权威 tick 进度；
- 施工按钮在未选择单位时会自动选择空闲工程车；施工位置吸附逻辑格，并实时显示建筑占格、外围工作位、工程车连线及绿/红合法性；
- 建筑足迹动态占用逻辑格，改变时触发导航修订；建筑被摧毁后释放占格；
- 工程车可通过权威维修 tick 恢复己方受损建筑生命；
- 指挥中心存活驱动的权威阵营胜负状态。

当前权威造价与时间（10 tick/秒）：

| 内容 | 造价 | 时间 |
|---|---:|---:|
| 指挥中心 | 500 | 10.0 秒 |
| 无人兵工厂 | 300 | 6.0 秒 |
| 前线支援站 | 225 | 4.0 秒 |
| 矿车 | 200 | 3.0 秒 |
| 工程车 | 175 | 2.5 秒 |
| 侦察车 | 100 | 2.0 秒 |
| 突击车 | 250 | 3.5 秒 |
| 导弹车 | 350 | 4.5 秒 |

底部工程/生产按钮显示这些造价和生产耗时，并依据己方当前矿石、建筑生产目录与五项队列容量实时禁用。指挥中心生产矿车/工程车，兵工厂生产侦察车/突击车/导弹车；等待项取消全额退款，当前项取消退款 75%，完成单位自动前往独立生产集结点；最终平衡仍需人工试玩。

### Gate D：任务与控制权

- TaskState/TaskSnapshot 具有 typed kind、phase、lifecycle、blocked reason、目标、半径、路线、参与者和进度；
- PLAYER_CONTROLLED、AGENT_ASSIGNED、TEMPORARILY_OVERRIDDEN、UNASSIGNED、DISABLED 控制状态；
- 玩家直接命令立即保留接管权，任务进入 BLOCKED，Agent 命令返回 AGENT_OVERRIDE_BLOCKED；
- RETURN、STAY、JOIN、MANUAL disposition；
- RETURN 使用 A* 到安全 rejoin point，不瞬移，完成后恢复 formation slot、Agent 和任务；
- 导弹车接管及归队进入 MissionState/MissionSnapshot。

### Gate E：四个高层命令

- StrategicOrderCommand：DEVELOP_RESOURCE、DEFEND_AREA、ATTACK_TARGET、SCOUT_AREA；
- TaskControlCommand：PAUSE、RESUME、CANCEL；
- 工业任务通过合法 HarvestCommand 与 ProduceUnitCommand 完成采集和第二矿车；
- 任务冲突按实际参与单位仲裁，而不是按领域整体互斥；工业、侦察和主力作战可以并行，同一个单位仍不能被两个开放任务同时占用；
- 战场自主模式以基地紧急威胁、远端可见接敌、例行驻防、前沿侦察为决策顺序，每 5 tick 刷新一次；高层切换通过带明确旧任务 ID 的战略命令完成，同一 Agent 只能替换自己的自主任务；
- 委托/自主权限下，开放任务会动态吸收尚未被玩家直接命令的新生产兼容单位：矿车领取现有采矿任务，作战单位加入当前战斗编队；协助权限只控制玩家明确选中的初始参与者；
- 防守任务显示半径并在目标越界时停止追击、返回防区；
- 侦察任务只接收侦察车，到达指定观察区后持续收集阵营可见情报，并回报识别到的敌对单位/建筑数量；自主侦察会选择可达的未探索前沿，持续无进展时改选目标，且不阻塞主力防守或反击；
- 攻击任务通过合法 AttackCommand 完成推进、交战、损失阈值撤退或完成；
- RTS 风格底部指挥台将当前选择/任务情报、战略命令、工程控制和五类单位生产分区呈现；左下角固定战术小地图，左上角金币条实时显示己方资源；
- 左侧工作流监控从阵营快照汇总采矿、施工、维修、侦察、防御和进攻单位数量，并列出并行委托的阶段与参与人数；
- 战场绘制任务目标、路线和防守半径。

### Gate F/G 技术切片

- 每阵营三态知识格：UNEXPLORED、EXPLORED、VISIBLE；
- faction snapshot 仅含己方、当前可见敌军与固定在 last_seen_position 的 stale contacts；
- 隐藏敌军不能被显式攻击，玩家 Host/输入/表现消费本阵营快照；
- 敌方阶段机依次执行经济、扩张、侦察、争矿、扩军、袭击、撤退和回防，并可循环进入下一轮集结；
- 敌方补充基地遇袭抢先回防、部队低生命撤退、威胁/兵种目标优先级、侦察/突击/导弹配比生产和工厂备选落点判定；默认敌方侦察车不再使用零速度/零伤害特例；
- 敌方 Easy/Normal/Hard/Expert 四档配置已数据化，实际控制开局延迟、矿车目标、袭击规模、战斗储备、战略/战术决策间隔、反应延迟、接触记忆、评分噪声、路线威胁权重、集火、攻势门槛、有限追击和撤退滞回；
- 敌方目标评分综合战略价值、威胁削减、经济伤害、残血机会、路程和沿途可见风险，并只根据已观察或衰减中的 last-seen 兵种构成调整生产；
- 敌方会补产损失的矿车/工程车，新矿车自动接续敌方矿区；工程车会维修受损设施并在工厂完成后建设支援站；同一 tick 经济补员优先于作战生产，避免命令相互覆盖；
- 敌方矿车、工程车、工厂与作战单位通过合法 Harvest/Build/Produce/Move/Attack 命令工作；
- 敌方只攻击当前可见单位/建筑，目标丢失后只前往 last_seen_position，不读取隐藏真值；
- Debug HUD 默认隐藏，按 `F3` 切换，并显示本地化敌方阶段、难度、目标/路线分数、观察兵种构成和最近决策原因，便于观察、试玩和节奏调优；
- Debug HUD 对比 visible/stale/hidden true-state 数量；
- MissionState 串联发展、防守、攻击、导弹车接管和归队；
- HUD、任务面板、调试信息、单位/建筑/资源名称和阵营名称支持简体中文与英文；单位、建筑和矿区提供延迟一秒、跟随鼠标且限制在视口内的双语说明；
- Godot `.po` 资源与 `TranslationServer` 提供本地化，ESC 菜单可运行时切换中文/英文；
- ESC 菜单提供继续游戏、语言、敌方难度、工业/战场 AI 授权与退出游戏，并在打开时暂停 SceneTree；
- 我方工业主管与战场将领支持 ADVISORY、ASSISTED、DELEGATED、AUTONOMOUS 四档权限：建议档只显示建议且从命令层拒绝委托，协助档只执行玩家明确委托，委托档还会自动接收兼容增援，自主档可按合法阵营信息主动创建发展、侦察或战斗任务；权限降低会清理未执行命令并暂停越权任务；
- 我方自主战场 AI 会保持侦察与主力任务并行：基地附近接敌进入紧急防守，远端侦察接敌后主力反击，威胁解除后可显式替换旧任务；战略验证先检查单位能力/路径，任务落地后才要求完整 Agent 任务上下文；
- 自主侦察任务发现近距敌军后进入 EVADING 阶段，只提交 Stop/FormationMove 命令，不设置攻击目标；撤离点依据敌军距离、返基地倾向和可达路径确定，威胁解除后重新选择未探索前沿；手动指定的侦察任务仍服从玩家目标；
- 新敌情首次进入视野时触发顶部双语警报和小地图扩散信号，同一目标带 5 秒冷却；存活但失去视野的敌方单位显示静态、半透明的情报残影，不再使用容易误解为死亡的 X，确认摧毁后才显示残骸；
- 规则驱动参谋部是全面接管时主动生产的唯一规划者：底部指挥台可在“未接管/手动”与均衡接管、经济优先、基地固守、主动进攻四种持久方针间切换；选择接管方针统一开启工业主管与战场将领的自主权限并重排旧自主战场任务，选择未接管则恢复协助权限并结束主动任务；参谋部按经济恢复、基地紧急防御、基础发展、合成部队、稳态的优先级仲裁两名主管，统一计算待付生产成本、400 矿石应急储备与常规可用额，给玩家保留每座生产建筑最后一个队列槽；基础矿车编制上限 2（经济优先为 3），战斗预备队基础目标为 1 侦察、3 突击、2 导弹，固守/进攻方针及已观察敌军构成会有限调整编制；当前方针、决策和预算均显示在工作流面板；
- 自主攻击任务在目标失去视野后前往最后确认位置搜索，不读取隐藏真值；搜索中重新发现目标会恢复合法攻击，超时未发现则结束任务并让战场将领重新决策，避免长期卡死；
- 表现层目标上限设为 120 FPS、物理帧率为 60，60 Hz 显示器通过垂直同步稳定运行；权威模拟仍为 10 Hz。单位/建筑/矿区代理和 HUD 每个新快照只完整同步一次，快照之间只更新单位/弹丸插值及必要覆盖层；
- 编队攻击会在命令生效的首个权威 tick 向每个兼容成员设置目标，各单位按自身射程独立开火；静止目标的追击重新寻路有 5 tick 冷却，任务成员迁移后空编队立即回收；
- ESC 菜单直接显示四级权限行为说明并提供当前级别 tooltip；左侧工作流持续显示工业/战场建议，可据此观察建议档不会执行、协助档等待明确命令、委托档吸收新单位、自主档自行创建任务；
- 离线运行，不接入 LLM 或联网服务。

## 3. 自动验证

最后已知结果：

```text
WARSEED tests passed: 13 suites
WARSEED Grey Ridge decision matrix passed: 6 strategies x 3 plans
WARSEED release balance audit passed: 72/72 cases, 0 rejected active commands, 12 authoritative timeout defeats
WARSEED vertical slice: ticks=3600 phases=[0,1,2,3,4,5,6,7,4,5,6,7,4,5,6,7,4,5,6,7] damage=43 destroyed=5 player_ore=10000 enemy_ore=7380 enemy_gold=1825
WARSEED Grey Ridge smoke: ticks=1200 entities=35 supply=2 reports=7 reactions=3 probe=2 thunder=2 armored=2 player_defeated=false
WARSEED_PERF 40  entities: simulation avg/p95/max 2.851/4.529/6.455 ms; presentation p95 1.055 ms
WARSEED_PERF 80  entities: simulation avg/p95/max 5.483/7.796/10.890 ms; presentation p95 2.142 ms
WARSEED_PERF 120 entities: simulation avg/p95/max 7.245/8.831/11.892 ms; presentation p95 2.495 ms
WARSEED_RENDER_PERF 80 entities, 30 s, 0 injected projectiles: frame avg/p95 9.335/14.396 ms; simulation p95 6.892 ms; input-to-presented p95 105.584 ms; path failures 1; formal gate passed
WARSEED_RENDER_PERF 120 entities, 30 s, 0 injected projectiles: frame avg/p95 10.982/19.931 ms; simulation p95 10.919 ms; input-to-presented p95 108.152 ms; path failures 3; extended measurement misses 60 FPS P95
WARSEED_RENDER_PERF 80/120 entities + 160 persistent projectiles: frame p95 16.243/21.869 ms; 80 reaches the numerical line, 120 does not; both remain outside the formal gate
WARSEED_RENDER_PERF 80 entities, 480 s: 4800/4800 ticks; frame avg/p95/max 8.333/9.198/30.865 ms; simulation p95/max 5.030/23.098 ms; path failures 0; unresolved authoritative/presented inputs 0/0; orphan/resource growth 0/0; long-run gate passed
```

覆盖：命令管线、固定 tick、对角最短路径/导航/编队、观测指标、试玩事件记录与 JSON 序列化、typed data、地图、精确单选/框选/局部编队命令、脱队成员边界、新生产单位与建筑选择、真实生产突击车的单独防守与委托增援、五类单位生产与可负担状态、职责过滤、Q 集火/单体移动攻击/射程预览、编队首 tick 响应与不同射程独立开火、远程追击与移动目标重新寻路、双方矿车对称自卫、目标式采矿/防守/侦察与敌情计数、可达前沿侦察、侦察接敌规避且不攻击、侦察/防守并行、远端接敌反击、基地紧急防守、攻击失联搜索与重新接敌、任务显式替换、600 tick 自主任务所有权与临时编队回收、敌方实际伤害、残骸超时清理、单位与建筑弹丸战斗、手动胜利、建筑施工/占格/完工/维修、真实矿车装卸往返、对角基地布局、经济与胜负、阵营知识、敌方 last-seen 生存/死亡语义、过期接触表现标记、同 tick 表现代理不重复同步、小地图敌情信号、60 FPS 最低项目目标、参谋部四方针直接接管/低资源跨域仲裁/生产承诺去重/预算账本/玩家队列预留/紧急储备释放/观察后友军编制调整/受阻发展恢复、敌方八阶段经济与作战循环、四档难度参数、反应时间差异、目标/路线评分、观察后兵种反制、有限追击、我方四级权限门禁/增援差异/建议状态/自主任务、经济损失补员/支援站扩张、四项高层任务、接管/归队、工程 UI 命令、右键建筑攻击、中英文即时刷新、完整切片和主场景 UI 控件。

本轮还通过：

- headless editor import；
- 主场景 headless smoke；
- 1280x720 中文实际渲染截图检查，确认补给条、战区支援、枢机情报、三名将领、四张部队卡、姿态/战法、预备卡投放预览、接管/归还与路线/阵线按钮无重叠；地图航路与可拖动节点、最终阵线端点、正面箭头、预测射界、试玩量化摘要和四卡战后结算/成长操作均完整可辨认；480x800 窄屏投放态也无元素互相覆盖；
- 中英文 HUD、单位/建筑标签、调试 HUD、小地图与暂停菜单检查；
- 四关隔离试玩启动器、逐场评估工具、分关队列汇总工具和试玩包构建器的 PowerShell 语法与烟测；启动器在续测时只评估本次改变的记录，报告烟测覆盖跨关输入与非法 ID 拒绝，队列烟测覆盖会战感知去重、分关覆盖、聚合指标、优先问题、坏报告与输入不可变，试玩包测试会实际创建 ZIP、解压、校验通用入口并逐文件比较 SHA-256；
- `tools/verify_grey_ridge_release.ps1` 使用锁定的 `4.6.3.stable.mono` 严格串行执行编辑器导入、两轮 13 套测试、旧切片与四关 smoke、逐关确定性矩阵、四关 72 案例发布平衡审计、40/80/120 实体基准、四项工具烟测、Windows export 和导出包隔离启动；新增平衡审计后的连续两轮完整门禁分别用时 `459.033/448.452` 秒并全部通过，四关人工工具扩展后的再次全门禁用时 `439.220` 秒并通过；`.github/workflows/grey-ridge-ci.yml` 在 Windows runner 上调用同一入口并上传试玩 ZIP；
- `git diff --check`。

Windows Desktop debug export 与导出的隔离参数 headless smoke 已在本机 `4.6.3.stable.mono` 模板通过；2026-08-20 的 RC4 完整发布门用时 `459.397` 秒并全部通过。当前 `warseed-debug.exe` 为 101,030,400 bytes、SHA-256 `679DF06F7F9F2D2293768747AA9AD71FB996869249960179ADA8180445FC0A7A`；PCK 为 5,858,368 bytes、SHA-256 `7F64AB55FCFE0DD5C85D53D7F7E3109EDBA400BC446B31672BACF705AD02ADD4`。唯一允许用于新 P6.7 场次的候选包是 `build/playtest-kits/WARSEED-Four-Operations-P67-RC4-20260820.zip`，大小 37,334,442 bytes、SHA-256 `775CE0A71A634938836ED30E75F4D200C2021F3CE206BA398AF5A08435C42D73`；独立解压后确认通用入口、四个会战 ID、说明文件、预注册 cohort 计划和 11 个清单文件的逐项哈希，包内 console EXE 隔离启动通过。RC、RC2、RC3 与所有名称含 `Latest` 的包只保留为审计产物，不再分发给新场次。`build/` 仍是本机生成目录，不成为源码运行依赖。调试 preset 不修改空白的 Windows 版本/图标资源，避免含中文工作区路径下无意义的模板二次写入；正式发布设置图标、版本和签名时需单独恢复并验证元数据修改。

标准 Windows 命令（从仓库根目录执行）：

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\verify_grey_ridge_release.ps1 `
  -GodotConsolePath <godot-console>

# 以下为需要定位单项问题时的拆分命令：
& <godot-console> --headless --editor --path . --quit
& <godot-console> --headless --path . --script res://tests/test_runner.gd
& <godot-console> --headless --path . --script res://tests/vertical_slice_smoke.gd
& <godot-console> --headless --path . --script res://tests/grey_ridge_smoke.gd
& <godot-console> --headless --path . --script res://tests/scenarios/grey_ridge_decision_matrix.gd
& <godot-console> --headless --path . --script res://tests/performance/grey_ridge_entity_benchmark.gd
powershell -ExecutionPolicy Bypass -File .\tests\tools\playtest_report_smoke.ps1
powershell -ExecutionPolicy Bypass -File .\tests\tools\isolated_playtest_launcher_smoke.ps1
powershell -ExecutionPolicy Bypass -File .\tests\tools\playtest_kit_smoke.ps1
powershell -ExecutionPolicy Bypass -File .\tests\tools\playtest_cohort_smoke.ps1
& <godot-console> --headless --path . --quit-after 3
& <godot-console> --headless --path . --export-debug "Windows Desktop" "build/windows/warseed-debug.exe"
& .\build\windows\warseed-debug.exe --headless --quit-after 3
```

## 4. 跨电脑复现

要求：

- Godot `4.6.3-stable`，Windows 推荐 Mono 构建；
- Windows export 时安装同版本 export templates；
- 不需要 C# SDK、第三方插件、Git LFS、云服务、账号或 LLM。

步骤：

1. `git clone https://github.com/msdest565/warseed-rts.git`；
2. Godot Project Manager 导入仓库根目录的 `project.godot`；
3. 首次导入完成后运行主项目；
4. 需要验证时执行上节命令。

`.godot/`、`build/`、本地日志、截图和凭据不得提交。所有运行所需 `.gd`、`.uid`、`.tscn`、`.tres`、`project.godot` 与 `export_presets.cfg` 必须保留在 Git。

## 5. 当前限制

- 当前跨局成长只有一项荣誉和一项装备，尚无士气、组织、失能、装备兼容性与更长战役层；
- 路线工具已支持直接拖动既有航路点与阵线端点、撤销最后航路点、载入并覆盖已提交路线、重画阵线和清除命令；当前射界扇区是按整卡存活战斗成员最大射程生成的规划反馈，尚未加入遮挡感知、方向装甲或复杂前后排编组；
- 将领行动/原因/ETA/风险/退出条件已具备自动化、防隐藏真值测试与双语 UI 覆盖；陌生玩家能否在压力下正确解释这些行为仍属未知，只能由可选真人研究回答，但不再阻塞工程；
- 《灰脊矿区》已有三套开局锁定敌方计划、独立装甲先遣和首个时间表佯攻；A/B/C 与三种自由命令组合的 18 场黄金矩阵已覆盖三套计划，反应表遵守合法阵营知识，反侦察和长期对手模型仍未覆盖；
- 《断桥回声》工程切片已完成：独立 `broken_bridge` 内容包/场景/存档/记录，河流与主桥权威阻断、工程渡口、高地火力收益、桥面暴露、两张新部队卡、两张新战法和三套锁定计划均已接入；4×3 双跑矩阵、1200 tick smoke 与真实键鼠全流程通过，陌生玩家理解度和平衡验收仍待执行；
- 《雾林输线》工程切片已完成：独立 `fog_forest` 内容包/场景、90—360 tick 情报衰减、真实运输纵队、前线节点一次性激活、敌方知识驱动的延迟拦截、两张新部队卡和三套锁定计划均已接入；4×3 双跑矩阵、1400 tick smoke 与 1280×720 真实键鼠全流程通过，陌生玩家理解度和平衡验收仍待执行；
- 《黑井反击》工程切片已完成：独立 `black_well` 内容包/场景、`7168×4608` 动态导航战场、五将领十二卡编成、组织度恢复、多轴增援、整卡有限撤出和同卡成长继承均已接入；4×3 双跑矩阵、2000 tick smoke 与 1280×720 真实键鼠全流程通过，陌生玩家理解度和平衡验收仍待执行；
- “快速架桥”和“高地监视”不再是说明文字：前者在玩家指定关联渡口轴线后，经正常支援校验自动扣除两补给并打开共享网格，同时让工程卡保持后置；后者让火力卡在目标后方 320 世界单位展开并准备 30 tick。行为、资源消耗、阵位和指挥反馈均有自动测试；
- 主程序现由数据驱动的“作战区”进入四场会战，测试夹具不会出现在玩家列表；暂停菜单可在确认后放弃未结算战斗，战后结算可直接返回作战区。选择页已在 1280×720 与 640×800 完成真实鼠标/键盘跳转和截图检查；
- 四关教程状态现已相互隔离并可从作战区重播；上下文拒绝原因、合法下一步和目标模式按键已经进入统一游戏内操作栏；
- 四关真实输入串联已在两个全新隔离档通过；当前固定的“全将领直取敌方总部”诊断输入四关均失败，它证明失败恢复和跨关持续性，不构成平衡或推荐打法证据；
- 统一发布门已串行覆盖两轮 13 套回归、《灰脊矿区》smoke/6×3 矩阵、《断桥回声》《雾林输线》《黑井反击》smoke/4×3 矩阵、四关 72 案例发布平衡审计、实体基准、Windows 导出和导出包启动；保留 `verify_grey_ridge_release.ps1` 文件名以兼容现有调用；
- 四关发布平衡审计覆盖推荐、保守、情报优先、资源贪婪、无干预和故意失败六类策略与三套锁定计划，共 `72/72` 案例通过；主动策略没有命令拒绝，12 个故意失败案例均达到权威超时失败。军团存档、教程和试玩记录格式冻结为 `3/2/3`；
- 40/80/120 实体已完成 headless 与 Windows 完整 HUD 基线；阻断格、单位与弹丸批处理后，最新 80/120 实体 Windows 帧 P95 为 14.396/19.931 ms，80/120+160 弹丸为 16.243/21.869 ms；80 正式门通过，120 的两项扩展测量均未达到 60 FPS 数值线；正式关卡人工八分钟会战仍待验证；
- 默认开局为 20 个友方加 14 个敌方实体；自定义开局人口由两张实际首发卡计算，四卡全部投入时仍为 34 个友方加 14 个敌方、共 48 个真实实体，达到首切片下限但没有达到完整 MVP 的 80—120 实体内容规模；
- 5—8 分钟敌人压力、资源节奏、地形克制幅度和指挥负担尚未经过陌生玩家试玩调优；
- 本地记录器能自动量化操作行为，但卡牌/实体识别、Agent 行为与敌方反应能否被理解，以及第二局意愿，仍需观察员和陌生玩家给出证据；
- 图形和提示音使用程序化占位资产，不是最终美术与音频；
- 语言可在运行时切换，但当前不跨启动持久化玩家选择；

AI 下一阶段的权限模型、分层决策频率、敌方难度参数、完整决策树、策略模板与验收矩阵已经整理在 [`AI_DESIGN_AND_DECISION_TREES.md`](AI_DESIGN_AND_DECISION_TREES.md)。该文档是后续规则 AI 实现基线；其中明确标记了现有能力、下一阶段和长期设计，不能把设计项视为当前已实现功能。

## 6. 历史下一步（已被 D-027 取代）

当前唯一下一工作项为 `WS-R2-001`：建立灰脊完整对局基线与因果观测契约。P6.7 可在条件允许时作为产品研究执行，但不再阻塞工程。实时入口见 `AI_DEVELOPMENT_STATE.md` 与 `GAMEPLAY_REWORK_ROADMAP.md`。

## 7. 接手规则

- 先运行 13 套件和主场景 smoke，再开始修改；
- 不 reset、clean、checkout 覆盖或丢弃现有工作；
- 每个增量都要完成解析、自动测试、主场景、Windows export、导出 exe smoke 和 `git diff --check`；
- 常规工程决策自行推进；核心产品范围、引擎版本、联网、付费资产、许可证或破坏性 Git 操作必须询问用户。
