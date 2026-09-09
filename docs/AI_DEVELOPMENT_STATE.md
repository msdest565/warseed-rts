# WARSEED AI 开发状态与任务队列

> 状态版本：37
> 更新时间：2026-09-10
> 更新规则：每个完成、阻塞或重新规划的工作项都必须更新本文件
> 执行规则：[`AI_DEVELOPMENT_WORKFLOW.md`](AI_DEVELOPMENT_WORKFLOW.md)
> 目标命令：[`AI_GOAL_COMMANDS.md`](AI_GOAL_COMMANDS.md)

## 1. 机器可读控制块

```yaml
workflow_version: 1.1
state_version: 37
updated_at: 2026-09-10
project: WARSEED
current_phase: R2
current_gate: R2_PRODUCT_ACCEPTANCE
phase_status: COMPLETE_SIMULATED_AWAITING_PRODUCT_ACCEPTANCE
release_candidate: R1-FEEDBACK-RC2
release_candidate_status: ENGINEERING_BASELINE_ARCHIVED
release_candidate_package: build/playtest-kits/WARSEED-R1-Feedback-RC2-20260901.zip
release_candidate_sha256: 730B7F496F8871D62CA887F5B955974CF540014F3B5EA9307E6F5D4070C10A08
active_maintenance_work_item: none
working_build_id: 0.1.0-r1-feedback.6-dev
latest_maintenance_work_item: WS-MAINT-20260910-001
latest_maintenance_status: READY
feedback_build_id: 0.1.0-r1-feedback.2
feedback_schema_version: 1
feedback_collection_status: COMPLETE_SIMULATED
feedback_human_validation_status: OPTIONAL_NOT_RUN
feedback_server_guide: docs/FEEDBACK_SERVER_GUIDE.md
feedback_focus_guide: docs/CURRENT_PLAYTEST_FEEDBACK_FOCUS.md
feedback_release_gate_duration_seconds: 489.325
field_execution_guide: docs/P6_7_FIELD_EXECUTION_CHECKLIST.md
human_evidence_checked_at: 2026-08-20
human_assessment_count: 0
cohort_summary_count: 0
countable_human_session_count: 0
unassigned_raw_session_count: 1
human_validation_policy: OPTIONAL_RESEARCH
human_evidence_required: false
release_human_evidence_required: false
human_validation_debt: CLOSED_BY_D026
human_validation_test_plan: docs/HUMAN_VALIDATION_TEST_PLAN.md
simulated_gate_authorized_at: 2026-08-21
simulated_gate_authority: product_owner_user_message
next_work_item: WS-R3-001
next_work_item_status: BLOCKED
next_work_item_blocker_kind: PRODUCT_OWNER_ACCEPTANCE
machine_ready_work_item: WS-MAINT-20260910-001
queued_maintenance_work_item: WS-MAINT-20260910-001
queued_maintenance_status: READY
expansion_implementation_allowed: true
phase_exit_requires_product_owner: true
r1_engineering_status: COMPLETE
r1_exit_status: ACCEPTED
r1_exit_authorized_at: 2026-09-07
r1_exit_authority: product_owner_user_message
r1_simulated_full_gate: PASS
r1_simulated_full_gate_duration_seconds: 651.775
r1_simulated_verified_at: 2026-08-21
r2_engineering_status: COMPLETE_SIMULATED
r2_exit_status: AWAITING_PRODUCT_ACCEPTANCE
r2_simulated_full_gate: PASS
r2_simulated_full_gate_duration_seconds: 1426.714
r2_simulated_verified_at: 2026-09-07
goal_protocol_version: 1.1
gameplay_rework_roadmap: docs/GAMEPLAY_REWORK_ROADMAP.md
recommended_goal_command: "/goal work-item WS-MAINT-20260910-001"
full_gate_command: >-
  powershell -ExecutionPolicy Bypass -File
  .\tools\verify_grey_ridge_release.ps1
  -GodotConsolePath <godot-console>
```

解释：产品负责人于 2026-09-07 接受 R1 工程出口并通过 D-026 取消真人证据硬门，同时通过 D-027 将 R2-R7 重排为玩法优先路线。真人试玩仍可作为可选产品研究，但 `NOT_RUN (HUMAN)` 不再阻塞工程、阶段或发布。R2 工程出口已完整通过，当前等待产品负责人接受残余产品风险；在接受前 `WS-R3-001` 保持 `BLOCKED`。用户在精简 HUD 验收中发现隐藏部队卡后战地补员和预备队投入失去入口，已登记 `WS-MAINT-20260910-001` 为当前唯一 `READY` 维护项。自动化仍只能标记为 `SIMULATED`，不得宣称已经证明真人理解或主观乐趣。

