import 'package:flutter/foundation.dart';

import '../db/db.dart';
import '../engine/engine.dart';
import '../presets/baoji_plan.dart';
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

  /// 复制计划（含全部训练日与动作），新计划不启用。返回新计划 id。
  Future<int> duplicatePlan(int sourcePlanId, String newName) async {
    final srcDays = await _db.planDays(sourcePlanId);
    final srcEx = await _db.daysExercisesMap(srcDays.map((d) => d.id!).toList());
    final newPlan = await _db.insertPlan(Plan(
      name: newName,
      source: 'copy',
      createdAt: fmtDate(DateTime.now()),
      isActive: 0,
    ));
    for (final day in srcDays) {
      final newDayId = await _db.insertPlanDay(PlanDay(
        planId: newPlan.id!,
        weekday: day.weekday,
        title: day.title,
        notes: day.notes,
      ));
      var i = 0;
      for (final ex in srcEx[day.id!] ?? const <PlanExercise>[]) {
        await _db.insertPlanExercise(ex.copyWith(dayId: newDayId, orderIdx: i++));
      }
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

  /// 某计划的飞书日历同步规格（未来日程写入用）。
  Future<List<PlanDaySyncSpec>> larkSpecsForPlan(int planId) async {
    final days = await _db.planDays(planId);
    final exMap =
        await _db.daysExercisesMap(days.map((d) => d.id!).toList());
    final specs = <PlanDaySyncSpec>[];
    for (final d in days) {
      final exs = exMap[d.id!] ?? const <PlanExercise>[];
      if (exs.isEmpty) continue;
      specs.add(PlanDaySyncSpec(
        planDayId: d.id!,
        weekday: d.weekday,
        title: d.title,
        detail: exs
            .map((e) => '· ${e.name} ${e.sets}×${e.repsMin}-${e.repsMax}')
            .join('\n'),
      ));
    }
    return specs;
  }

  /// 首次安装内置薄肌计划。已装过（同名 preset）则直接启用它，防双击装两份。
  Future<Plan> installBaojiPlan() async {
    final existing = await _db.allPlans();
    final preset =
        existing.where((p) => p.source == 'preset').firstOrNull;
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
    for (final m in metaMap.values) {
      await _db.upsertExerciseMeta(m);
    }
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
  final int sets;
  final int repsMin;
  final int repsMax;
  final int? restSec;
  final String? kind;
  final String? mainMuscle; // AI 判定的主肌群（词表外动作的兜底）
  const AiExerciseSpec({
    required this.name,
    required this.sets,
    required this.repsMin,
    required this.repsMax,
    this.restSec,
    this.kind,
    this.mainMuscle,
  });
}
