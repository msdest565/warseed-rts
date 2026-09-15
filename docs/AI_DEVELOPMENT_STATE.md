# WARSEED AI 开发状态与任务队列

> 状态版本：77
> 更新时间：2026-09-16
> 更新规则：每个完成、阻塞或重新规划的工作项都必须更新本文件
> 执行规则：[`AI_DEVELOPMENT_WORKFLOW.md`](AI_DEVELOPMENT_WORKFLOW.md)
> 目标命令：[`AI_GOAL_COMMANDS.md`](AI_GOAL_COMMANDS.md)

## 1. 机器可读控制块

```yaml
workflow_version: 1.2
state_version: 77
updated_at: 2026-09-16
project: WARSEED
current_phase: R5
current_gate: R5_ENEMY_OPERATION_IMPLEMENTATION
phase_status: READY
release_candidate: R1-FEEDBACK-RC2
release_candidate_status: ENGINEERING_BASELINE_ARCHIVED
release_candidate_package: build/playtest-kits/WARSEED-R1-Feedback-RC2-20260901.zip
release_candidate_sha256: 730B7F496F8871D62CA887F5B955974CF540014F3B5EA9307E6F5D4070C10A08
active_maintenance_work_item: none
working_build_id: 0.1.0-playable.20260914
latest_maintenance_work_item: WS-MAINT-20260916-001
latest_maintenance_status: DONE
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
next_work_item: WS-R5-002
next_work_item_status: READY
next_work_item_blocker_kind: none
next_work_item_blocker: none
machine_ready_work_item: WS-R5-002
active_work_item: none
queued_maintenance_work_item: none
queued_maintenance_status: none
expansion_implementation_allowed: true
agent_playbook: docs/AI_AGENT_PLAYBOOK.md
delegation_template: docs/AI_DELEGATION_TEMPLATE.md
low_cost_provider_guide: docs/AI_LOW_COST_PROVIDER.md
preferred_external_text_model: gpt-5.6-luna
external_model_qualification: SINGLE_REVIEW_SAMPLE_ONLY
primary_model_budget_usd: 400
primary_model_billing_source: USER_CONFIRMED_INPUT_10_OUTPUT_50_USD_PER_MILLION
primary_model_budget_enforcement: LOCAL_TOKEN_RECORD_CONSERVATIVE_ESTIMATE
primary_model_implementation_stop_usd: 370
performance_gate_policy: DEFERRED_BY_D028
external_luna_cost_in_budget: false
phase_exit_requires_product_owner: true
r1_engineering_status: COMPLETE
r1_exit_status: ACCEPTED
r1_exit_authorized_at: 2026-09-07
r1_exit_authority: product_owner_user_message
r1_simulated_full_gate: PASS
r1_simulated_full_gate_duration_seconds: 651.775
r1_simulated_verified_at: 2026-08-21
r2_engineering_status: COMPLETE_SIMULATED
r2_exit_status: ACCEPTED
r2_exit_authorized_at: 2026-09-10
r2_exit_authority: product_owner_goal_maintenance_then_R3_R4_R5
r2_simulated_full_gate: PASS
r2_simulated_full_gate_duration_seconds: 1426.714
r2_simulated_verified_at: 2026-09-07
r3_engineering_status: COMPLETE_SIMULATED
r3_exit_status: ACCEPTED
r3_exit_authorized_at: 2026-09-13
r3_exit_authority: product_owner_goal_maintenance_then_R3_R4_R5
r3_simulated_full_gate: PASS
r3_simulated_full_gate_duration_seconds: 686.300
r3_simulated_verified_at: 2026-09-13
r4_engineering_status: COMPLETE_SIMULATED
r4_exit_status: ACCEPTED
r4_exit_authority: USER_CONTINUATION_AND_D029
r4_simulated_full_gate_duration_seconds: 819.106
r4_simulated_verified_at: 2026-09-16

goal_protocol_version: 1.1
gameplay_rework_roadmap: docs/GAMEPLAY_REWORK_ROADMAP.md
recommended_goal_command: "/goal continue"
full_gate_command: >-
  powershell -ExecutionPolicy Bypass -File
  .\tools\verify_grey_ridge_release.ps1
  -GodotConsolePath <godot-console>
```

解释：产品负责人于 2026-09-07 接受 R1 工程出口并通过 D-026 取消真人证据硬门，同时通过 D-027 将 R2-R7 重排为玩法优先路线。2026-09-10 用户明确要求战术规划维护自检后完成 R3、R4、R5；维护现已通过完整发布门，以该授权接受已审查的 R2 工程出口并进入 R3。R3-001/002 已逐项完成，D-021 已按用户明确授权接受；控制交接与军团总览维护 `WS-MAINT-20260910-003` 已通过 1487.349 秒完整门并 DONE；R3-003 已按 D-021 实施并通过1745.289秒完整门；D-022 已于2026-09-11由用户明确接受；左侧冷却显示维护已完成，R3-004 已通过 1575.107 秒完整门并 DONE，R3-005已通过最终686.300秒完整门；R3-006出口审查完成，R4-001/002/003已完成，唯一下一项R4-004。001 临时文档已按用户要求删除，契约和验收归档在第 12 节；002 完成记录见第 13 节。自动化仍只能标记为 `SIMULATED`，不得宣称已经证明真人理解或主观乐趣。D-021/D-022 均已接受；完整 R3/R4/R5 goal 尚未完成。

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
| 存档 | 军团 v4（v1/v2/v3 保守迁移、备份及原子写入已验证）、教程 v2、试玩记录 v3；尚无战役行动图状态 |
| 自动化 | 18 套 headless 测试、四关 smoke、逐关矩阵、72 案例早期窗口审计、灰脊 15 案例完整对局基线、五档分辨率矩阵 |
| 反馈 | 战后双语问卷、本地 pending/sent、HTTP 临时收集服务、HTML/JSON/CSV 汇总；真人可用性未运行 |
| 性能 | 2026-09-13 R3最终门：80实体模拟P95 6.037ms；正式80实渲帧13.743ms、输入呈现107.407ms；120仅压力测量 |
| 可选产品研究 | P6.7 与集中真人用例尚未执行；D-026 后不参与工程、阶段或发布门 |

## 3. 当前阶段目标

2026-09-14最新用户指示覆盖下述继续授权：`WS-MAINT-20260914-001` 的手控战斗可靠性、单位批量可见性、已知总部进攻和补给数值显示已完成，可直接运行的Windows最终包已交付，开发现已暂停。R4-004现有实现保留并随包回归，但工作项保持用户暂停的BLOCKED；不领取R4-005或R5，不宣称R4/R5完整目标完成。当前维护DONE，最终证据见第20节。

2026-09-13 状态复核：共享增援冷却维护及R3-001至R3-006已完成。最终686.300秒发布门、双语五档、四关存档链和正式60/80实渲通过；606文件哈希复核变化0。R3工程出口已按用户R3/R4/R5继续授权接受，R4-001公平态势黑板与R4-002行动方案生成也已完成，R4-003方案比较与玩家确认也已完成，唯一下一项WS-R4-004（将领阶段任务图）。R4/R5尚未实现完成，完整目标继续。下文带日期的中途返工和旧阻塞仅作历史，当前结论以本段、控制块及第19节为准。

2026-09-10 活动目标：`WS-MAINT-20260910-002` 已完成战术暂停中的规划、右侧决策/底部军团与选项说明并通过完整自检；现在按独立工作项顺序推进 R3、R4、R5。本目标覆盖上述完整范围，不以 HUD 完成替代阶段完成。维护契约见 `work_items/WS-MAINT-20260910-002.md`，完整门 `1884.207s` PASS (`SIMULATED`)。R3-001/002 现已完成，R3-002 完整门 `1930.230s` PASS；旧记录中的“唯一 R2 审查入口”均为当时历史状态。D-021 已由用户接受，维护 003 已完整验证并 DONE，R3-003 已完成；D-022已接受，R3-004依赖满足，先处理新增的左侧冷却显示。

