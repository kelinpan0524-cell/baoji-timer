// 肌群恢复度引擎测试（点名条目四）：衰减数学、容量归一、肌群分摊、
// 窗口截断与统计纪律（热身组不计入）各有锁定。口径见 lib/engine/recovery.dart
// 头注释与 docs/recovery-heatmap.md。
import 'package:flutter_test/flutter_test.dart';
import 'package:baoji_timer/engine/engine.dart';

SetEntry _working(double w, int reps) => SetEntry(
      sessionExerciseId: 1,
      weightKg: w,
      reps: reps,
      rir: 2,
      kind: SetKind.working,
      doneAt: 0,
    );

final _meta = {
  '杠铃卧推': ExerciseMeta(
      '杠铃卧推',
      const MuscleGroups(main: '胸', secondary: ['肩', '手臂']),
      true),
  '未知动作xx': ExerciseMeta(
      '未知动作xx', const MuscleGroups(main: '其他'), false),
};

RecoverySession _session(Map<String, List<SetEntry>> byName,
        {required DateTime ended, DateTime? now}) =>
    RecoverySession(
      endedAtMs: now!.millisecondsSinceEpoch -
          now.difference(ended).inMilliseconds,
      workingByName: byName,
    );

void main() {
  final now = DateTime(2026, 9, 25, 12);

  test('无任何训练记录 → 全肌群 100%', () {
    final rec = muscleRecovery(sessions: const [], metaByName: _meta, now: now);
    for (final r in kMuscleRegions) {
      expect(rec[r], 100, reason: r);
    }
    // 全域键返回（计划页/统计页渲染依赖）
    expect(rec.keys.toSet(), kMuscleRegions.toSet());
  });

  test('刚练完：主肌群吃满容量，次肌群按 0.3 分摊', () {
    // 卧推 60×8×3 = 1440kg：胸 1440、肩 432、手臂 432
    final rec = muscleRecovery(
      sessions: [
        _session({
          '杠铃卧推': [_working(60, 8), _working(60, 8), _working(60, 8)],
        }, ended: now, now: now),
      ],
      metaByName: _meta,
      now: now,
    );
    // 胸：fatigue = 1440/8000 = 0.18 → 82%
    expect(rec['胸'], 82);
    // 肩/臂：432/8000 = 0.054 → 95%（round(94.6)）
    expect(rec['肩'], 95);
    expect(rec['手臂'], 95);
    // 未参与肌群满血
    expect(rec['腿'], 100);
    expect(rec['背'], 100);
  });

  test('48 小时衰减：疲劳过半（τ=48h，exp(-1)≈0.37）', () {
    final rec = muscleRecovery(
      sessions: [
        _session({
          '杠铃卧推': [_working(60, 8), _working(60, 8), _working(60, 8)],
        }, ended: now.subtract(const Duration(hours: 48)), now: now),
      ],
      metaByName: _meta,
      now: now,
    );
    // 0.18 × 0.3679 = 0.0662 → 93%
    expect(rec['胸'], 93);
  });

  test('窗口外截断：7 天前的训练不再计疲劳', () {
    final rec = muscleRecovery(
      sessions: [
        _session({
          '杠铃卧推': [_working(100, 8)],
        },
            ended: now.subtract(const Duration(days: 7, minutes: 1)),
            now: now),
      ],
      metaByName: _meta,
      now: now,
    );
    expect(rec['胸'], 100);
  });

  test('超大容量 clamp：单场即可把肌群打到 0%', () {
    final rec = muscleRecovery(
      sessions: [
        _session({
          '杠铃卧推': [
            for (var i = 0; i < 10; i++) _working(100, 8), // 8000kg
          ],
        }, ended: now, now: now),
      ],
      metaByName: _meta,
      now: now,
    );
    expect(rec['胸'], 0);
  });

  test('多场疲劳叠加：两场半预算同时刻 → 归零', () {
    final rec = muscleRecovery(
      sessions: [
        _session({
          '杠铃卧推': [_working(100, 8), _working(100, 8), _working(100, 8)],
        }, ended: now, now: now),
        _session({
          '杠铃卧推': [_working(100, 8), _working(100, 8), _working(100, 8)],
        }, ended: now, now: now),
      ],
      metaByName: _meta,
      now: now,
    );
    // 每场 2400/8000=0.3，两场叠加 0.6 → 恢复 40%
    expect(rec['胸'], 40);
  });

  test('未知动作按「其他」肌群 100% 计', () {
    final rec = muscleRecovery(
      sessions: [
        _session({
          '词表外怪动作': [_working(100, 10)],
        }, ended: now, now: now),
      ],
      metaByName: _meta, // 无该动作映射
      now: now,
    );
    expect(rec['其他'], lessThan(100));
    expect(rec['胸'], 100);
  });

  test('热身组不计入疲劳（统计纪律）', () {
    final warm = SetEntry(
      sessionExerciseId: 1,
      weightKg: 100,
      reps: 8,
      rir: 2,
      kind: SetKind.warmup,
      doneAt: 0,
    );
    final rec = muscleRecovery(
      sessions: [
        _session({
          '杠铃卧推': [warm],
        }, ended: now, now: now),
      ],
      metaByName: _meta,
      now: now,
    );
    expect(rec['胸'], 100);
  });

  test('负重量（辅助配重）容量为 0，不产生疲劳', () {
    final assist = SetEntry(
      sessionExerciseId: 1,
      weightKg: -30,
      reps: 8,
      rir: 2,
      kind: SetKind.working,
      doneAt: 0,
    );
    final rec = muscleRecovery(
      sessions: [
        _session({
          '杠铃卧推': [assist],
        }, ended: now, now: now),
      ],
      metaByName: _meta,
      now: now,
    );
    expect(rec['胸'], 100);
  });
}
