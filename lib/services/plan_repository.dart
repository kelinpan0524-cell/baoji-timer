import 'package:flutter/foundation.dart';

import '../db/db.dart';
import '../engine/engine.dart';
import '../presets/baoji_plan.dart';
import '../presets/exercise_library.dart';
import '../services/lark_service.dart';
import 'settings.dart';

/// 计划仓库：安装内置计划、AI 计划落库、今日训练生成（含渐进推荐）。
class PlanRepository extends ChangeNotifier {
  PlanRepository(this._db, this._settings);

  final Db _db;
  final Settings _settings;

  Plan? activePlan;
  Map<int, List<PlanExercise>> exercisesByDayId = {};
  List<PlanDay> days = [];

  /// 全部计划（多计划管理/切换器用）。
  List<Plan> allPlansCache = [];

  Future<void> reload({bool includeAll = false}) async {
    activePlan = await _db.activePlan();
    if (includeAll) {
      allPlansCache = await _db.allPlans();
    }
    if (activePlan == null) {
      days = [];
      exercisesByDayId = {};
      notifyListeners();
      return;
    }
    days = await _db.planDays(activePlan!.id!);
    exercisesByDayId =
        await _db.daysExercisesMap(days.map((d) => d.id!).toList());
    notifyListeners();
  }

  /// 某计划的全部训练日（不限激活计划）。
  Future<List<PlanDay>> daysOfPlan(int planId) => _db.planDays(planId);

  Future<Map<int, List<PlanExercise>>> exercisesOfDays(List<int> dayIds) =>
      _db.daysExercisesMap(dayIds);

  /// 计划里「有动作」的模板日数——循环排程每轮真正会轮到的训练日上限。
  /// 连练天数小于它时，多出的模板日在推导里永远轮不到（排程页据此警示）。
  Future<int> trainableDayCount(int planId) async {
    final days = await _db.planDays(planId);
    if (days.isEmpty) return 0;
    final exMap = await _db.daysExercisesMap(days.map((e) => e.id!).toList());
    var n = 0;
    for (final day in days) {
      if ((exMap[day.id] ?? const <PlanExercise>[]).isNotEmpty) n++;
    }
    return n;
  }

  /// 复制计划（含全部训练日与动作与排程模式），新计划不启用。返回新计划 id。
  Future<int> duplicatePlan(int sourcePlanId, String newName) async {
    final srcDays = await _db.planDays(sourcePlanId);
    final srcEx = await _db.daysExercisesMap(srcDays.map((d) => d.id!).toList());
    final plans = await _db.allPlans();
    final src = plans.where((p) => p.id == sourcePlanId).firstOrNull;
    final newPlan = await _db.insertPlan(Plan(
      name: newName,
      source: 'copy',
      createdAt: fmtDate(DateTime.now()),
      isActive: 0,
      pattern: src?.pattern ?? 'weekly',
      patternStart: src?.patternStart ?? '',
      cycleTrain: src?.cycleTrain ?? 0,
      cycleRest: src?.cycleRest ?? 0,
    ));
    // 旧 id → 新 id 映射：排程覆盖行跟着复制（改期历史不丢）
    final idMap = <int, int>{};
    for (final day in srcDays) {
      final newDayId = await _db.insertPlanDay(PlanDay(
        planId: newPlan.id!,
        weekday: day.weekday,
        title: day.title,
        notes: day.notes,
      ));
      idMap[day.id!] = newDayId;
      var i = 0;
      for (final ex in srcEx[day.id!] ?? const <PlanExercise>[]) {
        await _db.insertPlanExercise(ex.copyWith(dayId: newDayId, orderIdx: i++));
      }
    }
    for (final e in await _db.allScheduleEntries(sourcePlanId)) {
      await _db.upsertScheduleEntry(PlanScheduleEntry(
        planId: newPlan.id!,
        date: e.date,
        dayId: e.dayId == null ? null : idMap[e.dayId!],
      ));
    }
    return newPlan.id!;
  }

