// 循环排程「训练日搁浅」回归：连练 N < 有动作的训练日数时，
// 多出的模板日在 _cycleDayFor 里永远轮不到（用户报障：胸腿背计划一直只有胸腿）。
// 本文件锁定推导语义 + trainableDayCount 口径，UI 侧默认值与警示见 plan_page。
// 基建同 plan_repository_test：ffi 真库 + Db.forTesting + 唯一路径。
import 'package:flutter_test/flutter_test.dart';
import 'package:baoji_timer/db/db.dart';
import 'package:baoji_timer/models/models.dart';
import 'package:baoji_timer/services/plan_repository.dart';
import 'package:baoji_timer/services/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Db db;
  late SharedPreferences prefs;
  late PlanRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    final dir = await databaseFactory.getDatabasesPath();
    final path =
        '$dir/test_cycle_${DateTime.now().microsecondsSinceEpoch}.db';
    final rawDb = await databaseFactory.openDatabase(path);
    await Db.instance.createSchema(rawDb);
    db = Db.forTesting(rawDb);
    repo = PlanRepository(db, Settings(prefs));
  });

  tearDown(() async {
    await db.wipeAll();
  });

  /// 建「胸/腿/背」三模板日，每日 1 个动作；[backWithExercises]=false 时背日留空。
  Future<Plan> buildPushPullLegs({bool backWithExercises = true}) async {
    final plan = await db.insertPlan(Plan(
      name: '胸腿背',
      source: 'manual',
      createdAt: '2026-09-25',
      pattern: 'cycle',
      patternStart: '2026-09-01',
      cycleTrain: 2,
      cycleRest: 2,
    ));
    final titles = ['胸', '腿', '背'];
    for (var i = 0; i < titles.length; i++) {
      final day = await db.insertPlanDay(PlanDay(
          planId: plan.id!, weekday: i + 1, title: titles[i]));
      final withEx = i < 2 || backWithExercises;
      if (withEx) {
        await db.insertPlanExercise(PlanExercise(
          dayId: day,
          name: '卧推',
          orderIdx: 0,
          sets: 3,
          repsMin: 8,
          repsMax: 12,
          restSec: 90,
          kind: 'compound',
          rule: const ProgressionRule(repsMin: 8, repsMax: 12),
        ));
      }
    }
    return plan;
  }

  test('trainableDayCount：有动作的训练日数，空模板日不计入', () async {
    final plan = await buildPushPullLegs();
    expect(await repo.trainableDayCount(plan.id!), 3);

    final emptyBack = await buildPushPullLegs(backWithExercises: false);
    expect(await repo.trainableDayCount(emptyBack.id!), 2);
  });

  test('复现：连练2 < 3 个训练日时，第 3 天永远推导为休息（搁浅语义锁定）', () async {
    final plan = await buildPushPullLegs();
    // 周期 4：pos 0=胸 1=腿 2=休 3=休；背(下标2)永远轮不到 —— 用户报障的形状
    expect((await repo.dayForDateOn(plan, DateTime(2026, 9, 1)))!.title, '胸');
    expect((await repo.dayForDateOn(plan, DateTime(2026, 9, 2)))!.title, '腿');
    expect(await repo.dayForDateOn(plan, DateTime(2026, 9, 3)), isNull,
        reason: '连练2 < 训练日3：第 3 天被当作休息日，背排不上');
    expect(await repo.dayForDateOn(plan, DateTime(2026, 9, 4)), isNull);
    expect((await repo.dayForDateOn(plan, DateTime(2026, 9, 5)))!.title, '胸');
  });

  test('连练3 = 训练日数时正常轮转：胸腿背休休', () async {
    final plan = await buildPushPullLegs();
    await repo.updateSchedulePattern(
        planId: plan.id!,
        pattern: 'cycle',
        patternStart: '2026-09-01',
        cycleTrain: 3,
        cycleRest: 2);
    final reloaded = (await db.allPlans()).firstWhere((p) => p.id == plan.id);
    expect((await repo.dayForDateOn(reloaded, DateTime(2026, 9, 1)))!.title,
        '胸');
    expect((await repo.dayForDateOn(reloaded, DateTime(2026, 9, 2)))!.title,
        '腿');
    expect((await repo.dayForDateOn(reloaded, DateTime(2026, 9, 3)))!.title,
        '背', reason: '连练数与训练日数对齐后，背正常出现');
    expect(await repo.dayForDateOn(reloaded, DateTime(2026, 9, 4)), isNull);
    expect(await repo.dayForDateOn(reloaded, DateTime(2026, 9, 5)), isNull);
    expect((await repo.dayForDateOn(reloaded, DateTime(2026, 9, 6)))!.title,
        '胸');
  });

  test('空模板日被推导跳过：轮转只在有动作的模板日里循环', () async {
    final plan = await buildPushPullLegs(backWithExercises: false);
    // 连练2、可练日=[胸,腿]：pos 0=胸 1=腿，休 2 天后重复
    expect((await repo.dayForDateOn(plan, DateTime(2026, 9, 1)))!.title, '胸');
    expect((await repo.dayForDateOn(plan, DateTime(2026, 9, 2)))!.title, '腿');
    expect(await repo.dayForDateOn(plan, DateTime(2026, 9, 3)), isNull);
    expect((await repo.dayForDateOn(plan, DateTime(2026, 9, 5)))!.title, '胸');
  });
}
