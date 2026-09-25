# 渐进超负荷规则链（调研条目 15）

来源：docs/open-source-research-2026-09-25.md 条目 15（设计借鉴 LiftLog 的规则链语义，未搬任何源码）。
引擎实现：`lib/engine/progression_chain.dart`（纯 Dart，全部可单元测试，见 `test/progression_chain_test.dart`）。

本文档与代码同口径：改引擎必须同步改这里；每条语义都配一个 Example 推演（学 LiftLog「规则文档 + Example 推演」配对写法）。

## 1. 概念

一条**规则链**（`ProgressionChain`）是有序的**规则**（`ChainRule`）列表，存在
`plan_exercises.rule` JSON 的 `chain` 键里（可省略——省略时由旧参数派生默认双阶梯，见 §3）。每条规则带四个属性：

| 属性 | 字段 | 取值 | 含义 |
|---|---|---|---|
| 轴 | `axis` | `reps`（次数）/ `load`（重量） | 这条规则推进哪个维度 |
| 步长 | `step` | 次数轴为整数；重量轴为正 kg | 每次推进的幅度 |
| 天花板 | `ceiling` | 数值或 null（不设限） | 当前轴位 >= 天花板时该规则**无空间** |
| 触顶后行为 | `advanceOnCap` | `true`=进位 / `false`=停住 | 无空间时跳到链中下一条，或整链停住 |
| 次数复位 | `resetRepsTo` | 整数或 null（不变） | 本规则执行后目标次数重置为该值（「加重归 8」的 8） |

另有**链状态**（`ChainState`）= `(重量档, 当前次数目标)`，以及两条执行门规：

- **达标门槛**：会话结束**全场每组都达标**（每组正式组 reps ≥ 当前次数目标，
  且末组余力 RIR ≥ 目标-1）才推进链；推进的是**链中第一条还有空间的规则**。
- **减重分支**：有组低于 `reps_min`（区间下限）→ 减重约 5%，链不推进
  （口径与旧引擎一致；负重量/辅助配重方向语义同旧引擎）。

## 2. 推进算法

```
达标？
├─ 否：有组 < reps_min → 减重 5%；否则 hold（重量与次数目标都不动）
└─ 是：沿链找第一条「还有空间」的规则
   ├─ 找到 reps 规则 → 目标次数 + step
   ├─ 找到 load 规则 → 重量 + step，目标次数 → resetRepsTo（缺省不变）
   ├─ 无空间且 advanceOnCap → 跳过，看下一条
   ├─ 无空间且 hold        → 整链停住（hold）
   └─ 全链无空间           → hold（「规则链尽头」）
```

**可达性检查**（学 LiftLog 的 unreachableFrom）：从链首看，第一条 `advanceOnCap=false`
的规则之后的全部规则永远轮不到（`ProgressionChain.unreachableRuleIndexes()`），
UI 将来可用它把死规则置灰。

## 3. 默认双阶梯（老数据派生）

老 JSON 没有 `chain` 键时，由旧参数派生标准双阶梯：

```
规则1：axis=reps, step=+1, ceiling=reps_max, 触顶进位
规则2：axis=load, step=increment_kg, 无天花板, 触顶停住, reset_reps_to=reps_min
```

### Example A：经典 8→12 加重归 8

规则：`reps_min=8, reps_max=12, increment_kg=2.5`（未配 chain，走派生链）。

| 场次 | 上次成绩 | 推导状态 (重量, 目标) | 判定 | 下次状态 |
|---|---|---|---|---|
| 1 | 60kg×8×8×8 | (60, 8) | 达标 → 规则1 有空间(8<12) | (60, **9**) |
| 2 | 60kg×9×3 | (60, 9) | 达标 → 规则1 | (60, **10**) |
| 3 | 60kg×10×3 | (60, 10) | 达标 → 规则1 | (60, **11**) |
| 4 | 60kg×11×3 | (60, 11) | 达标 → 规则1 | (60, **12**) |
| 5 | 60kg×12×3 | (60, 12) | 规则1 无空间(12≥12)→进位；规则2 有空间 | (**62.5kg, 8**) |
| 6 | 62.5kg×8×3 | (62.5, 8) | 达标 → 规则1 | (62.5, **9**) |

「8 爬到 12、然后加重归 8」不是任何一行硬编码——它是两条规则组合后
**自然涌现**的循环。对应单测：`progression_chain_test.dart` 组「双阶梯涌现」。

### Example B：老用户行为连续性

规则：`reps_min=5, reps_max=8, increment_kg=2.5`；用户一直顶格练 8×3。

- 旧引擎：`全部组 ≥ reps_max=8` → 加重 2.5。
- 新链：上次成绩推导目标 = min(reps)=8 → clamp 到 reps_max=8 → 第一次达标
  规则1 就无空间（8≥8）→ 进位 → 规则2 加重 2.5、复位到 5。

**重量结果与旧引擎一致**（62.5kg）；差异只在目标次数语义——见 §5。

### Example C：区间内爬升（语义升级点）

同一规则（5-8）；上次做了 7×3。

- 旧引擎：7 < 8 → hold（永远要求直接顶格 8）。
- 新链：目标推导为 7 → 达标 → 规则1 → 下次目标 8；再达标 → 进位加重归 5。

重量判定结果相同（hold），但次数目标从「一步登顶」变成逐场 +1 的平滑爬升。

### Example D：天花板停住

配了 `chain: [reps(1, ceiling 8), load(2.5, ceiling 62.5, hold)]` 的动作，
重量到 62.5kg 后再达标 → 规则2 无空间且 hold → 整链停住（文案「规则链尽头」），
不会跳过它去执行不存在的下一条。

## 4. 状态从哪来（无持久化状态机）

链状态**不落库**，每场训练结束时从「上次该动作的正式组」纯函数推导
（`chainStateFromHistory`）：重量 = 上次最后一组；目标次数 = 上次全部正式组的
最小 reps，clamp 到 `[reps_min, reps_max]`；无历史 = reps_min（重量由预设起始重量填）。

好处：不需要新表/新偏好键，换机/重装后状态天然可从历史重建；
代价：用户跨档乱练（>5% 波动）的场次不参与推导（口径与判定同源）。

## 5. 与旧引擎（evaluateProgression）的关系

- `evaluateProgression` 保留（`lib/engine/engine.dart`），现有测试继续有效；
- 生产路径（`_recommendFor` 起组建议、`verdicts` 总结建议）已切到规则链；
- 达标口径、减重口径、±5% 重量档位过滤与旧引擎逐项一致，唯一语义变化
  是 Example C 的次数目标爬升。

## 6. 相关：模板快照与统计纪律（调研条目 14）

渐进判定的数据地基是「训练记录不受模板日后修改影响」。口径（实现见
`lib/db/db.dart` 头注释，迁移见 `upgradeV5to6`）：

- **快照**：开始训练时把模板目标参数（目标组数 `target_sets`、次数区间
  `target_reps_min/max`）整套快照进 `session_exercises`（v6 起）；
  v6 前的老记录三列为 0，消费端回退 `rule` JSON 里的参数——平滑兼容。
- **PROGRAM_SESSION_KEY 的对应物**：本库一次训练由 `sessions.id` 外键串起
  全部动作行与组记录，无需额外键。
- **统计过滤纪律**：一切聚合查询显式 `sessions.status='done'`（排除进行中/
  放弃的会话）、容量统计只认 `kind='working'`（热身组不计）；模板表
  （plans/plan_exercises）天然不进统计。SQL 层锁定见
  `test/db_migration_test.dart`「统计过滤纪律」组。