R1 的类型化目标与结果系统已经完成并由产品负责人接受。R2 已把《灰脊矿区》建立为可重复比较的玩法基准：完整对局观测、战线/威胁提示、异常驱动指挥、因果复盘和策略质量审计均通过工程出口，现已按用户继续授权进入 R3。固定路线过拟合、玩家发现性和主观乐趣未知仍是保留风险，不能据阶段推进声称已经验证。

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
| D-021 | 部队卡编制 | 稳定 entry ID 的混成编制与安全 v4 迁移 | ACCEPTED | 2026-09-10 用户要求按文档实施 |
| D-022 | 战斗复杂度 | 先传感器/压制/专业火力弹药/受限伤害标签 | ACCEPTED | 2026-09-11 用户明确通过方案 |
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

## 7. R2 已完成队列

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
| Windows 80 实体 | PASS (`SIMULATED`) | 2026-09-10 整卡入口完整门模拟 P95 10.029 ms、表现层 P95 1.259 ms；当前正式性能门 |
| Windows 120 实体 | MEASURED (`SIMULATED`) | 2026-09-10 整卡入口完整门模拟 P95 21.690 ms、表现层 P95 2.152 ms；扩展测量，不改变当前 60-80 范围 |
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
| 决策区整卡行动入口 | PASS (`SIMULATED`) | 稳定卡 ID 补员/预备队及五类卡目标支援、费用/人口/冷却/失败恢复、两步部署、意图继承、快照确认、五档实渲与完整发布门 `1486.851s` 通过；完整质量指纹保持不变 |
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
| 精简 HUD 后整卡动作入口缺失 | CLOSED (`WS-MAINT-20260910-001`) | 决策区已恢复任意缺员补员、预备队投入、筑垒、工程路线、快速机动与前线保障；五档真实窗口、权威命令确认和完整发布门通过，真人发现性仍为可选研究 |

## 10. 状态更新记录

| 日期 | 变更 | 证据/原因 | 下一工作项 |
|---|---|---|---|
| 2026-09-10 | 完成 WS-MAINT-20260910-001，删除临时文档并恢复正常工作流 | 决策区补员、预备队及既有卡支援闭环；两轮 18/18、四关、72 案例、30 场完整质量矩阵、五档实渲、80 实体 P95 `10.029ms`、Windows 导出/隔离启动通过；完整门 `1486.851s`，证据 `SIMULATED`。契约并入本文第 12 节 | `/goal review phase-exit R2` |
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
   成本分工和最短阅读路径见 `AI_AGENT_PLAYBOOK.md`；任务交接用 `AI_DELEGATION_TEMPLATE.md`。同一上下文内未变化的规范不重复读取，历史按需追溯。
2. R3出口、共享冷却及本次手控维护已完成；D-021/D-022均已接受，不重复确认。R4-001/002/003已完成，R4-004保留实现并因用户要求暂停而BLOCKED；
3. 先读第22节最新恢复指令：用户已恢复R4/R5，旧暂停记录仅作历史；先验收R4-004再按依赖继续。主模型200美元预算的计费来源尚待明确，不将未知费用写成预算内保证；
4. 所有自主试玩、规则代理和自动化证据继续标记为 `SIMULATED`，但真人 `NOT_RUN` 不再阻塞；
5. 若出现真人记录，可按构建哈希和原始记录审计为 `HUMAN` 可选研究，不改变工程完成状态；
6. R2-001 至 R2-006 已建立并验证完整对局观测、只读态势叠层、高层意图/异常队列、因果复盘、差异策略空间和发布门；R3已完成卡牌战术动词；R4继续方案与阶段任务图，不能把固定脚本策略外推为真人主观乐趣。
7. Markdown 清理 `WS-MAINT-20260907-001` 已完成；`AI_HANDOFF.md` 已删除，历史/打包文档已明确保留边界，后续不得重新把归档文档声明为实时状态源。
8. 决策区维护 `WS-MAINT-20260908-001` 已完成；后续若扩展异常动作，必须复用具名回执与统一命令管线，并保持撤离高于该将领的待执行自动指令。
9. 指挥协同维护 `WS-MAINT-20260909-001` 已完成；将领撤离是安全集结而非永久退场，同将领整卡协同只消费合法阵营知识并服从玩家接管、侦察、撤离和撤退优先级；后续修改必须保留这些边界。
10. HUD 已由 `WS-MAINT-20260910-002` 按用户新要求调整为右侧决策、底部将领分组与每张部队卡、左侧支援/小地图及空格战术暂停。旧“三张将领卡、不显示部队卡”的限制已被替代；后续仍须复用即时回执、明确失败、权威确认、悬停预览和本局历史链路。
11. `WS-MAINT-20260910-001` 已完成：整卡补员、预备队投入和五类卡目标支援均可在决策区操作；继续保持固定卡 ID、权威确认、具名拒绝和战中 Supply / 跨局补员点的区别。临时任务文档已删除，完整契约与证据保留在本文第 12 节，不重新创建临时交接入口。

## 12. 整卡入口维护契约与验收归档

按用户要求，临时工作项文档已阅读，契约归入本正常状态入口，原文件删除。

### WS-MAINT-20260910-001：决策区补齐部队卡行动入口

