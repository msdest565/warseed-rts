# WARSEED

> 一款保留传统 RTS 直接操作、同时让玩家指挥 AI 下属组织的即时战略游戏。

## 项目定位

《WARSEED》的基础体验类似经典即时战略游戏：玩家采集矿石、建设基地、生产部队、争夺矿区，并以摧毁敌方指挥中心取得胜利。

它的核心差异是“可执行的指挥链”：玩家既能亲自框选、移动、集火和撤退，也能向主 AI 参谋长下达“发展经济”“守住区域”“组建部队”“从西侧进攻”等高层目标。参谋长把任务分派给工业主管与战场将领，由他们通过合法游戏命令调度基础单位完成。

玩家始终拥有最终控制权，可以随时接管单位进行微操，并在操作结束后将其归还组织。

## 核心支柱

1. **完整的传统 RTS 操作**：采矿、建造、生产、侦察、战斗与编队。
2. **真正执行任务的 AI 下属**：委托会转化为地图上可见的单位行动。
3. **随时接管、稳定归队**：玩家直接命令永远高于 Agent 当前任务。
4. **透明而可干预的自动化**：玩家能看懂 Agent 的目标、路线、进度和受阻原因。
5. **从操作者成长为指挥官**：单位规模扩大时，挑战从手速自然转向组织与决策。

## MVP 摘要

- 一张 1v1 小型 2D 地图，目标对局时长 15—20 分钟；
- 一种资源：矿石；
- 三种建筑：指挥中心、无人兵工厂、前线支援站；
- 五类基础单位：矿车、工程车、侦察车、突击车、导弹车；
- 一个玩家方主 AI，以及工业主管、战场将领两个下属 Agent；
- 支持结构化高层命令、全权副官模式、玩家接管与单位归队；
- 一个会发展、骚扰、争夺矿区、进攻和回防的规则驱动敌方 AI。

首个可玩垂直切片会先压缩为 5—8 分钟，用“发展矿区、守住区域、攻击目标”三个命令验证核心体验。

## 文档

- [产品愿景](docs/PRODUCT_VISION.md)
- [MVP 范围](docs/MVP_SCOPE.md)
- [系统设计](docs/SYSTEM_DESIGN.md)
- [Godot 技术方案](docs/TECHNICAL_PLAN.md)
- [当前进展、AI 交接与下一步](docs/STATUS_AND_NEXT_STEPS.md)
- [AI handoff（英文简版）](docs/AI_HANDOFF.md)
- [开发路线图](docs/ROADMAP.md)
- [决策记录](docs/DECISIONS.md)

## 当前状态

项目已完成首个离线指挥链技术切片：精确单选与框选、五类单位职责隔离、三类建筑选择与生产、双方独立矿区与真实矿车往返、敌方矿车采矿中自卫、工程车施工/维修、动态建筑占格、对角最短路径、单位与建筑的统一弹丸战斗、纯手动胜利链、阵营知识、玩家接管与归队、三项高层委托，以及敌方经济/扩张/侦察/争矿/扩军/袭击/撤退/回防阶段机均已接入 10 Hz 权威模拟。单矿车可直接领取唯一已知矿区任务，相机支持地图边缘外平移以补偿底部菜单遮挡。左上金币条、底部中央指挥栏、任务路线可视化和中英双语 UI 同步可用；玩家基地位于地图左上角，敌方基地位于右下角。项目自有 runner 当前通过 12 个测试套件和 6 分钟权威切片 smoke，Windows debug export 已在具备同版本模板的环境验证。

这仍不是完整 15—20 分钟 MVP。下一阶段重点是 5—8 分钟垂直切片人工试玩与数值调优、任务并发策略、CI、操作反馈和正式美术。详细状态见[当前进展与下一步](docs/STATUS_AND_NEXT_STEPS.md)。

## 本地复现

1. 安装 Godot `4.6.3-stable`（Windows 推荐 Mono 构建，并安装同版本 export templates）。
2. 克隆仓库并从 Godot Project Manager 导入仓库根目录的 `project.godot`。
3. 按 `F6/F5` 或直接运行项目；主场景为 `scenes/game/game_root.tscn`。

命令行验证（将 `<godot-console>` 替换为本机 Godot console 路径）：

```powershell
& <godot-console> --headless --editor --path . --quit
& <godot-console> --headless --path . --script res://tests/test_runner.gd
& <godot-console> --headless --path . --script res://tests/vertical_slice_smoke.gd
& <godot-console> --headless --path . --quit-after 3
& <godot-console> --headless --path . --export-debug "Windows Desktop" "build/windows/warseed-debug.exe"
& .\build\windows\warseed-debug.exe --headless --quit-after 3
```

`.godot/` 与 `build/` 是本机生成目录，不随 Git 上传。项目运行时不依赖开发机绝对路径、联网服务或 LLM。

## 权利说明

本项目暂未选择开源许可证。除法律另有规定外，未经许可不得复制、修改或分发本仓库内容。
