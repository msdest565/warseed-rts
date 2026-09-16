# R5 阶段出口证据

2026-09-16：R5-001～005全部DONE。按用户持续完成R4/R5的授权接受工程出口；本目标完成，不进入R6/R7。最终游戏提交049a1b9。

证据全部SIMULATED。HUMAN为可选NOT_RUN；性能要求依D-028暂缓，未声称性能通过。

## 机制与证据

|要求|实现与验证|
|---|---|
|锁定行动与公平目标|EnemyOperationDefinition/Doctrine；开局深拷贝冻结；隐藏总部/经济污染专项|
|真实预备与撤退|总14=8主攻+2侦察+4预备；最早120tick合法条件释放，承诺上限与减员撤退专项|
|三种计划差异|独立typed资源；实际重复轨迹；西矿普通占领/结算2→0→2|
|反应与审计|普通/护送目标切换重置等待；接受/应用/结果分开；战略父子任务关联；部分可见人数隔离|
|玩家复盘|当前可见单位独立观察；真实射击事件；双语最近12条；不暴露内部规则/隐藏结果|

## 完整对局矩阵

每个组合2次重复，15组合共30场；determinism=true、quality=PASS、failures=[]。下表每行是第一次运行，重复结果与指纹完全相同。

|玩家策略|敌方计划|结束tick|结果|纠正次数|
|---|---|---:|---|---:|
|split_axis|central_assault|2576|victory|0|
|concentrated_attack|central_assault|384|victory|1|
|recon_then_commit|central_assault|4800|defeat|0|
|reserve_policy|central_assault|4800|defeat|0|
|no_intervention|central_assault|4800|defeat|0|
|split_axis|western_hook|2642|victory|0|
|concentrated_attack|western_hook|420|victory|1|
|recon_then_commit|western_hook|2026|defeat|0|
|reserve_policy|western_hook|4800|defeat|0|
|no_intervention|western_hook|4800|defeat|0|
|split_axis|western_feint|2476|victory|0|
|concentrated_attack|western_feint|381|victory|1|
|recon_then_commit|western_feint|4800|defeat|0|
|reserve_policy|western_feint|4800|defeat|0|
|no_intervention|western_feint|4800|defeat|0|

分轴与集中各3/3获胜，集中每局1次纠正，其余策略按既有基准9败。局部行动完成不等同会战胜利，不降低旧质量门。

## 发布与迁移

R5-001完整门765.543秒；002为815.577秒；003为1046.924秒；004最终完整门960.707秒，762受验文件无漂移。18套两轮、四关smoke/矩阵、72案例平衡、灰脊完整矩阵、存档与反馈、Windows导出和包哈希通过。

最终包：build/windows/warseed-debug.exe；PCK SHA-256 `DD5692F388A20D90557A8E27E1228D42E4A62E0AA950CB1DBDF2D50C4FD13578`。旧四关兼容，无军团存档格式变更；本局报告只追加可缺省观察字段。

实际证据位于artifacts/r5-004-release3.log、r5-004-frozen3.json、r5-004-full-match-evidence.json、r5-004-focused9.log；真实UI最终记录为artifacts/r5-004-ui5.log，五档中英全部PASS；完整门之后仅ArmyBoard/PrebattlePlanner纯UI布局修复，独立五档及重新导出/包smoke通过，其余受验源码哈希一致。日志为本机产物，提交内保留本摘要与可执行测试。

## 保留风险

- 模板差异、质量门和可复盘性为工程证据，不能证明真人主观乐趣。
- 观察页不推断失去视野后的敌方结果；内部AREA_REACHED仅表示抵达，父任务完成单独记录。
- 当前逐tick审计快照复制未作性能优化，后续恢复性能门时应测量。
- 初次套件曾有一次整卡选择失败，独立用例及随后多轮完整套件未复现，已保留失败详情；首次并行UI有鼠标命中异常，最终独立ui5全部通过。
- 后续R6/R7未获本目标实现授权；D-018/D-020/D-024仍待相应阶段决定。

交付包：`build/playtest-kits/WARSEED-R5-Playable-20260916.zip`，37,793,642 bytes，SHA-256 `F0A407F36E08CF3A275EA55E7A72111011C64EA34942C8964891852286A4CE9A`。17个清单文件逐个核对哈希、ZIP内容及CRC通过。解压运行START_WARSEED_PLAYTEST.cmd。

费用：原累计起点不重置，输入$10/M、输出$50/M、Luna排除。收尾前本地保守估算约725.52美元，上限1000美元；实际最终估算以artifacts/r4-r5-budget-latest.json为准，不冒充账单。
