// 数据模型：全部手写可序列化类，不引入代码生成。
// 约定：时间一律 epoch 毫秒（int）；日期一律 "yyyy-MM-dd"（本地时区）字符串。
import 'dart:convert';

class MuscleGroups {
  final String main;
  final List<String> secondary;
  const MuscleGroups({required this.main, this.secondary = const []});

  Map<String, dynamic> toJson() => {'main': main, 'secondary': secondary};
  factory MuscleGroups.fromJson(Map<String, dynamic> j) => MuscleGroups(
        main: (j['main'] as String?) ?? '其他',
        secondary: ((j['secondary'] as List?) ?? [])
            .map((e) => e.toString())
            .toList(),
      );
}

/// 渐进超负荷规则（存 plan_exercises.rule JSON）
class ProgressionRule {
  final int repsMin;
  final int repsMax;
  final double incrementKg; // 达标加重量
  final int rirTarget; // 末组目标余力
  final int workingSets;
  final String desc;

  const ProgressionRule({
    required this.repsMin,
    required this.repsMax,
    this.incrementKg = 2.5,
    this.rirTarget = 2,
    this.workingSets = 3,
    this.desc = '全部正式组达到次数上限且末组余力达标则加重；连续两次未达下限则减重 5%',
  });

  Map<String, dynamic> toJson() => {
        'reps_min': repsMin,
        'reps_max': repsMax,
        'increment_kg': incrementKg,
        'rir_target': rirTarget,
        'working_sets': workingSets,
        'desc': desc,
      };

  factory ProgressionRule.fromJson(Map<String, dynamic> j) => ProgressionRule(
        repsMin: (j['reps_min'] as num?)?.toInt() ?? 5,
        repsMax: (j['reps_max'] as num?)?.toInt() ?? 8,
        incrementKg: (j['increment_kg'] as num?)?.toDouble() ?? 2.5,
        rirTarget: (j['rir_target'] as num?)?.toInt() ?? 2,
        workingSets: (j['working_sets'] as num?)?.toInt() ?? 3,
        desc: (j['desc'] as String?) ?? '全部正式组达到次数上限且末组余力达标则加重',
      );

  static const ProgressionRule fallback =
      ProgressionRule(repsMin: 5, repsMax: 8);
}

class Plan {
  final int? id;
  final String name;
  final String source; // preset | ai | manual
  final String createdAt; // yyyy-MM-dd
  final int isActive; // 0/1

  /// 排程模式：weekly=按星期（固定周几）；cycle=循环「练 N 休 M」。
  final String pattern;

  /// cycle 模式的推导锚点：从这天起第 0 天开始 练N休M（空 = 首次设置时写今天）。
  final String patternStart;

  /// cycle 模式参数：连练 N 天、休 M 天（如"隔两天休息一天"= 练2休1）。
  final int cycleTrain;
  final int cycleRest;

  const Plan({
    this.id,
    required this.name,
    required this.source,
    required this.createdAt,
    this.isActive = 1,
    this.pattern = 'weekly',
    this.patternStart = '',
    this.cycleTrain = 0,
    this.cycleRest = 0,
  });

  bool get isCycle => pattern == 'cycle';

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'source': source,
        'created_at': createdAt,
        'is_active': isActive,
        'pattern': pattern,
        'pattern_start': patternStart,
        'cycle_train': cycleTrain,
        'cycle_rest': cycleRest,
      };

  factory Plan.fromMap(Map<String, dynamic> m) => Plan(
        id: m['id'] as int?,
        name: (m['name'] as String?) ?? '',
        source: (m['source'] as String?) ?? 'manual',
        createdAt: (m['created_at'] as String?) ?? '',
        isActive: (m['is_active'] as int?) ?? 0,
        pattern: (m['pattern'] as String?) ?? 'weekly',
        patternStart: (m['pattern_start'] as String?) ?? '',
        cycleTrain: (m['cycle_train'] as num?)?.toInt() ?? 0,
        cycleRest: (m['cycle_rest'] as num?)?.toInt() ?? 0,
      );

  Plan copyWith({
    int? id,
    String? name,
    int? isActive,
    String? pattern,
    String? patternStart,
    int? cycleTrain,
    int? cycleRest,
  }) =>
      Plan(
        id: id ?? this.id,
        name: name ?? this.name,
        source: source,
        createdAt: createdAt,
        isActive: isActive ?? this.isActive,
        pattern: pattern ?? this.pattern,
        patternStart: patternStart ?? this.patternStart,
        cycleTrain: cycleTrain ?? this.cycleTrain,
        cycleRest: cycleRest ?? this.cycleRest,
      );
}

