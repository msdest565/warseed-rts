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