2026-09-07 已完成开发标准与路线重排：新建 `GAMEPLAY_REWORK_ROADMAP.md`，R2 从正式地图管线改为灰脊乐趣基准，后续依次处理卡牌战术语法、我方分层 AI、敌方行动 AI、第一章行动层与内容生产。旧扩充路线保留为架构和迁移参考，不再决定任务领取。

以下 2026-08-25 至 2026-09-03 条目是历史记录，其中关于真人债务、R1 阶段门和 R2 禁令的措辞均已由 D-026、D-027 取代。

2026-08-25 已完成维护项 WS-MAINT-20260825-001：战后匿名反馈、本地不可丢失队列、本机/局域网临时收集服务、看板与 CSV 已形成工程闭环，并生成 R1-FEEDBACK-RC1。该候选包可用于收集真人意见，但反馈功能本身的真人可用性仍为 `NOT_RUN`，不改变 R1 阶段门或 R2 禁令。

2026-09-01 已完成维护项 WS-MAINT-20260901-001：灰脊教程改为带预期和通过标准的试玩验证目标；编成性格、姿态和战法补齐悬停解释；卡牌会战移除无效的旧 RTS 全面接管入口；预备卡部署通过权威校验解析到整卡安全锚点。R1-FEEDBACK-RC2 已通过完整工程门，但 `HV-MAINT-001` 至 `HV-MAINT-004` 仍为 `NOT_RUN (HUMAN)`。

2026-09-01 已完成维护项 WS-MAINT-20260901-002：卡牌会战单位主体、标签、选择覆盖物和批量渲染统一采用完整镜头反向补偿，屏幕尺寸不再随地图缩放改变。本地工作版本为 `0.1.0-r1-feedback.3-dev`，未生成新试玩包；人工视觉检查 `HV-MAINT-005` 仍为 `NOT_RUN (HUMAN)`。

2026-09-03 根据用户复测将 WS-MAINT-20260901-002 返回 `REWORK` 并完成二次修复：确认 `.3-dev` 漏掉了直接运行 `game_root.tscn` 的 `LEGACY_RTS` 分支；`.4-dev` 已将单位固定屏幕尺寸作为所有场景的通用表现规则，并由旧 RTS 与卡牌会战两条真实窗口路径分别验证。`HV-MAINT-005` 仍为 `NOT_RUN (HUMAN)`。

2026-09-03 根据用户再次复测将 WS-MAINT-20260901-002 第三次返回 `REWORK`：确认前两次把“固定体积”错误解释为“固定屏幕像素尺寸”，镜头反向补偿会改变坦克相对地图参照物的世界比例。`.5-dev` 已完全删除单位镜头反向补偿；详细代理固定为 `scale=1.0`，批量单位只保留兵种固定比例，屏幕投影正常随镜头变化。14 套测试、旧 RTS 真实窗口和卡牌会战五档窗口矩阵通过；`HV-MAINT-005` 仍为 `NOT_RUN (HUMAN)`。

2026-09-03 已完成维护项 WS-MAINT-20260903-001：编成页为战法和姿态补充明确字段标题，每张将领卡增加常驻影响说明区；悬停性格、战法或姿态控件时即时切换对应说明，展开候选项保留逐项中英文 tooltip，键盘焦点同样可更新说明。`.6-dev` 已通过 14 套测试与五档真实窗口矩阵；`HV-MAINT-006` 仍为 `NOT_RUN (HUMAN)`。

## 2. 当前基线

| 维度 | 当前事实 |
|---|---|
| 正式会战 | 灰脊矿区、断桥回声、雾林输线、黑井反击，共 4 场 |
| 内容 | 5 名将领、12 张部队卡、12 张战法、12 项成长、7 类支援行为 |
| 底层卡牌单位 | 侦察、突击、导弹、工程、运输，共 5 种有效战术类型 |
| 胜负 | 卡牌会战已由类型化目标系统结算；四关保持总部/超时等价行为，护送胜利与有序撤离由测试资源证明可达 |
| 地图 | 3 张 6144x4096、1 张 7168x4608；正式地图管线尚未完成 |
| 存档 | 军团 v3、教程 v2、试玩记录 v3；尚无战役行动图状态 |
| 自动化 | 18 套 headless 测试、四关 smoke、逐关矩阵、72 案例早期窗口审计、灰脊 15 案例完整对局基线、五档分辨率矩阵 |
| 反馈 | 战后双语问卷、本地 pending/sent、HTTP 临时收集服务、HTML/JSON/CSV 汇总；真人可用性未运行 |
| 性能 | 2026-09-10 维护版发布门：80 实体模拟 P95 15.344 ms，通过；120 实体模拟 P95 22.491 ms，仅保留为压力测量 |
| 可选产品研究 | P6.7 与集中真人用例尚未执行；D-026 后不参与工程、阶段或发布门 |