```yaml
work_item_id: WS-MAINT-20260910-001
title: Restore hidden unit-card actions through contextual decisions
phase: maintenance
type: ui_command_vertical_slice
status: DONE
owner: ai
blocker: none
reported_at: 2026-09-10
external_research: optional
objective: >-
  在不恢复常驻下属部队卡槽的前提下，把战地补员、预备队投入以及其他因卡槽隐藏而失去入口的既有整卡动作
  转化为决策区内可解释、可预览、可执行的上下文决策，并继续经过现有权威命令与确认链路。
why_now: >-
  WS-MAINT-20260909-002 将右侧收敛为三张将领卡，但 SupportPanel 和 ArmyBoard 的若干动作仍依赖玩家先选中
  已隐藏的 UnitCard。模拟能力仍存在，玩家却无法发现或触发，造成补员与预备队投入的功能回归。
depends_on:
  - WS-MAINT-20260909-002
source_documents:
  - docs/AI_DEVELOPMENT_STATE.md
  - docs/AI_DEVELOPMENT_WORKFLOW.md
  - docs/GAMEPLAY_REWORK_ROADMAP.md
  - docs/GAME_DESIGN_DOCUMENT.md
  - docs/work_items/WS-MAINT-20260909-002.md
current_evidence:
  - ArmyBoard commander_only 分支在创建下属 UnitCard 控件前返回，预备队部署按钮和卡牌选择入口均不再生成
  - SupportPanel 从 InputController.selected_unit_card_id 取得目标；隐藏卡槽后，战地补员、筑垒、快速机动、前线保障和工程路线缺少稳定的选卡入口
  - 战地补员的 SupportOrderCommand.FIELD_REINFORCEMENT、预备队的 DeployUnitCardCommand 及其权威校验和模拟行为仍存在并有自动测试
  - 战前与战后 ArmyRosterStore 补员仍可使用；本问题主要发生在会战 HUD，不是存档数据丢失
in_scope:
  - 从玩家合法 WorldSnapshot 投影需要玩家选择的受损已部署卡、可投入预备卡和既有卡目标支援动作
  - 在决策区显示部队卡名称、所属将领、当前/编制兵力、费用、补给、人口、冷却、目标和不可执行原因
  - 战地补员直接对决策绑定的稳定 unit_card_id 提交既有 FIELD_REINFORCEMENT 命令，不依赖隐藏选择
  - 预备队投入从决策行进入明确的地图投入点选择，沿用现有安全锚点解析、人口/补给校验和部署后加入将领意图的行为
  - 审计并恢复因隐藏 UnitCard 选择而不可达的既有筑垒、工程路线、快速机动和前线保障入口；不得新增支援机制
  - 复用 WS-MAINT-20260909-002 的即时回执、失败弹窗、15 tick 权威确认、路线/目标悬停预览和本局历史
  - 中英文文本、focused tests、五档真实窗口和完整发布门
out_of_scope:
  - 不恢复右侧完整部队卡列表、路线/姿态/战法编辑器或旧 HUD 信息密度
  - 不新增兵种、卡牌、支援类型、补员资源、战斗数值或跨局经济规则
  - 不改变战前/战后 ArmyRosterStore 补员成本和存档 schema
  - 不提前实现 R3 typed effect grammar、R4 通用 COA 或将领任务图重做
invariants:
  - SimulationWorld 仍以 10 Hz 持有权威状态；UI 只投影快照并提交命令
  - 玩家与 Agent 继续走同一命令、校验、事件和快照确认管线
  - 正式操作粒度保持整张部队卡；不通过单体实体补员或部署
  - 决策只消费玩家阵营合法知识，不显示隐藏敌方或未来状态
behavior_contract:
  discovery:
    - 只要存在受损且已部署的友方卡，决策区必须列出具名补员机会或具名不可执行原因
    - 只要存在可用预备卡，决策区必须列出投入机会，并说明所属将领、兵力、费用和当前目标
    - 没有合格对象时不生成伪决策；支援冷却、补给不足、人口已满和状态冲突必须可见而非静默禁用
  execution:
    - 补员动作绑定稳定 unit_card_id，提交后同帧显示接受或拒绝，并在权威快照中确认真实成员增加
    - 预备队动作先进入投入点选择；地图明确高亮合法总部部署区，取消、非法位置和最终提交都有直接反馈
    - 新部署卡沿用其将领当前高层意图和 Agent 控制，不在 UI 中直接改写任务或阵营状态
  parity:
    - 隐藏部队卡前可执行的既有整卡支援动作必须仍有明确入口，或在工作项结果中逐项说明为何产品决定移除
    - 决策历史按一次玩家提交只记录一条，保存对象、动作、结果、原因和 tick
persistence:
  format_change: false
  migration: none
acceptance_criteria:
  - 隐藏全部下属部队卡时，玩家仍能从决策区为指定受损整卡完成战地补员
  - 隐藏全部下属部队卡时，玩家仍能从决策区选择预备卡、选择合法投入点并完成部署
  - 补给不足、人口已满、冷却、满编、错误部署状态和非法位置均显示具名原因与恢复建议
  - 补员后真实成员、人口、补给和冷却与既有权威规则一致；部署后整卡加入负责将领当前意图
  - 筑垒、工程路线、快速机动和前线保障不再因 selected_unit_card_id 无入口而永久不可用
  - 右侧仍只显示三张将领卡，决策区和地图在 480x800 至 2560x1600 无遮挡或横向滚动
  - focused tests、18 套回归、四关 smoke/矩阵、五档真实窗口、完整发布门和 git diff --check 通过
verification:
  focused:
    - CommandDesk contextual card decisions and stable card binding
    - SupportPanel selection-independent command submission or delegated decision execution
    - InputController reserve deployment targeting entered from a decision row
    - SimulationWorld field reinforcement and reserve deployment authoritative confirmation
    - GameIntegration commander-only HUD preserves unit-card action parity
  full_gate: true
  evidence_level: SIMULATED
expected_files:
  - src/ui/command_desk.gd
  - src/ui/support_panel.gd
  - src/ui/army_board.gd
  - src/input/input_controller.gd
  - src/presentation/command_situation_projector.gd
  - src/presentation/command_situation_snapshot.gd
  - src/app/game_root.gd
  - locale/zh_CN.po
  - locale/en.po
  - tests/unit/test_command_situation.gd
  - tests/integration/test_game_integration.gd
  - tests/tools/accessibility_resolution_matrix.gd
  - docs/AI_DEVELOPMENT_STATE.md
risks:
  - 把所有支援都变成常驻决策会再次造成信息过载；只在存在合格对象或明确阻塞原因时生成上下文行，并保持去重
  - UI 若直接调用世界方法会绕过统一管线；必须复用 SupportOrderCommand、DeployUnitCardCommand 和 SimulationHost.submit_command
  - 预备队部署是两步交互，不能把进入目标选择误记为权威成功；历史成功必须等最终命令接受和快照确认
rollback: >-
  移除新增的上下文卡牌决策投影和入口即可；既有 SupportPanel、ArmyBoard、权威命令、模拟规则与存档格式保持不变。
```

### 调查结论

- 这是 UI 可达性回归，不是补员或部署模拟逻辑缺失。权威命令、校验、真实实体生成、补给/人口扣除和现有测试仍在。
- `ArmyBoard._create_commander_column()` 在 `commander_only` 模式添加将领状态后立即返回，因此不会生成下属卡选择、部署和控制按钮。
- `SupportPanel.update_snapshot()` 仍通过 `input_controller.selected_unit_card_id` 解析战地补员及多项卡目标支援；当前精简 HUD 没有替代选卡方式。
- 战前和战后持久军团补员由 `PrebattlePlanner`、`BattleDebrief` 和 `ArmyRosterStore` 提供，仍然可达；不要把跨局 replacement points 补员与战中 Supply 补员混为一套资源。
- 推荐实现顺序：先冻结“隐藏卡槽下动作可达性”失败测试，再建立 typed 上下文决策投影，接入既有命令和响应观察，最后补五档实渲与完整发布门。


执行记录：READY → DISCOVERY。只读预检工作区干净；普通沙箱启动 Godot 因用户日志目录不可写崩溃，正在以许可的完整用户目录权限执行基线。

契约冻结：基线 18/18 PASS (SIMULATED)。新建 typed CardActionSnapshot/CardActionProjector，只消费合法阵营快照及静态 BattleDefinition。补员覆盖任意缺员；预备队两步选择并持续显示总部部署区；既有卡支援从决策行绑定 ID 执行。补充可用预备兵力、机动剩余时间和本阵营已开工程路线的值拷贝快照以对齐现有规则。支持逐项费用、人口、冷却、阻塞恢复和中英文。提交复用原命令，成功等待真实快照，15 tick 为响应确认窗，部署动画另计既有 deployment_ticks。无存档格式/数值/阶段变化。

状态：DISCOVERY → CONTRACT → IMPLEMENTING。

实现/返工记录：IMPLEMENTING → VERIFYING → REWORK → VERIFYING。修正 focused 严格类型与零冷却工程确认；100 tick 部署按现有动画等待，不放宽 15 tick 初始响应窗。focused 全部整卡动作及固定卡 ID、命令拒绝、人口/Supply/冷却、意图继承已通过。五档真实窗口首次完整 PASS，最终输入绑定与简短支援标题修订后重跑五档并执行完整发布门。全部为 SIMULATED。

### 实现与验证记录（WS-MAINT-20260910-001）

- `CardActionSnapshot` / `CardActionProjector` 从合法阵营快照和静态会战 Resource 建立具名整卡决策；缺一名成员即出现战地补员，可用预备兵力按实际 available strength 展示。
- 决策行显示卡牌/将领、兵力、Supply 费用与余额、人口空间、冷却、当前目标及阻塞恢复；支援面板进入相应筛选列表，右侧继续只有三张将领卡。
- 补员、筑垒、工程路线、快速机动与前线保障均由绑定的稳定卡牌 ID 提交现有命令。前线保障按组织损失或存活成员受伤投影，不能混同于补员。
- 预备队两步交互固定卡牌及所属将领，选择期间持续预览总部部署范围；右键/C 取消，非法落点给出可恢复失败，合法落点沿用原安全锚点解析。15 tick 内确认开始部署，随后等待原卡牌 deployment_ticks；真实成员到场后更新同一条历史为完成。
- 新增 available_strength、机动剩余时间和本阵营开路记录的值拷贝快照；其他阵营看不到私有开路记录。存档格式、经济规则、战斗数值和阶段未改变。
- 新增整卡按钮跨 tick 保持实例的鼠标测试；同一候选的内容更新不会销毁尚未松开鼠标的按钮。历史确认复用原记录并处理 64 条上限后的索引移动。
- focused 覆盖全部五种支援、预备队、任意缺员、固定 ID、另一张卡被选中、取消、非法点恢复、满编拒绝、补给/人口/冷却、Agent 与当前意图继承、快照值拷贝和知识边界；最终 `CARD_ACTION_FOCUSED failures=0`。
- 最终 UI 复测曾在 2560x1600 的既有战后 Cards 悬停断言失败，整卡动作当次通过；测试现显式刷新 Input 事件缓冲，保留全部鼠标和键盘断言后重跑。完整发布门的运行时代码没有因此变化。
- 双语检查：新增 CARD 文本完整且没有新增重复 key；英文战后复盘已有 31 个重复 msgid 与 HEAD 相同，未在本项扩大清理。
- 当前证据路径：`artifacts/maint-card-focused.log`、`artifacts/maint-card-ui-final3.log`、`artifacts/accessibility_resolution_matrix.json`、`artifacts/accessibility/<resolution>/card_reinforcement.png`、`reserve_targeting.png`、`card_decisions_confirmed.png`、`artifacts/maint-20260910-release.log`。

