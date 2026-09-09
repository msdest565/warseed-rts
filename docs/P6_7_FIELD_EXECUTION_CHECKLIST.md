# P6.7 现场执行、证据登记与 AI 接手清单

> 状态：可选产品研究，D-026 后不参与工程、阶段或发布门
> 生效日期：2026-08-20
> 规则来源：[`P6_7_PLAYTEST_COHORT_PLAN.md`](P6_7_PLAYTEST_COHORT_PLAN.md)
> 观察协议：[`PLAYTEST_PROTOCOL.md`](PLAYTEST_PROTOCOL.md)

## 1. 冻结候选包

```yaml
candidate_id: P6.7-RC4
status: ACTIVE_FOR_NEW_HUMAN_SESSIONS
package: build/playtest-kits/WARSEED-Four-Operations-P67-RC4-20260820.zip
package_bytes: 37334442
package_sha256: 775CE0A71A634938836ED30E75F4D200C2021F3CE206BA398AF5A08435C42D73
manifest_file_count: 11
scenario_ids:
  - grey_ridge
  - broken_bridge
  - fog_forest
  - black_well
engineering_gate: PASS
human_gate: NOT_RUN
```

RC4 是唯一允许分发给新场次的候选包。RC、RC2、RC3 与所有名称含 `Latest` 的包只保留用于审计，不能与 RC4 混入同一 cohort。完整发布门、清单哈希和导出程序启动已经通过，但不构成真人理解度或正式平衡证据。

## 2. 场次开始前

观察员每次开始前逐项确认：

- 从原始 RC4 ZIP 完整解压，不在压缩包预览窗口运行；
- 校验 ZIP SHA-256 与上方一致；
- 新参与者只使用分配的 `p67-01` 至 `p67-09`，不复用开发者或其他玩家会话；
- 记录实际分辨率、`mouse` 或 `touchpad`、界面语言和观察员 ID；
- 确认参与者未看过源码、企划、操作视频或其他测试场次；
- 观察员不在首条有效命令或 30 秒前给出操作、编成、路线或计划建议；
- 首场双击 `START_WARSEED_PLAYTEST.cmd`，后续场次使用同一 ID 和 `-Resume`；
- 游戏退出后的观察评价必须基于玩家原话或可观察行为，不允许补写推断。

续测命令从 RC4 解压目录执行：

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\start_isolated_playtest.ps1 `
  -ExecutablePath .\build\windows\warseed-debug.exe `
  -SessionId "p67-01" -Resume -Evaluate
