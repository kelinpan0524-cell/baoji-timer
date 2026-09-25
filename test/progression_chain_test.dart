// 渐进超负荷规则链引擎测试（调研条目 15）。
// 核心断言：「8→12 加重归 8」双阶梯由规则链自然涌现；达标门槛、
// 触顶行为、减重分支、静态可达性与 JSON 兼容各有锁定。
import 'package:flutter_test/flutter_test.dart';
import 'package:baoji_timer/engine/engine.dart';

SetEntry _set(double w, int reps, {int rir = 2, int at = 1000}) => SetEntry(
      sessionExerciseId: 1,
      weightKg: w,
      reps: reps,
      rir: rir,
      kind: SetKind.working,
      doneAt: at,
    );

/// 全达标的一场：n 组同重量同次数。
List<SetEntry> _session(double w, int reps, {int n = 3, int rir = 2}) => [
      for (var i = 0; i < n; i++) _set(w, reps, rir: rir, at: 1000 + i),
    ];

void main() {
  group('双阶梯涌现：8→12 加重归 8', () {
    // reps_min=8, reps_max=12, increment=2.5
    final rule =
        const ProgressionRule(repsMin: 8, repsMax: 12, incrementKg: 2.5);

    ChainVerdict run(List<SetEntry> lastSession) {
      final state = chainStateFromHistory(lastSession, rule);
      return evaluateChain(rule: rule, state: state, workingSets: lastSession);
    }

    test('60kg×8 全达标 → 次数目标升到 9，重量不变', () {
      final v = run(_session(60, 8));
      expect(v.action, 'advance');
      expect(v.next.weightKg, 60);
      expect(v.next.targetReps, 9);
      expect(v.reason, contains('9 次'));
    });

    test('逐场爬升 9→10→11→12，全程重量不变', () {
      for (final reps in [9, 10, 11]) {
        final v = run(_session(60, reps));
        expect(v.next.weightKg, 60, reason: 'reps=$reps 不应加重');
        expect(v.next.targetReps, reps + 1, reason: 'reps=$reps');
      }
      // 爬到 12 后再达标即触顶进位（下一用例专门断言）
    });

    test('次数轴触顶 12 后进位：加重 2.5kg、目标复位回 8（涌现）', () {
      final v = run(_session(60, 12));
      expect(v.next.weightKg, 62.5);
      expect(v.next.targetReps, 8);
      expect(v.reason, contains('62.5kg'));
      expect(v.reason, contains('8 次'));
    });

    test('加重后从 8 重新爬升（下一轮）', () {
      final v = run(_session(62.5, 8));
      expect(v.next.weightKg, 62.5);
      expect(v.next.targetReps, 9);
    });
  });

  group('与旧引擎行为兼容（默认派生链）', () {
    // 老数据 rule 无 chain：一直顶格练的用户首次判定应与旧 evaluateProgression 同重。
    final rule = const ProgressionRule(repsMin: 5, repsMax: 8);

    test('5-8 动作顶格 8×3 达标 → 加重 2.5（与旧判定重量一致）', () {
      final last = _session(60, 8);
      final state = chainStateFromHistory(last, rule);
      expect(state.targetReps, 8); // 上次最小 reps=8 → 顶到 repsMax
      final v = evaluateChain(rule: rule, state: state, workingSets: last);
      expect(v.next.weightKg, 62.5);
      expect(v.next.targetReps, 5); // 加重归下限
      // 旧引擎同场对比：重量增量一致
      final old = evaluateProgression(
          workingSets: last, currentWeight: 60, rule: rule);
      expect(old.action, ProgressionAction.increase);
      expect(old.deltaKg, 2.5);
    });

    test('区间内未达目标（7×3）→ 重量保持、次数目标爬到 8', () {
      final v = evaluateChain(
        rule: rule,
        state: const ChainState(weightKg: 60, targetReps: 7),
        workingSets: _session(60, 7),
      );
      expect(v.action, 'advance');
      expect(v.next.weightKg, 60);
      expect(v.next.targetReps, 8);
    });

    test('有组低于下限 → 减重约 5%', () {
      final v = evaluateChain(
        rule: rule,
        state: const ChainState(weightKg: 60, targetReps: 5),
        workingSets: [_set(60, 4), _set(60, 5), _set(60, 5)],
      );
      expect(v.action, 'decrease');
      expect(v.next.weightKg, 57); // 60 - 5%
      expect(v.next.targetReps, 5);
    });

    test('末组余力不足（rir 0 < rirTarget-1）→ 不加重', () {
      final v = evaluateChain(
        rule: rule,
        state: const ChainState(weightKg: 60, targetReps: 5),
        workingSets: _session(60, 8, rir: 0),
      );
      expect(v.action, 'hold');
      expect(v.next.weightKg, 60);
    });

    test('全部组与历史档位不同（>5% 波动）→ hold', () {
      final v = evaluateChain(
        rule: rule,
        state: const ChainState(weightKg: 60, targetReps: 5),
        workingSets: _session(80, 8),
      );
      expect(v.action, 'hold');
      expect(v.reason, contains('档位'));
    });

    test('无正式组 → hold', () {
      final v = evaluateChain(
        rule: rule,
        state: const ChainState(weightKg: 60, targetReps: 5),
        workingSets: [_set(60, 8, at: 1).copyWithKind(SetKind.warmup)],
      );
      expect(v.action, 'hold');
    });
  });

  group('chainStateFromHistory', () {
    final rule = const ProgressionRule(repsMin: 5, repsMax: 8);
    test('无历史 → 重量 0、目标 = repsMin', () {
      final s = chainStateFromHistory(const [], rule);
      expect(s.weightKg, 0);
      expect(s.targetReps, 5);
    });

    test('热身组不参与推导', () {
      final s = chainStateFromHistory(
          [_set(60, 8, at: 1).copyWithKind(SetKind.warmup)], rule);
      expect(s.weightKg, 0);
    });

    test('多档混合只看同场次、取最小 reps 并 clamp', () {
      // 同一场（时间相邻）：8/6/6 → 最小 6
      final same = [
        _set(60, 8, at: 1000),
        _set(60, 6, at: 2000),
        _set(60, 6, at: 3000),
      ];
      expect(chainStateFromHistory(same, rule).targetReps, 6);
      // 低于下限 clamp 到 repsMin
      final below = [_set(60, 3, at: 1000)];
      expect(chainStateFromHistory(below, rule).targetReps, 5);
      // 高于上限 clamp 到 repsMax
      final above = [_set(60, 12, at: 1000)];
      expect(chainStateFromHistory(above, rule).targetReps, 8);
      // 4 小时窗口外是另一场，不参与最小值
      final twoSessions = [
        _set(60, 5, at: 1000),
        _set(60, 8, at: 1000 + 5 * 3600 * 1000),
      ];
      final s = chainStateFromHistory(twoSessions, rule);
      expect(s.weightKg, 60); // 最后一组重量
      expect(s.targetReps, 8); // 只统计最近一场
    });
  });

  group('自定义链：天花板与触顶行为', () {
    test('重量轴设天花板，触顶 hold 停住', () {
      final rule = const ProgressionRule(
        repsMin: 5,
        repsMax: 8,
        chain: [
          ChainRule(axis: 'reps', step: 1, ceiling: 8),
          ChainRule(
              axis: 'load', step: 2.5, ceiling: 62.5, advanceOnCap: false),
        ],
      );
      // 60 → 达标 → 62.5
      final v1 = evaluateChain(
        rule: rule,
        state: const ChainState(weightKg: 60, targetReps: 8),
        workingSets: _session(60, 8),
      );
      expect(v1.next.weightKg, 62.5);
      // 62.5 已到天花板：再达标也停在 62.5
      final v2 = evaluateChain(
        rule: rule,
        state: const ChainState(weightKg: 62.5, targetReps: 8),
        workingSets: _session(62.5, 8),
      );
      expect(v2.action, 'hold');
      expect(v2.next.weightKg, 62.5);
      expect(v2.reason, contains('规则链尽头'));
    });

    test('resetRepsTo 缺省时加重不改变次数目标', () {
      final rule = const ProgressionRule(
        repsMin: 5,
        repsMax: 8,
        chain: [
          ChainRule(axis: 'load', step: 2.5, ceiling: null,
              advanceOnCap: false, resetRepsTo: null),
        ],
      );
      final v = evaluateChain(
        rule: rule,
        state: const ChainState(weightKg: 60, targetReps: 6),
        workingSets: _session(60, 6),
      );
      expect(v.next.weightKg, 62.5);
      expect(v.next.targetReps, 6);
    });
  });

  group('静态可达性 unreachableRuleIndexes', () {
    test('hold 规则之后的规则永远轮不到', () {
      final chain = ProgressionChain([
        const ChainRule(axis: 'reps', step: 1, ceiling: 12),
        const ChainRule(axis: 'load', step: 2.5, advanceOnCap: false),
        const ChainRule(axis: 'load', step: 5), // 被 hold 堵死
      ]);
      expect(chain.unreachableRuleIndexes(), [2]);
    });

    test('全进位链无不可达', () {
      final chain = ProgressionChain([
        const ChainRule(axis: 'reps', step: 1, ceiling: 12),
        const ChainRule(axis: 'load', step: 2.5),
      ]);
      expect(chain.unreachableRuleIndexes(), isEmpty);
    });

    test('链首 hold：其后全部不可达', () {
      final chain = ProgressionChain([
        const ChainRule(axis: 'load', step: 2.5, advanceOnCap: false),
        const ChainRule(axis: 'reps', step: 1),
      ]);
      expect(chain.unreachableRuleIndexes(), [1]);
    });
  });

  group('JSON 序列化与老数据兼容', () {
    test('带 chain 的 rule 序列化回环', () {
      const rule = ProgressionRule(
        repsMin: 8,
        repsMax: 12,
        incrementKg: 2.5,
        chain: [
          ChainRule(axis: 'reps', step: 1, ceiling: 12),
          ChainRule(
              axis: 'load', step: 2.5, advanceOnCap: false, resetRepsTo: 8),
        ],
      );
      final back = ProgressionRule.fromJson(rule.toJson());
      expect(back.chain, isNotNull);
      expect(back.chain!.length, 2);
      expect(back.chain![0].axis, 'reps');
      expect(back.chain![0].ceiling, 12);
      expect(back.chain![1].resetRepsTo, 8);
      expect(back.chain![1].advanceOnCap, isFalse);
      // 走 DB 的 JSON 编解码包装函数同样回环
      final viaDb = ruleFromJson(ruleToJson(back));
      expect(viaDb.chain, back.chain);
    });

    test('老 JSON 无 chain 键 → chain 为 null，走默认派生链', () {
      final legacy = ProgressionRule.fromJson({
        'reps_min': 5,
        'reps_max': 8,
        'increment_kg': 2.5,
      });
      expect(legacy.chain, isNull);
      final chain = ProgressionChain.of(legacy);
      expect(chain.rules.length, 2);
      expect(chain.rules[0].axis, 'reps');
      expect(chain.rules[0].ceiling, 8);
      expect(chain.rules[1].axis, 'load');
      expect(chain.rules[1].step, 2.5);
      expect(chain.rules[1].resetRepsTo, 5);
    });
  });
}

extension on SetEntry {
  SetEntry copyWithKind(String kind) => SetEntry(
        id: id,
        sessionExerciseId: sessionExerciseId,
        weightKg: weightKg,
        reps: reps,
        rir: rir,
        kind: kind,
        doneAt: doneAt,
        note: note,
      );
}
