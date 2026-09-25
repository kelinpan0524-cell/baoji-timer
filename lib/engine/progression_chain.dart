import 'engine.dart';

export '../models/models.dart' show ChainRule;

/// 渐进超负荷规则链引擎（调研条目 15，设计借鉴 LiftLog 的规则链语义，
/// 未搬任何源码；语义文档见 docs/progression-rules.md）。
///
/// 核心思想：
/// - 每条规则带**轴**（次数/重量）、**步长**、**天花板**、**触顶后行为**
///   （进位下一条 / 停住），可编排成有序链；
/// - 会话结束**全场每组都达标**才推进「链中第一条还有空间的规则」；
/// - 经典的「8→12 加重归 8」双阶梯不是硬编码，而是
///   `[次数轴 8→12 触顶进位] → [重量轴 +2.5kg 并把次数复位到 8]`
///   两条规则组合后的**自然涌现**；
/// - [unreachableRuleIndexes] 提供静态可达性检查（学 LiftLog 的
///   unreachableFrom：被 hold 堵点截断的后续规则永远轮不到，UI 可据此置灰）。
///
/// 与旧引擎（evaluateProgression）的关系：
/// - 达标判定口径完全一致（全部正式组达目标次数 + 末组余力容差 1 次）；
/// - 减重分支一致（有组低于 reps_min → 减 5%，负重量同向）；
/// - 差异只在达标后的目标语义：旧引擎固定要求顶格 reps_max，新链的
///   目标次数会从上次成绩出发逐场 +1 爬升（见 chainStateFromHistory）。

/// 链状态：当前重量档 + 当前次数目标。
class ChainState {
  final double weightKg;
  final int targetReps;

  const ChainState({required this.weightKg, required this.targetReps});

  @override
  bool operator ==(Object other) =>
      other is ChainState &&
      other.weightKg == weightKg &&
      other.targetReps == targetReps;

  @override
  int get hashCode => Object.hash(weightKg, targetReps);

  @override
  String toString() => 'ChainState(${weightKg}kg x$targetReps)';
}

/// 规则链：有序规则列表。null/空链时用 [defaultFor] 从旧式
/// ProgressionRule 参数派生默认双阶梯，保证老数据行为连续。
class ProgressionChain {
  final List<ChainRule> rules;

  const ProgressionChain(this.rules);

  /// 从旧式规则参数派生默认双阶梯：
  /// 1. 次数轴：达标目标 +1 次，天花板 = reps_max，触顶进位；
  /// 2. 重量轴：+increment_kg（不设上限），触顶停住，执行后次数复位到 reps_min。
  /// 「加重归下限」由此涌现——派生链与旧引擎的加重行为一致。
  factory ProgressionChain.defaultFor(ProgressionRule rule) => ProgressionChain([
        ChainRule(
          axis: 'reps',
          step: 1,
          ceiling: rule.repsMax.toDouble(),
          advanceOnCap: true,
        ),
        ChainRule(
          axis: 'load',
          step: rule.incrementKg,
          ceiling: null,
          advanceOnCap: false,
          resetRepsTo: rule.repsMin,
        ),
      ]);

  /// 规则优先级：显式配置的 chain > 旧参数派生的默认双阶梯。
  static ProgressionChain of(ProgressionRule rule) =>
      (rule.chain != null && rule.chain!.isNotEmpty)
          ? ProgressionChain(rule.chain!)
          : ProgressionChain.defaultFor(rule);

  /// 规则是否「还有空间」（可再推进一步）。
  bool _hasRoom(ChainRule r, ChainState s) {
    if (r.axis == 'reps') {
      return r.ceiling == null || s.targetReps < r.ceiling!;
    }
    return r.ceiling == null || s.weightKg < r.ceiling!;
  }

  /// 链推进：执行第一条还有空间的规则；无空间且 advanceOnCap 的规则被
  /// 跳过（进位），遇到无空间且 hold 的规则整链停住。
  /// 仅在「全场每组达标」时由 [evaluateChain] 调用。
  ChainState advance(ChainState s, ProgressionRule rule) {
    for (final r in rules) {
      if (_hasRoom(r, s)) {
        if (r.axis == 'reps') {
          return ChainState(
            weightKg: s.weightKg,
            targetReps: s.targetReps + r.step.round(),
          );
        }
        return ChainState(
          weightKg: round05(s.weightKg + r.step),
          targetReps: r.resetRepsTo ?? s.targetReps,
        );
      }
      if (!r.advanceOnCap) {
        return s; // 触顶且停住：整链不再推进
      }
      // 触顶且进位：看下一条规则
    }
    return s; // 全链无空间
  }

  /// 静态可达性（学 LiftLog unreachableFrom）：从链首找第一条有空间的规则
  /// 意味着「无空间且进位」的规则会被跳过，但一旦遇到「无空间且 hold」的
  /// 规则整链停住——它之后的规则永远轮不到。返回这些规则的链下标。
  /// 状态相关的空间判断不在此处（运行时才有），此处只查 hold 堵点截断。
  List<int> unreachableRuleIndexes() {
    final out = <int>[];
    var blocked = false;
    for (var i = 0; i < rules.length; i++) {
      if (blocked) {
        out.add(i);
      } else if (!rules[i].advanceOnCap) {
        // 第一条 hold 规则本身可达（有空间时会被执行），其后全部不可达
        blocked = true;
      }
    }
    return out;
  }
}

