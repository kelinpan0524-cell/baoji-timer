// 计划模板快照接线测试（调研条目 14）：开始训练时模板目标参数
// （组数 / 次数区间）整套快照进 session_exercises 行；总结建议文案
// 携带快照目标。引擎侧规则链判定见 test/progression_chain_test.dart。
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:baoji_timer/db/db.dart';
import 'package:baoji_timer/engine/engine.dart';
import 'package:baoji_timer/models/models.dart';
import 'package:baoji_timer/services/session_controller.dart';
import 'package:baoji_timer/services/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // 测试环境没有宿主插件：wakelock_plus 的 pigeon toggle 通道挂 mock 回包。
    final binding = TestWidgetsFlutterBinding.instance;
    final pigeonNullReply = ByteData(3)
      ..setUint8(0, 12)
      ..setUint8(1, 1)
      ..setUint8(2, 0);
    binding.defaultBinaryMessenger.setMockMessageHandler(
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
      (data) async => pigeonNullReply,
    );
  });

  late Db db;
  late SharedPreferences prefs;
  final controllers = <SessionController>[];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    final dir = await databaseFactory.getDatabasesPath();
    final path = '$dir/snap_${DateTime.now().microsecondsSinceEpoch}.db';
    final rawDb = await databaseFactory.openDatabase(path);
    await Db.instance.createSchema(rawDb);
    db = Db.forTesting(rawDb);
  });

  tearDown(() async {
    for (final c in controllers) {
      c.dispose();
    }
    controllers.clear();
    await db.wipeAll();
  });

  Future<(PlanDay, List<PlanExercise>)> makeDay() async {
    final plan = await db.insertPlan(Plan(
      name: '快照计划',
      source: 'manual',
      createdAt: '2026-09-25',
      isActive: 1,
    ));
    final dayId = await db.insertPlanDay(
        PlanDay(planId: plan.id!, weekday: 3, title: '推日'));
    final day = PlanDay(id: dayId, planId: plan.id!, weekday: 3, title: '推日');
    final ex = PlanExercise(
      id: await db.insertPlanExercise(PlanExercise(
        dayId: dayId,
        name: '杠铃卧推',
        orderIdx: 0,
        sets: 4,
        repsMin: 6,
        repsMax: 10,
        restSec: 150,
        kind: 'compound',
        rule: const ProgressionRule(repsMin: 6, repsMax: 10, workingSets: 4),
      )),
      dayId: dayId,
      name: '杠铃卧推',
      orderIdx: 0,
      sets: 4,
      repsMin: 6,
      repsMax: 10,
      restSec: 150,
      kind: 'compound',
      rule: const ProgressionRule(repsMin: 6, repsMax: 10, workingSets: 4),
    );
    return (day, [ex]);
  }

  test('startFromDay 把模板目标参数全套快照进训练记录', () async {
    final (day, exs) = await makeDay();
    final c = SessionController(db, Settings(prefs), prefs, null);
    controllers.add(c);
    await c.startFromDay(day: day, planExercises: exs);

    expect(c.exercises, hasLength(1));
    final se = c.exercises.first;
    expect(se.targetSets, 4); // 模板组数
    expect(se.targetRepsMin, 6); // 模板次数区间
    expect(se.targetRepsMax, 10);
    expect(se.restSec, 150);
    expect(se.name, '杠铃卧推');

    // 落库读回一致（不只内存态）
    final rows = await db.sessionExercises(c.session!.id!);
    expect(rows.first.targetSets, 4);
    expect(rows.first.targetRepsMin, 6);
    expect(rows.first.targetRepsMax, 10);
  });

  test('模板日后修改不影响已快照的老记录', () async {
    final (day, exs) = await makeDay();
    final c = SessionController(db, Settings(prefs), prefs, null);
    controllers.add(c);
    await c.startFromDay(day: day, planExercises: exs);
    final seId = c.exercises.first.id!;

    // 模板被改成 2×12-15
    final pe = exs.first;
    await db.updatePlanExercise(pe.copyWith(sets: 2, repsMin: 12, repsMax: 15));

    // 老记录的快照原样保留
    final rows = await db.sessionExercises(c.session!.id!);
    final old = rows.firstWhere((r) => r.id == seId);
    expect(old.targetSets, 4);
    expect(old.targetRepsMin, 6);
    expect(old.targetRepsMax, 10);
  });

  test('verdicts 文案携带快照目标（无快照回退规则参数）', () async {
    final (day, exs) = await makeDay();
    final c = SessionController(db, Settings(prefs), prefs, null);
    controllers.add(c);
    await c.startFromDay(day: day, planExercises: exs);
    await c.completeSet(weight: 60, reps: 8, rir: 2, kind: SetKind.working);

    final vs = await c.verdicts();
    expect(vs, hasLength(1));
    expect(vs.single, contains('计划目标 4×6-10'));
  });
}
