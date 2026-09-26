// 历史页表格化排版（2026-09-26 Arono：别再一条文字流，要格子）
//   + 1RM 序列同场叠点修复（旧 bug：同场破 PR 各组叠在同一 x 成竖线）。
// 覆盖：日期单独做卡片标题、计划标题独立一行、每动作一张
// 「组/重量 kg/次数/余力」表（R2 缩写改明示余力列）、备注保留。
// 明细行走公开布局函数 buildSessionDetailRows 直测（不绕页面异步）。
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baoji_timer/engine/engine.dart';
import 'package:baoji_timer/ui/stats_page.dart' show addRmPointToSeries;
import 'package:baoji_timer/ui/history_page.dart';

void main() {
  testWidgets('明细布局：计划标题一行 + 动作表四列 + 余力明示 + 备注保留',
      (tester) async {
    final se = SessionExercise(
      sessionId: 1,
      name: '杠铃划船',
      orderIdx: 0,
      kind: 'compound',
      rule: ProgressionRule.fallback,
    ).copyWithId(7);
    const s = Session(
      id: 1,
      date: '2026-09-26',
      planDayTitle: '背 + 肩',
      startedAt: 1000,
      endedAt: 2000,
      status: 'done',
      restMs: 31 * 60000,
      activeMs: 26 * 60000,
    );
    final rows = buildSessionDetailRows(s, [se], {
      7: const [
        SetEntry(
          sessionExerciseId: 7,
          weightKg: 50,
          reps: 8,
          rir: 2,
          kind: SetKind.working,
          doneAt: 1100,
        ),
        SetEntry(
          sessionExerciseId: 7,
          weightKg: 30,
          reps: 10,
          rir: 1,
          kind: SetKind.warmup,
          doneAt: 1200,
          note: '热身偏轻',
        ),
      ],
    }, bodyWeightKg: 70);

    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(children: rows),
      ),
    ));
    await tester.pump();

    // 计划标题独立一行
    expect(find.text('背 + 肩'), findsOneWidget);
    expect(find.textContaining('训练 26 分 · 休息 31 分'), findsOneWidget);
    // 动作名 + 表头四列（余力列头明示，不再 R2 缩写）
    expect(find.text('杠铃划船'), findsOneWidget);
    expect(find.text('组'), findsOneWidget);
    expect(find.text('重量 kg'), findsOneWidget);
    expect(find.text('次数'), findsOneWidget);
    expect(find.text('余力'), findsOneWidget);
    // 两行数据：正式组 50/8/2，热身 30/10/热
    expect(find.text('50'), findsOneWidget);
    expect(find.text('8'), findsOneWidget);
    expect(find.text('2'), findsNWidgets(2),
        reason: '第一组余力 2 + 第二行组号 2 同字');
    expect(find.text('30'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);
    expect(find.text('热'), findsOneWidget);
    expect(find.text('1'), findsOneWidget, reason: '第一列组号');
    expect(find.textContaining('R2'), findsNothing, reason: '不再用 R 缩写');
    // 备注保留
    expect(find.textContaining('备注'), findsOneWidget);
    expect(find.textContaining('热身偏轻'), findsOneWidget);
  });

  group('addRmPointToSeries（1RM 竖线修复）', () {
    test('同一场破 PR 多组：只保留该场最佳，不叠同 x 点', () {
      final list = <FlSpot>[];
      addRmPointToSeries(list, 0, 40);
      addRmPointToSeries(list, 0, 45.6); // 同场更好：原地替换
      addRmPointToSeries(list, 0, 42); // 同场更差：忽略
      expect(list.length, 1, reason: '同一场只留一个点（旧 bug 会叠成竖线）');
      expect(list.single.y, 45.6);
      expect(list.single.x, 0);
    });

    test('跨场次：只记超过此前最佳的进步节点', () {
      final list = <FlSpot>[];
      addRmPointToSeries(list, 0, 45.6);
      addRmPointToSeries(list, 1, 40); // 退步：不记
      addRmPointToSeries(list, 1, 46); // 场内超过历史最佳：记第 2 点
      addRmPointToSeries(list, 2, 30); // 大退步：不记
      expect(list, hasLength(2));
      expect(list[1].x, 1);
      expect(list[1].y, 46);
    });

    test('首场即起点（空序列直接记点）', () {
      final list = <FlSpot>[];
      addRmPointToSeries(list, 3, 50);
      expect(list.single, const FlSpot(3, 50));
    });
  });
}