## 3. 当前阶段目标

R1 的类型化目标与结果系统已经完成并由产品负责人接受。R2 已把《灰脊矿区》建立为可重复比较的玩法基准：完整对局观测、战线/威胁提示、异常驱动指挥、因果复盘和策略质量审计均通过工程出口，当前等待产品负责人接受产品风险后再进入 R3。

R1 已具备的 `SIMULATED` 出口证据：

- 目标定义、稳定 ID、受限 kind、两层 `ALL/ANY` 与数据校验；
- 目标状态、值拷贝快照、结构化事件和确定性同 tick 结算；
- 四关总部/超时等价迁移，Legacy RTS 保留旧胜利链；
- `BattleOutcome`、结束后命令拒绝、tick 冻结和一次性结算/存档保护；
- 护送胜利与有序撤离的权威测试场景；
- 14 套测试、四关 smoke/矩阵、72 案例、80 实体、五档分辨率和 Windows 发布门通过。

未执行的真人用例见 `HUMAN_VALIDATION_TEST_PLAN.md`，其状态为可选研究，不阻塞当前队列。新的阶段和工作项顺序以 `GAMEPLAY_REWORK_ROADMAP.md` 为准。

## 4. 产品决策状态

| ID | 决策 | 推荐值 | 当前状态 | 解除条件 |
|---|---|---|---|---|
| D-018 | 战役形态 | 轻量行动图 | DEFERRED | R6 冻结 |
| D-019 | 胜负框架 | 类型化目标 + 两层 ALL/ANY | ACCEPTED | R1 实施 |
| D-020 | 战中经济 | Supply 为唯一可消费资源 | DEFERRED | R6 冻结 |
| D-021 | 部队卡编制 | 稳定 entry ID 的混成编制 | DEFERRED | R3 冻结 |
| D-022 | 战斗复杂度 | 先传感器/压制/弹药/伤害标签 | DEFERRED | R3 冻结 |
| D-023 | 正式规模 | 近期 60-80 实体 | ACCEPTED | 持续性能门 |
| D-024 | 叙事基调 | 可审计自主指挥与责任 | DEFERRED | R6 冻结 |
| D-025 | 真人门处理 | 工程模拟条件放行，真人债务保留 | SUPERSEDED | 由 D-026 取代 |
| D-026 | 真人证据政策 | 可选产品研究，不作为工程/阶段/发布硬门 | ACCEPTED | 已生效；保持证据来源诚实 |
| D-027 | R2-R7 路线 | 玩法优先重排 | ACCEPTED | `GAMEPLAY_REWORK_ROADMAP.md` 生效 |

未接受的推荐值可以用于设计讨论，不能被 AI 当作已经生效的产品承诺。

## 5. R0 历史队列

| ID | 状态 | 工作项 | 所有者 | 依赖 | 下一动作 |
|---|---|---|---|---|---|
| WS-R0-001 | CANCELLED (D-026) | 执行 P6.7 陌生玩家 cohort | 真人组织者 | 需求已取消 | 可作为自愿研究重新发起，不恢复旧门禁 |
| WS-R0-002 | CANCELLED (D-026) | 汇总 cohort 与分级缺陷 | AI + 产品 | R0-001 已取消 | none |
| WS-R0-003 | CANCELLED (D-026) | 修复 P0/P1 与重复 P2 | AI | R0-002 已取消 | 新发现缺陷按当前阶段维护项处理 |
| WS-R0-004 | CANCELLED (D-027) | 评审 D-018 至 D-024 | 产品负责人 | 由逐阶段决策取代 | none |
| WS-R0-005 | CANCELLED (D-027) | 冻结第一扩充切片 | 产品 + AI | 由玩法优先路线取代 | none |
| WS-R0-006 | CANCELLED (D-027) | R0 阶段出口验证 | AI + 产品 | R1 已按 D-025 完成 | none |

## 6. R1 历史队列

R1 已完成。其自动化与开发者试玩证据继续标记为 `SIMULATED`，但 D-026 已移除真人验证债务。

| ID | 状态 | 工作项 | 依赖 |
|---|---|---|---|
| WS-R1-001 | DONE (`SIMULATED`) | 目标定义、稳定 ID、参数和数据校验 | D-019、D-025 |
| WS-R1-002 | DONE (`SIMULATED`) | 目标状态、快照与结构化事件 | R1-001 |
| WS-R1-003 | DONE (`SIMULATED`) | 确定性 `ObjectiveSystem` 与同 tick 结算 | R1-002 |
| WS-R1-004 | DONE (`SIMULATED`) | 四关等价总部目标迁移 | R1-003 |
| WS-R1-005 | DONE (`SIMULATED`) | `BattleOutcome`、结算一次性保护和目标 UI | R1-004 |
| WS-R1-006 | DONE (`SIMULATED`) | 护送胜利纵向测试场景 | R1-005 |
| WS-R1-007 | DONE (`SIMULATED`) | 有序撤离纵向测试场景 | R1-005 |
| WS-R1-008 | DONE (`SIMULATED`) | R1 阶段出口验证 | R1-006、R1-007 |