  /// 删除计划后若没有启用中的计划，自动启用最近的一个。
  Future<void> deletePlanAndFixActive(int planId) async {
    final wasActive = activePlan?.id == planId;
    await _db.deletePlan(planId);
    if (wasActive) {
      final rest = await _db.allPlans();
      if (rest.isNotEmpty) {
        await _db.setActivePlan(rest.first.id!);
      }
    }
    activePlan = await _db.activePlan();
  }

  /// 某计划的飞书日历同步规格（未来 14 天，逐日按排程解析出具体日期）。
  Future<List<PlanDaySyncSpec>> larkSpecsForPlan(int planId) async {
    final plans = await _db.allPlans();
    final plan = plans.where((p) => p.id == planId).firstOrNull;
    if (plan == null) return [];
    final specs = <PlanDaySyncSpec>[];
    final today = DateTime.now();
    for (var i = 0; i < 14; i++) {
      final d = today.add(Duration(days: i));
      final day = await dayForDateOn(plan, d);
      if (day == null) continue;
      final exs = await _db.dayExercises(day.id!);
      if (exs.isEmpty) continue;
      specs.add(PlanDaySyncSpec(
        planDayId: day.id!,
        date: fmtDate(d),
        title: day.title,
        detail: exs
            .map((e) => '· ${e.name} ${e.sets}×${e.repsMin}-${e.repsMax}')
            .join('\n'),
      ));
    }
    return specs;
  }

  /// 把全量内置动作库写入 exercise_meta（App 首启/模板安装时调用，幂等）。
  Future<void> seedExerciseLibrary() async {
    for (final m in kExerciseLibrary) {
      await _db.upsertExerciseMeta(m);
    }
  }

  /// 安装计划模板（三分化/五分化/功能性/居家…）。
  /// 查重带来源校验（对齐 installBaojiPlan）：只有同名**且同源（preset）**的模板
  /// 已存在才算已安装；用户自建（manual）的同名计划不受影响。
  /// 返回 (计划, 是否新建)——命中同名返回 (same, false)，新建返回 (plan, true)。
  Future<(Plan, bool)> installTemplate(PlanTemplate template,
      {bool activate = true}) async {
    await seedExerciseLibrary();
    final existing = await _db.allPlans();
    final same = existing
        .where((p) => p.source == template.source && p.name == template.name)
        .firstOrNull;
    if (same != null) {
      if (activate) await _db.setActivePlan(same.id!);
      await reload(includeAll: true);
      return (same, false);
    }
    final plan = await _db.insertPlan(Plan(
      name: template.name,
      source: template.source,
      createdAt: fmtDate(DateTime.now()),
      isActive: 0,
    ));
    // 按星期升序编号：「第 N 练」是模板内第几个训练日，
    // 非连练模板（如 1/3/5）不再出现序号=星期数的错误
    var seq = 0;
    final weekdays = template.byWeekday.keys.toList()..sort();
    for (final weekday in weekdays) {
      seq++;
      final dayId = await _db.insertPlanDay(PlanDay(
        planId: plan.id!,
        weekday: weekday,
        title: _templateDayTitle(weekday, seq),
      ));
      var i = 0;
      for (final pe in template.byWeekday[weekday]!) {
        await _db.insertPlanExercise(
            pe.toPlanExercise(dayId, i++));
      }
    }
    if (activate) {
      await _db.setActivePlan(plan.id!);
    }
    await reload(includeAll: true);
    return (plan, true);
  }

  /// 模板训练日标题：'周X · 第 seq 练'（seq = 模板内第几个训练日，按星期升序）。
  String _templateDayTitle(int weekday, int seq) {
    const wd = '一二三四五六日';
    return '周${wd[weekday - 1]} · 第 $seq 练';
  }

