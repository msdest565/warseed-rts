# R4 阶段出口工程证据

证据：SIMULATED。D-029 已由用户接受；性能按 D-028 暂缓，HUMAN 为 OPTIONAL_NOT_RUN。

当前18场对局审计PASS：8/9组合完成原批准目标，集中投入和侧翼推进各覆盖三种敌方计划。每组合重复两次，完整任务图事件、终局时刻和结果指纹一致。

| 敌方计划 | 我方方案 | 批准目标 | 完成 tick | 强制纠正 | 会战结果 |
|---|---|---|---:|---:|---|
| central_assault | direct_commitment | 完成 | 291 | 0 | 失败 |
| central_assault | flanking_advance | 完成 | 650 | 0 | 失败 |
| central_assault | reconnaissance_first | 完成 | 256 | 0 | 失败 |
| western_hook | direct_commitment | 完成 | 249 | 0 | 失败 |
| western_hook | flanking_advance | 完成 | 540 | 0 | 失败 |
| western_hook | reconnaissance_first | 未完成 | -1 | 1 | 失败 |
| western_feint | direct_commitment | 完成 | 291 | 0 | 失败 |
| western_feint | flanking_advance | 完成 | 650 | 0 | 失败 |
| western_feint | reconnaissance_first | 完成 | 256 | 0 | 失败 |

完成标准覆盖任务图全部EXPLOIT节点，包含后来投入的预备；不能将8个中央目标完成写成8场胜利。该审计只批准中央目标并监测执行，完成后未持续下发全局进攻决策，因此不能代表成熟玩家的整局胜率。正式发布门另有多策略完整对局质量矩阵。

唯一失败组合在tick118由scout卡损失触发一次真实PLAYER RETREAT，命令被接受，主力撤回完成，已损失侦察卡撤退失败；目标仍计失败。其它8组由持续失败/受阻监测器检查，未触发强制纠正；不是以无输入代替监测。滚动6000tick最多1次，低于门槛2次。

复现：Godot --headless --path . --script res://tests/tools/r4_phase_exit_audit.gd。原始日志artifacts/r4-006-exit-final.log，完整JSON artifacts/r4-phase-exit-audit.json。每个组合的初始方案文本、完整事件、纠正凭据与撤退结果均保留。

首次重复不一致及修复详见WS-R4-006。仅保留初始计划Dictionary的诊断运行因延长StringName生命周期掩盖排序问题，不作为最终证据；最终实现对所有相关ID显式按文本排序，最终审计保留JSON字符串。

最终完整发布门819.106秒退出0；18套测试、四关矩阵、存档、Windows导出及包校验通过。五档真实UI通过，702个受验文件SHA256无漂移。R4-006经REVIEWING后DONE，依据用户持续推进授权与D-029接受R4工程出口。PCK SHA256：`0998E2970932942CB3B56FAAEF14C550733442B3487BD2FDFDD5C6C7915C8062`。