## 7. R2 活动队列

R2 的目标是建立灰脊玩法基准，不在本阶段批量增加地图、卡牌或战役内容。完整契约与后续阶段见 `GAMEPLAY_REWORK_ROADMAP.md`。

| ID | 状态 | 工作项 | 依赖 |
|---|---|---|---|
| WS-R2-001 | DONE (`SIMULATED`) | 灰脊完整对局基线与因果观测契约 | R1 出口、D-026、D-027 |
| WS-R2-002 | DONE (`SIMULATED`) | 战线、威胁、情报不确定性与补给承诺叠层 | R2-001 |
| WS-R2-003 | DONE (`SIMULATED`) | 高层意图与异常驱动指挥界面 | R2-002 |
| WS-R2-004 | DONE (`SIMULATED`) | 战后关键转折、卡牌贡献和失败因果 | R2-001、R2-003 |
| WS-R2-005 | DONE (`SIMULATED`) | 完整策略质量审计与灰脊调优 | R2-002 至 R2-004 |
| WS-R2-006 | DONE (`SIMULATED`) | R2 阶段出口 | R2-005 |

## 8. 已有验证证据

| 证据 | 状态 | 边界 |
|---|---|---|
| 18 套 headless 测试 | PASS (`SIMULATED`) | 新增完整玩法报告、战场态势、高层意图、异常与战后复盘投影的 schema、确定性、值拷贝和知识边界；不证明真人理解 |
| 战场态势叠层 | PASS (`SIMULATED`) | 战线、整卡任务轴、已知/最后已知威胁、探索不确定区和 Supply 承诺只由玩家合法快照派生；四层开关与小地图同步 |
| 灰脊 15 案例完整策略质量矩阵 | PASS (`SIMULATED`) | 3 敌方计划 × 5 玩家策略 × 2 重复均确定性；分轴与集中突破各跨三计划获胜，侦察后投入、静态预备队和无干预各三败；质量门 `PASS`，aggregate fingerprint `a994185d975a06e046fe608567e9adb685b6a9525a83fdc85b858477d8a51255` |
| 四关 smoke | PASS | 机制触发和稳定性，不证明完整胜率 |
| 四关 72 案例审计 | PASS | 主动策略主要覆盖前 200 tick，不是 72 场完整对局 |
| Windows 80 实体 | PASS (`SIMULATED`) | 2026-09-10 完整门模拟 P95 15.344 ms、表现层 P95 1.725 ms；当前正式性能门 |
| Windows 120 实体 | MEASURED (`SIMULATED`) | 2026-09-10 完整门模拟 P95 22.491 ms、表现层 P95 2.562 ms；扩展测量，不改变当前 60-80 范围 |
| 五档分辨率矩阵 | PASS (`SIMULATED`) | 1280x720、1920x1080、2560x1600、640x800、480x800；不替代真人可访问性 |
| R1 完整发布门 | PASS (`SIMULATED`) | 2026-08-21，651.775 秒；含两轮 14 套测试、四关、72 案例、性能、导出和包内启动 |
| P6.7-RC4 完整发布门 | PASS | 2026-08-20，459.397 秒；工程门通过不替代真人证据 |
| P6.7-RC4 候选包 | PASS | 11 项清单、逐文件哈希、独立解压和包内 console EXE 启动通过 |
| P6.7 cohort | OPTIONAL_NOT_RUN (`HUMAN`) | D-026 后仅作可选产品研究，不参与门禁 |
| R1 机制真人专项 | OPTIONAL_NOT_RUN (`HUMAN`) | 用例保留在 `HUMAN_VALIDATION_TEST_PLAN.md`，不参与门禁 |
| 反馈收集完整链路 | PASS (`SIMULATED`) | 本地先落盘、HTTP 确认、服务幂等、sent 归档、看板与 CSV；不证明真人发现或理解 |
| 反馈 UI 五档矩阵 | PASS (`SIMULATED`) | 中英文、必填校验、滚动可达与真实窗口截图；鼠标/触控板真实体验仍为 `NOT_RUN` |
| 反馈真人专项 | OPTIONAL_NOT_RUN (`HUMAN`) | 可选研究；HV-FB-001 至 HV-FB-005 不参与门禁 |
| R1-FEEDBACK-RC2 完整发布门 | PASS (`SIMULATED`) | 2026-09-01，489.325 秒；两轮 14 套测试、四关、72 案例、80/120 实体、反馈链路、Windows 导出和包内启动 |
| 首关反馈修复真人专项 | OPTIONAL_NOT_RUN (`HUMAN`) | 可选研究；HV-MAINT-001 至 HV-MAINT-004 不参与门禁 |
| 单位固定世界体积 | PASS (`SIMULATED`) | 详细代理世界比例恒为 `1.0`，批量比例固定；旧 RTS 与卡牌会战五档真实窗口路径通过；HV-MAINT-005 仍为 `NOT_RUN (HUMAN)` |
| 编成战术选择信息披露 | PASS (`SIMULATED`) | 字段标签、常驻说明、折叠控件悬停连接和逐项 tooltip 通过；五档真实窗口布局通过；HV-MAINT-006 仍为 `NOT_RUN (HUMAN)` |
| 高层意图与异常驱动指挥 | PASS (`SIMULATED`) | 五字段意图、显式取消、五类异常、稳定去重/解决/重开、有限合法处置、完整报告与五档鼠标交互通过；不证明真人纠正负担或主观乐趣 |
| 决策回执与将领撤离链路 | PASS (`SIMULATED`) | 异常动作具名回执保持 30 tick 并抑制重复提交；撤离清除旧意图、取消侦察任务、转为总部安全集结并取消已排队/后续自动战法；完整发布门与五档实渲通过 |
| 指挥响应、整卡协同与情境教程 | PASS (`SIMULATED`) | 动作按控制权投影并给出具名拒绝/恢复；同将领附近 Agent 战斗卡共同响应合法可见威胁，整卡可攻击成员自动开火；领队阵亡不再瘫痪整卡；教程等待权威快照并提供常驻指南。完整门 `1930.881s`、四关矩阵、72 案例、30 场完整质量矩阵、80 实体与 Windows 导出通过 |
| 精简 HUD 与可靠决策闭环 | PASS (`SIMULATED`) | 卡牌会战收敛为支援、小地图、高层意图、扩大决策区、三张将领卡和暂停入口；悬停预览路线/目标；成功即时回执，拒绝、过期、宿主不可用和 15 tick 超时弹窗；本局历史默认隐藏。五档真实窗口与完整门 `1885.515s` 通过 |
| 战后因果复盘 | PASS (`SIMULATED`) | 真实宿主合法观测、3-7 个转折、逐卡贡献、结果主因与支撑事实、来源签名及隐藏身份过滤通过；三视图五档实渲可达，不证明真人理解 |
| R2 完整发布门 | PASS (`SIMULATED`) | 2026-09-07，1426.714 秒；两轮 18 套测试、四关 smoke/矩阵、72 案例、30 场完整质量矩阵、80/120 实体、反馈工具链、Windows 导出与包内启动通过 |
| R2 五档真实窗口 | PASS (`SIMULATED`) | 五档均覆盖战场态势、高层意图、异常队列和战后三区；命令回执不得遮挡资源栏、战况栏或态势开关，桌面与 480x800 截图已人工视觉抽查 |