  /// 首次安装内置薄肌计划。已装过（同名 preset）则直接启用它，防双击装两份。
  Future<Plan> installBaojiPlan() async {
    await seedExerciseLibrary();
    final existing = await _db.allPlans();
    final preset =
        existing.where((p) => p.source == 'preset' && p.name == kBaojiPlanName).firstOrNull;
    if (preset != null) {
      await _db.setActivePlan(preset.id!);
      await reload();
      return preset;
    }
    final plan = await _db.insertPlan(Plan(
      name: kBaojiPlanName,
      source: 'preset',
      createdAt: fmtDate(DateTime.now()),
    ));
    for (final entry in kBaojiExercisesByWeekday.entries) {
      final dayId = await _db.insertPlanDay(PlanDay(
        planId: plan.id!,
        weekday: entry.key,
        title: kBaojiDayTitles[entry.key] ?? '训练日',
      ));
      var i = 0;
      for (final pe in entry.value) {
        await _db.insertPlanExercise(pe.toPlanExercise(dayId, i++));
      }
    }
    for (final meta in kBaojiExerciseMeta) {
      await _db.upsertExerciseMeta(meta);
    }
    await _db.setActivePlan(plan.id!);
    await reload();
    return plan;
  }

  /// 把 AI 拆解结果落库为一个新的计划并激活。
  /// 落库前二次清洗（与 parseResponse 的清洗互为兜底）：weekday 越界跳过、
  /// 同 weekday 合并、sets/reps 钳制；main_muscle 词形归一（"背部"→"背"）。
  Future<Plan> saveAiPlan({
    required String name,
    required List<AiDaySpec> specs,
    required Map<String, ExerciseMeta> metaMap,
    bool activate = true,
  }) async {
    final clean = <AiDaySpec>[];
    final byWeekday = <int, int>{};
    for (final spec in specs) {
      if (spec.weekday < 1 || spec.weekday > 7) continue;
      final idx = byWeekday[spec.weekday];
      if (idx == null) {
        byWeekday[spec.weekday] = clean.length;
        clean.add(spec);
      } else {
        final old = clean[idx];
        clean[idx] = AiDaySpec(old.weekday, old.title, [...old.exercises, ...spec.exercises]);
      }
    }
    final plan = await _db.insertPlan(Plan(
      name: name,
      source: 'ai',
      createdAt: fmtDate(DateTime.now()),
    ));
    for (final spec in clean) {
      final dayId = await _db.insertPlanDay(PlanDay(
        planId: plan.id!,
        weekday: spec.weekday,
        title: spec.title,
      ));
      var i = 0;
      for (final ex in spec.exercises) {
        final meta = metaMap[ex.name];
        // 词表外动作：用 AI 判定的肌群沉淀进动作库，热力图才能正确归类；
        // 词形归一：AI 常回 "背部"/"腿部"，匹配含"部"字的肌群名
        final muscleToken = ex.mainMuscle;
        final normalizedMuscle = muscleToken == null
            ? null
            : kMuscleRegions.firstWhere(
                (r) => r == muscleToken || muscleToken.contains(r),
                orElse: () => '');
        if (meta == null &&
            normalizedMuscle != null &&
            normalizedMuscle.isNotEmpty) {
          final newMeta = ExerciseMeta(
            ex.name,
            MuscleGroups(main: normalizedMuscle),
            ex.kind == 'compound',
          );
          metaMap[ex.name] = newMeta;
          await _db.upsertExerciseMeta(newMeta);
        }
        final kind = meta?.isCompound == true
            ? 'compound'
            : (ex.kind ?? 'assistance');
        await _db.insertPlanExercise(PlanExercise(
          dayId: dayId,
          name: ex.name,
          orderIdx: i++,
          sets: ex.sets,
          repsMin: ex.repsMin,
          repsMax: ex.repsMax,
          restSec: ex.restSec ??
              defaultRestSec(kind,
                  compound: _settings.restCompoundSec,
                  assistance: _settings.restAssistanceSec),
          kind: kind,
          rule: ProgressionRule(
            repsMin: ex.repsMin,
            repsMax: ex.repsMax,
            incrementKg: kind == 'compound' ? 2.5 : 1.25,
            workingSets: ex.sets,
          ),
        ));
      }
    }
    // 注意：这里不做 metaMap 全量落库——词表外新动作已在上面逐条沉淀，
    // 全量 REPLACE 会把用户在编辑器改过的肌群/器械标注静默重置回内置默认。
    if (activate) {
      await _db.setActivePlan(plan.id!);
    }
    await reload(includeAll: true);
    return plan;
  }