```

## 3. 参与者登记

`PENDING` 只能由真人组织者改成 `SCHEDULED`、`IN_PROGRESS`、`COMPLETE` 或 `WITHDRAWN`。设备与语言覆盖必须记录实际值，不能按计划预填。

| ID | 必测会战 | 分辨率 | 指针设备 | 语言 | 观察员 | 状态 |
|---|---|---|---|---|---|---|
| p67-01 | 灰脊、断桥、雾林、黑井 | 待登记 | 待登记 | 待登记 | 待登记 | PENDING |
| p67-02 | 灰脊、断桥、雾林、黑井 | 待登记 | 待登记 | 待登记 | 待登记 | PENDING |
| p67-03 | 灰脊、断桥、雾林、黑井 | 待登记 | 待登记 | 待登记 | 待登记 | PENDING |
| p67-04 | 灰脊、断桥 | 待登记 | 待登记 | 待登记 | 待登记 | PENDING |
| p67-05 | 灰脊、断桥 | 待登记 | 待登记 | 待登记 | 待登记 | PENDING |
| p67-06 | 灰脊、雾林 | 待登记 | 待登记 | 待登记 | 待登记 | PENDING |
| p67-07 | 灰脊、雾林 | 待登记 | 待登记 | 待登记 | 待登记 | PENDING |
| p67-08 | 灰脊、黑井 | 待登记 | 待登记 | 待登记 | 待登记 | PENDING |
| p67-09 | 灰脊、黑井 | 待登记 | 待登记 | 待登记 | 待登记 | PENDING |

环境最低覆盖：低分辨率至少 3 人、触控板至少 2 人、鼠标至少 4 人、中文界面至少 7 人。一个参与者可以同时贡献多个环境维度。

## 4. 二十四场最低证据账本

每格只使用 `PENDING`、`RAW_ONLY`、`ASSESSED`、`INVALID` 或 `RETEST_REQUIRED`。只有原始记录与独立 assessment 都存在且上下文完整时才能标记 `ASSESSED`。

| 参与者 | grey_ridge | broken_bridge | fog_forest | black_well | 串联要求 |
|---|---|---|---|---|---|
| p67-01 | PENDING | PENDING | PENDING | PENDING | battle_count 最终为 4 |
| p67-02 | PENDING | PENDING | PENDING | PENDING | battle_count 最终为 4 |
| p67-03 | PENDING | PENDING | PENDING | PENDING | battle_count 最终为 4 |
| p67-04 | PENDING | PENDING | 不要求 | 不要求 | 同一 ID 续测 |
| p67-05 | PENDING | PENDING | 不要求 | 不要求 | 同一 ID 续测 |
| p67-06 | PENDING | 不要求 | PENDING | 不要求 | 同一 ID 续测 |
| p67-07 | PENDING | 不要求 | PENDING | 不要求 | 同一 ID 续测 |
| p67-08 | PENDING | 不要求 | 不要求 | PENDING | 同一 ID 续测 |
| p67-09 | PENDING | 不要求 | 不要求 | PENDING | 同一 ID 续测 |

每个 `ASSESSED` 场次必须能定位：

- 不可人工修改的 `latest_<scenario>.json` 或归档原始记录；
- 对应的 `*_assessment.json`；
- participant group、observer ID、分辨率、输入设备、语言、会战结果和开始时间；
- 四项观察结论的玩家原话或行为证据；后三关还需新增规则理解结论。

## 5. 当前未归属记录

现有会话 `123` 有一份《断桥回声》胜利原始记录，但没有 assessment、观察员、参与者组和环境上下文。它当前标记为 `RAW_ONLY / NOT_COUNTABLE`。该 `latest_broken_bridge.json` 的最近写入时间为 `2026-08-18T16:54:55.1824165Z`，SHA-256 为 `57B977E1951E5BEB4CB9E4FCE1A0155DC04CAB51E900D9A456DD2F13BEF7DC32`。真人组织者可以确认它是否来自合格陌生玩家，并基于当时真实观察补交独立 assessment；不得猜测、改写原始 JSON，或仅凭胜利结果把它归入 `p67-*`。

`codex-full-run` 与 `codex-investigate-20260811` 是自动化或开发调查会话，永久不计入 P6.7 真人样本。其 latest 文件 SHA-256 分别为 `72DE70E7A5A43BF62C3E39ACC033DD5C2CBA159E2352B610B0D2701EF1B46610` 与 `D8E34F864D3CB4E2639C777D237437DCD2BBA90BC14069699FF9E14405AEEF4D`，用于后续增量审计时排除既有开发证据。

## 6. 汇总与 AI 接手

收集到 assessment 后，先生成不可覆盖的汇总文件：

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\summarize_playtest_cohort.ps1 `
  -InputDirectory "$env:APPDATA\Godot\app_userdata\WARSEED\playtest_runs" `
  -OutputPath ".\artifacts\playtests\p67-rc4-cohort-<YYYYMMDD-HHMMSS>.json"
```

然后向 AI 直接发送：

```text
/goal work-item WS-R0-002
starting_evidence:
  - artifacts/playtests/p67-rc4-cohort-<YYYYMMDD-HHMMSS>.json
required_verification:
  - 原始记录不可变
  - assessment 与匿名会话逐项对应
  - 灰脊 9 份、其余三关各 5 份
  - 3 人四关串联和全部环境覆盖
stop_when:
  - 证据不足或存在无法归属的记录
  - 需要真人补充观察结论
```

AI 必须先审计原始记录、assessment、去重键和环境覆盖，再判断 R0-001 是否完成。汇总工具的 `cohort_status`、自动化全绿或胜率都不能单独放行 P6.7。

## 7. 缺陷与产品决定

发现 P0/P1 或 3 人以上重复 P2 后发送：

```text
/goal work-item WS-R0-003
starting_evidence:
  - artifacts/playtests/<cohort-summary>.json
constraints:
  - 每个缺陷独立复现、修复和验收
  - 不实现 R1 扩充功能
required_verification:
  - 14 套回归
  - 受影响会战 smoke
  - 必要的陌生玩家复测
```

产品负责人完成证据评审后，把下列占位值逐项替换为 `Accepted`、`Rejected` 或 `Deferred`，再发送：

```text
/goal work-item WS-R0-004
starting_evidence:
  - artifacts/playtests/<cohort-summary>.json
product_owner_decisions:
  D-018: <Accepted|Rejected|Deferred>
  D-019: <Accepted|Rejected|Deferred>
  D-020: <Accepted|Rejected|Deferred>
  D-021: <Accepted|Rejected|Deferred>
  D-022: <Accepted|Rejected|Deferred>
  D-023: <Accepted|Rejected|Deferred>
  D-024: <Accepted|Rejected|Deferred>
constraints:
  - 只写入产品负责人明确给出的结论
  - 为每项决定记录证据、理由和下游影响
stop_when:
  - 任一决定仍缺失或含义不明确
```

本段为 D-026 前的历史接手模板。当前状态不得回退到 `R0 / WAITING_HUMAN_EVIDENCE`；是否执行该清单由产品负责人自愿决定，结果不改变工程阶段状态。