最终实渲证据：五档矩阵 `resolutions=5`、退出码 0，所有鼠标/键盘断言保留；最窄补员界面和桌面投入区截图人工视觉抽查通过。实渲观察仍标记 SIMULATED，不作为真人研究结果。

审查：VERIFYING → REVIEWING。完整发布门 `1486.851s` PASS；两轮 18/18、四关 smoke/矩阵、72 案例、30 场完整质量矩阵、反馈链路、Windows 导出/隔离启动及试玩包 smoke 全通过。发布日志无 SCRIPT ERROR、Parse Error 或 TEST FAILED。

最终交接：REVIEWING → DONE。临时任务文件已按用户明确要求删除；开发状态恢复为没有活动维护项、没有 READY 项，唯一下一入口为 `/goal review phase-exit R2`。R2 产品验收仍待负责人决定，未解锁 R3。

- 完整发布门：`1486.851s` PASS，Windows EXE `101030400` bytes / SHA-256 `679DF06F7F9F2D2293768747AA9AD71FB996869249960179ADA8180445FC0A7A`；PCK `6127528` bytes / SHA-256 `514CE2FD1CABFECAB5B32A3CFE7E11A88F10C7AEF40293A4FF43009DAD7AA7DD`。
- 80 实体：模拟 P95 `10.029ms`、表现 P95 `1.259ms`，正式门 PASS。120 实体：模拟 P95 `21.690ms`、表现 P95 `2.152ms`，仅作扩展压力测量。
- 15 案例 × 2 完整重复确定，质量 `PASS`；fingerprint 保持 `a994185d975a06e046fe608567e9adb685b6a9525a83fdc85b858477d8a51255`。
- 验证摘要：`artifacts/maint-20260910-summary.json`。上述自动化与视觉抽查均为 `SIMULATED`；真人可发现性和操作体验 `OPTIONAL_NOT_RUN (HUMAN)`，不阻塞完成。原英文复盘重复翻译 key 保留为既有低风险项。
- 实际 diff 已审查、`git diff --check` 通过；未提交、未推送、未创建分支或 PR。当前导出是工程工作版本，不创建新的正式候选包。

## 13. WS-MAINT-20260910-002 完成记录

状态 `DONE`；契约见 `work_items/WS-MAINT-20260910-002.md`。右侧扩大决策区，底部按将领分组显示每张卡现员/编制及将领汇总、风格和绿/黄/红任务文本；最终目标与途经区分离。说明等待 0.5 秒后显示 0.5 秒进度，再展示文本。空格只冻结战场推进，规划、菜单和统一命令排队可用，恢复不补跑。

- 最终 focused 与五档真实窗口交互 PASS；底部原生姿态菜单与自定义说明避让，旧补员/预备两步投入保持可达。
- 完整门 `1884.207s` PASS：两轮 18/18、Legacy/四关 smoke/矩阵、72 案例、30 场完整对局、反馈与工具、导出和包内启动通过。完整策略质量与确定性 PASS，指纹仍为 `a994185d975a06e046fe608567e9adb685b6a9525a83fdc85b858477d8a51255`。
- 80 实体模拟/表现 P95 `15.462/1.812 ms`，正式门通过；120 实体 `19.315/2.391 ms`，仅压力测量。
- EXE SHA-256 `679DF06F7F9F2D2293768747AA9AD71FB996869249960179ADA8180445FC0A7A`；PCK `6147024` bytes / `B686ADC446726320AFEBA71B7C9241D93D36BBB69D56FDB07B1611BF58EAA3D4`。
- 证据：`artifacts/maint-002-summary.json`、`artifacts/maint-002-release-final.log`、`artifacts/maint-002-focused-final2.log`、`artifacts/maint-002-ui-final2.log`、`artifacts/maint-002-evidence/`。第一次中止的发布门不计 PASS。
- 无存档格式变化；合法知识、值拷贝、统一命令和 10 Hz 边界保持。diff 审查与 `git diff --check` 通过，无提交/推送/分支/PR。全部工程与视觉证据为 `SIMULATED`；真人理解与主观操作体验 `OPTIONAL_NOT_RUN (HUMAN)`。旧英文复盘重复 key 保留。

## 14. R3 已完成队列

R2 出口审查已复核，用户“维护自检后完成 R3、R4、R5”的明确指令作为继续授权，未重复索取阶段顺序确认。产品决定方案见 `R3_ENTRY_REVIEW.md`；技术准备见 `R3_TACTICAL_GRAMMAR.md`。D-021 已于 2026-09-10 按用户要求接受，D-022 已于 2026-09-11 明确接受。

| ID | 状态 | 工作项 | 依赖 |
|---|---|---|---|
| WS-R3-001 | DONE (`SIMULATED`) | 类型化战法语法与加载验证 | R2 出口、维护 002 自检均满足 |
| WS-R3-002 | DONE (`SIMULATED`) | 首条效果注册器纵向切片 | R3-001 已满足 |
| WS-R3-003 | DONE (`SIMULATED`) | composition 与安全存档兼容 | R3-002、D-021、维护 003 均满足 |
| WS-R3-004 | DONE (`SIMULATED`) | 首批差异卡 | 1575.107 秒完整门、五档、生命周期、最终 60/80 实窗通过 |
| WS-R3-005 | DONE (`SIMULATED`) | 灰脊内容迁移 | 686.300秒完整门、606文件哈希、双语五档、四关联动、正式60/80实渲全部通过 |
| WS-R3-006 | DONE (`SIMULATED`) | R3 出口 | 606文件一致，契约、最终完整门和风险审查通过 |

R3-001 已完成七类 typed Resource 与加载验证、无效内容拒绝和旧十二战法兼容。证据：`artifacts/r3-001-import.log`、`artifacts/r3-001-focused-final.log`、`artifacts/r3-001-tests.log`（18/18 PASS）。无运行行为或存档变化，本项按数据矩阵不额外重跑完整门。首次测试 fixture 外部 Resource 共享问题已用完整深复制修复，缓存污染断言保留。`git diff --check` 通过；证据均为 `SIMULATED`。

R3-002：VERIFYING → REVIEWING → DONE。交替掩护正式数据接入类型注册器，世界应用合法阵营快照计算出的任务参数；任务效果元数据值拷贝，编成页显示反制说明。三处行为名称分支已移除，其他十一战法保持兼容，无存档格式变化。