  /// 今天的 PlanDay（无则 null）。
  PlanDay? dayForWeekday(int weekday) {
    for (final d in days) {
      if (d.weekday == weekday) return d;
    }
    return null;
  }

  // ================= 日期化排程 =================
  //
  // 解析优先级：手动覆盖行（plan_schedule，含"显式休息"墓碑）
  //   > 循环推导（练 N 休 M，按 patternStart 纯数学算，不落库）
  //   > 按星期模板（旧行为）。
  // 手动拖动/添加/清空只写覆盖行；没动过的日子永远跟随模板/循环规则。

  /// 激活计划在某天该练什么（首页/计划页/飞书同步共用）。
  Future<PlanDay?> dayForDate(DateTime d) async {
    final plan = activePlan;
    if (plan?.id == null) return null;
    return dayForDateOn(plan!, d);
  }

  Future<PlanDay?> dayForDateOn(Plan plan, DateTime d) async {
    if (plan.id == null) return null;
    final override = await _db.scheduleEntryOn(plan.id!, fmtDate(d));
    if (override != null) {
      if (override.dayId == null) return null; // 显式休息
      return await _db.planDayById(override.dayId!);
    }
    if (plan.isCycle) return _cycleDayFor(plan, d);
    return _dayForWeekdayOn(plan, d.weekday);
  }

  /// 某计划的星期模板日（不依赖激活缓存）。
  Future<PlanDay?> _dayForWeekdayOn(Plan plan, int weekday) async {
    final days = await _db.planDays(plan.id!);
    for (final d in days) {
      if (d.weekday == weekday) return d;
    }
    return null;
  }

  /// 循环推导：patternStart 起第 k 天，k % (练N+休M) < N → 按顺序循环用模板日。
  /// 只取有动作的模板日（空模板日跳过，避免循环到"空训练日"）。
  Future<PlanDay?> _cycleDayFor(Plan plan, DateTime d) async {
    if (plan.patternStart.isEmpty || plan.cycleTrain <= 0) return null;
    final period = plan.cycleTrain + (plan.cycleRest > 0 ? plan.cycleRest : 0);
    if (period <= 0) return null;
    final start = parseDate(plan.patternStart);
    final k = DateTime(d.year, d.month, d.day)
        .difference(DateTime(start.year, start.month, start.day))
        .inDays;
    if (k < 0) return null;
    final pos = k % period;
    if (pos >= plan.cycleTrain) return null; // 循环里的休息日
    final days = await _db.planDays(plan.id!);
    final exMap = await _db.daysExercisesMap(days.map((e) => e.id!).toList());
    final trainable = <PlanDay>[];
    for (final day in days) {
      if ((exMap[day.id] ?? const <PlanExercise>[]).isNotEmpty) {
        trainable.add(day);
      }
    }
    if (trainable.isEmpty) return null;
    return trainable[pos % trainable.length];
  }

  /// 手动覆盖：把某天设为指定模板日（dayId=null = 显式休息）。
  Future<void> setOverride(Plan plan, DateTime d, int? dayId) async {
    await _db.upsertScheduleEntry(
        PlanScheduleEntry(planId: plan.id!, date: fmtDate(d), dayId: dayId));
  }

  /// 清除某天覆盖行：回到按模板/循环的默认推导。
  Future<void> clearOverride(Plan plan, DateTime d) async {
    final e = await _db.scheduleEntryOn(plan.id!, fmtDate(d));
    if (e != null) await _db.deleteScheduleEntry(e.id!);
  }

