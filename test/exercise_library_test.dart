import 'package:flutter_test/flutter_test.dart';
import 'package:baoji_timer/engine/engine.dart';
import 'package:baoji_timer/presets/baoji_plan.dart';
import 'package:baoji_timer/presets/exercise_library.dart';

/// 内置动作库与计划模板的数据完整性。
void main() {
  group('动作库完整性', () {
    test('数量充足（≥60）且无重名', () {
      expect(kExerciseLibrary.length, greaterThanOrEqualTo(60));
      final names = kExerciseLibrary.map((m) => m.name).toSet();
      expect(names.length, kExerciseLibrary.length, reason: '动作名不能重复');
    });

    test('每个动作：肌群合法、场景合法、名称非空', () {
      for (final m in kExerciseLibrary) {
        expect(m.name.trim(), isNotEmpty, reason: '${m.name} 名称非空');
        expect(kMuscleRegions, contains(m.muscles.main),
            reason: '${m.name} 主肌群 ${m.muscles.main} 必须在区域内');
        expect(['gym', 'home', 'both'], contains(m.equipment),
            reason: '${m.name} 场景 ${m.equipment} 非法');
        for (final sec in m.muscles.secondary) {
          expect(kMuscleRegions, contains(sec),
              reason: '${m.name} 次肌群 $sec 非法');
        }
      }
    });

    test('居家与健身房两个场景都有充足选择', () {
      final home =
          kExerciseLibrary.where((m) => m.equipment != 'gym').length;
      final gym =
          kExerciseLibrary.where((m) => m.equipment != 'home').length;
      expect(home, greaterThan(20), reason: '居家可选动作充足');
      expect(gym, greaterThan(20), reason: '健身房可选动作充足');
      // 每个大肌群在两个场景都至少有 2 个动作
      for (final region in ['胸', '背', '肩', '手臂', '腿', '核心']) {
        final homeN = kExerciseLibrary
            .where((m) => m.muscles.main == region && m.equipment != 'gym')
            .length;
        final gymN = kExerciseLibrary
            .where((m) => m.muscles.main == region && m.equipment != 'home')
            .length;
        expect(homeN, greaterThanOrEqualTo(2),
            reason: '$region 居家动作不足');
        expect(gymN, greaterThanOrEqualTo(2),
            reason: '$region 健身房动作不足');
      }
    });
  });

  group('计划模板完整性', () {
    test('模板数量与命名', () {
      expect(kPlanTemplates.length, 4);
      final names = kPlanTemplates.map((t) => t.name).toSet();
      expect(names.length, 4, reason: '模板名不重复');
      expect(names, contains('三分化（推·拉·腿）'));
      expect(names, contains('五分化（胸·背·肩·臂·腿）'));
      expect(names, contains('功能性训练（全身）'));
      expect(names, contains('居家哑铃全身'));
    });

    test('每个模板：天数合法、动作都在词表、数值在合理区间', () {
      final libNames = kExerciseLibrary.map((m) => m.name).toSet();
      for (final t in kPlanTemplates) {
        expect(t.byWeekday.keys.every((wd) => wd >= 1 && wd <= 7), isTrue,
            reason: '${t.name} weekday 越界');
        expect(t.byWeekday.length, greaterThanOrEqualTo(3),
            reason: '${t.name} 至少 3 个训练日');
        for (final entry in t.byWeekday.entries) {
          expect(entry.value.length, greaterThanOrEqualTo(4),
              reason: '${t.name} 周${entry.key} 动作过少');
          for (final ex in entry.value) {
            expect(libNames, contains(ex.name),
                reason: '${t.name} 的「${ex.name}」不在动作库中');
            expect(ex.sets, inInclusiveRange(1, 20));
            expect(ex.repsMin, inInclusiveRange(1, 60));
            expect(ex.repsMax, inInclusiveRange(ex.repsMin, 60),
                reason: '${ex.name} reps 倒挂（计时类动作上限 60 秒）');
            expect(ex.restSec, inInclusiveRange(15, 600));
            expect(['compound', 'assistance'], contains(ex.kind));
          }
        }
      }
    });

    test('薄肌计划模板（内置）动作也都在词表', () {
      final libNames = kExerciseLibrary.map((m) => m.name).toSet();
      for (final list in kBaojiExercisesByWeekday.values) {
        for (final ex in list) {
          expect(libNames, contains(ex.name),
              reason: '薄肌计划的「${ex.name}」不在动作库');
        }
      }
    });
  });
}
