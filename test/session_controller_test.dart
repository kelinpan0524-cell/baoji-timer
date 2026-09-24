// 批次1 修复回归：会话状态机（A1-1 撤销计数 / A1-2 零动作脏会话 / A1-5 双击竞态）、
// 休息时间源与闹钟回调（A1-4 controller 半边）、数据层正确性（A5-2 截断方向 / A5-3 导出）。
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:baoji_timer/db/db.dart';
import 'package:baoji_timer/engine/engine.dart';
import 'package:baoji_timer/services/export_service.dart';
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
    // pigeon 对 null 回包一律抛 channel-error，void 方法的合法回包是
    // 编码后的 [null]（StandardMessageCodec：list 头 0x0C + 长度 0x01 + null 0x00）。
    final binding = TestWidgetsFlutterBinding.instance;
    final pigeonNullReply = ByteData(3)
      ..setUint8(0, 12)
      ..setUint8(1, 1)
      ..setUint8(2, 0);
    binding.defaultBinaryMessenger.setMockMessageHandler(
        'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
        (data) async => pigeonNullReply);
  });

  late Db db;
  late Database rawDb; // 直查用（绕开 Db 封装断言库内真值）
  late SharedPreferences prefs;
  final controllers = <SessionController>[];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    // 微秒时间戳唯一路径 = 每个测试独立数据库（ffi 对同路径会复用连接）
    final dir = await databaseFactory.getDatabasesPath();
    final path =
        '$dir/test_sess_${DateTime.now().microsecondsSinceEpoch}.db';
    rawDb = await databaseFactory.openDatabase(path);
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

  SessionController makeController() {
    final c = SessionController(db, Settings(prefs), prefs, null);
    controllers.add(c);
    return c;
  }

  Future<PlanDay> makePlanDay(String title) async {
    final plan = await db.insertPlan(Plan(
        name: '测试计划-$title',
        source: 'manual',
        createdAt: '2026-09-24',
        isActive: 1));
    final dayId = await db.insertPlanDay(
        PlanDay(planId: plan.id!, weekday: 3, title: title));
    return PlanDay(
        id: dayId, planId: plan.id!, weekday: 3, title: title);
  }

  Future<PlanExercise> addPlanEx(PlanDay day, String name, int order,
      {int sets = 3, int restSec = 120, int workingSets = 3}) async {
    final pe = PlanExercise(
      dayId: day.id!,
      name: name,
      orderIdx: order,
      sets: sets,
      repsMin: 5,
      repsMax: 8,
      restSec: restSec,
      kind: 'compound',
      rule: ProgressionRule(repsMin: 5, repsMax: 8, workingSets: workingSets),
    );
    final id = await db.insertPlanExercise(pe);
    return pe.copyWith(id: id);
  }

  test('A1-1：跨动作回退撤销后计数收敛到 DB 真值，剩余组仍是 PR 则保留标记', () async {
    // 前置历史：深蹲 在一次 done 会话里推过 60kg（62.5 即历史新高）
    final s0 = await db.insertSession(Session(
        date: '2026-09-01',
        planDayTitle: '旧训练',
        startedAt: 1,
        endedAt: 2,
        status: 'done'));
    final se0 = await db.insertSessionExercise(SessionExercise(
        sessionId: s0.id!,
        name: '深蹲',
        orderIdx: 0,
        kind: 'compound',
        rule: const ProgressionRule(repsMin: 5, repsMax: 8, workingSets: 3)));
    await db.insertSet(SetEntry(
        sessionExerciseId: se0,
        weightKg: 60,
        reps: 8,
        kind: SetKind.working,
        doneAt: 1000));

    final day = await makePlanDay('腿日');
    final a = await addPlanEx(day, '深蹲', 0, workingSets: 3);
    final b = await addPlanEx(day, '腿举', 1, sets: 1, workingSets: 1);

    final c = makeController();
    await c.startFromDay(day: day, planExercises: [a, b]);
    expect(c.hasActive, isTrue);
    expect(c.curExIdx, 0);

    // 记满 A 的 3 个正式组 → 自动推进到 B 并进入休息
    for (var i = 0; i < 3; i++) {
      await c.completeSet(
          weight: 62.5, reps: 8, rir: 2, kind: SetKind.working);
    }
    expect(c.curExIdx, 1, reason: 'A 记满 3 组已推进到 B');
    expect(c.prHit, contains('深蹲'));

    // 休息态撤销：回退到 A 删最后一组
    await c.undoLastSet();
    expect(c.workingSetsDone, 2, reason: '按剩余正式组重算，不再出现 -1');
    expect(c.curExIdx, 0, reason: '回退到动作 A');
    expect(c.currentSets.length, 2, reason: 'A 只剩 2 组');
    expect(c.prHit, contains('深蹲'),
        reason: '剩余两组 62.5 仍高于历史 60，PR 标记保留');

    // 继续撤销直到 A 一个正式组不剩：已无任何"历史新高"组 → 标记清除
    await c.undoLastSet();
    expect(c.workingSetsDone, 1);
    await c.undoLastSet();
    expect(c.workingSetsDone, 0);
    expect(c.currentSets, isEmpty);
    expect(c.prHit, isNot(contains('深蹲')),
        reason: '剩余正式组全删后 PR 标记应清除');
  });

  test('A1-2：零动作 active 脏会话 restore 自动作废，不再锁死启动', () async {
    await db.insertSession(Session(
        date: '2026-09-24',
        planDayTitle: '脏会话',
        startedAt: 1,
        status: 'active'));
    final dirty = await db.activeSession();
    expect(dirty, isNotNull);

    final c = makeController();
    // 修复前：exercises 为空 → currentEx! 解引用抛
    // "Null check operator used on a null value"，启动即崩
    await c.restore();
    expect(c.hasActive, isFalse);
    expect(c.session, isNull);
    expect(c.phase, WorkoutPhase.idle);

    final after = await db.sessionById(dirty!.id!);
    expect(after!.status, 'quit', reason: '孤儿会话被自动作废');

    // 作废后可正常开新会话
    final day = await makePlanDay('推日');
    final e = await addPlanEx(day, '卧推', 0);
    await c.startFromDay(day: day, planExercises: [e]);
    expect(c.hasActive, isTrue);
    expect(c.exercises.length, 1);
    expect(c.phase, WorkoutPhase.lifting);
  });

  test('A5-2：historySets 超 2000 行时截掉最旧、保留最新且仍按时间升序', () async {
    final s = await db.insertSession(Session(
        date: '2026-09-01',
        planDayTitle: 't',
        startedAt: 1,
        endedAt: 2,
        status: 'done'));
    final se = await db.insertSessionExercise(SessionExercise(
        sessionId: s.id!,
        name: '卧推',
        orderIdx: 0,
        kind: 'compound',
        rule: const ProgressionRule(repsMin: 5, repsMax: 8)));
    const base = 1700000000000;
    var latest = 0;
    for (var i = 0; i < 2001; i++) {
      latest = base + i * 1000;
      await db.insertSet(SetEntry(
          sessionExerciseId: se,
          weightKg: 60,
          reps: 8,
          kind: SetKind.working,
          doneAt: latest));
    }

    final list = await db.historySets('卧推');
    expect(list.length, 2000, reason: '封顶 2000 行');
    expect(list.first.doneAt < list.last.doneAt, isTrue, reason: '时间升序');
    expect(list.last.doneAt, latest, reason: '最后一条是最新的组（截掉的是最旧段）');
  });

  test('A5-3：exportAllJson 导出包含 exercise_meta', () async {
    await db.upsertExerciseMeta(const ExerciseMeta(
        '词表外动作', MuscleGroups(main: '胸', secondary: ['肩']), true, 'gym'));

    final data = await db.exportAllJson();
    expect(data.containsKey('exercise_meta'), isTrue);
    final rows = data['exercise_meta'] as List<dynamic>;
    expect(rows, isNotEmpty);
    expect((rows.first as Map)['name'], '词表外动作');
  });

  test('A1-5（controller 侧）：已有 active 会话时再调 startFromDay 直接返回', () async {
    final day = await makePlanDay('日');
    final e = await addPlanEx(day, '卧推', 0);

    final c = makeController();
    await c.startFromDay(day: day, planExercises: [e]);
    final firstId = c.session!.id;
    await c.startFromDay(day: day, planExercises: [e]); // 模拟双击第二击
    expect(c.session!.id, firstId, reason: '内存态已 active，第二次调用直接返回');
    var rows = await rawDb.query('sessions', where: "status='active'");
    expect(rows.length, 1, reason: '不产生第二条 active 会话');

    // DB 层已有 active 而内存未加载（如恢复失败）时，插入前重查兜底同样拦截
    final c2 = makeController();
    await c2.startFromDay(day: day, planExercises: [e]);
    expect(c2.session, isNull, reason: 'DB 重查兜底拦截，未开新会话');
    rows = await rawDb.query('sessions', where: "status='active'");
    expect(rows.length, 1);
  });

  test('A1-4（controller 半边）：暂停态 +30 秒不被 resume 丢弃；闹钟回调跟随时间源', () async {
    final alarmCalls = <int?>[];
    final day = await makePlanDay('日');
    final e = await addPlanEx(day, '卧推', 0, workingSets: 3, restSec: 120);

    final c = makeController();
    c.onRestAlarmChanged = (endAtMs) async => alarmCalls.add(endAtMs);
    await c.startFromDay(day: day, planExercises: [e]);
    await c.completeSet(
        weight: 60, reps: 8, rir: 2, kind: SetKind.working);
    expect(c.phase, WorkoutPhase.resting);
    final endAfterStart = c.restEndAt;
    expect(alarmCalls.last, endAfterStart, reason: '开始休息即挂精确闹钟');

    c.pauseRest();
    expect(c.isRestPaused, isTrue);
    expect(alarmCalls.last, isNull, reason: '暂停即取消精确闹钟');

    final remainingBefore = c.restRemainingMs.value;
    final prefsEndAtBefore = prefs.getInt('rest.endAt');
    c.extendRest(30);
    expect(c.restRemainingMs.value, remainingBefore + 30000,
        reason: '暂停态加时立即反映在剩余时间上');
    expect(prefs.getInt('rest.endAt'), prefsEndAtBefore,
        reason: '暂停态加时不写 prefs');
    expect(c.restEndAt, endAfterStart, reason: '暂停态不改动 restEndAt');

    c.resumeRest();
    expect(c.isRestPaused, isFalse);
    expect(c.restEndAt, greaterThan(endAfterStart),
        reason: '继续后按冻结剩余+加时重算结束时刻');
    expect(prefs.getInt('rest.endAt'), c.restEndAt);
    expect(alarmCalls.last, c.restEndAt, reason: '恢复时重挂闹钟到新时刻');
    expect(c.restEndAt - DateTime.now().millisecondsSinceEpoch,
        closeTo(remainingBefore + 30000, 2000),
        reason: 'resume 保留暂停态加的 30 秒，不再被静默丢弃');

    // 等 completeSet → _beginRestFor 的异步续体（预载下一动作上下文）跑完，
    // 避免它在 tearDown dispose 之后才 notifyListeners 报"used after dispose"。
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });

  test('B1：同一动作组间休息保留手动调过的重量，换动作才重新推荐', () async {
    final day = await makePlanDay('日');
    final a = await addPlanEx(day, '动作甲', 0, sets: 2, workingSets: 2);
    final b = await addPlanEx(day, '动作乙', 1, sets: 1, workingSets: 1);

    final c = makeController();
    await c.startFromDay(day: day, planExercises: [a, b]);
    // 推荐值是内置起始 20：手动加重后做一组
    c.setWeightDraft(62.5);
    await c.completeSet(
        weight: 62.5, reps: 8, rir: 2, kind: SetKind.working);
    expect(c.phase, WorkoutPhase.resting);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(c.weightDraft, 62.5,
        reason: '同动作继续：手动调过的重量不被推荐值冲掉');

    // 记满动作甲 → 推进到动作乙：换动作才刷新推荐重量
    await c.completeSet(
        weight: c.weightDraft, reps: 8, rir: 2, kind: SetKind.working);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(c.curExIdx, 1);
    expect(c.weightDraft, presetStartOf('动作乙'),
        reason: '无历史的动作用内置起始重量');
  });

  test('B2：动作练满进休息可回退加练一组，加练按正式组记录', () async {
    final day = await makePlanDay('日');
    final a = await addPlanEx(day, '动作甲', 0, sets: 1, workingSets: 1);
    final b = await addPlanEx(day, '动作乙', 1, sets: 1, workingSets: 1);

    final c = makeController();
    await c.startFromDay(day: day, planExercises: [a, b]);
    await c.completeSet(
        weight: 60, reps: 8, rir: 2, kind: SetKind.working);
    expect(c.curExIdx, 1, reason: '动作甲练满已推进');
    expect(c.extraSetExerciseName, '动作甲', reason: '休息页应有加练入口');

    await c.startExtraSet();
    expect(c.phase, WorkoutPhase.lifting);
    expect(c.curExIdx, 0);
    expect(c.extraSetExerciseName, isNull);
    expect(c.workingSetsDone, 1);

    // 加练一组：作为正式组落库
    await c.completeSet(
        weight: 60, reps: 8, rir: 2, kind: SetKind.working);
    final map = await db.setsOfSession(c.session!.id!);
    final working = (map[c.exercises[0].id] ?? [])
        .where((e) => e.kind == SetKind.working)
        .length;
    expect(working, 2, reason: '加练组按正式组记录');
    expect(c.curExIdx, 1, reason: '加练满后再次推进到下一动作');
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });

  test('B6：组间（未练满）休息也有「再来一组」，重量继承最后一组实际值', () async {
    final day = await makePlanDay('日');
    final a = await addPlanEx(day, '动作甲', 0, sets: 3, workingSets: 3);

    final c = makeController();
    await c.startFromDay(day: day, planExercises: [a]);
    c.setWeightDraft(52.5); // 手调重量（推荐 20）
    await c.completeSet(
        weight: 52.5, reps: 8, rir: 2, kind: SetKind.working);
    expect(c.phase, WorkoutPhase.resting);
    expect(c.workingSetsDone, 1, reason: '只做了 1/3 组，未练满');
    expect(c.extraSetExerciseName, '动作甲',
        reason: '组间休息也提供「再来一组」回到本动作');

    await c.startExtraSet();
    expect(c.phase, WorkoutPhase.lifting);
    expect(c.weightDraft, 52.5,
        reason: '再来一组继承最后一组实际重量，不被推荐值冲回');
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });

  test('B7：负重量（辅助器械配重）可记录、容量按 0 计、跨次渐进', () async {
    final day = await makePlanDay('日');
    final a = await addPlanEx(day, '引体向上', 0, sets: 1, workingSets: 1);

    final c = makeController();
    await c.startFromDay(day: day, planExercises: [a]);

    c.setWeightDraft(-30); // 辅助配重 30kg：从自重 0 往下减
    expect(c.weightDraft, -30, reason: '负值保留，不再被钳到 0');
    await c.completeSet(
        weight: -30, reps: 8, rir: 2, kind: SetKind.working);
    final stats = await c.stats();
    expect(stats.volume, 0, reason: '辅助配重按 0 容量计（不回减总容量）');

    // 下次训练该动作：历史 -30 达标 → 推荐 -27.5（辅助减少 = 进步）
    await c.finish();
    final c2 = makeController();
    await c2.startFromDay(day: day, planExercises: [a]);
    expect(c2.weightDraft, -27.5,
        reason: '负重量同样渐进，不再卡死在原配重');
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });

  test('B8：toggleBodyweightDraft 对辅助配重态一键归零；下限 -300 防手抖', () async {
    final day = await makePlanDay('日');
    final a = await addPlanEx(day, '引体向上', 0, sets: 1, workingSets: 1);

    final c = makeController();
    await c.startFromDay(day: day, planExercises: [a]);
    c.setWeightDraft(-30);
    c.toggleBodyweightDraft();
    expect(c.weightDraft, 0, reason: '辅助态点一下切回纯自重');

    c.setWeightDraft(-5000);
    expect(c.weightDraft, -300, reason: '负值下限 -300kg');
  });

  test('B9：手动改重量并完成后，下次训练直接从实际重量开始（不回计划初始）', () async {
    final day = await makePlanDay('日');
    final a = await addPlanEx(day, '动作甲', 0, sets: 2, workingSets: 2);

    final c = makeController();
    await c.startFromDay(day: day, planExercises: [a]);
    final base = c.weightDraft; // 无历史：内置起始重量
    c.setWeightDraft(base + 40); // 手动加 40kg（换器械/个人偏好）
    await c.completeSet(
        weight: c.weightDraft, reps: 7, rir: 2, kind: SetKind.working);
    await c.completeSet(
        weight: c.weightDraft, reps: 7, rir: 2, kind: SetKind.working);
    await c.finish();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    // 下次训练：次数在区间内但未全达上限 → 渐进判 hold（+0），
    // 推荐重量 = 上次实际重量——手动调整无需每次重来
    final c2 = makeController();
    await c2.startFromDay(day: day, planExercises: [a]);
    expect(c2.weightDraft, base + 40,
        reason: '下次训练从上次实际重量开始，手动调整被记住');
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });

  test('B3：训练中可追加动作、可替换未记组动作，已记组不可替换', () async {
    final day = await makePlanDay('日');
    final a = await addPlanEx(day, '动作甲', 0, sets: 3, workingSets: 3);

    final c = makeController();
    await c.startFromDay(day: day, planExercises: [a]);

    await c.appendExercises(const [
      ExerciseMeta('临时动作', MuscleGroups(main: '胸'), true),
    ]);
    expect(c.exercises.length, 2);
    expect(c.exercises.last.name, '临时动作');
    expect(c.exercises.last.orderIdx, 1, reason: '追加到队尾');
    final added = await rawDb
        .query('session_exercises', where: "name = '临时动作'");
    expect(added.length, 1, reason: '追加动作落库');

    // 当前动作还没记组：可替换（沿用规则只换名）
    final ok = await c.replaceCurrentExercise(
        const ExerciseMeta('替换动作', MuscleGroups(main: '背'), false));
    expect(ok, isTrue);
    expect(c.exercises[0].name, '替换动作');
    final renamed = await rawDb.query('session_exercises',
        where: 'id = ?', whereArgs: [c.exercises[0].id]);
    expect(renamed.first['name'], '替换动作');

    // 已记组：不可替换（防把已记的组串到别的动作名下）
    await c.completeSet(
        weight: 60, reps: 8, rir: 2, kind: SetKind.working);
    final ok2 = await c.replaceCurrentExercise(
        const ExerciseMeta('再换一个', MuscleGroups(main: '肩'), false));
    expect(ok2, isFalse);
    expect(c.exercises[0].name, '替换动作');
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });

  test('B4：休息减时有 5 秒地板，不把剩余时间减穿（暂停态同理）', () async {
    final day = await makePlanDay('日');
    final a = await addPlanEx(day, '动作甲', 0,
        sets: 3, workingSets: 3, restSec: 120);

    final c = makeController();
    await c.startFromDay(day: day, planExercises: [a]);
    await c.completeSet(
        weight: 60, reps: 8, rir: 2, kind: SetKind.working);
    expect(c.phase, WorkoutPhase.resting);

    c.extendRest(-118); // 120 - 118 ≈ 2s → 地板抬到 5s
    expect(c.restEndAt - DateTime.now().millisecondsSinceEpoch,
        closeTo(5000, 1500));

    c.pauseRest();
    c.extendRest(-30); // 剩余 ≈5s，减 30 也被地板挡住
    expect(c.restRemainingMs.value, 5000);
    c.resumeRest();
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });

  test('B5：restoreFromJson 清空恢复后外键关系完整，缺段报错且不动数据', () async {
    final plan = await db.insertPlan(Plan(
        name: '计划', source: 'manual', createdAt: '2026-09-24', isActive: 1));
    final dayId = await db.insertPlanDay(
        PlanDay(planId: plan.id!, weekday: 1, title: '推日'));
    await db.insertPlanExercise(PlanExercise(
        dayId: dayId,
        name: '卧推',
        orderIdx: 0,
        sets: 3,
        repsMin: 5,
        repsMax: 8,
        restSec: 120,
        kind: 'compound',
        rule: ProgressionRule.fallback));
    final s = await db.insertSession(Session(
        date: '2026-09-20',
        planDayTitle: '推日',
        startedAt: 1,
        endedAt: 2,
        status: 'done'));
    final se = await db.insertSessionExercise(SessionExercise(
        sessionId: s.id!,
        name: '卧推',
        orderIdx: 0,
        kind: 'compound',
        rule: ProgressionRule.fallback));
    await db.insertSet(SetEntry(
        sessionExerciseId: se,
        weightKg: 60,
        reps: 8,
        kind: SetKind.working,
        doneAt: 1000,
        note: '状态好'));
    await db.upsertBodyMetric(const BodyMetric(
        date: '2026-09-21', weightKg: 70.5));

    final data = await db.exportAllJson();
    final svc = ExportService(db);
    final n = await svc.restoreFromJson(data);
    expect(n, 1);

    // 清空重灌后，会话→动作→组 的外键链与计划/身体数据完整
    final sessions = await db.recentSessions(limit: 100);
    expect(sessions.length, 1);
    final ses = await db.sessionExercises(sessions.first.id!);
    expect(ses.length, 1);
    final sets = await db.setsOfSession(sessions.first.id!);
    expect(sets[ses.first.id]!.length, 1);
    expect(sets[ses.first.id]!.first.note, '状态好');
    expect((await db.allPlans()).length, 1);
    expect((await db.bodyMetrics()).length, 1);

    // 缺关键段：抛 FormatException，且在清库之前校验（现有数据不动）
    expect(() => svc.restoreFromJson({'sessions': []}),
        throwsFormatException);
    expect((await db.recentSessions(limit: 100)).length, 1);
  });
}