class PlanDay {
  final int? id;
  final int planId;
  final int weekday; // 1=周一 ... 7=周日
  final String title;
  final String notes;

  const PlanDay({
    this.id,
    required this.planId,
    required this.weekday,
    required this.title,
    this.notes = '',
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'plan_id': planId,
        'weekday': weekday,
        'title': title,
        'notes': notes,
      };

  factory PlanDay.fromMap(Map<String, dynamic> m) => PlanDay(
        id: m['id'] as int?,
        planId: (m['plan_id'] as num).toInt(),
        weekday: (m['weekday'] as num).toInt(),
        title: (m['title'] as String?) ?? '',
        notes: (m['notes'] as String?) ?? '',
      );
}

/// 某具体日期的排程覆盖行：这天练 dayId 对应的模板日。
/// dayId = null 表示"显式休息"（循环推导本该练，但用户手动挪走/清掉了）。
/// 只在用户手动改期/添加/清空时写入——纯按星期或循环推导的日子不落行，
/// 这样改模板/改循环参数后未手动动过的日子自动跟随新规则。
class PlanScheduleEntry {
  final int? id;
  final int planId;
  final String date; // yyyy-MM-dd
  final int? dayId; // plan_days.id，null = 显式休息

  const PlanScheduleEntry({
    this.id,
    required this.planId,
    required this.date,
    this.dayId,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'plan_id': planId,
        'date': date,
        'day_id': dayId,
      };

  factory PlanScheduleEntry.fromMap(Map<String, dynamic> m) =>
      PlanScheduleEntry(
        id: m['id'] as int?,
        planId: (m['plan_id'] as num).toInt(),
        date: (m['date'] as String?) ?? '',
        dayId: m['day_id'] as int?,
      );
}

class PlanExercise {
  final int? id;
  final int dayId;
  final String name;
  final int orderIdx;
  final int sets;
  final int repsMin;
  final int repsMax;
  final int restSec;
  final String kind; // compound | assistance
  final ProgressionRule rule;

  const PlanExercise({
    this.id,
    required this.dayId,
    required this.name,
    required this.orderIdx,
    required this.sets,
    required this.repsMin,
    required this.repsMax,
    required this.restSec,
    required this.kind,
    required this.rule,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'day_id': dayId,
        'name': name,
        'order_idx': orderIdx,
        'sets': sets,
        'reps_min': repsMin,
        'reps_max': repsMax,
        'rest_sec': restSec,
        'kind': kind,
        'rule': ruleToJson(rule),
      };

  factory PlanExercise.fromMap(Map<String, dynamic> m) => PlanExercise(
        id: m['id'] as int?,
        dayId: (m['day_id'] as num).toInt(),
        name: (m['name'] as String?) ?? '',
        orderIdx: (m['order_idx'] as num?)?.toInt() ?? 0,
        sets: (m['sets'] as num?)?.toInt() ?? 3,
        repsMin: (m['reps_min'] as num?)?.toInt() ?? 5,
        repsMax: (m['reps_max'] as num?)?.toInt() ?? 8,
        restSec: (m['rest_sec'] as num?)?.toInt() ?? 120,
        kind: (m['kind'] as String?) ?? 'assistance',
        rule: ruleFromJson(m['rule']),
      );

  PlanExercise copyWith({
    int? id,
    int? dayId,
    String? name,
    int? orderIdx,
    int? sets,
    int? repsMin,
    int? repsMax,
    int? restSec,
    String? kind,
    ProgressionRule? rule,
  }) =>
      PlanExercise(
        id: id ?? this.id,
        dayId: dayId ?? this.dayId,
        name: name ?? this.name,
        orderIdx: orderIdx ?? this.orderIdx,
        sets: sets ?? this.sets,
        repsMin: repsMin ?? this.repsMin,
        repsMax: repsMax ?? this.repsMax,
        restSec: restSec ?? this.restSec,
        kind: kind ?? this.kind,
        rule: rule ?? this.rule,
      );
}

Object ruleToJson(ProgressionRule r) => jsonEncode(r.toJson());
ProgressionRule ruleFromJson(Object? v) {
  if (v == null) return ProgressionRule.fallback;
  if (v is Map) return ProgressionRule.fromJson(Map<String, dynamic>.from(v));
  if (v is String && v.isNotEmpty) {
    try {
      return ProgressionRule.fromJson(
          Map<String, dynamic>.from(jsonDecode(v) as Map));
    } catch (_) {
      return ProgressionRule.fallback;
    }
  }
  return ProgressionRule.fallback;
}

/// 训练动作库条目（用于肌肉映射、AI 拆解提示词与动作库浏览）
class ExerciseMeta {
  final String name;
  final MuscleGroups muscles;
  final bool isCompound;