  /// 拖拉改期：把 from 日的训练挪到 to 日；to 日已有训练则两天内容互换。
  /// from 出发后落"显式休息"墓碑，推导不会再把训练填回来。
  Future<void> moveScheduleDay(Plan plan, DateTime from, DateTime to) async {
    final fDate = fmtDate(from);
    final tDate = fmtDate(to);
    if (fDate == tDate) return;
    final fromEntry = await _db.scheduleEntryOn(plan.id!, fDate);
    final toEntry = await _db.scheduleEntryOn(plan.id!, tDate);
    final fromDay = fromEntry != null && fromEntry.dayId != null
        ? await _db.planDayById(fromEntry.dayId!)
        : await dayForDateOn(plan, from);
    if (fromDay == null) return; // 起点没有训练可挪
    final toDayId = toEntry != null
        ? toEntry.dayId
        : (await dayForDateOn(plan, to))?.id; // 目的地按规则本有训练 → 互换
    await _db.upsertScheduleEntry(PlanScheduleEntry(
        planId: plan.id!, date: tDate, dayId: fromDay.id));
    await _db.upsertScheduleEntry(PlanScheduleEntry(
        planId: plan.id!, date: fDate, dayId: toDayId));
  }

  /// 更新计划的排程模式/循环参数（patternStart 的唯一写入口）。
  Future<void> updateSchedulePattern({
    required int planId,
    required String pattern,
    String? patternStart,
    int cycleTrain = 0,
    int cycleRest = 0,
  }) async {
    await _db.updatePlanFields(planId, {
      'pattern': pattern,
      'pattern_start': ?patternStart,
      'cycle_train': cycleTrain,
      'cycle_rest': cycleRest,
    });
  }

  /// 某动作的建议重量：历史渐进推荐 → 内置起始重量 → 20kg。
  double recommendedWeight(String name) {
    return _recommendCache[name] ?? _presetStart(name) ?? 20;
  }

  final Map<String, double> _recommendCache = {};

  /// 训练开始前刷新所有推荐重量（读历史，开销小）。
  Future<void> refreshRecommendations(Iterable<String> names) async {
    for (final n in names) {
      final rule = _ruleFor(n);
      final history = await _db.historySets(n);
      final rec = recommendWeight(
          historyWorkingSets:
              history.where((s) => s.kind == SetKind.working).toList(),
          rule: rule);
      if (rec != null) _recommendCache[n] = rec;
    }
  }

  ProgressionRule _ruleFor(String name) {
    for (final list in exercisesByDayId.values) {
      for (final ex in list) {
        if (ex.name == name) return ex.rule;
      }
    }
    return ProgressionRule.fallback;
  }

  double? _presetStart(String name) {
    for (final list in kBaojiExercisesByWeekday.values) {
      for (final pe in list) {
        if (pe.name == name) return pe.startWeightKg;
      }
    }
    return null;
  }
}

/// AI 拆解中间结构（服务层产出 → 仓库落库）。
class AiDaySpec {
  final int weekday;
  final String title;
  final List<AiExerciseSpec> exercises;
  const AiDaySpec(this.weekday, this.title, this.exercises);
}

class AiExerciseSpec {
  final String name;

  /// AI 输出的原始动作名（调研条目 12：预览页逐动作确认的数据锚点）。
  final String rawName;

  /// 六级匹配未自动命中（模糊级 score/覆盖率不达标）→ 预览页需人工确认。
  final bool needsConfirm;

  /// 匹配候选（top5，按相似度升序失败即按编辑距离排序），预览页点选替换。
  final List<String> candidates;
  final int sets;
  final int repsMin;
  final int repsMax;
  final int? restSec;
  final String? kind;
  final String? mainMuscle; // AI 判定的主肌群（词表外动作的兜底）
  const AiExerciseSpec({
    required this.name,
    this.rawName = '',
    this.needsConfirm = false,
    this.candidates = const [],
    required this.sets,
    required this.repsMin,
    required this.repsMax,
    this.restSec,
    this.kind,
    this.mainMuscle,
  });

  /// 预览页确认后替换动作名（并解除待确认态）。
  AiExerciseSpec withName(String newName) => AiExerciseSpec(
        name: newName,
        rawName: rawName,
        needsConfirm: false,
        candidates: const [],
        sets: sets,
        repsMin: repsMin,
        repsMax: repsMax,
        restSec: restSec,
        kind: kind,
        mainMuscle: mainMuscle,
      );
}