- 黄金 61 tick 轨迹前后 SHA-256 均为 `c4dd3d05dce912c94d39b9ad5a27cc44ddb95a028e7b5f66647350e2920fecda`，永久回归覆盖接管、归还、重下令；专项另覆盖改 ID/时序、知识污染、非法定义及快照不变。
- 完整门 `1930.230s` PASS，进程退出 0：两轮 18/18、Legacy/四关 smoke 与矩阵、72 案例、15×2 完整对局、性能、反馈与工具、Windows 导出、包内启动及试玩包校验全部通过。策略质量与确定性 PASS，汇总指纹仍为 `a994185d975a06e046fe608567e9adb685b6a9525a83fdc85b858477d8a51255`。
- 80 实体模拟/表现 P95 `13.582/1.726 ms`，正式门 PASS；120 实体 `22.077/2.626 ms`，仅压力测量。最终连续五档真实窗口交互 PASS；超高/窄窗定位返工保留原鼠标和键盘断言。
- EXE `101030400` bytes / SHA-256 `679DF06F7F9F2D2293768747AA9AD71FB996869249960179ADA8180445FC0A7A`；PCK `6167268` bytes / `FF7966887AEFC3D872256F10A4AF7DFE435E8331EA3603827D7C2B93E888E472`。这是工作版本导出，没有创建新的正式候选。
- 证据：`artifacts/r3-002-summary.json`、`artifacts/r3-002-release.log`、`artifacts/r3-002-focused.log`、`artifacts/r3-002-tests.log`、`artifacts/r3-002-ui-final2.log`、`artifacts/r3-002-evidence/`。321 个受验源码文件与启动完整门时哈希一致；完整矩阵和 72 案例 JSON 已独立归档。
- 实际 diff 与文档链接已审查，`git diff --check` 通过；保留既有无关修改，未提交/推送/创建分支或 PR。证据均为 `SIMULATED`；真人文字理解、发现性和主观体验为 `OPTIONAL_NOT_RUN (HUMAN)`，不构成阻塞。旧英文复盘重复 key 继续保留。

状态版本 42 的历史阻塞记录（现已由用户接受 D-021 解除）：当时下一项 WS-R3-003 因 D-021 尚为 Deferred 而 BLOCKED；D-022 同样待用户答复，但它是 R3-004 的门。已发送的审查方案见 `R3_ENTRY_REVIEW.md`，没有把阶段继续授权代替具体产品决定。依照 `AGENTS.md` 第 5 节“缺少产品决策、任务依赖或外部授权时保持 BLOCKED，不得用推测补齐”，不开始混成/存档实现。收到对应决定后，更新 `DECISIONS.md` 并将 R3-003 按状态机领取。R4/R5 保持原路线依赖，完整 goal 未标记完成。

## 15. 控制交接与完整军团总览维护

`WS-MAINT-20260910-003` 已 DONE，契约及验收见 `work_items/WS-MAINT-20260910-003.md`。用户明确要求新的玩家将领决策交还相应手控卡，并提供 R 快捷键、主动按钮和左上提醒；旧任务不存在或已取消时也可交还，后台 Agent 不抢回控制。底部按将领汇总并直接展示当前最多十二张卡，保留逐卡兵力和绿黄红工作文字。

已完成控制链实现与拒绝/隔离/同 tick/快照测试；最终 `maint-003-tests-final2.log` 18/18 PASS、`maint-003-ui-final6.log` 五档真实窗口 PASS，包含每档十二卡可见和逐卡点击，桌面与最窄截图已视觉抽查。已修复小地图旧 232px 最小宽度与 180px 左栏冲突，定向隔离及最终回归均通过；超大窗口真实输入先同步物理鼠标，原地图面积、遮挡、点击、历史与黄金断言均保留。323 个受验文件已记录哈希，完整发布门已 PASS，日志 `artifacts/maint-003-release.log`，最终证据如下。

本维护无存档格式变化，证据仅为 SIMULATED，真人操作理解仍为 OPTIONAL_NOT_RUN。维护完成后唯一下一项为已解锁的 WS-R3-003，按 Accepted D-021 实施混成条目与安全 v4 迁移；不再请求 D-021 确认。完整 R3/R4/R5 goal 保持活动。

最终 VERIFYING → REVIEWING → DONE：完整门 `1487.349s` PASS，正常退出 0；两轮 18/18、Legacy/四关、72 案例、15×2 完整对局、反馈工具、性能、导出与试玩包全部通过。完整策略指纹保持 `a994185d975a06e046fe608567e9adb685b6a9525a83fdc85b858477d8a51255`。80 实体模拟/表现 P95 `10.472/1.344 ms`，120 实体 `15.429/1.928 ms` 仅压力测试。323 个受验文件哈希前后一致，实际 diff 与 `git diff --check` 通过。

PCK `6178532` bytes / SHA-256 `CAF20D37F891353931E0DF089187F695D92923AA2EBD2DD5AAB3932B2173284C`；EXE SHA-256 `679DF06F7F9F2D2293768747AA9AD71FB996869249960179ADA8180445FC0A7A`。摘要 `artifacts/maint-003-summary.json`；日志 `artifacts/maint-003-release.log`；五档、完整对局、72 案例和源码哈希归档 `artifacts/maint-003-evidence/`。上述“正在运行”为中间历史，不再是当前状态。

## 16. R3-003：混成编制与安全存档完成

WS-R3-003 已按 VERIFYING → REVIEWING → DONE 完成。typed 条目永久 ID、统一部署/补员/撤离、值拷贝快照、v1/v2/v3 → v4 安全迁移及失败提示/重试均已接通；混成说明纳入既有延迟悬停。旧十二卡保持单一 main 编制，未重做兵力比例。契约见 `work_items/WS-R3-003.md`，设计见 `R3_COMPOSITION_AND_SAVE_COMPATIBILITY.md`。

- 专项 `r3-003-focused7.log`、最终18套 `r3-003-tests-final.log`、连续五档 `r3-003-ui-full3.log` 均 PASS；每档包含十二卡总览、两条目兵员说明、坏档禁开局、保存失败及真实点击重试。桌面/480窄屏截图已人工查看，证据来源仍为 SIMULATED。
- 四关链式 `r3-003-campaign.log` PASS：battle_count=4，补充16人，rescue_citation 跨关保留。实际文件核对为 v4/content1、12卡、8份备份，已复制隔离档归档；未接触正式玩家存档。
- 完整发布门 `r3-003-release.log` 在1745.289秒正常退出0：两轮18/18、Legacy/四关、72案例、15×2完整对局、反馈工具、性能、Windows导出/包内启动和试玩包校验全部PASS。完整策略指纹保持 `a994185d975a06e046fe608567e9adb685b6a9525a83fdc85b858477d8a51255`。
- 80实体模拟/表现P95为15.125/1.678ms，正式门PASS；120实体13.708/1.821ms，仅压力测量。EXE SHA-256 `679DF06F7F9F2D2293768747AA9AD71FB996869249960179ADA8180445FC0A7A`；PCK 6209388 bytes / `48CF8410D841ABB68CC3E92B565D1DDED80EDD9BED1BEF3F74CBD9F151B772EB`。
- 564个受验源码文件在发布门前后哈希一致；实际diff与 `git diff --check` 通过。摘要 `artifacts/r3-003-summary.json`，源码哈希/矩阵/链式存档/截图在 `artifacts/r3-003-evidence/`。无提交、推送、分支或PR；001临时文档保持删除。
- 真人对混成明细、错误提示和主观乐趣的理解仍为 OPTIONAL_NOT_RUN (HUMAN)，不阻止已满足的工程验收。旧版程序应使用保留的迁移备份，不逆向猜测混成编制；本项不自动清理历史备份。

状态版本 46 的历史阻塞记录：当时 WS-R3-004 的工程依赖已满足，但 D-022 仍 Deferred，故按产品决定门保持 BLOCKED。2026-09-11 用户明确接受 `R3_ENTRY_REVIEW.md` 中传感器/识别、组织压制、专业火力弹药与受限伤害标签的首批范围，现已解除该阻塞。R3/R4/R5 完整 goal 尚未完成。


## 17. 左侧冷却维护及D-022接受

2026-09-11用户明确接受D-022并要求继续后续工作，旧阻塞记录已失效，DECISIONS.md现为Accepted。R3-004恢复READY；先按READY → DISCOVERY → CONTRACT领取WS-MAINT-20260911-001，现进入IMPLEMENTING，仅补左侧支援入口的快照冷却显示，18套及五档验证后继续R3-004。契约见work_items/WS-MAINT-20260911-001.md。无需再次确认D-021或D-022，完整R3/R4/R5目标保持原范围。


左侧冷却维护现已按 IMPLEMENTING → VERIFYING → REVIEWING → DONE 完成。18/18 回归与五档真实窗口连续 PASS，桌面/窄屏截图可读；日志 artifacts/maint-20260911-001-tests.log、artifacts/maint-20260911-001-ui.log，矩阵和截图归档 artifacts/maint-20260911-001-evidence/。纯 UI 不重复权威发布门。证据 SIMULATED；可选真人研究 NOT_RUN。