  /// 器械场景：gym=健身房（杠铃/器械）、home=居家（哑铃/弹力带/自重）、both=皆可
  final String equipment;

  const ExerciseMeta(this.name, this.muscles, this.isCompound,
      [this.equipment = 'both']);

  String get equipmentLabel => switch (equipment) {
        'gym' => '健身房',
        'home' => '居家',
        _ => '皆可',
      };

  Map<String, dynamic> toMap() => {
        'name': name,
        'main_muscle': muscles.main,
        'secondary': muscles.secondary.join(','),
        'is_compound': isCompound ? 1 : 0,
        'equipment': equipment,
      };

  factory ExerciseMeta.fromMap(Map<String, dynamic> m) => ExerciseMeta(
        (m['name'] as String?) ?? '',
        MuscleGroups(
          main: (m['main_muscle'] as String?) ?? '其他',
          secondary: ((m['secondary'] as String?) ?? '')
              .split(',')
              .where((s) => s.isNotEmpty)
              .toList(),
        ),
        (m['is_compound'] as int?) == 1,
        (m['equipment'] as String?) ?? 'both',
      );
}

class Session {
  final int? id;
  final String date; // yyyy-MM-dd
  final int? planDayId;
  final String planDayTitle;
  final int startedAt; // epoch ms
  final int? endedAt;
  final String status; // active | done | quit
  final String notes;

  /// 休息/训练净时长（毫秒，结束時計入；老记录为 0）。
  final int restMs;
  final int activeMs;

  const Session({
    this.id,
    required this.date,
    this.planDayId,
    required this.planDayTitle,
    required this.startedAt,
    this.endedAt,
    required this.status,
    this.notes = '',
    this.restMs = 0,
    this.activeMs = 0,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'date': date,
        'plan_day_id': planDayId,
        'plan_day_title': planDayTitle,
        'started_at': startedAt,
        'ended_at': endedAt,
        'status': status,
        'notes': notes,
        'rest_ms': restMs,
        'active_ms': activeMs,
      };

  factory Session.fromMap(Map<String, dynamic> m) => Session(
        id: m['id'] as int?,
        date: (m['date'] as String?) ?? '',
        planDayId: m['plan_day_id'] as int?,
        planDayTitle: (m['plan_day_title'] as String?) ?? '',
        startedAt: (m['started_at'] as num?)?.toInt() ?? 0,
        endedAt: m['ended_at'] as int?,
        status: (m['status'] as String?) ?? 'active',
        notes: (m['notes'] as String?) ?? '',
        restMs: (m['rest_ms'] as num?)?.toInt() ?? 0,
        activeMs: (m['active_ms'] as num?)?.toInt() ?? 0,
      );

  /// 训练时长（分钟，不足 1 分钟按 1 分钟计）。
  int get durationMin =>
      endedAt == null ? 0 : ((endedAt! - startedAt) / 60000).ceil();
}

/// 一次训练里的一个动作（快照名称与类型，避免计划后续被改影响历史）
class SessionExercise {
  final int? id;
  final int sessionId;
  final String name;
  final int orderIdx;
  final String kind; // compound | assistance
  final int restSec; // 该动作的休息秒数（计划里配置，0=按全局设置）
  final ProgressionRule rule;

  /// 临时调整痕迹（点名条目三）：'' = 计划原样；
  /// '替换自：X' = 训练中把 X 换成当前动作（器械被占等）；'追加于：Y' =
  /// 训练中在动作 Y 之后临时追加。只写本会话记录行，不改计划本体，
  /// 便于历史/统计追溯这次训练与计划的偏差。
  final String trace;

