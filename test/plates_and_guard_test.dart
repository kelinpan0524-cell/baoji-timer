// 杠铃片速配引擎（platesForLoad）：贪心配片、配不平时报余量、空杆/自重不配。
// 忘停表守护（isSuspiciousSessionDuration）：一组没记挂机 30 分+ / 有记录但组均 15 分+。
// 动作库器械归类完整性（2026-09-26 数据修复回归）：99 个动作全部有合法器械标注。
import 'package:baoji_timer/engine/engine.dart';
import 'package:baoji_timer/presets/exercise_library.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('platesForLoad', () {
    test('60kg：每边 20kg（杠铃片优先用大片）', () {
      final b = platesForLoad(60);
      expect(b.perSide, [20]);
      expect(b.exact, isTrue);
    });

    test('77.5kg：每边 28.75 = 25 + 2.5 + 1.25（贪心优先大片）', () {
      final b = platesForLoad(77.5);
      expect(b.perSide, [25, 2.5, 1.25]);
      expect(b.exact, isTrue);
    });

    test('100kg：每边 40 = 25 + 15', () {
      final b = platesForLoad(100);
      expect(b.perSide, [25, 15]);
      expect(b.exact, isTrue);
    });

    test('空杆 20kg 与自重 0：空组合不报错', () {
      expect(platesForLoad(20).perSide, isEmpty);
      expect(platesForLoad(20).exact, isTrue);
      expect(platesForLoad(0).perSide, isEmpty);
    });

    test('低于杆重的负重返回空组合', () {
      final b = platesForLoad(15);
      expect(b.perSide, isEmpty);
      expect(b.exact, isTrue);
    });

    test('配不平：库存最小 1.25，每边差值如实报出', () {
      // 62.6 → 每边 21.3 = 20 + 1.25，差 0.05
      final b = platesForLoad(62.6);
      expect(b.exact, isFalse);
      expect(b.leftoverPerSide, closeTo(0.05, 0.001));
    });

    test('浮点误差不产生假余量（0.5 步进反复加减）', () {
      for (var w = 25.0; w <= 120; w += 2.5) {
        final b = platesForLoad(w);
        expect(b.exact, isTrue, reason: '$w kg 应能精确配平');
      }
    });
  });

  group('isSuspiciousSessionDuration', () {
    final start = DateTime(2026, 9, 26, 18, 0).millisecondsSinceEpoch;
    int min(int n) => start + n * 60000;

    test('正常训练：50 分钟 12 组 → 不可疑', () {
      expect(
        isSuspiciousSessionDuration(
            startedAtMs: start, nowMs: min(50), setCount: 12),
        isFalse,
      );
    });

    test('忘停表：50 分钟只有 1 组（组均 50 分）→ 可疑', () {
      expect(
        isSuspiciousSessionDuration(
            startedAtMs: start, nowMs: min(50), setCount: 1),
        isTrue,
      );
    });

    test('不足 45 分钟但组数少 → 不可疑（避免误伤短训）', () {
      expect(
        isSuspiciousSessionDuration(
            startedAtMs: start, nowMs: min(40), setCount: 2),
        isFalse,
      );
    });

    test('一组没记挂机 30 分钟+ → 可疑', () {
      expect(
        isSuspiciousSessionDuration(
            startedAtMs: start, nowMs: min(31), setCount: 0),
        isTrue,
      );
    });

    test('一组没记但刚开 10 分钟 → 不可疑（可能刚开门）', () {
      expect(
        isSuspiciousSessionDuration(
            startedAtMs: start, nowMs: min(10), setCount: 0),
        isFalse,
      );
    });
  });

  group('动作库器械归类完整性', () {
    const validGears = {
      '杠铃', '哑铃', '龙门架绳索', '固定器械', '弹力带', '自重', '壶铃', '其他器械',
    };

    test('内置动作库每个动作都有合法的器械归类', () {
      expect(kExerciseLibrary, isNotEmpty);
      for (final m in kExerciseLibrary) {
        expect(validGears.contains(m.gear), isTrue,
            reason: '${m.name} 的器械标注为 "${m.gear}"，不在 8 类合法值里');
      }
    });

    test('杠铃类动作存在（速配功能的数据前提）', () {
      expect(
        kExerciseLibrary.any((m) => m.gear == '杠铃'),
        isTrue,
      );
    });

    test('libraryMetaByName 按名命中、词表外返回 null', () {
      expect(libraryMetaByName('杠铃卧推')?.gear, '杠铃');
      expect(libraryMetaByName('根本不存在的动作'), isNull);
    });
  });
}
