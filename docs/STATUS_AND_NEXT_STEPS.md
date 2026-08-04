# WARSEED 项目状态与交接

> 最后更新：2026-08-04
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
- 普通点击精确单选、拖框选择框内多个单位、Shift 追加/切换、Alt 点击整组选中当前编队、数字控制组；
- 局部选择下发单体命令并脱离编队跟随；只有完整选中编队时才合并为一条编队命令；
- 新生产单位部署在建筑外侧可通行且不重叠的格子，可立即点选、框选和下达命令；
- 相机平移/缩放、小地图导航；
- Move、Stop、Attack、AttackMove 全部经过统一命令管线；
- 普通点击可选择己方建筑并显示选择框；选中可运行的兵工厂后，可从底部生产栏主动生产全部五类单位；
- 单位能力由数据明确声明：矿车只采矿、工程车只施工/维修，只有侦察车、突击车和导弹车响应攻击、防守与移动攻击；混合选择下达战斗命令不会中断工人任务；
- 防守命令进入地图目标模式，可点击指定防守中心与固定半径；采矿命令可点击指定已知矿区；
- 96x64 逻辑格、支持安全对角移动的 AStarGrid2D、Octile 启发式、可见直线段精简、路径缓存、稳定编队槽位、窄通道纵队和卡住恢复；
- typed 单位/战斗/建筑 Resource catalog 与数据校验；
- 权威弹丸、护甲伤害、追击、AttackMove 自动接敌和死亡 tombstone；单位残骸保留 7 秒后从权威状态、编队和阵营接触记录中清理；
- 单位与建筑共用攻击目标、弹丸和伤害链，玩家可手动摧毁可见敌方建筑；
- 最后一座敌方指挥中心被摧毁后，权威胜负状态立即闭合；
- 玩家基地固定在地图左上区域 `(15, 10)`，敌方基地固定在右下区域 `(86, 54)`。

### 经济与场景状态

- 五类单位数据：矿车、工程车、侦察车、突击车、导弹车；
- 三类建筑数据：指挥中心、无人兵工厂、前线支援站；
- 阵营、建筑、矿点及 immutable snapshots；
- HarvestCommand、ProduceUnitCommand、BuildBuildingCommand、RepairBuildingCommand；
- 矿车实际前往矿区、装载货物、返回指挥中心并卸载后，阵营矿石才增加；
- 玩家和敌方矿车均遵守同一往返采集链；敌方战斗单位的投射物会实际命中并扣除玩家单位生命；
- 工程车按目标位置施工，建筑经历未完工到可运行状态的权威 tick 进度；
- 建筑足迹动态占用逻辑格，改变时触发导航修订；建筑被摧毁后释放占格；
- 工程车可通过权威维修 tick 恢复己方受损建筑生命；
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
- 底部中央扁平指挥栏提供战略、施工、任务控制、指定采矿和五类单位生产入口；左上角金币条实时显示己方资源；
- 战场绘制任务目标、路线和防守半径。

### Gate F/G 技术切片

- 每阵营三态知识格：UNEXPLORED、EXPLORED、VISIBLE；
- faction snapshot 仅含己方、当前可见敌军与固定在 last_seen_position 的 stale contacts；
- 隐藏敌军不能被显式攻击，玩家 Host/输入/表现消费本阵营快照；
- 敌方阶段机依次执行经济、扩张、侦察、争矿、扩军、袭击、撤退和回防，并可循环进入下一轮集结；
- 敌方矿车、工程车、工厂与作战单位通过合法 Harvest/Build/Produce/Move/Attack 命令工作；
- 敌方只攻击当前可见单位/建筑，目标丢失后只前往 last_seen_position，不读取隐藏真值；
- Debug HUD 显示本地化敌方阶段，便于观察、试玩和节奏调优；
- Debug HUD 对比 visible/stale/hidden true-state 数量；
- MissionState 串联发展、防守、攻击、导弹车接管和归队；
- HUD、任务面板、调试信息、单位/建筑/资源名称和阵营名称支持简体中文与英文；
- Godot `.po` 资源与 `TranslationServer` 提供本地化，ESC 菜单可运行时切换中文/英文；
- ESC 菜单提供继续游戏、语言选择与退出游戏，并在打开时暂停 SceneTree；
- 离线运行，不接入 LLM 或联网服务。

## 3. 自动验证

最后已知结果：

```text
WARSEED tests passed: 12 suites
```

覆盖：命令管线、固定 tick、对角最短路径/导航/编队、观测指标、typed data、地图、精确单选/框选/局部编队命令、脱队成员边界、新生产单位与建筑选择、五类单位生产、职责过滤、目标式采矿/防守、敌方实际伤害、残骸超时清理、单位与建筑弹丸战斗、手动胜利、建筑施工/占格/完工/维修、真实矿车装卸往返、对角基地布局、经济与胜负、阵营知识、敌方 last-seen 边界、敌方八阶段经济与作战循环、三项高层任务、接管/归队、工程 UI 命令、右键建筑攻击、中英文即时刷新、完整切片和主场景 UI 控件。

本轮还通过：

- headless editor import；
- 主场景 headless smoke；
- 1280x720 实际渲染截图检查，确认金币条、底部双行指挥栏、小地图和调试 HUD 无重叠；此前阶段亦已检查 1920x1080、2560x1080；
- 中英文 HUD、单位/建筑标签、调试 HUD、小地图与暂停菜单检查；
- `git diff --check`。

Windows Desktop debug export 已在此前具备 `4.6.3.stable.mono` export templates 的环境通过。本机本轮复验时缺少对应模板，因此安装同版本模板后需重新执行 export 与导出 exe smoke；该失败不涉及 GDScript 解析或主场景运行。

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

- 三项委托当前串行执行，暂不支持复杂并发资源冲突和任务图编辑；
- 敌方八阶段循环已有确定性成功路径测试，但真实 5—8 分钟时长、敌人压力和数值尚未经过完整人工试玩调优；
- 图形使用程序化占位绘制，不是最终美术；
- 语言可在运行时切换，但当前不跨启动持久化玩家选择；
- 当前机器缺少 `4.6.3.stable.mono` Windows export templates，需安装后恢复本机导出复验。

## 6. 下一步

1. 对敌方阶段机和现有三项高层委托进行完整人工试玩，形成稳定、可读的 5—8 分钟垂直切片；
2. 校准采集、施工、维修、生产、单位速度、射程、伤害、袭击规模和撤退阈值；
3. 设计任务并发与资源仲裁规则，逐步解除三项委托只能串行执行的限制；
4. 增加 CI 的 headless tests 和 Windows export smoke，并在本机补装同版本 export templates；
5. 迭代选择反馈、命令反馈、程序化占位图形与音效，明确正式美术资产管线；
6. Gate G 人工试玩通过后，再扩展 15—20 分钟完整 MVP。

## 7. 接手规则

- 先运行 12 套件和主场景 smoke，再开始修改；
- 不 reset、clean、checkout 覆盖或丢弃现有工作；
- 每个增量都要完成解析、自动测试、主场景、Windows export、导出 exe smoke 和 `git diff --check`；
- 常规工程决策自行推进；核心产品范围、引擎版本、联网、付费资产、许可证或破坏性 Git 操作必须询问用户。
