# 当前进展与下一步工作计划

> 更新时间：2026-07-30

## 当前状态摘要

WARSEED 已完成项目立项、MVP 范围收敛、系统设计以及 Godot 技术选型。目前处于**文档基线已建立、Godot 工程尚未创建**的阶段。

GitHub 私有仓库：<https://github.com/msdest565/warseed-rts>

当前主线基线：

- 分支：`main`
- 最新提交：`baf8d02`（`docs: define Godot technical baseline`）
- 本地 `main` 与 `origin/main` 已同步；
- 工作区干净；
- 当前没有实现代码、Godot 场景、脚本、插件或游戏资产。

## 已完成工作

### 1. 产品定义

已明确：

- WARSEED 是传统 RTS 直接操作与 AI 指挥链结合的游戏；
- 玩家始终拥有最高控制权；
- 主 AI 参谋长负责目标分发和汇总；
- 工业主管负责经济、建造和生产；
- 战场将领负责编队、侦察、防守、进攻和撤退；
- Agent 必须把任务转化为地图上真实、可观察的单位行动；
- 玩家可以随时接管单位，并明确选择归队、留在原地或持续手动。

对应文档：

- [产品愿景](PRODUCT_VISION.md)
- [MVP 范围](MVP_SCOPE.md)

### 2. MVP 范围

已固定：

- 一张 1v1 小型 2D 地图；
- 一种资源、三种建筑、五类单位；
- 完整 MVP 对局目标为 15—20 分钟；
- 首个垂直切片压缩为 5—8 分钟；
- 首切片只验证“发展矿区、守住区域、攻击目标”三个高层命令；
- 玩家必须能接管导弹车并稳定归队；
- MVP 离线可运行，不依赖语言模型；
- 玩家/Agent 的已知状态过滤和不作弊边界属于 P0。

### 3. 系统架构

已确定以下核心规则：

```text
Input / UI / Agent
        ↓
GameCommand
        ↓
CommandValidator
        ↓
CommandQueue
        ↓
SimulationWorld
        ↓
SimulationEvent / WorldSnapshot
        ↓
Godot presentation / HUD / DebugLayer
```

- `SimulationWorld` 是唯一权威战局状态；
- UI 与 Agent 使用同一套命令类型和验证器；
- Godot 节点、动画和 HUD 不直接修改位置、生命、资源、任务或控制权；
- 玩家直接命令优先于高层命令、Agent 任务和单位默认行为；
- 玩家接管后，Agent 不得自动抢回；
- 任务、控制权转换和受阻原因进入结构化事件日志。

对应文档：[系统设计](SYSTEM_DESIGN.md)

### 4. Godot 技术方案

已批准的技术基线：

| 项目 | 当前决策 |
|---|---|
| 引擎 | Godot 4.6 stable 系列 |
| 精确版本 | 工程创建时锁定最新 `4.6.x-stable` |
| 语言 | typed GDScript |
| 首发平台 | Windows 10/11 x86-64 |
| 游戏形式 | 2D top-down RTS |
| 地图 | `TileMapLayer` + 独立逻辑格 |
| 全局寻路 | `AStarGrid2D` |
| 编队 | 自定义 formation slots |
| 权威模拟 | 固定 10 Hz `SimulationTick` |
| 显示目标 | 60 FPS，快照之间插值 |
| 数据 | typed custom `Resource` + `.tres` |
| 测试 | 纯模拟 + Godot headless 集成/场景测试 |
| GUT | 待技术 spike，不是已采用依赖 |
| Git LFS | 初期不启用 |

对应文档：[Godot 技术方案](TECHNICAL_PLAN.md)

### 5. GitHub 和项目治理

已完成：

- 创建私有仓库 `msdest565/warseed-rts`；
- 使用 `main` 作为默认分支；
- 建立 README、路线图和决策日志；
- 通过 PR #1 将 Godot 技术基线 squash merge 到主线；
- 记录玩家控制权、统一命令边界、无 LLM、Godot 技术栈、固定 tick、导航和数据策略等决策。

对应文档：

- [开发路线图](ROADMAP.md)
- [决策记录](DECISIONS.md)

## 尚未完成

以下内容尚未开始，不能视为已有实现：

