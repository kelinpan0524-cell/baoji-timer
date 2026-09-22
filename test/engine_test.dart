import 'package:flutter_test/flutter_test.dart';
import 'package:baoji_timer/engine/engine.dart';

SetEntry _ws(double w, int reps, {int rir = 2, int at = 1000}) => SetEntry(
      sessionExerciseId: 1,
      weightKg: w,
      reps: reps,
      rir: rir,
      kind: SetKind.working,
      doneAt: at,
    );

void main() {
  group('渐进超负荷判定', () {
    const rule = ProgressionRule(
        repsMin: 5, repsMax: 8, incrementKg: 2.5, rirTarget: 2, workingSets: 3);

    test('三组全部达到上限且末组余力充足 → 加重', () {
      final v = evaluateProgression(
        workingSets: [_ws(80, 8), _ws(80, 8), _ws(80, 8, rir: 2)],
        currentWeight: 80,
        rule: rule,
      );
      expect(v.action, ProgressionAction.increase);
      expect(v.deltaKg, 2.5);
    });

    test('末组余力不足 → 保持', () {
      final v = evaluateProgression(
        workingSets: [_ws(80, 8), _ws(80, 8), _ws(80, 8, rir: 0)],
        currentWeight: 80,
        rule: rule,
      );
      expect(v.action, ProgressionAction.hold);
    });

    test('有组低于下限 → 减重约 5%', () {
      final v = evaluateProgression(
        workingSets: [_ws(80, 8), _ws(80, 4), _ws(80, 8)],
        currentWeight: 80,
        rule: rule,
      );
      expect(v.action, ProgressionAction.decrease);
      expect(v.deltaKg, lessThan(0));
      expect(v.deltaKg, -4.0); // 80*5% = 4
    });

    test('区间内完成 → 保持', () {
      final v = evaluateProgression(
        workingSets: [_ws(80, 7), _ws(80, 6), _ws(80, 8)],
        currentWeight: 80,
        rule: rule,
      );
      expect(v.action, ProgressionAction.hold);
      expect(v.deltaKg, 0);
    });

    test('无正式组 → 保持且不崩溃', () {
      final v = evaluateProgression(
        workingSets: [_ws(40, 5, rir: 3).copyWarm()],
        currentWeight: 80,
        rule: rule,
      );
      expect(v.action, ProgressionAction.hold);
    });

    test('recommendWeight：无历史返回 null，有历史按判定推下一重量', () {
      expect(recommendWeight(historyWorkingSets: [], rule: rule), isNull);
      final rec = recommendWeight(
        historyWorkingSets: [
          _ws(80, 8, at: 1),
          _ws(80, 8, at: 2),
          _ws(80, 8, at: 3)
        ],
        rule: rule,
      );
      expect(rec, 82.5);
    });

    test('回归：同一次训练的多组都参与判定（不是只看最后一组）', () {
      // 同一次训练内：8、4、8 → 有组破下限 → 应减重
      // 若错误地只看末组（8次）会误判为加重
      final hourMs = 3600 * 1000;
      final rec = recommendWeight(
        historyWorkingSets: [
          _ws(80, 8, at: 1000),
          _ws(80, 4, at: 2 * hourMs),
          _ws(80, 8, at: 4 * hourMs),
        ],
        rule: rule,
      );
      expect(rec, 76.0); // 80 - 5% = 76
    });

    test('回归：超过 4 小时窗口视为两次训练，只看最近一次', () {
      final hourMs = 3600 * 1000;
      final rec = recommendWeight(
        historyWorkingSets: [
          _ws(80, 4, at: 1000), // 上一次的失手组，不应影响本次判定
          _ws(80, 8, at: 10 * hourMs),
          _ws(80, 8, at: 10 * hourMs + 60),
          _ws(80, 8, at: 10 * hourMs + 120),
        ],
        rule: rule,
      );
      expect(rec, 82.5); // 最近一次三组全 8 → 加重
    });
  });

  group('1RM 与 PR', () {
    test('Epley 估算', () {
      expect(estimate1RM(100, 1), 100);
      expect(estimate1RM(100, 6), closeTo(120, 0.01));
      expect(estimate1RM(0, 5), 0);
    });

    test('PR 检测：超过历史最佳重量才算', () {
      final history = [_ws(80, 8), _ws(82.5, 5)];
      expect(isPrWeight(82.5, history), isFalse); // 平记录不算
      expect(isPrWeight(85, history), isTrue);
      expect(isPrWeight(80, []), isFalse); // 无历史（首次）不算
    });
  });

  group('容量与肌群', () {
    test('sessionStats：热身组不计容量', () {
      final stats = sessionStatsFrom({
        1: [
          _ws(20, 8).asWarm(),
          _ws(80, 8),
          _ws(80, 6),
        ],
      }, [
        const SessionExercise(
            sessionId: 1,
            id: 1,
            name: '卧推',
            orderIdx: 0,
            kind: 'compound',
            rule: ProgressionRule(repsMin: 5, repsMax: 8)),
      ]);
      expect(stats.volume, 80 * 8 + 80 * 6);
      expect(stats.workingSets, 2);
      expect(stats.reps, 14);
    });

    test('muscleLoadShare 按主肌群聚合且归一化', () {
      const meta = {
        '卧推': ExerciseMeta('卧推', MuscleGroups(main: '胸'), true),
        '划船': ExerciseMeta('划船', MuscleGroups(main: '背'), false),
      };
      final share = muscleLoadShare([
        MapEntry('卧推', [_ws(80, 10)]), // 800
        MapEntry('划船', [_ws(50, 10)]), // 500
      ], meta);
      expect(share['胸'], closeTo(800 / 1300, 0.001));
      expect(share['背'], closeTo(500 / 1300, 0.001));
      final sum = share.values.fold(0.0, (a, b) => a + b);
      expect(sum, closeTo(1.0, 0.001));
    });

    test('未知动作归入「其他」不崩溃', () {
      final share = muscleLoadShare([
        MapEntry('神秘动作', [_ws(30, 10)]),
      ], const {});
      expect(share['其他'], closeTo(1.0, 0.001));
    });
  });

  group('日期工具', () {
    test('mondayOf 返回周一零点', () {
      final d = DateTime(2026, 9, 23); // 周三
      final m = mondayOf(d);
      expect(m.weekday, DateTime.monday);
      expect(m, DateTime(2026, 9, 21));
    });

    test('fmtDate/parseDate 往返一致', () {
      final d = DateTime(2026, 9, 5);
      expect(fmtDate(d), '2026-09-05');
      expect(parseDate(fmtDate(d)), d);
    });
  });
}

extension _SetExt on SetEntry {
  SetEntry copyWarm() => SetEntry(
        sessionExerciseId: sessionExerciseId,
        weightKg: weightKg,
        reps: reps,
        rir: rir,
        kind: SetKind.warmup,
        doneAt: doneAt,
      );

  SetEntry asWarm() => copyWarm();
}