具体测试数字和限制见 [`EXPANSION_CURRENT_STATE_AUDIT.md`](EXPANSION_CURRENT_STATE_AUDIT.md)。

## 9. 当前风险

| 风险 | 状态 | 控制 |
|---|---|---|
| 核心交互的主观理解与乐趣缺少真人样本 | ACCEPTED_PRODUCT_RISK | 使用完整对局代理、因果指标和开发者试玩推进；不得声称已证明真人体验 |
| `SimulationWorld` 继续增长关卡特判 | OPEN | R2-R5 先建立观测、效果与 AI 扩展点；不批量生产内容 |
| 新卡只换名称不换底层行为 | OPEN | R3 要求混成卡和可解释单位行为纵向切片 |
| 新地图继续依赖 `test_arena` | OPEN | R6 正式地图/内容验证器；此前不新增正式地图 |
| 自动化平衡证据被过度解读 | CONTROLLED | 报告强制标注 tick 窗口与断言范围 |
| 120 实体被误当近期目标 | CONTROLLED | 正式门固定 60-80，复测后再决定 |
| 护送/撤离仅有工程测试资源，尚无正式玩家入口 | OPEN | R6 内容迁移时建立正式入口；当前不把测试夹具当成玩家内容 |
| 临时反馈服务器无生产级认证与 TLS | CONTROLLED | 仅限受信任临时局域网；默认 loopback，`-Lan` 显式开放；不得映射公网 |
| 自动化指标被误写成主观乐趣证明 | CONTROLLED | 报告只陈述策略差异、纠正负担和因果完整性；主观结论保持未知 |
| 灰脊脚本策略可能过拟合固定路线与时点 | CONTROLLED | 两种不同兵力/路线跨三敌方计划获胜并保留三类稳定失败；完整矩阵锁定策略链、权衡和确定性，但不外推真人发现性或其他地图平衡 |
| 友军协同发现距离可能改变接敌节奏 | CONTROLLED | 只允许同将领、附近、Agent 控制且不处于侦察/撤离/撤退的战斗卡响应合法可见目标；四关矩阵和完整灰脊质量门锁定当前行为，真人节奏感仍未知 |
| 友方任务无法完成可观测目标 | OPEN | 完整基线所有 case 的任务 `completed=0`；R2-002/R2-003 暴露受阻与承诺，R4 重做任务图和重规划 |
| Markdown 存在重复或过时权威声明 | CLOSED | `WS-MAINT-20260907-001` 删除重复交接、分层 README 权威入口并标记历史边界；打包协议与历史架构依据继续保留 |
| 精简 HUD 后整卡动作入口缺失 | OPEN (`WS-MAINT-20260910-001`) | 补员、预备队投入及多项选卡式支援的权威逻辑仍在，但隐藏卡槽使其不可达；下一维护项必须在决策区恢复上下文入口，不恢复重复常驻面板 |

