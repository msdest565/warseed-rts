# 《灰脊矿区》首切片验收审计

> 审计日期：2026-08-09
> 产品基线：`GAME_DESIGN_DOCUMENT.md` 14、`MVP_SCOPE.md` 2/7/8、`TECHNICAL_PLAN.md` Gate G
> 自动验证入口：`tools/verify_grey_ridge_release.ps1`
> 历史说明：本文结论冻结于审计日期；D-026 已取消真人证据硬门，当前门禁以 `AI_DEVELOPMENT_STATE.md` 为准。

## 1. 审计结论

- **工程实现与自动验收：已证明。** 本机 Godot `4.6.3.stable.mono.official.7d41c59c4` 完整执行统一入口，用时 64.686 秒；两轮 13 套测试、双 smoke、6×3 黄金矩阵、40/80/120 实体基准、四项 PowerShell 工具烟测、Windows export 和导出包隔离启动均通过。
- **可分发切片：已证明。** 最新 ZIP 为 `build/playtest-kits/WARSEED-Grey-Ridge-20260809-094509.zip`，大小 37,305,766 bytes，SHA-256 为 `25F48613896AB9A9E557DDE73301BF39BCC69B99A0D693A835EA09DDADBA7095`，清单包含 8 个文件。
- **首切片产品通过标准：未证明。** 尚无真实陌生玩家按 `PLAYTEST_PROTOCOL.md` 完成整局与战后提问，因此不能宣布 Gate G 或完整 MVP 通过，也不能扩充正式卡牌内容。
- **CI 远端状态：待首次运行。** `.github/workflows/grey-ridge-ci.yml` 已接入本地同一验收入口；只有代码推送后产生的 GitHub Actions 运行记录才能证明远端 runner 通过。

## 2. 企划书 14.1 必须实现

| 要求 | 状态 | 当前权威证据 |
|---|---|---|
| 一张《灰脊矿区》地图和八分钟胜负链 | 已证明 | `test_game_integration.gd::_test_grey_ridge_scene_is_the_playable_slice` 校验主场景与 08:00 HUD；`test_simulation_world.gd::_test_grey_ridge_initial_state` 和场景 smoke 校验专用权威场景。 |
| tick 0 战前军团编成 | 已证明 | `test_game_integration.gd::_test_grey_ridge_prebattle_planning` 覆盖 tick 冻结、容量、战法、姿态、两张首发、非法计划和提交后真实编成。 |
| 三名将领或等价节点 | 已证明 | `_test_grey_ridge_initial_state` 校验 3 名将领；场景集成测试校验中英文行动、ETA、风险和退出条件。 |
| 至少四张部队卡、展开不少于 40 个实体 | 已证明 | `_test_grey_ridge_initial_state` 校验 4 卡与开局 34 个实体；`grey_ridge_smoke.gd` 校验两张预备卡再展开 14 个实体，总授权规模 48。 |
| 常驻军团板和地图联动 | 已证明 | 场景集成测试校验 4 卡持续可见；`test_player_input.gd` 覆盖卡牌选择、双向实体选择与地图命令。 |
| 将领拖动、姿态、整卡路线/阵线、归还 | 已证明 | `test_player_input.gd` 覆盖将领卡/任务环拖动和路线编辑；`test_simulation_world.gd` 覆盖整卡接管、路线/阵线和无瞬移归还。 |
| 至少四张改变 Agent 行为的战法卡 | 已证明 | `ArmyPlan` 与四份 `.tres` 数据由资源测试加载；`_test_grey_ridge_doctrine_constraints` 和行为反馈测试覆盖执行约束。 |
| 补给、三区、预备投入、两项支援 | 已证明 | `_test_grey_ridge_region_control_and_settlement`、`_test_grey_ridge_reserve_deployment`、`_test_grey_ridge_support_orders` 覆盖周期、费用、部署时间与合法目标。 |
| 高/中/未知情报与最后确认 | 已证明 | `_test_grey_ridge_initial_state` 校验三类开局报告；`test_faction_knowledge.gd` 覆盖 last-seen、快照复制与隐藏目标拒绝。 |
| 地形、四类战团、视野依赖和撤退 | 已证明 | `_test_grey_ridge_terrain_role_behaviors` 覆盖侦察、突击、装甲与火力角色规则；姿态、脱离集结和合法情报风险由模拟测试覆盖。 |
| 锁定敌方计划与反应规则 | 已证明 | `_test_grey_ridge_locked_enemy_reactions_use_faction_knowledge` 校验合法阵营知识；6 种玩家策略 × 3 套开局计划的 18 个黄金哈希全部通过。 |
| 战后损失回写 | 已证明 | `_test_grey_ridge_battle_loss_persistence`、`_test_grey_ridge_post_battle_progression` 覆盖现员、补员、功勋、荣誉、装备与第二局加载。 |
| 离线运行与确定性测试 | 已证明 | 运行时无 LLM/联网依赖；导出 EXE 隔离 headless 启动通过；固定种子与 18 个黄金哈希提供确定性证据。 |

