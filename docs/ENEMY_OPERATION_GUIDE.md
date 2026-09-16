# 敌方行动系统开发入口

实时任务以AI_DEVELOPMENT_STATE为准；本文说明接口，不表示R5全部完成。

## 数据与兼容

- `BattleEnemyPlanDefinition`保留现有稳定计划ID。`operation`可指定完整typed行动；未指定时由`EnemyOperationDefinition.compile_legacy`把旧主攻、试探、佯动和后续字段编译为阶段，禁止在世界类增加地图ID分支。
- `EnemyOperationDoctrine`定义最大同时投入兵力、最低承诺时间和撤退阈值。默认资源为`data/ai/enemy_operation_doctrine.tres`；旧计划承诺时间仍然有效。
- `EnemyOperationPhaseDefinition`规定稳定阶段ID、编队角色、最早时刻、地图目标和路线。OPENING固定tick0，REDIRECT和EXPLOIT按时间与己方编队状态触发。
- 目标坐标是开局前编制的地图目标区，不得在运行时用隐藏敌方实体坐标替换。主动接敌必须经过普通视野与攻击校验。

## 权威与快照

`SimulationWorld`在初始化读取玩家本局行为之前调用`lock_plan`，随后只调度世界所有的`EnemyOperationSystem.start/advance`。数据深拷贝，运行中不得更改共享`.tres`。正式命令通过同一校验/应用管线；开局在世界初始化中验证后立即应用，后续入普通队列。

阶段接受命令后为ACTIVE，抵达目标区才COMPLETED，编队损失为FAILED。不要把入队等同于抵达。撤退条件为当前兵力**至阈值或以下**，满足后锁存；不得让战略、反应或拦截逻辑立即将撤退部队派回进攻。

`EnemyOperationSnapshot`和阶段快照递归复制资源。敌方可读本方副本，诊断真值可读全部；正常玩家快照不含隐藏敌方行动。战后解释由R5-004另行设计合法投影，不能直接把诊断对象交给UI。

## 扩展与验证

R5-002接入预备队时必须保留已有部队与资源总量、明确何时解除待命、避免重复分配，且运行时投入仍受准则上限约束。R5-003模板应改变实际轴线、目标或补给影响。R5-004审计须区分命令接受、实际执行和结果，保留事实来源、延迟与成本。

专项入口`tests/tools/enemy_operation_smoke.gd`已纳入`TestSimulationWorld`。修改共享权威系统后运行完整发布门。灰脊短局矩阵同时检查黄金和重复确定性；更新黄金必须保留旧失败日志、解释每类变化，并用反事实或状态差异证明原因。R5-001的反事实恢复了全部18个旧黄金，正式新黄金只反映撤退行为与阶段日志变化。

核心战斗不得依赖外部模型。Luna输出仅为候选代码或审查意见，必须由本地编译、专项、完整门和实际diff验收。

当前R5-002已接入EnemyReservePolicy和纯快照EnemyReserveEvaluator；灰脊8主攻+2试探+4预备，总量仍14。显式预备120tick后按合法触发投入，累计释放上限与准则投入上限同时约束。R5-003～005尚未实施。

## 灰脊正式模板（R5-003）

三份`data/ai/grey_ridge_*.tres`为正式执行资源，BattleEnemyPlanDefinition.operation引用它们；旧字段保留兼容元数据，未指定operation的其他三关仍走legacy编译。改变灰脊阶段请编辑正式资源，不只改旧字段。

| 计划 | 开局投入与轴线 | 后续与补给作用 |
|---|---|---|
| central_assault | 8主攻中央接近区，2侦察西矿 | 4条件预备沿主攻；侦察不能占矿 |
| western_hook | 8主攻经中央转西矿，2侦察中央 | 4条件预备沿西路；普通占领使玩家失去每结算2点西矿收入 |
| western_feint | 8主攻中央，2侦察先到西矿 | 最早240tick且编队空闲后转中央，4条件预备；转向可被真实轨迹观察 |

专项TestEnemyOperationTemplates隔离战斗测量真实路径，三计划各重复一次；补给测试以普通占领/行军/结算覆盖2→0→2，夹具移除守军仅用于归因，不宣称该脚本等同完整对局。完整发布矩阵另跑5策略×3计划×2自然结局，保持旧黄金；原R5-002条件预备、兵力与撤退专项继续运行。Luna建议中的“必定tick240执行”和“预备无视野”不是本项目契约，未采纳。