/// 链判定结果。
class ChainVerdict {
  /// 'advance'（达标推进）/ 'hold'（保持）/ 'decrease'（减重）
  final String action;
  final ChainState next;
  final String reason;

  const ChainVerdict(this.action, this.next, this.reason);
}

/// 从「上次该动作的正式组」推导当前链状态：
/// - 重量 = 上次最后一组重量（与旧引擎 currentWeight 同源）；
/// - 次数目标 = 上次全部正式组的最小 reps，clamp 到 [reps_min, reps_max]
///   （低于下限视为还没站上下限台阶；高于上限说明超量完成，顶到上限）；
/// - 无历史 → 次数目标 = reps_min（重量由 presetStart 另行填充）。
///
/// 由此旧用户平滑迁移：一直顶格练的人，推导目标 = reps_max = 次数轴
/// 天花板 → 第一次达标就进位加重，与旧行为一致；而从区间内某档起步
/// 的人获得逐场 +1 的平滑爬升。
ChainState chainStateFromHistory(
    List<SetEntry> lastSessionWorkingSets, ProgressionRule rule) {
  final ws = lastSessionWorkingSets
      .where((s) => s.kind == SetKind.working)
      .toList(growable: false);
  if (ws.isEmpty) {
    return ChainState(weightKg: 0, targetReps: rule.repsMin);
  }
  final last = ws.last;
  // 同一次训练的组时间相邻（训练总时长一般 <4 小时），
  // 不能用毫秒相等判断——每组 doneAt 至少差 1ms。
  const sessionWindowMs = 4 * 3600 * 1000;
  final sameSession = ws
      .where((s) =>
          last.doneAt - s.doneAt < sessionWindowMs &&
          s.doneAt >= last.doneAt - sessionWindowMs)
      .toList();
  final minReps =
      sameSession.map((s) => s.reps).fold(sameSession.first.reps, (a, b) => b < a ? b : a);
  final clamped = minReps < rule.repsMin
      ? rule.repsMin
      : (minReps > rule.repsMax ? rule.repsMax : minReps);
  return ChainState(weightKg: last.weightKg, targetReps: clamped);
}

/// 综合判定：会话结束对该动作走一次链。
///
/// 口径（与旧 evaluateProgression 对齐的部分）：
/// - 只看正式组；与当前重量档相差 >5% 的组视为另一档，不参与判定；
/// - **全场每组达标**（每组 reps >= state.targetReps 且末组余力
///   >= rir_target - 1）才推进链；
/// - 有组低于 reps_min → 减重约 5%（负重量同向：辅助配重变得更"负"
///   = 阻力更小，方向语义一致）；
/// - 其余 → hold（重量与次数目标都不动）。
ChainVerdict evaluateChain({
  required ProgressionRule rule,
  required ChainState state,
  required List<SetEntry> workingSets,
}) {
  final ws = workingSets
      .where((s) => s.kind == SetKind.working)
      .toList(growable: false);
  if (ws.isEmpty || state.weightKg == 0) {
    return ChainVerdict(
        'hold', state, '本次无正式组记录，重量保持不变');
  }
  // 只统计当前重量附近的正式组（重量波动 >5% 视为另一档）。
  // 负重量（辅助配重）下 5% 容差同样取绝对值，否则阈值变负、
  // 过滤恒为空 → 辅助器械动作永远判不出渐进。
  final near = ws
      .where((s) =>
          (s.weightKg - state.weightKg).abs() <=
          state.weightKg.abs() * 0.05)
      .toList(growable: false);
  if (near.isEmpty) {
    return ChainVerdict(
        'hold', state, '本次重量与历史档位不同，重量保持不变');
  }

  final allMetTarget = near.every((s) => s.reps >= state.targetReps);
  final lastSet = near.last;
  final lastSetRirOk = lastSet.rir >= rule.rirTarget - 1; // 允许差 1 次余力
  final anyBelowMin = near.any((s) => s.reps < rule.repsMin);

  if (allMetTarget && lastSetRirOk) {
    final chain = ProgressionChain.of(rule);
    final next = chain.advance(state, rule);
    if (next == state) {
      return ChainVerdict(
          'hold', state, '已到规则链尽头（次数 ${state.targetReps} 次、'
              '重量 ${state.weightKg}kg 触顶）→ 保持当前档');
    }
    if (next.weightKg != state.weightKg) {
      return ChainVerdict(
        'advance',
        next,
        '${near.length} 组全部达到 ${state.targetReps} 次目标，'
            '次数轴触顶 → 下次加重至 ${next.weightKg}kg、目标回到 ${next.targetReps} 次',
      );
    }
    return ChainVerdict(
      'advance',
      next,
      '${near.length} 组全部达到 ${state.targetReps} 次目标且末组余力 '
          '${lastSet.rir} 次 → 下次目标 ${next.targetReps} 次（重量不变）',
    );
  }
  if (anyBelowMin) {
    // 减重方向对负重量同样成立：delta 为负 = 正重量更轻 / 辅助配重更多
    final cut = -round05(state.weightKg.abs() * 0.05);
    return ChainVerdict(
      'decrease',
      ChainState(
          weightKg: round05(state.weightKg + cut),
          targetReps: state.targetReps),
      '有组未达到下限 ${rule.repsMin} 次 → 建议减重约 5%（$cut kg），先稳动作',
    );
  }
  return ChainVerdict(
      'hold', state, '完成情况未达 ${state.targetReps} 次目标 → 重量与次数目标保持，继续冲');
}
