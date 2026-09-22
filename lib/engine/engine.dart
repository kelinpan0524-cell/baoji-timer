import '../models/models.dart';

export '../models/models.dart';

/// 纯函数业务引擎：渐进超负荷判定、1RM、容量、肌肉分布。
/// 不依赖 Flutter，全部可单元测试。

/// Epley 公式估算 1RM。
double estimate1RM(double weight, int reps) {
  if (reps <= 0 || weight <= 0) return 0;
  if (reps == 1) return weight;
  return weight * (1 + reps / 30.0);
}

/// 判定一次训练后某动作的渐进结果。
/// [workingSets] 本次训练该动作的正式组；[rule] 该动作的规则。
enum ProgressionAction { increase, hold, decrease }

class ProgressionVerdict {
  final ProgressionAction action;
  final double deltaKg;
  final String reason;

  const ProgressionVerdict(this.action, this.deltaKg, this.reason);
}

ProgressionVerdict evaluateProgression({
  required List<SetEntry> workingSets,
  required double currentWeight,
  required ProgressionRule rule,
}) {
  final ws = workingSets
      .where((s) => s.kind == SetKind.working)
      .toList(growable: false);
  if (ws.isEmpty) {
    return ProgressionVerdict(
        ProgressionAction.hold, 0, '本次无正式组记录，重量保持不变');
  }
  // 只统计当前重量附近的正式组（重量波动 >5% 视为另一档）
  final near = ws
      .where((s) => (s.weightKg - currentWeight).abs() <= currentWeight * 0.05)
      .toList();
  if (near.isEmpty) {
    return ProgressionVerdict(
        ProgressionAction.hold, 0, '本次重量与历史档位不同，重量保持不变');
  }

  final allReachedMax = near.every((s) => s.reps >= rule.repsMax);
  final lastSet = near.last;
  final lastSetRirOk = lastSet.rir >= rule.rirTarget - 1; // 允许差 1 次余力
  final anyBelowMin = near.any((s) => s.reps < rule.repsMin);

  if (allReachedMax && lastSetRirOk) {
    return ProgressionVerdict(
      ProgressionAction.increase,
      rule.incrementKg,
      '${near.length} 组全部达到 ${rule.repsMax} 次，末组余力 ${lastSet.rir} 次 → 下次加重 ${rule.incrementKg}kg',
    );
  }
  if (anyBelowMin) {
    final cut = -_round05(currentWeight * 0.05);
    return ProgressionVerdict(
      ProgressionAction.decrease,
      cut,
      '有组未达到下限 ${rule.repsMin} 次 → 建议减重约 5%（${cut}kg），先稳动作',
    );
  }
  return ProgressionVerdict(
      ProgressionAction.hold, 0, '完成情况在区间内 → 重量保持，继续冲次数');
}

/// 0.5kg 步进取整（引擎与状态机共用）。
double round05(double v) => (v * 2).roundToDouble() / 2;

double _round05(double v) => round05(v);

/// 根据历史记录给出某动作的建议起始重量。
/// 规则：取"最后一次训练"（与末组时间差 <4 小时的组视为同一次训练）
/// → 应用渐进判定；无历史返回 null（由用户首填）。
double? recommendWeight({
  required List<SetEntry> historyWorkingSets,
  required ProgressionRule rule,
}) {
  if (historyWorkingSets.isEmpty) return null;
  final last = historyWorkingSets.last;
  // 同一次训练的组时间相邻（训练总时长一般 <4 小时），
  // 不能用毫秒相等判断——每组 doneAt 至少差 1ms。
  const sessionWindowMs = 4 * 3600 * 1000;
  final sameSession = historyWorkingSets
      .where((s) => last.doneAt - s.doneAt < sessionWindowMs && s.doneAt >= last.doneAt - sessionWindowMs)
      .toList();
  final v = evaluateProgression(
    workingSets: sameSession,
    currentWeight: last.weightKg,
    rule: rule,
  );
  final next = last.weightKg + v.deltaKg;
  return next > 0 ? _round05(next) : _round05(last.weightKg);
}

/// 按动作类型给默认休息秒数。
int defaultRestSec(String kind, {int? compound, int? assistance}) {
  if (kind == 'compound') return compound ?? 180;
  return assistance ?? 120;
}

/// 汇总一次训练的指标。
class SessionStats {
  final double volume;
  final int totalSets;
  final int workingSets;
  final int reps;
  final List<String> exercises;

  const SessionStats({
    required this.volume,
    required this.totalSets,
    required this.workingSets,
    required this.reps,
    required this.exercises,
  });
}

SessionStats sessionStatsFrom(
    Map<int, List<SetEntry>> setsByExercise, List<SessionExercise> order) {
  var volume = 0.0, total = 0, working = 0, reps = 0;
  final names = <String>[];
  for (final se in order) {
    final sets = setsByExercise[se.id] ?? const <SetEntry>[];
    if (sets.isEmpty) continue;
    names.add(se.name);
    for (final s in sets) {
      total++;
      if (s.kind == SetKind.working) {
        working++;
        reps += s.reps;
        volume += s.volume;
      }
    }
  }
  return SessionStats(
      volume: volume,
      totalSets: total,
      workingSets: working,
      reps: reps,
      exercises: names);
}

/// 肌肉群清单（热力图分区）。
const kMuscleRegions = [
  '胸', '肩', '背', '手臂', '腿', '核心', '其他'
];

/// 周内各肌群正式组容量占比（0-1）。
/// 入参为 (动作名, 该动作本周正式组) 的列表。
Map<String, double> muscleLoadShare(
    List<MapEntry<String, List<SetEntry>>> weekWorkingByName,
    Map<String, ExerciseMeta> metaByName) {
  final load = <String, double>{};
  for (final r in kMuscleRegions) {
    load[r] = 0;
  }
  for (final entry in weekWorkingByName) {
    final meta = metaByName[entry.key];
    final main = meta?.muscles.main ?? '其他';
    for (final s in entry.value) {
      load[main] = (load[main] ?? 0) + s.volume;
    }
  }
  final total = load.values.fold(0.0, (a, b) => a + b);
  if (total <= 0) return load;
  return load.map((k, v) => MapEntry(k, v / total));
}

/// PR 检测：本次组是否超过历史最佳重量。
bool isPrWeight(double weight, List<SetEntry> historyBefore) {
  if (historyBefore.isEmpty) return false;
  final best =
      historyBefore.fold(0.0, (m, s) => s.weightKg > m ? s.weightKg : m);
  return weight > best + 0.01;
}

/// 训练日历：给定日期集合渲染辅助。
DateTime parseDate(String d) {
  final p = d.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

String fmtDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 本周一的日期。
DateTime mondayOf(DateTime d) {
  final wd = d.weekday; // 1=Mon
  return DateTime(d.year, d.month, d.day).subtract(Duration(days: wd - 1));
}
