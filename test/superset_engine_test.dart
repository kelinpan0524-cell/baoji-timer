// 超级组引擎（v9）纯函数测试：分组识别、轮转推进、恢复落点、标记清理。
// 全部输入用 tags/plannedSets/doneWorking 三列表达，不碰 DB 与 UI。
import 'package:flutter_test/flutter_test.dart';
import 'package:baoji_timer/engine/superset.dart';

void main() {
  group('contiguousSupersetGroups / supersetMembersOf', () {
    test('空 tag 与单人段不成组；相邻同 tag ≥2 人成组', () {
      final groups = contiguousSupersetGroups(['', 'g', 'g', '', 'h', 'h', 'h']);
      expect(groups, [
        [1, 2],
        [4, 5, 6],
      ]);
      expect(supersetMembersOf(0, ['', 'g', 'g']), null);
      expect(supersetMembersOf(1, ['', 'g', 'g']), [1, 2]);
    });

    test('被隔开的同 tag 不算同组（拆散即各自独立）', () {
      final groups = contiguousSupersetGroups(['g', 'x', 'g', 'g']);
      // 第二个 g 与第三个 g 相邻成组；首尾被隔开的不并
      expect(groups, [
        [2, 3],
      ]);
    });

    test('单人段（前后都不是同 tag）不成组', () {
      expect(contiguousSupersetGroups(['g', '', 'g']), isEmpty);
    });
  });

  group('nextExerciseIdxAfterSet：不配对 = 旧线性语义', () {
    test('未练满留在原动作；练满进下一个；末尾 = null 结束', () {
      const tags = ['', '', ''];
      const planned = [3, 3, 3];
      expect(
          nextExerciseIdxAfterSet(
              tags: tags,
              plannedSets: planned,
              doneWorking: [1, 0, 0],
              justIdx: 0),
          0);
      expect(
          nextExerciseIdxAfterSet(
              tags: tags,
              plannedSets: planned,
              doneWorking: [3, 0, 0],
              justIdx: 0),
          1);
      expect(
          nextExerciseIdxAfterSet(
              tags: tags,
              plannedSets: planned,
              doneWorking: [3, 3, 3],
              justIdx: 2),
          null);
    });
  });

  group('nextExerciseIdxAfterSet：超级组轮转', () {
    const tags = ['s', 's', ''];
    const planned = [3, 3, 2];

    test('等组数两人组：A1→B、B1→A、A2→B、B2→A', () {
      expect(
          nextExerciseIdxAfterSet(
              tags: tags, plannedSets: planned, doneWorking: [1, 0, 0], justIdx: 0),
          1);
      expect(
          nextExerciseIdxAfterSet(
              tags: tags, plannedSets: planned, doneWorking: [1, 1, 0], justIdx: 1),
          0);
      expect(
          nextExerciseIdxAfterSet(
              tags: tags, plannedSets: planned, doneWorking: [2, 1, 0], justIdx: 0),
          1);
      expect(
          nextExerciseIdxAfterSet(
              tags: tags, plannedSets: planned, doneWorking: [2, 2, 0], justIdx: 1),
          0);
    });

    test('组内练满后出组到组尾后第一个动作；末组练满 = null 结束', () {
      // A、B 都练满 → 出组到下标 2
      expect(
          nextExerciseIdxAfterSet(
              tags: tags, plannedSets: planned, doneWorking: [3, 3, 1], justIdx: 1),
          2);
      // 无组尾后动作（组在末尾）→ null
      expect(
          nextExerciseIdxAfterSet(
              tags: ['', 's', 's'],
              plannedSets: [2, 3, 3],
              doneWorking: [2, 3, 3],
              justIdx: 2),
          null);
    });

    test('不等组数：B 先练满后 A 继续自己（只剩自己 = 留在原动作）', () {
      // A 计划 4 组、B 计划 2 组：B2 完成后回 A3
      expect(
          nextExerciseIdxAfterSet(
              tags: ['s', 's'],
              plannedSets: [4, 2],
              doneWorking: [2, 2],
              justIdx: 1),
          0);
      // A3 完成，B 已满 → 唯一剩自己 → 留在 A
      expect(
          nextExerciseIdxAfterSet(
              tags: ['s', 's'],
              plannedSets: [4, 2],
              doneWorking: [3, 2],
              justIdx: 0),
          0);
    });

    test('乱序完成（先做完 B）：轮转推导仍收敛到 A 的剩余组', () {
      // 用户跳页先把 B 三组全做完，A 只做了 1 组 → A 之后该回 A
      expect(
          nextExerciseIdxAfterSet(
              tags: ['s', 's'],
              plannedSets: [3, 3],
              doneWorking: [1, 3],
              justIdx: 1),
          0);
    });
  });

  group('plannedVisitSequence / resumeExerciseIdx', () {
    test('两人等组数交替展开；非成员线性展开', () {
      expect(
        plannedVisitSequence(tags: ['s', 's', ''], plannedSets: [2, 2, 2]),
        [0, 1, 0, 1, 2, 2],
      );
    });

    test('三连组与不等组数：缺失的成员只出现在自己的轮里', () {
      expect(
        plannedVisitSequence(tags: ['s', 's', 's'], plannedSets: [3, 2, 3]),
        [0, 1, 2, 0, 1, 2, 0, 2],
      );
    });

    test('不配对时恢复落点 = 旧线性「第一个未练满」；全练满回落最后', () {
      expect(
        resumeExerciseIdx(
            tags: ['', '', ''],
            plannedSets: [3, 3, 3],
            doneWorking: [3, 1, 0]),
        1,
      );
      expect(
        resumeExerciseIdx(
            tags: ['', '', ''],
            plannedSets: [3, 3, 3],
            doneWorking: [3, 3, 3]),
        2,
      );
    });

    test('超级组中断恢复：A2B1 已做 → 下一个是 B2；B 先做完 → 回 A 剩余', () {
      // A3B3，进度 A=2、B=1：已消费 A,B,A → 下一个槽位 B
      expect(
        resumeExerciseIdx(
            tags: ['s', 's'], plannedSets: [3, 3], doneWorking: [2, 1]),
        1,
      );
      // 跳页先做完 B 全部、A=2：序列消费 A,B,A,B,B → 下一个 A
      expect(
        resumeExerciseIdx(
            tags: ['s', 's'], plannedSets: [3, 3], doneWorking: [2, 3]),
        0,
      );
      // 全做完 → 回落最后一个
      expect(
        resumeExerciseIdx(
            tags: ['s', 's'], plannedSets: [3, 3], doneWorking: [3, 3]),
        1,
      );
    });
  });

  group('supersetTagClears（标记清理）', () {
    test('连续段 ≥2 保留；单人段与被隔开段清空', () {
      // g,g 相邻保留；x 单人清空；y,y 相邻保留
      expect(supersetTagClears(['g', 'g', 'x', '', 'y', 'y']), [2]);
      // 同 tag 被空位隔开 → 两个单人段都清空
      expect(supersetTagClears(['y', '', 'y']), [0, 2]);
      // 同 tag 被其他动作隔开 → 拆散清空（中间的孤 tag z 也一并清）
      expect(supersetTagClears(['y', 'z', 'y']), [0, 1, 2]);
    });

    test('全部干净时无清理', () {
      expect(supersetTagClears(['', 'g', 'g', '']), isEmpty);
    });
  });

  test('newSupersetTag 进程内唯一', () {
    final seen = {for (var i = 0; i < 200; i++) newSupersetTag()};
    expect(seen.length, 200);
  });
}