## 3. MVP 自动验收

| 自动门 | 状态 | 直接证据 |
|---|---|---|
| 卡牌来自权威状态，旧快照不可变 | 通过 | `_test_army_roster_snapshot_tracks_real_entities`。 |
| 一张卡稳定绑定、选择和命令全部存活成员 | 通过 | `_test_army_card_selects_bound_entities`、`_test_grey_ridge_unit_card_takeover_and_return`。 |
| 玩家接管期间 Agent 不覆盖 | 通过 | `_test_grey_ridge_unit_card_takeover_and_return`、集成接管回归。 |
| 明确归还后安全归队且不瞬移 | 通过 | 同上，验证整卡成员完成 rejoin 后才恢复任务。 |
| 两名将领维持独立目标 | 通过 | `_test_grey_ridge_independent_commander_orders`。 |
| 资源区按周期与控制状态结算 | 通过 | `_test_grey_ridge_region_control_and_settlement`。 |
| 预备队扣补给并在 10 秒后生成 | 通过 | `_test_grey_ridge_reserve_deployment` 与部署拒绝测试。 |
| 未知区域不泄露真实位置 | 通过 | `_test_grey_ridge_commander_outlook_uses_legal_intelligence`、阵营知识测试。 |
| 敌方改令可追溯 | 通过 | 锁定计划测试与黄金矩阵审计日志。 |
| 相同构建、初态、种子与命令可复现 | 通过 | 18 个黄金哈希与 `_test_deterministic_replay`。 |
| A/B/C 加三种自由组合覆盖三计划 | 通过 | `grey_ridge_decision_matrix.gd`：6×3 全部通过。 |
| 80 实体满足 10 Hz 预算 | 通过 | 最新 headless 80 实体模拟 P95 为 7.796 ms；Windows 80 实体正式实渲门 P95 为 14.396 ms。 |
| headless、主场景 smoke、Windows export | 通过 | 统一发布验收入口完整通过。 |

## 4. 人工试玩门

以下项目全部为 **待真实陌生玩家证明**：

1. 30 秒内理解卡牌与真实编队关系；
2. 30 秒内下达第一条有效将领或部队卡命令；
3. 能解释至少一名将领为何推进、停下或撤退；
4. 根据至少一条带可信度的情报改变部署；
5. 至少一次接管完整部队卡并明确归还；
6. 不依赖单兵诊断解决核心问题；
7. 能解释敌方反应来自预先锁定规则；
8. 愿意改变编成、战法或主攻方向再玩一局。

试玩必须使用隔离匿名会话和真实观察员结论。自动记录、预填答案、测试夹具或开发者自测都不能把这些项目改为通过。完成一批试玩后，先用 `complete_playtest_report.ps1` 生成单局评估，再用 `summarize_playtest_cohort.ps1` 汇总；队列状态仍不自动宣称 MVP 通过或定义样本量。

## 5. 放行规则

在人工试玩门有真实证据前：

- 保持四张正式部队卡与四张正式战法卡，不横向扩充内容；
- 只修正试玩暴露出的卡牌对应、任务透明度、控制负担、节奏与数值问题；
- 保持统一发布验收、Windows CI、18 个黄金哈希和实渲性能门通过；
- 不把完整 MVP、最终美术、80—120 实体正式内容或 15—25 分钟会战描述为已完成。
