# WARSEED 项目状态与交接

> 最后更新：2026-08-03
> 本文是当前权威交接入口。产品目标与验收门见 `MVP_SCOPE.md`、`TECHNICAL_PLAN.md` 和 `ROADMAP.md`。

## 1. 当前结论

WARSEED 是 Godot 4.6.3、typed GDScript、Windows-first 的离线 2D RTS。当前仓库已经从移动 spike 推进为可运行的指挥链技术切片，但尚不是完整发布版 MVP。

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
- 点选、框选、Shift 追加、Alt 单选编队成员、数字控制组；
- 相机平移/缩放、小地图导航；
- Move、Stop、Attack、AttackMove 全部经过统一命令管线；
- 96x64 逻辑格、AStarGrid2D 静态导航、路径缓存、稳定编队槽位、窄通道纵队和卡住恢复；
- typed 单位/战斗/建筑 Resource catalog 与数据校验；
- 权威弹丸、护甲伤害、追击、AttackMove 自动接敌和死亡 tombstone。

### 经济与场景状态

- 五类单位数据：矿车、工程车、侦察车、突击车、导弹车；
- 三类建筑数据：指挥中心、无人兵工厂、前线支援站；
- 阵营、建筑、矿点及 immutable snapshots；
- HarvestCommand、ProduceUnitCommand、固定 tick 采集与生产；
- 指挥中心存活驱动的权威阵营胜负状态。

### Gate D：任务与控制权

- TaskState/TaskSnapshot 具有 typed kind、phase、lifecycle、blocked reason、目标、半径、路线、参与者和进度；
- PLAYER_CONTROLLED、AGENT_ASSIGNED、TEMPORARILY_OVERRIDDEN、UNASSIGNED、DISABLED 控制状态；
- 玩家直接命令立即保留接管权，任务进入 BLOCKED，Agent 命令返回 AGENT_OVERRIDE_BLOCKED；
- RETURN、STAY、JOIN、MANUAL disposition；
- RETURN 使用 A* 到安全 rejoin point，不瞬移，完成后恢复 formation slot、Agent 和任务；
- 导弹车接管及归队进入 MissionState/MissionSnapshot。

### Gate E：三个高层命令

- StrategicOrderCommand：DEVELOP_RESOURCE、DEFEND_AREA、ATTACK_TARGET；
- TaskControlCommand：PAUSE、RESUME、CANCEL；
- 工业任务通过合法 HarvestCommand 与 ProduceUnitCommand 完成采集和第二矿车；
- 防守任务显示半径并在目标越界时停止追击、返回防区；
- 攻击任务通过合法 AttackCommand 完成推进、交战、损失阈值撤退或完成；
- 左侧任务面板显示目标、阶段、生命周期、路线、参与者、进度和阻塞原因；
- 战场绘制任务目标、路线和防守半径。

### Gate F/G 技术切片

- 每阵营三态知识格：UNEXPLORED、EXPLORED、VISIBLE；
- faction snapshot 仅含己方、当前可见敌军与固定在 last_seen_position 的 stale contacts；
- 隐藏敌军不能被显式攻击，玩家 Host/输入/表现消费本阵营快照；
- 延时规则敌方袭击队只攻击当前可见单位；目标丢失后只前往 last_seen_position；
- Debug HUD 对比 visible/stale/hidden true-state 数量；
- MissionState 串联发展、防守、攻击、导弹车接管和归队；
- ESC 菜单提供 Continue 与 Exit Game，并在打开时暂停 SceneTree；
- 离线运行，不接入 LLM 或联网服务。

## 3. 自动验证

最后已知结果：

```text
WARSEED tests passed: 12 suites
```

覆盖：命令管线、固定 tick、导航/编队、观测指标、typed data、地图、玩家输入、弹丸战斗、经济与胜负、阵营知识、敌方 last-seen 边界、三项高层任务、接管/归队、完整切片和主场景 UI 控件。

本轮还通过：

- headless editor import；
- 主场景 headless smoke；
- Windows Desktop debug export；
- `git diff --check`。

标准 Windows 命令（从仓库根目录执行）：

```powershell
& <godot-console> --headless --editor --path . --quit
& <godot-console> --headless --path . --script res://tests/test_runner.gd
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

- 建筑施工、工程车维修和资源返仓动画/空间过程尚未实现；当前采集按固定 tick 结算；
- 战斗目标目前是单位，建筑尚未接入统一弹丸伤害，因此“玩家手动摧毁敌方指挥中心”的完整胜利链未闭合；
- 敌方 AI 目前只有一支延时规则袭击队，不是完整发展/侦察/争矿/扩军阶段机；
- 三项委托当前串行执行，暂不支持复杂并发资源冲突和任务图编辑；
- 5-8 分钟流程已具备确定性成功路径测试，但真实时长、敌人压力和数值尚未经过完整人工试玩调优；
- 图形使用程序化占位绘制，不是最终美术；
- Windows 导出已生成并验证，新增任务 UI 仍需要下一轮在不同分辨率进行人工图形交互检查。

## 6. 下一步

1. 让建筑进入攻击/弹丸/伤害链，闭合纯手动摧毁指挥中心的胜利流程；
2. 实现工程车施工、建筑占格、维修与真实矿车往返；
3. 扩展敌方阶段机并将袭击、争矿、进攻和回防调为稳定 5-8 分钟切片；
4. 在 1280x720、1920x1080 和超宽屏实际操作任务面板、ESC 菜单、接管/归队流程；
5. 增加 CI 的 headless tests 和 Windows export smoke；
6. Gate G 人工试玩通过后，再扩展 15-20 分钟完整 MVP。

## 7. 接手规则

- 先运行 12 套件和主场景 smoke，再开始修改；
- 不 reset、clean、checkout 覆盖或丢弃现有工作；
- 每个增量都要完成解析、自动测试、主场景、Windows export、导出 exe smoke 和 `git diff --check`；
- 常规工程决策自行推进；核心产品范围、引擎版本、联网、付费资产、许可证或破坏性 Git 操作必须询问用户。