## 18. R3-004 差异卡

READY → DISCOVERY → CONTRACT：D-022 已正式接受，读取路线、产品规格和现有命令/战斗/知识/卡牌快照后冻结首批五卡纵向契约。旧十二卡和正式四关保持兼容；新卡以独立内容样板验证，R3-005 再迁移灰脊。详见 work_items/WS-R3-004.md。完整 R3/R4/R5 目标继续，不以维护完成替代阶段完成。

R3-004 已实现五张独立差异卡的 typed 能力、权威执行、专业弹药/压制/识别、正常决策UI和快照Agent。专项 focused6、首轮18套与五卡部署/撤离/v4恢复生命周期全部PASS（SIMULATED）；五档实窗、专业卡性能及完整发布门正在验证，尚未DONE。实现/返工细节见工作项契约。

2026-09-11性能返工：专业卡80实体实渲初测frame P95 174.050ms未通过；重复文本/布局、逐实体压制决策、地形和迷雾绘制、视野及火控扫描已优化。最新3秒诊断frame P95 22.980ms仍未通过16.667ms门，不能据短测或诊断开关标DONE。artifacts/r3-004-rework-tests2.log的18/18回归PASS；最终五档正在执行，完整采样性能及完整发布门尚待通过。所有新增证据均为SIMULATED，HUMAN研究仍可选。


R3-004现已返回VERIFYING：artifacts/r3-004-rework-ui.log五档全部PASS，artifacts/r3-004-focused-fairness.log的新鲜合法快照污染对照PASS。artifacts/r3-004-render-rework.log完整15秒60/80实渲通过：80实体frame P95 14.843ms、模拟10.943ms、呈现输入104.503ms，150/150 tick、路径失败0；先前短测失败保留，不声称执行了480秒长局门。源码清单已冻结，正在运行完整发布门，下一项仍须等待本项DONE。

2026-09-11 审查返工：自然结束的观察动作残留持续识别计时，下一次冷却后重启会跳过10 tick识别窗口。artifacts/r3-004-observation-probe.log已复现。完整门主动中止，原日志保留为非最终证据；修复新动作/自然结束时清理计时，并新增跨冷却周期测试。需重新冻结和验证，当前不是DONE。

识别生命周期修复专项artifacts/r3-004-lifecycle-rework.log PASS（SIMULATED），REWORK → VERIFYING；冻结清单仅更新执行系统与测试两个文件，完整发布门重新运行。

最终 VERIFYING → REVIEWING → DONE：`artifacts/r3-004-release-final.log` 完整门 1575.107 秒 PASS、正常退出 0、无脚本错误。两轮 18/18、Legacy/四关、72 案例、15×2 完整对局、反馈、性能、Windows 导出与包校验通过，完整策略指纹保持 `a994185d975a06e046fe608567e9adb685b6a9525a83fdc85b858477d8a51255`。80 实体 headless 模拟/表现 P95 9.663/1.441 ms；120 实体 13.444/2.110 ms 仅压力测量。

识别修复后的 `artifacts/r3-004-render-final.log` 最终 15 秒实窗 PASS：60/80 实体 frame P95 14.104/15.018 ms，80 实体模拟 10.859 ms、输入呈现 105.801 ms，150/150 tick、零路径失败。80 实体卡住事件 8、恢复峰值 2；不声称已恢复全部事件或通过 480 秒长局门，未注入弹丸峰值。五档最终 UI PASS，最后生命周期修复不改变 UI；最新实窗截图已检查。589 文件哈希一致，实际 diff 和 `git diff --check` PASS；摘要 `artifacts/r3-004-summary.json`，归档 `artifacts/r3-004-evidence/`。PCK 6268816 bytes / SHA-256 `1407F6383808900E93F1AE8D43AE93D3E0296E2D856EC944DD083C83B9FA4FD2`。HUMAN 仍为可选未运行，所有证据为 SIMULATED。唯一下一项 WS-R3-005 已 READY；不提前标记 R3/R4/R5 goal 完成。


2026-09-12 发布证据与更正：保留 `artifacts/r3-005-release-final4.log` 的脚本 PASS 事实，PCK SHA-256 `45F0928F5F281627859F1A449A0CDE9EC46E03480F4F3605FC7273B647B4B6BB`。该脚本不证明未接入的战术贡献/归因契约，也不替代迁移后的战术 UI 五档实渲和换 ID/参数专项审查。本次 `artifacts/r3-005-push-focused.log` 正式五动作专项退出 0。原 R3-005 DONE 与 R3-006 READY 均为验收误记，现已纠正；没有完成 R3/R4/R5。

2026-09-12 增援冷却同步维护：修正 `SupportPanel` contextual 分支覆盖权威 `disabled` 状态的问题，并使 `CommandDesk` 决策动作按 `CardActionSnapshot.reason` 同步置灰；左侧与决策区均显示按 10 Hz tick 换算的剩余秒数。集成回归 `artifacts/maintenance-reinforcement-cooldown-tests.log` 18/18 PASS，新增断言覆盖决策区下发增援后左侧入口的禁用与倒计时同步。证据为 `SIMULATED`，不改变 R3-005 的未闭环状态。

2026-09-12继续验收：维护 `WS-MAINT-20260912-001` 修复无选中卡时入口错误禁用，左右入口统一读取冷却来源，决策按钮直接显示秒数；最终两卡补员/暂停/到期回归PASS。桌面截图确认左右同时置灰且显示30秒，五档遇异常鼠标坐标316663616和自动审批503，维护BLOCKED，不宣称五档通过。

R3-005已接通独立Supply来源/卡ID及战术贡献报告、typed DTO和中英复盘。五动作、同tick费用、有效压制封顶、隐藏事件污染、旧报告值拷贝、三战法改ID/改参数及中英UI专项PASS；最终18/18和编制存档专项PASS。完整发布脚本 `artifacts/r3-005-contributions-release.log` 1059.921秒退出0，30场完整对局质量与确定性、四关兼容、80实体、工具、Windows导出与包校验PASS。80实体模拟/表现更新P95 6.409/0.814ms；PCK SHA-256 `041F68E844D5907940E6CD4117B25CAF1851EFB78DCDF5A47CFD9D46FE629C65`。运行源码474文件哈希已记录并复核。详见工作项末尾；仍待五档/60-80实渲及四关联动实窗证据复核，R3-005保持VERIFYING、R3-006仍BLOCKED。以上为SIMULATED，HUMAN仍可选未运行。

Git交接：此前 `.git/index.lock` 权限与审批服务503阻塞已于2026-09-13在用户开放完整访问后解除。当前实现提交 `2cc0343` 与七个资源末尾空行修正 `b9a34a3` 已成功push到origin/main；远程引用已核对。已找到既有Godot 4.6.3安装，未将开发机路径写入运行代码。474文件冻结清单中467个逐字节一致，七个资源仅删除文件末尾空行；此前完整门行为证据仍有效。

2026-09-13恢复实窗验收：五档矩阵 `artifacts/r3-005-ui-full-access.log` 全部通过，异常鼠标坐标未复现，左右补员入口同时置灰并显示30秒；正在追加中英冷却和战后贡献截图。五卡样板60/80实体15秒实渲 `artifacts/r3-005-render-full-access.json` PASS，80实体帧/模拟/输入呈现P95为10.767/7.254/103.006ms，150/150 tick、零路径失败；卡住事件7，不宣称全部恢复或480秒长局通过。四关连续实窗尚在执行；维护回到VERIFYING，R3-005保持VERIFYING，不提前解锁出口。

## 19. R3出口与R4当前队列

2026-09-13：增援共享冷却维护及WS-R3-005、WS-R3-006均DONE。最终完整门686.300秒、两轮18/18、Legacy/四关、72案例、30场完整对局、反馈工具、Windows导出及包校验全部PASS。606文件哈希复核变化0，完整策略指纹保持4fb412b52bca4e5aee0f659694f5b7e9ab086c1b570571d5890f329b2030855f。完整审查见[WS-R3-006](work_items/WS-R3-006.md)。

