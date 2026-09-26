// 平台期渐进提醒（2026-09-26 Arono：薄肌渐进超负荷主动提示）引擎单测。
// plateauOf：同一动作按训练分组取各次最大正式组重量，从最近往回数
// 连续停留同一重量的次数与天数；阈值 = 连续 ≥3 次，或 ≥2 次且 ≥12 天。
import 'package:flutter_test/flutter_test.dart';
import 'package:baoji_timer/engine/engine.dart';

SetEntry _set(
  int sessionExerciseId,
  double weight,
  int reps,
  int doneAt, {
  String kind = 'working',
}) =>
    SetEntry(
      sessionExerciseId: sessionExerciseId,
      weightKg: weight,
      reps: reps,
      kind: kind,
      doneAt: doneAt,
    );

void main() {
  const day = 86400000;
  // 三个训练日：每次 3 组正式组，都在 60kg
  List<SetEntry> sessionsAt60({
    required int firstAtDaysAgo,
    required int gapDays,
    required int reps,
    int count = 3,
  }) {
    final out = <SetEntry>[];
    for (var i = 0; i < count; i++) {
      for (var s = 0; s < 3; s++) {
        // 负时间戳 = 距今 N 天前（纯函数只做差值，绝对值无意义）
        out.add(_set(100 + i, 60, reps,
            -(firstAtDaysAgo - i * gapDays) * day + s * 60000));
      }
    }
    return out;
  }

  test('连续 3 次同重量 → 平台期（sessions=3，天数=首末跨度）', () {
    final h = sessionsAt60(firstAtDaysAgo: 14, gapDays: 5, reps: 6);
    final info = plateauOf(h, repsMax: 8);
    expect(info, isNotNull);
    expect(info!.weightKg, 60);
    expect(info.sessions, 3);
    expect(info.days, 10, reason: '首(14天前)→末(4天前) 跨 10 天');
    expect(info.hitTop, isFalse, reason: '次数 6 < 目标上限 8');
  });

  test('2 次但跨度 ≥12 天 → 平台期（薄肌"两周"口径）', () {
    final h = sessionsAt60(firstAtDaysAgo: 15, gapDays: 13, reps: 8, count: 2);
    final info = plateauOf(h, repsMax: 8);
    expect(info, isNotNull);
    expect(info!.sessions, 2);
    expect(info.days, 13);
    expect(info.hitTop, isTrue, reason: '最近一次次数 8 ≥ 上限 8 → 可直接加重');
  });

  test('2 次且只隔 3 天 → 未到阈值，不打扰', () {
    final h = sessionsAt60(firstAtDaysAgo: 5, gapDays: 3, reps: 6, count: 2);
    expect(plateauOf(h, repsMax: 8), isNull);
  });

  test('最近已加重 → 停滞链断在旧重量上，次数不足 → 不提醒', () {
    // 远古 3 次 55kg + 最近 1 次 60kg：最近只有 1 次同重量
    final h = [
      ...sessionsAt60(firstAtDaysAgo: 30, gapDays: 5, reps: 6)
          .map((e) => e.weightKg == 60
              ? _set(e.sessionExerciseId, 55, e.reps, e.doneAt)
              : e),
      _set(200, 60, 6, -2 * day),
    ];
    expect(plateauOf(h, repsMax: 8), isNull,
        reason: '已进步到新重量，旧重量的停滞不该再提醒');
  });

  test('训练内重量取最大正式组：某次冲过 62.5 → 链断，不误报 60 停滞', () {
    final h = [
      ...sessionsAt60(firstAtDaysAgo: 12, gapDays: 4, reps: 6),
      _set(300, 62.5, 5, -1 * day),
    ];
    final info = plateauOf(h, repsMax: 8);
    expect(info, isNull, reason: '最近一次顶格 62.5，60kg 的连续链已被打断');
  });

  test('空历史 / 单次训练 → null', () {
    expect(plateauOf(const [], repsMax: 8), isNull);
    expect(plateauOf([_set(1, 60, 8, day)], repsMax: 8), isNull);
  });

  test('同训练多组取最大重量与最大次数（hitTop 判定用整次最好成绩）', () {
    final h = [
      for (var i = 0; i < 3; i++) ...[
        _set(100 + i, 60, 5, -(20 - i * 5) * day),
        _set(100 + i, 60, 8, -(20 - i * 5) * day + 60000),
      ],
    ];
    final info = plateauOf(h, repsMax: 8);
    expect(info, isNotNull);
    expect(info!.hitTop, isTrue, reason: '最好一组做到 8 = 目标上限');
  });

  test('组内混重：顶格取最大重量，hitTop 只看顶格重量的次数', () {
    final h = [
      // 每次训练：60×5 + 62.5×3——顶格是 62.5、顶格次数 3
      for (var i = 0; i < 3; i++) ...[
        _set(100 + i, 60, 8, -(20 - i * 6) * day),
        _set(100 + i, 62.5, 3, -(20 - i * 6) * day + 60000),
      ],
    ];
    final info = plateauOf(h, repsMax: 8);
    expect(info, isNotNull);
    expect(info!.weightKg, 62.5, reason: '组内取最大重量为该次顶格');
    expect(info.hitTop, isFalse,
        reason: '60kg 那组做到 8 次不算——轻于顶格的退让组不计入 hitTop');
  });

  test('负重量（辅助配重）同样可判平台期', () {
    final h = [
      for (var i = 0; i < 3; i++)
        _set(100 + i, -30, 10, -(14 - i * 5) * day),
    ];
    final info = plateauOf(h, repsMax: 12);
    expect(info, isNotNull);
    expect(info!.weightKg, -30);
    expect(info.sessions, 3);
    expect(info.hitTop, isFalse, reason: '顶格次数 10 < 目标 12');
  });
}
