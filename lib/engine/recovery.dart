// 肌群恢复度（0-100%）——调研报告候选条目「肌群恢复度热力图」（Fitbod 候选）。
// 纯启发式衰减模型，口径全文见 docs/recovery-heatmap.md。
//
// ## 口径（与代码一致，改动须同步文档）
//
// 1. **输入**：近 7 天内全部 `status='done'` 会话的正式组（热身组不计入，
//    未完成/放弃会话由查询侧排除——见 db.dart 头部统计过滤纪律）；
// 2. **单动作容量**：正式组 重量×次数 之和（自重动作可选按体重折算，
//    与容量统计同口径 setVolumeWithBodyweight）；
// 3. **肌群分摊**：主肌群吃该动作容量的 100%，每个次肌群各吃 30%
//    （次肌群是协同受力，负担小于主动肌；0.3 为经验系数）；
//    exercise_meta 里查不到的动作按「其他」肌群 100% 计；
// 4. **单场疲劳分**：`fatigue = min(1, 肌群容量 / kFatigueRefVolume)`，
//    kFatigueRefVolume = 8000kg（约等于 100kg×8次×10 组的主肌群训练量，
//    打满即该肌群本场归零恢复）；
// 5. **时间衰减**：`exp(-距该场结束小时数 / kRecoveryTauHours)`，
//    τ = 48 小时（半衰期约 33 小时——两天后剩一半疲劳，一周后剩约 8%）；
// 6. **恢复度** = `round(100 × (1 - min(1, 各场疲劳分之和)))`，clamp 0-100；
//    无任何记录 = 100%（完全恢复）。
//
// 该值是粗略体感参考，不是生理测量；只出现在计划页与统计页，
// 绝不进训练中页三要素（当前动作/本组目标/倒计时）。

import 'dart:math' as math;

import 'engine.dart';

/// 单场打满一个肌群恢复预算的参考容量（kg）。
const double kFatigueRefVolume = 8000;

/// 疲劳衰减时间常数（小时）。exp(-t/48)：24h 剩 61%，48h 剩 37%，168h 剩 3%。
const double kRecoveryTauHours = 48;

/// 回看窗口（天）。窗口外残量 <3%，截断。
const int kRecoveryLookbackDays = 7;

/// 次肌群容量分摊系数。
const double kSecondaryMuscleShare = 0.3;

/// 一次已结束训练的恢复度输入。
class RecoverySession {
  /// 会话结束时间（epoch 毫秒）。
  final int endedAtMs;

  /// 动作名 → 该动作本次的正式组。
  final Map<String, List<SetEntry>> workingByName;

  const RecoverySession({required this.endedAtMs, required this.workingByName});
}

/// 计算各肌群恢复度（0-100）。返回键覆盖 kMuscleRegions 全部区域。
/// [now] 缺省取当前时间；[bodyWeightKg] > 0 时自重动作按体重折算容量。
Map<String, int> muscleRecovery({
  required List<RecoverySession> sessions,
  required Map<String, ExerciseMeta> metaByName,
  DateTime? now,
  double bodyWeightKg = 0,
}) {
  final t = now ?? DateTime.now();
  final nowMs = t.millisecondsSinceEpoch;
  final cutoff = nowMs - kRecoveryLookbackDays * 24 * 3600 * 1000;
  final fatigue = <String, double>{
    for (final r in kMuscleRegions) r: 0,
  };

  for (final ses in sessions) {
    if (ses.endedAtMs < cutoff || ses.endedAtMs > nowMs) continue;
    final hoursSince = (nowMs - ses.endedAtMs) / 3600000.0;
    final decay = math.exp(-hoursSince / kRecoveryTauHours);
    final volByMuscle = <String, double>{};
    for (final e in ses.workingByName.entries) {
      final meta = metaByName[e.key];
      final main = meta?.muscles.main ?? '其他';
      final secondary = meta?.muscles.secondary ?? const <String>[];
      var v = 0.0;
      for (final s in e.value) {
        if (s.kind != SetKind.working) continue;
        v += bodyWeightKg > 0
            ? setVolumeWithBodyweight(s,
                exerciseName: e.key, bodyWeightKg: bodyWeightKg)
            : s.volume;
      }
      if (v <= 0) continue;
      volByMuscle[main] = (volByMuscle[main] ?? 0) + v;
      for (final m in secondary) {
        volByMuscle[m] = (volByMuscle[m] ?? 0) + v * kSecondaryMuscleShare;
      }
    }
    for (final entry in volByMuscle.entries) {
      final f = math.min(1.0, entry.value / kFatigueRefVolume) * decay;
      fatigue[entry.key] = (fatigue[entry.key] ?? 0) + f;
    }
  }

  return fatigue.map((k, v) {
    final rec = (100 * (1 - math.min(1.0, v)));
    return MapEntry(k, rec.round().clamp(0, 100));
  });
}
