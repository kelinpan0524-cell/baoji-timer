// 批次2 修复回归：计划域（A2-5 模板「第 N 练」序号 / A2-4 模板查重带来源校验 /
// A3-1 saveAiPlan 不全量覆盖用户动作标注）。
// 基建同批次1 session_controller_test：ffi 真库 + Db.forTesting + wipeAll。
import 'package:flutter_test/flutter_test.dart';
import 'package:baoji_timer/db/db.dart';
import 'package:baoji_timer/models/models.dart';
import 'package:baoji_timer/presets/exercise_library.dart';
import 'package:baoji_timer/services/ai_service.dart';
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
    // 微秒时间戳唯一路径 = 每个测试独立数据库（ffi 对同路径会复用连接）
    final dir = await databaseFactory.getDatabasesPath();
    final path =
        '$dir/test_plan_${DateTime.now().microsecondsSinceEpoch}.db';
    final rawDb = await databaseFactory.openDatabase(path);
    await Db.instance.createSchema(rawDb);
    db = Db.forTesting(rawDb);
    repo = PlanRepository(db, Settings(prefs));
  });

  tearDown(() async {
    await db.wipeAll();
  });

  test('A2-5：非连练模板安装后「第 N 练」按模板内序号递增，不再等于星期数', () async {
    final (plan, created) = await repo.installTemplate(kHomeTemplate);
    expect(created, isTrue);
    final days = await db.planDays(plan.id!);
    expect(days.length, 3, reason: '居家哑铃全身为 1/3/5 三练');
    final titleByWeekday = {for (final d in days) d.weekday: d.title};
    // 全 App 星期格式为汉字「周一」（wd='一二三四五六日'，plan_page 同款），
    // ask 断言里的「周1」是笔误——核心断言是序号按模板内递增、不等于星期数
    expect(titleByWeekday[1], '周一 · 第 1 练');
    expect(titleByWeekday[3], '周三 · 第 2 练', reason: '第 2 练，不再是「第 3 练」');
    expect(titleByWeekday[5], '周五 · 第 3 练', reason: '第 3 练，不再是「第 5 练」');
  });

  test('A2-4：用户自建同名计划不拦截模板安装；重复安装同模板不重复建', () async {
    // 用户先自建了一个恰好同名的空白计划（source='manual'，7 个空训练日）
    final manual = await db.insertPlan(Plan(
        name: kHomeTemplate.name,
        source: 'manual',
        createdAt: '2026-09-24'));
    for (var wd = 1; wd <= 7; wd++) {
      await db.insertPlanDay(
          PlanDay(planId: manual.id!, weekday: wd, title: '训练日'));
    }

    // 装同名模板：不被 manual 同名计划误判为已安装，模板内容真实写入
    final (plan, created) = await repo.installTemplate(kHomeTemplate);
    expect(created, isTrue, reason: 'manual 同名计划不算已安装');
    expect(plan.source, 'preset');

    final active = await db.activePlan();
    expect(active, isNotNull);
    expect(active!.id, plan.id, reason: '模板计划成为使用中');
    expect(active.source, 'preset');

    final days = await db.planDays(plan.id!);
    expect(days.length, 3);
    final exMap = await db.daysExercisesMap(days.map((d) => d.id!).toList());
    final total = exMap.values.fold<int>(0, (n, list) => n + list.length);
    expect(total, 15, reason: '3 练 × 5 动作真实写入，不是空计划被直接启用');

    // 再装一次同模板：命中同名同源 preset → 不重复建
    final (same, createdAgain) = await repo.installTemplate(kHomeTemplate);
    expect(createdAgain, isFalse);
    expect(same.id, plan.id);
    final sameNameCount =
        (await db.allPlans()).where((p) => p.name == kHomeTemplate.name).length;
    expect(sameNameCount, 2, reason: 'manual 那份仍在，模板本身只有一份');
  });

  test('A3-1：saveAiPlan 不再把内置词表全量 REPLACE，覆盖用户改过的标注', () async {
    // 用户在编辑器里把「杠铃卧推」的主肌群改成了「肩」（词表内动作默认是「胸」）
    await db.upsertExerciseMeta(
        const ExerciseMeta('杠铃卧推', MuscleGroups(main: '肩'), true, 'gym'));

    final ai = AiService(Settings(prefs));
    await repo.saveAiPlan(
      name: 'AI 计划',
      specs: const [
        AiDaySpec(1, '推日', [
          AiExerciseSpec(
              name: '杠铃卧推',
              sets: 3,
              repsMin: 5,
              repsMax: 8,
              kind: 'compound'),
        ]),
      ],
      metaMap: ai.metaMap(),
    );

    final meta = await db.exerciseMeta('杠铃卧推');
    expect(meta, isNotNull);
    expect(meta!.muscles.main, '肩',
        reason: '修复前：saveAiPlan 尾部全量落库会把标注静默重置回内置默认「胸」');
  });
}