- Godot 工程和 `project.godot`；
- 游戏目录、场景和脚本；
- `SimulationWorld`、`SimulationHost` 与固定 tick；
- `GameCommand`、`CommandValidator` 和 `CommandQueue`；
- RTS 相机、点选、框选和右键移动；
- `TileMapLayer`、逻辑格和 `AStarGrid2D`；
- formation slots、separation 和卡住恢复；
- 单位、建筑、采矿、生产和战斗；
- Agent、控制权接管和归队；
- 战争迷雾、敌情记忆和不作弊测试；
- headless 测试 runner、GUT 评估和 CI；
- Windows debug export；
- 美术、音频和正式平衡数值。

## 下一步工作计划

下一次工作从**阶段 1：Godot 技术基线与工程引导**开始，不继续扩写产品范围。

### Step 1：环境与版本锁定

1. 检查本机 Godot 安装路径和实际版本；
2. 确认使用 Godot 4.6 stable 系列；
3. 锁定精确 `4.6.x-stable` patch；
4. 验证命令行和 `--headless` 可运行；
5. 确认 export templates 与编辑器版本一致。

完成标准：版本信息可复现，编辑器、headless 和导出工具使用同一版本。

### Step 2：工程 bootstrap

1. 从独立功能分支创建 `project.godot`；
2. 建立技术方案规定的 `src/`、`scenes/`、`data/`、`assets/`、`tests/` 等目录；
3. 添加与实际工程一致的 Godot `.gitignore`；
4. 创建最小 `GameRoot`、`SimulationHost` 和空白主场景；
5. 创建 Windows debug export preset；
6. 保持 Git LFS 关闭。

完成标准：工程能打开、运行和导出，Git 中不包含 `.godot/` 缓存或构建产物。

### Step 3：固定模拟与统一命令链路

1. 实现 10 Hz `SimulationWorld`；
2. 建立稳定 `EntityId`；
3. 定义首个 `MoveCommand`；
4. 实现 `CommandValidator` 和 `CommandQueue`；
5. 让测试 UI 与测试 Agent 通过同一链路提交移动命令；
6. 发布 `SimulationEvent` 和 `WorldSnapshot`；
7. 表现节点根据快照更新，而非直接持有权威状态。

完成标准：UI 和 Agent 的等价移动命令经过相同验证器，固定 tick 下结果可复现。

### Step 4：导航与编队技术 spike

1. 创建一张最小 `TileMapLayer` 测试地图；
2. 从地图生成独立逻辑格；
3. 使用 `AStarGrid2D` 绕过静态障碍；
4. 实现基础 formation slots；
5. 测试简单 separation、卡住检测和狭窄通道纵队降级；
6. 记录路径请求、失败与模拟 tick 耗时。

完成标准：5 个左右的单位能沿路径移动、通过狭窄区域并重新形成基础队形；不可达目标产生明确原因。

### Step 5：headless 测试与 Windows 导出

1. 评估 GUT 是否兼容锁定的 Godot 版本；
2. 若兼容则固定插件版本，否则建立最小项目测试 runner；
3. 添加命令验证、固定 tick 和导航的首批测试；
4. 验证 headless 退出码；
5. 完成 Windows debug export 冒烟测试。

完成标准：测试可无渲染运行，失败会返回非零退出码，Windows 构建能在干净环境启动。

## 下一次会话的首要任务

> 使用已确定的 Godot 安装路径，完成版本验证和最小工程 bootstrap；不要直接开始完整 RTS 或 Agent 功能。

建议下一次按以下顺序执行：

1. 读取本进展文档和 [Godot 技术方案](TECHNICAL_PLAN.md)；
2. 确认本地 `main` 与 `origin/main` 同步；
3. 创建 `feat/godot-bootstrap` 分支；
4. 完成 Step 1 和 Step 2；
5. 运行工程、headless 和导出验证；
6. 通过 PR 合并工程基线后，再进入固定模拟与统一命令链路。

## 暂停点

本次会话在“文档与技术方案完成、Godot 工程尚未创建”的干净边界暂停。下一次无需重新进行产品总结或引擎比较，可直接从 Godot 环境和工程 bootstrap 开始。
