# WARSEED `/goal` 目标命令手册

> 协议版本：1.1
> 建立日期：2026-08-20
> 解析入口：仓库根目录 [`AGENTS.md`](../AGENTS.md)
> 当前状态：[`AI_DEVELOPMENT_STATE.md`](AI_DEVELOPMENT_STATE.md)
> 执行流程：[`AI_DEVELOPMENT_WORKFLOW.md`](AI_DEVELOPMENT_WORKFLOW.md)

## 1. 命令性质

本文件定义的是 WARSEED 仓库级 `/goal` 提示协议。它让用户可以用短命令启动持续目标，由 AI 自动读取状态、展开工作项、验证和交接。

这些命令不是 PowerShell、Godot 或仓库脚本，也不假设某个公开 Codex CLI 版本原生提供同名斜杠命令。用户直接把命令作为聊天消息发送即可；仓库中的 `AGENTS.md` 规定后续 AI 如何解释。

目标与普通单次请求的区别：

- 目标可以跨多个自动续跑回合持续推进；
- 目标必须有明确出口，不以“先做一点”结束；
- 一个目标只覆盖一个工作项、一个阶段或一个明确维护范围；
- 同一时间只保留一个活动目标；
- 遇到阶段门、依赖或产品决定时保持阻塞，不自行越过。

## 2. 最短用法

### 2.1 执行下一个可做任务

```text
/goal next
```

AI 会读取 `AI_DEVELOPMENT_STATE.md`，领取第一个依赖满足的 `READY` 工作项。当前若没有 `READY` 项，只报告阻塞条件，不跳到后续阶段。

### 2.2 执行指定工作项

```text
/goal work-item WS-R1-001
```

AI 只完成该工作项的发现、契约、实现、验证、审查和状态更新。依赖未满足时不开始修改。

### 2.3 推进一个完整阶段

```text
/goal phase R1
```

AI 按依赖顺序执行 R1 中已解锁的工作项，直到全部阶段出口通过或遇到真实阻塞。阶段目标不允许跨入 R2。

### 2.4 创建独立维护目标

```text
/goal maintenance WS-MAINT-20260820-001
objective: 修复一项明确的候选版问题
in_scope:
  - 写出允许修改的行为和模块
out_of_scope:
  - 不改变扩充阶段和产品范围
done_when:
  - 写出可观察验收条件
```

维护目标不改变 `current_phase`。缺少 `objective`、`in_scope` 或 `done_when` 时，AI 先补齐契约，不直接编辑。

### 2.5 发起只读审查

```text
/goal review working-tree
focus:
  - bugs
  - regressions
  - missing tests
write_changes: false
```

默认只读。只有明确写 `write_changes: true` 才授权在发现后修复。

### 2.6 查询或继续目标

```text
/goal status
```

```text
/goal continue
```

`status` 只报告当前目标、工作项、已经验证的结果、剩余出口和阻塞。`continue` 保持同一目标和范围继续执行。

## 3. 可选命令体

短命令之后可以追加 YAML 风格约束：

```text
/goal work-item WS-R1-001
priority: P0
budget: 120000
constraints:
  - 不改变存档格式
  - 不修改 UI
required_verification:
  - tests/test_runner.gd 全套 headless tests（当前18套）
  - 受影响数据测试
stop_when:
  - 需要新增产品决策
```

字段语义：

| 字段 | 作用 | 规则 |
|---|---|---|
| `priority` | 用户指定紧急度 | 不覆盖依赖和阶段门 |
| `budget` | 目标 token 预算 | 只在用户明确填写时使用 |
| `constraints` | 额外不可违反约束 | 与 Accepted 决策冲突时停止并报告 |
| `required_verification` | 用户要求的附加验证 | 只能增加，不能删除工作流最低门 |
| `stop_when` | 提前停止并请求决定的条件 | 不等于目标完成 |
| `write_changes` | 审查是否允许修复 | `review` 默认 `false` |
| `starting_evidence` | 用户提供的新证据路径 | AI 必须先验证存在和来源 |

不建议在目标命令中列出具体实现步骤。实现步骤应由 AI 在 `DISCOVERY` 后根据代码事实和现有模式确定。

## 4. 命令解析规则

### `/goal next`

1. 读取状态控制块；
2. 若存在活动目标，报告该目标而不是创建新目标；
3. 按队列顺序选择首个 `READY` 且依赖满足的工作项；
4. 把工作项契约展开为目标；
5. 执行到 `DONE` 或真实阻塞；
6. 更新状态文件并给出唯一下一工作项。

### `/goal work-item <ID>`