双语五档通过，左右补员同步致灰/倒计时、暂停、AI交接、六卡及十二卡总览和战后贡献均覆盖；英文标题撑宽左栏问题已修复。四关实窗链4次结算、补充3人、荣誉/累计损失保持，四场失败仅作流程证据。正式60/80实体15秒实渲帧P95 12.601/13.743ms，80输入呈现107.407ms、模拟5.808ms，150/150tick，路径失败0。80卡住事件30、恢复峰值7，未证明全部恢复或480秒长局；tasks_completed=0由R4阶段任务图继续处理。固定脚本过拟合与真人理解未知保留，HUMAN研究OPTIONAL_NOT_RUN。全部工程证据为SIMULATED。

证据：artifacts/r3-005-final-evidence/、artifacts/r3-005-summary.json；PCK 6311428 bytes / B41CA543B86845DF57178D0877C84CFCA6AF974A42E1E3DBCF58320CBD82AB70。R3最终修复与正常状态文档已提交0f0ecb3并成功推送；此前2cc0343和b9a34a3亦在origin/main。直连GitHub超时，通过Windows已有本地代理的单命令Git配置恢复，未改永久配置。

| ID | 状态 | 工作项 | 依赖 |
|---|---|---|---|
| WS-R4-001 | DONE (`SIMULATED`) | 公平态势评估黑板 | R3出口已满足 |
| WS-R4-002 | DONE (`SIMULATED`) | 行动方案定义、生成与效用比较 | R4-001 |
| WS-R4-003 | DONE (`SIMULATED`) | 参谋方案比较与玩家确认UI | R4-002 |
| WS-R4-004 | DONE | 将领阶段化任务图 | 完整门与8场定向审计通过 |
| WS-R4-005 | DONE | 预备队、增援、撤退与受阻重规划 | 功能专项、8场审计、五档与681.26秒发布门PASS |
| WS-R4-006 | DONE | R4阶段出口 | D-029：8/9组合、两方案全覆盖；18场确定性、819.106秒完整门及五档UI通过 |
| WS-R5-001 | DONE | 敌方Doctrine与阶段计划 | 765.543秒完整门；719受验文件无漂移 |
| WS-R5-002 | READY | 兵力分配与预备策略 | 依赖已满足 |

用户已授权按独立工作项完成R3/R4/R5，本次R3工程出口审查通过后仅解锁R4-001；R4和R5尚未完成。临时WS-MAINT-20260910-001文档保持删除，契约仍在第12节，不另建交接文档。

2026-09-13 R4-001已DONE：只读typed态势黑板、宿主入口、双方隐藏信息污染/情报老化/矛盾/值拷贝/接管与预备区别通过；18套和四关smoke PASS，60/80各150评估P95 0.248/0.343ms。日志artifacts/r4-001-regression.log、r4-001-focused2.log及r4-001-staff-situation.json。无权威/命令/存档/UI变化，本项未重复发布或五档门；方案、任务图与纠正负担仍待R4后续工作，HUMAN可选NOT_RUN。下一项WS-R4-002，完整R3/R4/R5目标继续。

2026-09-13 R4-002已DONE：三类typed方案通过只读宿主生成，逐卡分工/预备/战略路标/准备延迟/预算与人口约束/效用分量可审计。最终专项、18套及四关smoke PASS，60/80规划P95 1.073/1.306ms；日志artifacts/r4-002-focused-final.log、r4-002-regression.log和r4-002-staff-plans.json。未改变执行行为、不宣称导航或胜率；下一项WS-R4-003，完成玩家比较、修改、批准和拒绝流程。R3修复0f0ecb3、R4-001的14d4451均已通过已有系统代理推送并核对远程；本项待提交推送，完整目标继续。

R4-002的983b87a现已推送并核对远端。R4-003审批、修改/拒绝和比较UI已实现，审查后补齐本地玩家阵营校验，并修正五档弹窗测试：鼠标经根窗口输入路由，无直接按钮回调补偿。最终专项 `artifacts/r4-003-focused-final.log`、双语五档 `artifacts/r4-003-ui-final.log` PASS，包含真实同tick接管与审批竞态；高分辨率和480窄屏截图已检查。此前含回调补偿的结果不作为最终鼠标证据。当前VERIFYING，冻结源码清单后重新运行完整门 `artifacts/r4-003-release-final.log`；未通过前不解锁004、不把批准记录当作已执行任务图。所有新证据为SIMULATED，HUMAN方案理解仍可选NOT_RUN，存档格式不变。

2026-09-13 R4-003现已DONE：最终双语五档（r4-003-ui-layout-final.log）、专项及665.333秒完整门（r4-003-release-final2.log）全部PASS；两轮18/18、Legacy/四关、72案例、30场完整对局、反馈工具、80实体、Windows导出与包校验通过，无脚本错误，649受验文件哈希变化0。80实体模拟/表现更新P95 5.712/0.744ms；120实体仅压力测量。PCK SHA-256 40C2A740CDAE10BF8B592D78829D2F98283D3623F1F3AEFD0EBC2051E963A9E2。源码、矩阵、截图和摘要见artifacts/r4-003-evidence/与r4-003-summary.json，详细验收见work_items/WS-R4-003.md。此前验证中及返工描述仅作历史。所有证据SIMULATED、HUMAN理解研究可选NOT_RUN，无存档格式变化；批准只是本局权威记录。唯一下一项WS-R4-004已READY，实际阶段任务执行由该项实现；R4/R5完整目标尚未完成。


R4-004已接通批准后的真实六阶段任务、依赖/整卡执行、手控恢复与显式撤退，审查边界及18/18回归通过（artifacts/r4-004-regression-boundaries.log）。当前VERIFYING：完整对局复测、双语五档、活动图60/80性能和完整发布门尚未全部完成；不提前解锁005或标DONE。完整目标保持活动，最新已推送为R4-003的f4cc93c。

## 20. 手控战斗修复与可玩包

2026-09-14 最新用户指示优先完成 `WS-MAINT-20260914-001` 并交付游戏包，然后暂停开发。上节 R4-004 验收中的描述为历史；其已有实现保留，当前状态为 BLOCKED / USER_PAUSE，不能继续 R4-005 或 R5，也不宣称 R4 阶段完成。

本维护已修复超过56实体后的批量显示坐标与地形遮挡、手控局部自主攻击、Q攻击移动接敌/继续路线、旧AI任务与低组织阻断基础命令、混成卡攻击时成员脱离，并增加合法发现敌方总部后的进攻决策。左侧支援区顶部常驻当前补给/上限，支持中英切换；既有左右增援入口共享置灰与倒计时。坦克地形倍率、快速机动结束及队形等待规则已验证不累乘，详见 `PLAYABLE_20260914.md`。

已验证（SIMULATED）：`artifacts/manual-battle-final2.log` 手控专项及四地图总部目标寻路 PASS；`manual-visibility2.log` 的55→57→80→40实体实渲像素检查 PASS；`manual-final-regression3.log` 18/18 PASS；`manual-shipping-ui.log` 中英五档真实窗口全部 PASS，包含补给常驻/刷新、左右冷却、R交还、总部点击与十二卡总览。独立解压包已通过清单哈希校验；包内EXE真实窗口完成选关→军团编成→进入会战，实际显示“补给4/10”，空格切换“已暂停”，退出前日志无脚本错误。未执行成功的临时外部启动脚本已移除，不作为通过证据。

产品负责人明确允许本包暂时放宽帧数要求并停止调优：80实体最新实渲帧/模拟/输入呈现P95为16.803/10.003/102.786ms，150/150tick，零路径失败。原16.667ms帧门未通过，保留 `manual-render-fog-cache.log`、`manual-render-measured.json` 及此前失败记录；此例外不修改后续阶段性能标准。HUMAN主观体验为 OPTIONAL_NOT_RUN。