  const SessionExercise({
    this.id,
    required this.sessionId,
    required this.name,
    required this.orderIdx,
    required this.kind,
    this.restSec = 0,
    required this.rule,
    this.trace = '',
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'session_id': sessionId,
        'name': name,
        'order_idx': orderIdx,
        'kind': kind,
        'rest_sec': restSec,
        'rule': ruleToJson(rule),
        'trace': trace,
      };

  factory SessionExercise.fromMap(Map<String, dynamic> m) => SessionExercise(
        id: m['id'] as int?,
        sessionId: (m['session_id'] as num).toInt(),
        name: (m['name'] as String?) ?? '',
        orderIdx: (m['order_idx'] as num?)?.toInt() ?? 0,
        kind: (m['kind'] as String?) ?? 'assistance',
        restSec: (m['rest_sec'] as num?)?.toInt() ?? 0,
        rule: ruleFromJson(m['rule']),
        trace: (m['trace'] as String?) ?? '',
      );

  SessionExercise copyWithId(int newId) => SessionExercise(
        id: newId,
        sessionId: sessionId,
        name: name,
        orderIdx: orderIdx,
        kind: kind,
        restSec: restSec,
        rule: rule,
        trace: trace,
      );
}

class SetKind {
  static const warmup = 'warmup';
  static const working = 'working';
  static const failure = 'failure';
}

/// 一组记录
class SetEntry {
  final int? id;
  final int sessionExerciseId;
  final double weightKg;
  final int reps;
  final int rir; // 余力 0-5
  final String kind; // warmup | working | failure
  final int doneAt; // epoch ms
  final String note;

  const SetEntry({
    this.id,
    required this.sessionExerciseId,
    required this.weightKg,
    required this.reps,
    this.rir = 2,
    required this.kind,
    required this.doneAt,
    this.note = '',
  });

  /// 训练容量 = 重量 × 次数（热身组不计入容量）。
  /// 负重量（辅助器械配重）与自重（0）一样按 0 容量计——
  /// 辅助配重是"抵消负荷"，计入容量会把总容量往回减。
  double get volume =>
      kind == SetKind.warmup || weightKg <= 0 ? 0 : weightKg * reps;

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'session_exercise_id': sessionExerciseId,
        'weight_kg': weightKg,
        'reps': reps,
        'rir': rir,
        'kind': kind,
        'done_at': doneAt,
        'note': note,
      };

  factory SetEntry.fromMap(Map<String, dynamic> m) => SetEntry(
        id: m['id'] as int?,
        sessionExerciseId: (m['session_exercise_id'] as num).toInt(),
        weightKg: (m['weight_kg'] as num?)?.toDouble() ?? 0,
        reps: (m['reps'] as num?)?.toInt() ?? 0,
        rir: (m['rir'] as num?)?.toInt() ?? 2,
        kind: (m['kind'] as String?) ?? SetKind.working,
        doneAt: (m['done_at'] as num?)?.toInt() ?? 0,
        note: (m['note'] as String?) ?? '',
      );
}

class BodyMetric {
  final int? id;
  final String date;
  final double? weightKg;
  final double? waistCm;
  final double? bodyFatPct;

  const BodyMetric({
    this.id,
    required this.date,
    this.weightKg,
    this.waistCm,
    this.bodyFatPct,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'date': date,
        'weight_kg': weightKg,
        'waist_cm': waistCm,
        'bodyfat_pct': bodyFatPct,
      };

  factory BodyMetric.fromMap(Map<String, dynamic> m) => BodyMetric(
        id: m['id'] as int?,
        date: (m['date'] as String?) ?? '',
        weightKg: (m['weight_kg'] as num?)?.toDouble(),
        waistCm: (m['waist_cm'] as num?)?.toDouble(),
        bodyFatPct: (m['bodyfat_pct'] as num?)?.toDouble(),
      );
}

/// 飞书日历同步记录
class LarkSync {
  final int? id;
  final String refType; // plan_day | session
  final int refId;
  final String larkEventId;
  final String eventDate;
  final int syncedAt;
  final String summary;

  const LarkSync({
    this.id,
    required this.refType,
    required this.refId,
    required this.larkEventId,
    required this.eventDate,
    required this.syncedAt,
    this.summary = '',
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'ref_type': refType,
        'ref_id': refId,
        'lark_event_id': larkEventId,
        'event_date': eventDate,
        'synced_at': syncedAt,
        'summary': summary,
      };

  factory LarkSync.fromMap(Map<String, dynamic> m) => LarkSync(
        id: m['id'] as int?,
        refType: (m['ref_type'] as String?) ?? 'plan_day',
        refId: (m['ref_id'] as num?)?.toInt() ?? 0,
        larkEventId: (m['lark_event_id'] as String?) ?? '',
        eventDate: (m['event_date'] as String?) ?? '',
        syncedAt: (m['synced_at'] as num?)?.toInt() ?? 0,
        summary: (m['summary'] as String?) ?? '',
      );
}