1. 在状态文件或路线图中找到 ID；
2. 校验阶段、依赖、所有者和权限；历史 `human_required` 字段不再参与门禁；
3. 缺少完整任务契约时先生成契约；
4. 不自动执行兄弟任务；
5. 工作项完成后结束目标。

### `/goal phase <Rn>`

1. 目标阶段必须是当前阶段，或已经由前一阶段出口解锁；
2. 按依赖执行多个小工作项，不把阶段合并成一次大改；
3. 每个工作项独立验证和更新状态；
4. 每 3-5 个实现工作项运行一次完整发布门；
5. 阶段出口需要产品决定或工程证据时停在门前；
6. 不自动进入下一阶段。

### `/goal maintenance <ID>`

1. ID 必须以 `WS-MAINT-` 开头；
2. 必须提供明确行为目标和完成条件；
3. 建立临时工作项并记录在状态文件；
4. 不修改 R0-R7 队列依赖，除非维护结果确实解除已有阻塞；
5. 完成后把临时工作项移入状态更新记录。

### `/goal review <scope>`

1. 明确审查对象和基准；
2.  findings 按严重级排序，给出文件和行号；
3. 默认不写文件；
4. 没有发现时说明残余测试缺口；
5. 若允许修复，先完成审查，再把修复拆为工作项。

## 5. 当前阶段可直接发送的命令

2026-09-16当前入口：用户已明确恢复R4/R5，使用 `/goal continue` 继续原范围并逐项检查依赖。09-14暂停已经解除；D-021/D-022已接受无需重复确认。D-028暂缓性能通过要求，其他功能门保持。实时进度以状态文件第1及22节为准。

R1-001至R1-008已完成并由产品负责人接受。D-026取消真人证据硬门，D-027启用 [`GAMEPLAY_REWORK_ROADMAP.md`](GAMEPLAY_REWORK_ROADMAP.md)。R2/R3及D-021/D-022的接受记录保留在状态文件；R4继续须服从最新用户暂停和工作项依赖，不从历史授权自动恢复。

### 5.1 已完成的 R2 阶段出口审查示例

```text
/goal review phase-exit R2
focus:
  - 完整发布门、五档 UI、80 实体与完整策略矩阵证据
  - 固定脚本路线过拟合和真人主观体验未知的残余风险
  - 是否接受 R2 工程出口并解锁 WS-R3-001
write_changes: true
```

该审查只决定是否接受已经通过的 R2 工程出口。接受后把当前阶段推进到 R3，并仅将 `WS-R3-001` 设为 `READY`；不一次解锁或实现整个 R3。

### 5.2 可选：收到真人记录后审计

```text
/goal review human-validation
starting_evidence:
  - artifacts/playtests/<candidate-id>/
focus:
  - 构建哈希与匿名会话一致性
  - 原始记录与 assessment 逐项对应
  - P6.7 九人/24 场和环境覆盖
  - HV-R1、HV-UI、HV-A11Y、HV-E2E 结果
  - P0/P1/P2 缺陷与复测需求
write_changes: false
stop_when:
  - 原始证据缺失、构建混用或需要观察员补充玩家原话
```

证据不足时只生成缺口清单，不把 `SIMULATED` 或 `INCOMPLETE` 改写为真人通过。该审查是可选产品研究，不改变工程阶段状态。

### 5.3 处理验收缺陷

```text
/goal maintenance WS-MAINT-<DATE>-<SEQ>
objective: 修复一个已由验收用例定位的明确问题
in_scope:
  - <问题影响的行为和模块>
out_of_scope:
  - 不扩大当前 R2 工作项
done_when:
  - 原问题自动复现通过
  - 全套回归（当前18套）和受影响关卡通过
  - 可选真人研究不作为完成条件
```

### 5.4 推进当前 R2 阶段

只有 `AI_DEVELOPMENT_STATE.md` 中当前工作项依赖已经满足时，才发送：

```text
/goal phase R2
constraints:
  - 只改灰脊，不批量增加地图或卡牌
  - 先冻结完整对局基线，再改变表现与玩法
  - 不把模拟证据描述为真人体验结论
stop_when:
  - 当前工作项依赖未满足
  - 需要扩大到 R3 卡牌或 R4 AI
```

## 6. R1-R7 阶段命令

这些命令只有在对应阶段已解锁后才能发送。未解锁时 AI 必须报告 `PHASE_GATE`。

### R1：目标与结果系统

```text
/goal phase R1
constraints:
  - 先等价迁移四关，再启用新胜利条件
  - Legacy RTS 保留旧胜利链
  - 目标组合只允许限定 kind 与两层 ALL/ANY
done_when:
  - 护送胜利和有序撤离均可由权威系统结算
  - 四关无非预期回归
  - R1 阶段出口通过
```

### R2：灰脊乐趣基准