最终交付入口：`build/playable/WARSEED-Playable-20260914-final/WARSEED.exe`；ZIP：`build/playable/WARSEED-Playable-20260914-final.zip`，SHA-256 `1AF08EEC4AA0A80AB181C6C0FB46103A5B34C91C2B8E483BC0F9237EBDC738C8`。最终PCK为6412340字节 / SHA-256 `F241FB8418F159EDB3A473786EE0EB1D3B7BFD6671E109D7561AA94F6C4F06A4`，与完整门导出完全一致；EXE SHA-256 `679DF06F7F9F2D2293768747AA9AD71FB996869249960179ADA8180445FC0A7A`。旧无final后缀包仅保留历史，不作为最终交付入口。

VERIFYING → REVIEWING → DONE：`artifacts/manual-release-final2.log` 完整发布门727.735秒PASS、退出0、无脚本错误。两轮18/18、Legacy及四关smoke/矩阵、72案例、30场确定性完整对局、反馈工具、Windows导出与包校验均通过。80实体headless模拟/表现更新P95为6.429/0.946ms，120实体只作压力测量；此结果不替代上述实渲帧数例外。首轮唯一黄金漂移已单变量证明来自新增手控自主攻击，仅更新对应灰脊案例；其余黄金与确定性要求不变。

714项冻结清单中现存712文件哈希均未变化，仅移除两个未使用的临时启动测试文件；不是受验运行代码变化。两次导出PCK的636项内容逐项比较，唯一差异为 `.godot/uid_cache.bin`，635项内容一致，详见 `artifacts/manual-package-pck-comparison.json`。最终ZIP独立解压清单校验和真实窗口选关→编成→战场→空格暂停再次通过；`manual-package-final-visible.log` 无脚本错误。源码diff已审查，`git diff --check`通过。上述证据全部为SIMULATED，HUMAN仍可选未运行；无存档格式变化。交付后停止开发，R4-004保持BLOCKED / USER_PAUSE。

## 21. 低成本开发与后续代理入口

2026-09-16 `WS-MAINT-20260916-001` 已DONE。用户授权建立低成本分工规范，并比较Kimi K3、GPT-5.6-Luna、Agents-A1、DeepSeek-V4-Flash-0731。此为开发流程维护，未恢复游戏开发；R4_USER_PAUSE、R4-004 BLOCKED和09-14可玩包保持原状。

正常入口 `AGENTS.md` 已接入 `AI_AGENT_PLAYBOOK.md`（渐进阅读、L0–L3风险分工、代码导航、后续阶段恢复顺序）、`AI_DELEGATION_TEMPLATE.md`（输入/交付/验收契约）和 `AI_LOW_COST_PROVIDER.md`（本机接入及对比事实）。修正主工作流与目标协议的旧阶段提示和14套旧口径；验证仅在同一受验源码/环境/命令及可复核日志下复用，核心工程门不降低。

四模型同题各一次，Luna在27.605秒内六项判断正确、零误报，服务报告输入648/输出1247token；Kimi与Agents响应没有可用正文，DeepSeek请求超时。选择 `gpt-5.6-luna` 为当前低风险文本委派首选，仅完成一个审查题样本，不能声称模型综合最强或代码实现资质已认证。详细回执与失败边界见服务指南，费用UNKNOWN，不持续付费重试。

`tools/ask_low_cost_ai.py` 提供固定同源HTTPS、显式文件输入、无自动重试、重复run-id拒绝、输出usage的一次文本请求；不执行外部补丁/工具。`python tests/tools/test_low_cost_ai.py` 离线5/5通过，文档20条本地链接/围栏及11文件密钥检查通过，实际diff和空白检查通过；本机配置只保存凭据路径，位于Git忽略目录。未改游戏源码，不重复游戏发布门；证据SIMULATED，HUMAN不适用。当前流程维护改动未提交/推送，游戏最新提交仍238613a。后续只有用户明确恢复时才验收R4-004，不从头重做，也不越过依赖执行R4-005/R5。


## 22. R4/R5 恢复与预算约束（当前）

2026-09-16 用户明确恢复并持续完成 R4、R5，使用 GPT-5.6-Luna 辅助；此前 USER_PAUSE 和第20/21节暂停结论已被本次授权替代。R4-004 恢复 VERIFYING，005 仍等待004 DONE，不重复既有实现。用户授权主模型上限200美元，小模型费用排除；按用户确认输入10美元/百万、输出50美元/百万，以本地会话 token_usage_record 的累计差值保守估算，全部输入不计缓存折扣。基线输入292997349、输出927181，对应本轮请求之前的记录；本地脚本 artifacts/check-r4-r5-budget.py 与 budget-latest.json 保存用量。170美元停止新增实现，保留30美元用于验证、交接；此为估算控制，不冒充服务商美元账单，也不自设goal token预算。

D-028 已按用户最新指示 Accepted：整体逻辑优先，性能门暂缓，数据仅供参考；功能、10Hz逻辑语义、确定性、公平知识、存档安全、UI和导出门继续执行。R4-004 8场整局定向审计通过（含撤退、跨策略差异、阻塞原因和重复确定性）；节点反射复制改为显式值拷贝并通过全字段与数组隔离测试。60/80实渲本次frame P95为13.820/15.590ms，80模拟8.196ms，150/150tick；性能记录保留，不继续调优或以其取代功能验收。当前完整发布门日志 artifacts/r4-004-resume-release.log 尚在执行，不提前DONE。所有工程证据SIMULATED，HUMAN仍OPTIONAL_NOT_RUN。

R4-004最终DONE：完整发布门退出0，8场postcopy定向整局审计PASS，704受验文件无漂移；详见工作项最终证据。当前唯一下一项R4-005 READY。低成本流程与D-028已提交并推送1cb7499；原第21节未推送描述仅是历史。

R4-005已冻结独立契约并进入IMPLEMENTING；当前下一步为四类适应动作纵向实现。R4-004提交23aa5a8，发布门694.338秒PASS。

R4-005功能专项及8场整局审计PASS，进入VERIFYING；完整门artifacts/r4-005-release.log与五档UI进行中，不提前DONE。当前主模型本地保守估算约117美元，170美元停止新增实现规则保持。

R4-005最终DONE：完整门681.26秒及最终UI/导出/包校验PASS，性能DEFERRED；原运行源码冻结未漂移，最后三处纯UI文案变化已单独验证并导出。下一项R4-006为PRODUCT_DECISION阻塞，用户尚未回复出口指标建议（不是已接受）；当前只读研究正确计数5/9，9場均结束但会战胜利0，不能将其报告为R4阶段完成。新接手按R4_R5_NEXT_AGENT_HANDOFF.md和WS-R4-006.md进行，R5依赖尚未解锁。R4/R5持续目标未完成，预算基线不重置，主模型本地估算最近约151美元，最终实际估算以budget-latest.json为准。

2026-09-16最新授权：用户扩大主模型累计额度至400美元（原用量基线不变，370美元停止新增实现），并接受R4出口指标，D-029 Accepted。R4-006解除PRODUCT_DECISION阻塞，按BLOCKED → READY → DISCOVERY → CONTRACT → IMPLEMENTING继续；R5仍依赖真实出口通过。

R4-006最终DONE：VERIFYING → REVIEWING → DONE。D-029指标8/9、集中投入与侧翼推进各3/3；18场重复指纹相同，纠正0或1次/10分钟，失败例有实际撤退凭据与主力恢复结果。完整发布门819.106秒、五档真实UI、702受验文件哈希无漂移；详细表见[R4_EXIT_EVIDENCE.md](R4_EXIT_EVIDENCE.md)。R4工程出口依据用户持续推进及D-029授权接受，R5-001 READY。HUMAN为可选NOT_RUN，性能DEFERRED。主模型累计保守估算250.37美元，400美元上限及370美元停止新增实现保持。

R5-001 DONE：typed准则、阶段化行动、命令与快照、公平目标和实际撤退完成。完整发布门765.543秒通过；黄金迁移与集中进攻侦察修复均已解释并验证。R5-002 READY，其余R5尚未完成。模块入口[ENEMY_OPERATION_GUIDE.md](ENEMY_OPERATION_GUIDE.md)。