## 10. 状态更新记录

| 日期 | 变更 | 证据/原因 | 下一工作项 |
|---|---|---|---|
| 2026-09-10 | 登记 WS-MAINT-20260910-001 决策区部队卡行动入口修复 | 用户验收发现：右侧只保留将领卡后，战地补员仍要求先选中隐藏 UnitCard，预备队投入按钮也随卡槽消失；同类依赖 selected_unit_card_id 的既有支援需要一并审计。权威命令和模拟测试仍存在，问题定位为 UI 可达性回归 | `/goal work-item WS-MAINT-20260910-001` |
| 2026-09-10 | 完成 WS-MAINT-20260909-002 战场 HUD 收敛与可靠决策闭环 | 常驻 HUD 收敛为支援、小地图、高层意图、扩大决策区、三张将领卡与暂停；路线/目标悬停预览，成功即时回执，拒绝/过期/宿主不可用/15 tick 超时弹窗和隐藏式本局历史完成。两轮 18/18、四关 smoke/矩阵、72 案例、30 场完整质量矩阵、五档真实窗口、80 实体 P95 `15.344ms`、Windows 导出和隔离启动通过；完整门 `1885.515s`，证据为 `SIMULATED` | `/goal review phase-exit R2` |
| 2026-09-09 | 完成 WS-MAINT-20260909-001 指挥响应、整卡协同与情境教程修复 | 决策动作按控制权投影并显示对象、拒绝原因与恢复；同将领附近 Agent 战斗卡共同接敌、整卡多成员自动开火，领队阵亡后剩余成员仍可行动；教程等待权威状态并新增常驻指南。完整发布门 `1930.881s`、两轮 18/18、四关 smoke/矩阵、72 案例、30 场完整质量矩阵、80 实体 P95 `12.478ms`、Windows 导出和隔离启动通过；证据为 `SIMULATED` | `/goal review phase-exit R2` |
| 2026-09-09 | 完成 WS-MAINT-20260908-001 决策区反馈与撤离链路修复 | 具名回执保持 30 tick 并锁定重复动作；撤离清除旧意图、取消 `SCOUT_AREA`、创建安全集结任务并抑制已排队/后续自动战法；完整发布门 `1000.437s`、两轮 18/18、四关矩阵、72 案例、30 场完整策略矩阵、80 实体 P95 `10.413ms`、五档真实窗口与 Windows 导出通过；证据为 `SIMULATED` | `/goal review phase-exit R2` |
| 2026-09-07 | 完成 WS-MAINT-20260907-001 Markdown 权威性与引用清理 | 删除仅由 README 引用且内容过时的 `AI_HANDOFF.md`；README 收敛当前权威入口；旧评估与 AI 设计补归档/路线边界；43 份源码 Markdown 零失效链接、零异常围栏；试玩包 smoke 与 `git diff --check` 通过 | `/goal review phase-exit R2` |
| 2026-09-07 | 完成 WS-R2-006 工程出口，等待产品负责人接受 R2 残余风险 | 最终完整门 1426.714 秒；两轮 18/18、四关 smoke/矩阵、72/72、5×3×2 完整质量矩阵、80 实体 P95 13.373 ms、五档真实窗口、Windows 导出与启动通过；修复命令回执遮挡 HUD；证据为 `SIMULATED` | `/goal review phase-exit R2`；接受后解锁 `WS-R3-001` |
| 2026-09-07 | 完成 WS-R2-005，修复灰脊策略只争夺区域、不转入总部突击的根本问题 | 18/18 tests；总部目标合法可见性 focused test；5 策略 × 3 计划 × 2 重复完整质量矩阵通过；分轴与集中突破各三胜，三类劣势策略各三败；质量 fingerprint `f5afda05a1cb0579c633d61caccf5496b950c32b46d08a0ff19f9c56540c1085`；未运行阶段出口完整发布门 | `/goal work-item WS-R2-006` |
| 2026-09-07 | 完成 WS-R2-004，建立可追溯战后转折、逐卡贡献与结果因果 | 18/18 tests；focused determinism/deep-copy/live-capture/knowledge-boundary；3×5×2 完整基线确定且 aggregate fingerprint 保持 `4d8204397a86e63d408e8c56cfd1866c2d7c1f60434c5b0e2adec293c433aa32`；三视图五档真实窗口与最窄截图通过；未运行非必需完整发布门 | `/goal work-item WS-R2-005` |
| 2026-09-07 | 完成 WS-R2-003，建立高层意图与异常驱动指挥闭环 | 17/17 tests 两轮；五类异常 focused suite；3×5×2 完整基线确定且 aggregate fingerprint `4d8204397a86e63d408e8c56cfd1866c2d7c1f60434c5b0e2adec293c433aa32`；五档真实窗口；完整发布门 811.468 秒；80 实体 P95 12.618 ms；Windows 导出与包内启动通过 | `/goal work-item WS-R2-004` |
| 2026-09-07 | 完成 WS-R2-001，冻结灰脊完整对局和因果观测基线 | 修改后 15/15 tests；3 计划 × 5 策略 × 2 完整重复确定；15/15 `defeat/collapse`、任务完成数均为 0；报告 fingerprint `1f13738901225350cca5dc340f69f09c9c0fee94706156a9d8c66764f9990353` | `/goal work-item WS-R2-002` |
| 2026-09-07 | 完成 WS-R2-002，建立合法阵营态势与补给承诺叠层 | 16/16 tests；灰脊 6×3 矩阵与 3×5×2 完整基线通过且 aggregate fingerprint 不变；五档真实窗口、鼠标/快捷键切换和整卡高亮通过 | `/goal work-item WS-R2-003` |
| 2026-09-07 | D-026 取消真人证据硬门；D-027 通过 R1 出口并重排 R2-R7 | 产品负责人明确授权；新建玩法优先路线与 WS-R2-001 契约；历史证据标签保留 | `/goal work-item WS-R2-001` |
| 2026-09-03 | 返工并完成 WS-MAINT-20260901-002；建立 `.4-dev` 即时验证版本 | 用户复测发现 `.3-dev` 仅覆盖卡牌会战；14 套测试通过；旧 RTS 实际 Canvas 在镜头 `0.20/1.20` 均为 `0.5500`；卡牌会战滚轮前后均为 `0.55`；未导出、未打包 | 用户在正确 Godot 工程执行 HV-MAINT-005，或 `/goal review phase-exit R1` |
| 2026-09-01 | 完成 WS-MAINT-20260901-002；建立 `.3-dev` 即时验证版本 | 14 套测试通过；真实窗口镜头 `0.1019965 -> 0.2019965` 时单位屏幕比例保持 `0.55`；未导出、未打包，RC2 不变 | 用户在 Godot 执行 HV-MAINT-005，或 `/goal review phase-exit R1` |
| 2026-09-01 | 完成 WS-MAINT-20260901-001，冻结 R1-FEEDBACK-RC2 | 发布门 489.325 秒；两轮 14 套测试；五档真实窗口；72 案例；80 实体 P95 6.735 ms；EXE SHA-256 `679DF06F7F9F2D2293768747AA9AD71FB996869249960179ADA8180445FC0A7A`；PCK SHA-256 `6B0584E99524ECB084AAE08C8B598A29C9CBD518A69D62FEE096C39E214ED107`；ZIP SHA-256 `730B7F496F8871D62CA887F5B955974CF540014F3B5EA9307E6F5D4070C10A08` | 执行 HV-MAINT-001 至 HV-MAINT-004，或 `/goal review phase-exit R1` |
| 2026-08-25 | 完成 WS-MAINT-20260825-001，冻结 R1-FEEDBACK-RC1 | 发布门 485.651 秒；两轮 14 套测试；72 案例；80 实体 P95 6.717 ms；五档截图；反馈完整链路；ZIP SHA-256 `C26466252AC7372C469107988B4FB3D49C0B2B90A9BC475B30B356519CBD5DC7` | `/goal review phase-exit R1` 或执行 HV-FB 真人专项 |
| 2026-08-21 | R1-001 至 R1-008 完成 `SIMULATED` 工程出口，停在阶段出口审查 | 14 套测试；四关 smoke/矩阵；72 案例；80 实体 P95 10.195 ms；五档分辨率；Windows 完整门 651.775 秒；真人证据仍为 `NOT_RUN` | `/goal review phase-exit R1` |
| 2026-08-21 | 建立集中真人验收测试方案 | `HUMAN_VALIDATION_TEST_PLAN.md` 覆盖 P6.7、目标 UI、总部/超时、护送、撤离、结算原因、可访问性和四关串联 | 等待阶段审查或真人批次 |
| 2026-08-21 | 产品负责人授权工程模拟条件放行，阶段推进到 R1 | D-025；P6.7 真人证据保留为发布债务，所有替代验证必须标记 `SIMULATED` | WS-R1-001 |
| 2026-08-21 | 冻结 R1 必需决策并延后无关决策 | D-019、D-023 Accepted；D-018、D-020 至 D-022、D-024 Deferred 到对应阶段 | WS-R1-001 |
| 2026-08-20 | 复查 P6.7 外部证据与产品决定，状态保持 `WAITING_HUMAN_EVIDENCE` | 用户数据目录仍为 0 份 assessment、0 份 cohort 汇总；`123` 只有一份缺上下文的断桥原始记录；D-018 至 D-024 仍全为 `PROPOSED` | WS-R0-001 |
| 2026-08-20 | 晋升 `P6.7-RC4` 为唯一新场次候选包；RC3 与所有 `Latest` 包停止用于新场次 | 完整发布门 459.397 秒通过；RC4 ZIP SHA-256 `775CE0A71A634938836ED30E75F4D200C2021F3CE206BA398AF5A08435C42D73`；11 项清单哈希与包内 console EXE 隔离启动通过 | WS-R0-001 |
| 2026-08-20 | 建立 P6.7 现场登记、证据账本和 AI 接手清单 | `P6_7_FIELD_EXECUTION_CHECKLIST.md` 固定 9 人、24 场最低覆盖及未归属原始记录处理规则 | WS-R0-001 |
| 2026-08-20 | 建立仓库级 `/goal` 协议；推荐命令为 `/goal phase R0` | `AGENTS.md` 与 `AI_GOAL_COMMANDS.md` 已定义解析、范围和门禁规则 | WS-R0-001 |
| 2026-08-20 | 建立 AI 主工作流和状态队列；当前阶段保持 R0 | 全仓审计与扩充文档已完成，P6.7 人工证据仍缺失 | WS-R0-001 |