```text
/goal phase R2
constraints:
  - 完整对局不能被短窗口替代
  - 不调整数值美化初始基线
  - 不批量增加地图、卡牌或战役内容
done_when:
  - 灰脊具备完整对局因果观测
  - 战线、威胁、补给承诺和异常可辨识
  - 至少两种完整策略可被机器区分
  - R2 阶段出口通过
```

### R3：卡牌战术语法

```text
/goal phase R3
constraints:
  - 先实现受限的 typed effect grammar
  - composition entry ID 永久稳定
  - v3 同质卡保守迁入 main 条目
  - 卡牌差异优先改变动作、信息、编制与约束，不堆倍率
done_when:
  - 4-6 张卡具备不同战术动词、代价和反制
  - 一张混成卡完成部署、接管、战损、撤出和存档闭环
  - 旧十二卡兼容
  - 60-80 实体性能通过
```

### R4：我方分层 AI

```text
/goal phase R4
constraints:
  - 参谋只读取 FactionSnapshot
  - 参谋提供 2-3 个方案，不伪装唯一最优解
  - 将领执行必须经过任务图和统一命令管线
done_when:
  - 行动方案具有兵力、路线、代价、风险和预备队
  - 将领具备阶段、撤退、增援和受阻重规划
  - 完整对局纠正负担达到冻结门槛
  - R4 阶段出口通过
```

### R5：敌方行动 AI

```text
/goal phase R5
constraints:
  - 开局计划在读取玩家本局行为前锁定
  - 反应只消费敌方合法知识
  - 多轴与欺骗必须有投入、延迟和撤退条件
done_when:
  - Doctrine、Operation Plan、Reaction Rules 和 Reserve Policy 数据化
  - 至少三种敌方计划产生不同可观察压力
  - 每次改令都可在战后追溯原因
```

### R6：第一章行动层

```text
/goal phase R6
constraints:
  - 采用轻量行动图，不做国家级领土沙盘
  - 战役存档与军团存档分离并由 manifest 关联
  - 正式地图兼容只存在于 Loader/Compiler
done_when:
  - 现有四关形成连续行动与跨关后果
  - 前一关结果至少改变下一关两项权威上下文
  - 完整战役存档、双语、性能和导出通过
```

### R7：内容生产与最终表现

```text
/goal phase R7
constraints:
  - 先以第二章两关证明内容管线
  - 不把 120 实体自动设为正式目标
  - 内容扩充不得绕过稳定 ID、目标、地图和存档管线
done_when:
  - 第二关不需要新增通用系统或世界类特判
  - 内容验证器、正式资产、存档、性能、UI、本地化和导出通过
  - 后续三章扩展由新产品决策决定
```

## 7. 常用工作项目标

### 实现一个具体任务

```text
/goal work-item <WORK_ITEM_ID>
constraints:
  - 保护工作区已有修改
  - 使用现有代码模式
  - 只修改工作项范围内行为
required_verification:
  - 工作项 focused tests
  - git diff --check
```

### 修复一个明确问题

```text
/goal maintenance WS-MAINT-<DATE>-<SEQ>
objective: <一句话描述错误行为和正确行为>
in_scope:
  - <允许修改的模块或行为>
out_of_scope:
  - <明确不处理的相邻问题>
done_when:
  - <可观察的修复结果>
  - <回归测试结果>
```

### 审查一个阶段出口

```text
/goal review phase-exit <R0-R7>
focus:
  - 未满足的完成定义
  - 被误读的自动化证据
  - 存档、性能、公平知识、完整对局指标和证据边界
write_changes: false
```

### 审查当前代码

```text
/goal review working-tree
focus:
  - correctness
  - behavioral regressions
  - persistence safety
  - missing tests
write_changes: false
```

## 8. 不应使用的目标

以下目标范围过大或试图越过门禁，AI 应拒绝直接执行并要求拆分：

```text
/goal 完成整个 WARSEED 游戏
/goal 一次实现 R1 到 R7
/goal 跳过完整对局和工程门直接扩充全部内容
/goal 重写 SimulationWorld、地图、战斗、存档和 UI
/goal 自动选择并接受全部产品决策
```

正确做法是使用 `/goal phase <Rn>`，或从 `/goal next` 领取单一工作项。

## 9. 用户推荐操作顺序

```text
1. `/goal status`
2. `/goal review phase-exit R2`
3. 产品负责人接受 R2 残余风险后执行 `/goal work-item WS-R3-001`
4. 每个后续阶段完成后执行阶段出口审查
5. 有真人记录时可选执行 `/goal review human-validation`，但不改变工程状态
```

当前目标覆盖维护及R3、R4、R5，用户已恢复后续工作，可使用：

```text
/goal continue
```
