# WARSEED 四场会战陌生玩家试玩协议

> D-026 后本协议用于可选产品研究，不再完成任何工程、阶段或发布硬门。自动测试不能代替玩家理解、解释和重玩意愿；观察员结论也不能写回权威模拟或改变敌方锁定计划。

样本分组、设备覆盖和放行阈值在 [`P6_7_PLAYTEST_COHORT_PLAN.md`](P6_7_PLAYTEST_COHORT_PLAN.md) 中预注册。执行中不得根据已收集结果降低门槛。

## 1. 试玩目标

每次试玩同时收集两类证据：

- 游戏自动记录：战前编成耗时、首条有效命令、情报后行动、整卡接管/归还、改令、拒绝命令和单体诊断尝试；
- 观察员判断：卡牌与实体对应、将领行为解释、敌方反应解释和第二局意愿。

单局报告只能证明某名测试者在某场会战是否达到标准。四关覆盖、测试者是否真正陌生以及样本量由项目负责人预先确定；没有完整人工证据前，不据此宣称整个 MVP 已通过，也不因单次失败立即扩充内容。

## 2. 准备

观察员可从仓库生成不依赖完整源码目录的 Windows 试玩包：

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\build_playtest_kit.ps1
```

输出目录和 ZIP 位于 `build\playtest-kits\`。包内 `MANIFEST.json` 记录所有必需文件的大小和 SHA-256；分发前保留 ZIP，不要只发送 `.exe`，因为 Godot 项目数据位于同目录的 `.pck`。测试机解压后双击 `START_WARSEED_PLAYTEST.cmd`，输入新的匿名编号即可开始。`START_GREY_RIDGE_PLAYTEST.cmd` 只作为旧包兼容入口保留，两者现在都可记录四场会战。

1. 使用最新 Windows debug export，并通过隔离启动器为每名玩家建立新的匿名会话；不要删除、移动或复用普通玩家的 `user://grey_ridge_roster.json`；
2. 保持中文或英文界面由玩家自行选择，不讲解卡牌层级、A/B/C 方案或敌方计划；
3. 观察员记录玩家是否主动寻找单兵选择、卡牌对应错误和无法解释的 Agent 行为；
4. 除非发生程序错误，试玩中不打开 `F3` 诊断层；若玩家主动尝试，照常记录，不替玩家完成操作；
5. 在玩家下达第一条有效命令或经过 30 秒前，不给予操作提示。

从仓库根目录启动一名新测试者：

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\start_isolated_playtest.ps1 `
  -SessionId "player-001"
```

加入 `-Evaluate` 会在游戏退出后，对本次启动期间新建或改变的每场会战分别询问四项核心观察结论，后三关另询问新增规则理解。已经存在数据的编号默认拒绝启动；只有明确继续同一名玩家时才使用 `-Resume`。同一游戏进程内进入下一场，或之后使用相同编号和 `-Resume`，都会保留该匿名会话自己的战损与成长；未改变的旧记录不会被重复评估。

评估开始时还会要求填写 `宽x高` 分辨率、`mouse/touchpad/other` 主指针设备、`zh_CN/en` 界面语言和预注册匿名席位。这些字段写入评估报告的 `session_context`，用于核对 cohort 环境覆盖，不写入游戏存档。

Godot 用户数据默认位于：

```text
%APPDATA%\Godot\app_userdata\WARSEED\
```