## 11. 下一次 AI 接手检查单

1. 读取根目录 `AGENTS.md`、本文件控制块、D-026、D-027 与 `GAMEPLAY_REWORK_ROADMAP.md`；
2. R2 工程出口已完成，阶段队列没有 `READY` 项；当前唯一可领取的是维护项 `WS-MAINT-20260910-001`，产品负责人接受产品风险前 `WS-R3-001` 仍保持 `BLOCKED`；
3. 若产品负责人接受 R2 出口，先建立并冻结 `docs/work_items/WS-R3-001.md`，不得同时实现 R3 的其他兄弟任务；
4. 所有自主试玩、规则代理和自动化证据继续标记为 `SIMULATED`，但真人 `NOT_RUN` 不再阻塞；
5. 若出现真人记录，可按构建哈希和原始记录审计为 `HUMAN` 可选研究，不改变工程完成状态；
6. R2-001 至 R2-006 已建立并验证完整对局观测、只读态势叠层、高层意图/异常队列、因果复盘、差异策略空间和发布门；后续 R3 必须优先解决卡牌战术动词与同质化，不能把固定脚本策略外推为真人主观乐趣。
7. Markdown 清理 `WS-MAINT-20260907-001` 已完成；`AI_HANDOFF.md` 已删除，历史/打包文档已明确保留边界，后续不得重新把归档文档声明为实时状态源。
8. 决策区维护 `WS-MAINT-20260908-001` 已完成；后续若扩展异常动作，必须复用具名回执与统一命令管线，并保持撤离高于该将领的待执行自动指令。
9. 指挥协同维护 `WS-MAINT-20260909-001` 已完成；将领撤离是安全集结而非永久退场，同将领整卡协同只消费合法阵营知识并服从玩家接管、侦察、撤离和撤退优先级；后续修改必须保留这些边界。
10. HUD 收敛维护 `WS-MAINT-20260909-002` 已完成；卡牌会战常驻界面只保留支援、小地图、高层意图、决策区、三张将领卡和暂停入口。后续扩展决策必须复用即时回执、明确失败弹窗、权威确认、悬停预览和本局历史链路。
11. 当前唯一可领取项是 `WS-MAINT-20260910-001`：在不恢复下属卡常驻槽的前提下，把战地补员、预备队投入和其他因隐藏选卡而不可达的既有整卡支援接入决策区；必须区分战中 Supply 补员与战前/战后 replacement points 补员。