隔离试玩数据位于 `playtest_runs\<匿名编号>\`，普通存档与其他测试者的数据不会被读取或覆盖。

## 3. 四关覆盖安排

每名测试者首先从《灰脊矿区》开始，以证明首次接触、卡牌对应和基础命令是否可理解。随后按《断桥回声》《雾林输线》《黑井反击》顺序继续，用于观察工程路线、情报时效、运输保护、组织恢复、多轴增援和十二卡管理是否能从教程中迁移。

四关不要求在一次坐席内完成。需要休息时，在返回作战区后退出；下一次用同一匿名编号和 `-Resume -Evaluate` 继续。每场会战是独立评估单元，队列汇总会按会战 ID 分开统计覆盖，不能用大量《灰脊矿区》报告冒充后续三关证据。

若项目负责人采用分组测试而非每人四关，必须在测试前写明分组和每关目标样本；仍需保证所有测试者先完成《灰脊矿区》，且四个会战都有陌生玩家记录。脚本不会替项目定义样本量。

## 4. 试玩过程

观察员只记录，不引导玩家选择中央、西部或东部：

1. 玩家自行完成当前会战的战前编成并开始会战；
2. 记录玩家何时理解将领卡、部队卡、战法和地图实体的关系；
3. 出现带可信度的新情报后，观察玩家是否据此改变部署或任务；
4. 观察玩家是否至少一次接管完整部队卡，并在直接控制完成后明确归还；
5. 让玩家完成胜利或失败结算，不以提前退出代替完整一局；
6. 后续会战继续记录玩家能否把既有知识迁移到新战法、更多卡牌和新的任务规则。

## 5. 战后提问

会战结束后再询问以下问题，尽量保留玩家原话：

1. “一张部队卡和地图上的单位是什么关系？”
2. “选一名将领，说说他为什么推进、停下、撤退或等待支援。”
3. “选一次敌方反应，说说你认为它为什么发生。”
4. “你愿意换一种编成、战法、路线或主攻方向再打一局吗？”
5. 对断桥、雾林和黑井再问：“这一关新增的规则怎样改变了你的部署或操作？”

观察员对每项填写 `pass`、`fail` 或 `not_observed`。`not_observed` 表示证据缺失，不能当作通过。《灰脊矿区》的第 5 项由工具自动记为 `not_applicable`，后三关必须填写并保留玩家原话或行为证据。

## 6. 生成评估报告

普通运行会把原始记录写入 `user://playtests/`；隔离启动器会写入 `user://playtest_runs/<匿名编号>/playtests/`。在仓库根目录运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\complete_playtest_report.ps1
```

工具默认读取 `latest_grey_ridge.json`；也可通过 `-ScenarioId broken_bridge`、`fog_forest` 或 `black_well` 读取普通用户目录中对应的最新记录。它会逐项询问观察员，并在同一目录另存带 `_assessment.json` 后缀的报告；原始记录不会被修改。需要指定隔离会话中的某一局时：

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\complete_playtest_report.ps1 `
  -RecordPath "$env:APPDATA\Godot\app_userdata\WARSEED\playtest_runs\player-001\playtests\latest_broken_bridge.json" `
  -ObserverId "observer-01"
```

可使用命令行参数非交互填写观察结论与 `DisplayResolution`、`InputDevice`、`InterfaceLanguage`、`ParticipantGroup`；后三关还需要 `OperationRuleExplanation`。`-RequireContext` 会强制补齐环境字段，`-RequirePass` 会在未通过时返回退出码 2。它们适合批量检查，但不能把预填答案当作人工证据。

## 7. 汇总一批试玩

完成多名玩家的单局评估后，可递归汇总所有 `*_assessment.json`：

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\summarize_playtest_cohort.ps1
```

工具默认读取 `%APPDATA%\Godot\app_userdata\WARSEED\playtest_runs\`，接受四个合法会战 ID，并在其中生成同名的 JSON 与 Markdown 汇总。也可明确指定输入目录和新的输出路径：

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\summarize_playtest_cohort.ps1 `
  -InputDirectory "$env:APPDATA\Godot\app_userdata\WARSEED\playtest_runs" `
  -OutputPath ".\build\playtest-results\warseed-operation-cohort.json"
```

同一会话、会战 ID、开局时间和局号的重复评估只保留 `assessed_unix_time` 最新的一份；不同会战不会互相覆盖。缺少会话身份的旧报告才按原始记录路径去重。汇总会列出分关覆盖、通过/失败/不完整数量、自动与观察项、开局计划、战果、主要操作指标、第二局意愿和优先问题，并单独报告损坏或不兼容的输入。

`all_sessions_pass` 只表示当前收集到的有效单局都通过，不等于 MVP 已验收。工具固定输出 `mvp_gate_claimed = false` 和 `sample_threshold_defined = false`；样本量、玩家是否真正陌生以及是否达到阶段退出条件仍由项目负责人依据预先约定的试玩方案判断，不能由脚本或测试夹具补齐。

## 8. 单局判定

单局只有同时满足以下条件才显示 `pass`：

- 完成一局；
- 30 秒内下达第一条有效将领或部队卡命令；
- 至少一次在新情报后采取玩家行动；
- 至少一次接管整张部队卡并明确归还；
- 未启用单体诊断选择；
- 没有 Agent 抢权导致的命令拒绝；
- 四项观察员判断全部为 `pass`。

任一自动或观察项明确失败时结果为 `fail`；没有明确失败但存在 `not_observed` 时结果为 `incomplete`。胜负本身不是理解门槛，失败局同样可以通过试玩门。

## 9. 数据边界

- 原始战斗日志和观察员评估仍只保存在试玩电脑；玩家在战后主动提交的匿名意见会先本地保存，再发送到明确配置的临时反馈服务器；
- 临时反馈服务器只接收问卷字段和最小构建上下文，不接收原始战斗事件轨迹；
- `ObserverId` 可留空或使用匿名编号，不记录姓名、账号和联系方式；
- 原始日志与评估报告分开保存，避免人工答案覆盖机器证据；
- 队列汇总只读取单局评估并另存新文件，不回写原始日志或评估报告；
- 根据多名玩家重复出现的问题修正卡牌对应、任务透明度或控制负担；通过人工门前不扩充正式部队卡与战法内容。
