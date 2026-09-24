import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../db/db.dart';
import '../engine/engine.dart';
import '../presets/baoji_plan.dart';
import 'focus_service.dart';
import 'settings.dart';

enum WorkoutPhase { idle, lifting, resting }

/// 训练状态机（按 PRD 流程图）：
/// idle → lifting（热身/正式循环）→ resting → lifting → … → finished/quit
/// 休息用墙钟时间（restEndAt = epoch ms），锁屏/杀进程都不影响正确性；
/// 恢复逻辑：prefs 里存 sessionId + restEndAt，启动时若会话仍 active 则还原。
class SessionController extends ChangeNotifier {
  SessionController(this._db, this._settings, this._prefs, this._focus);

  final Db _db;
  final Settings _settings;
  final SharedPreferences _prefs;
  final FocusService? _focus;

  Session? session;
  List<SessionExercise> exercises = [];
  Map<int, List<SetEntry>> setsByEx = {};
  Map<String, List<SetEntry>> lastWorkout = {}; // 动作名 → 上次正式组
  Map<String, List<SetEntry>> historyBefore = {}; // 动作名 → 本次之前的全部历史

  WorkoutPhase phase = WorkoutPhase.idle;
  int curExIdx = 0;
  int curSetIdx = 0; // 当前动作已完成组数（含热身）
  int restEndAt = 0;
  int restTotalMs = 0;
  double weightDraft = 0;
  int workingSetsDone = 0; // 当前动作正式组完成数
  final Set<String> prHit = {};

  /// 休息中可加练的"刚完成的动作"名（null = 无加练入口）。
  /// 每次进入休息都会置位（组间休息也能"再来一组"），
  /// 休息结束/结束训练时清除。
  String? extraSetExerciseName;

  /// 本次训练净时长（毫秒）：休息桶 / 训练桶，随相位切换累计，
  /// 结束时写入 sessions（总结页、历史、AI 分析评估休息长短用）。
  int restMs = 0;
  int activeMs = 0;
  DateTime? _phaseSince;

  void _accrueTime() {
    final since = _phaseSince;
    if (since == null) return;
    final dt = DateTime.now().difference(since).inMilliseconds;
    if (dt <= 0) return;
    if (phase == WorkoutPhase.resting) {
      restMs += dt;
    } else if (phase == WorkoutPhase.lifting) {
      activeMs += dt;
    }
    _phaseSince = DateTime.now();
  }

  Timer? _tick;
  final ValueNotifier<int> restRemainingMs = ValueNotifier(0);
  final ValueNotifier<String> focusBanner = ValueNotifier('');
  bool _restNotified = false;

  bool get hasActive => session != null && session!.status == 'active';
  SessionExercise? get currentEx =>
      exercises.isEmpty ? null : exercises[curExIdx];
  List<SetEntry> get currentSets =>
      currentEx == null ? [] : (setsByEx[currentEx!.id] ?? []);

  // ---------- 启动 / 恢复 ----------

  /// App 启动时调用：还原进行中的会话（含休息中状态）。
  /// 任何异常（脏数据/半写会话）都不允许锁死启动：回退到空闲态并吞掉。
  Future<void> restore() async {
    try {
      final active = await _db.activeSession();
      if (active == null) return;
      final ok = await _loadSession(active.id!);
      if (!ok) return;
      // 时长统计从恢复时刻重新起表（历史段在进程被杀时已丢，无法追平）
      restMs = 0;
      activeMs = 0;
      _phaseSince = DateTime.now();
      final restEnd = _prefs.getInt('rest.endAt') ?? 0;
      final sid = _prefs.getInt('rest.sessionId') ?? 0;
      if (sid == active.id && restEnd > DateTime.now().millisecondsSinceEpoch) {
        _startRestAt(restEnd, notifyUi: false);
      } else {
        _setPhase(WorkoutPhase.lifting);
      }
    } catch (_) {
      session = null;
      exercises = [];
      phase = WorkoutPhase.idle;
    }
  }

  Future<bool> _loadSession(int sessionId) async {
    final s = await _db.sessionById(sessionId);
    if (s == null || s.status != 'active') return false;
    session = s;
    exercises = await _db.sessionExercises(sessionId);
    if (exercises.isEmpty) {
      // 零动作的孤儿会话（半写/进程被杀残留）：自动作废，
      // 否则 currentEx! 解引用会让 App 启动即崩（restore 已把 session 置回 null，
      // 避免回落后 hasActive 仍为 true 造成二次崩溃）。
      session = null;
      await _db.updateSession(sessionId, {
        'ended_at': DateTime.now().millisecondsSinceEpoch,
        'status': 'quit',
      });
      return false;
    }
    setsByEx = await _db.setsOfSession(sessionId);
    // 找到第一个"正式组未做完"的动作（与 completeSet 的推进判据一致：
    // 只数 working 组，热身/力竭组不算完成进度）
    curExIdx = exercises.length - 1;
    for (var i = 0; i < exercises.length; i++) {
      final done = (setsByEx[exercises[i].id] ?? [])
          .where((e) => e.kind == SetKind.working)
          .length;
      if (done < exercises[i].rule.workingSets) {
        curExIdx = i;
        break;
      }
    }
    curSetIdx = (setsByEx[currentEx!.id] ?? []).length;
    workingSetsDone =
        currentSets.where((e) => e.kind == SetKind.working).length;
    await _loadContextForCurrent();
    weightDraft = _recommendFor(currentEx!.name);
    _setPhase(WorkoutPhase.lifting, silent: true);
    return true;
  }

  double _recommendFor(String name) {
    // 上次该动作那次训练的正式组 → 应用渐进判定
    final last = lastWorkout[name] ?? const <SetEntry>[];
    if (last.isNotEmpty) {
      final rule = currentEx?.rule ?? ProgressionRule.fallback;
      final v = evaluateProgression(
        workingSets: last,
        currentWeight: last.last.weightKg,
        rule: rule,
      );
      // 负重量（辅助配重）同样渐进：-30 → -27.5 = 辅助减少 2.5kg，是进步。
      // 不再做 next>0 检查——那会让辅助器械动作永远卡在原配重。
      return round05(last.last.weightKg + v.deltaKg);
    }
    return _presetStartFor(name);
  }

  double _presetStartFor(String name) => presetStartOf(name);

  Future<void> _loadContextForCurrent() async {
    if (currentEx == null) return;
    final name = currentEx!.name;
    lastWorkout[name] = await _db.lastWorkingSets(name);
    final seId = currentEx!.id;
    // PR 判定只看正式组历史（热身大重量不应抬高 PR 门槛）
    historyBefore[name] = await _db.historySets(name,
        beforeSessionExerciseId: seId, kindFilter: SetKind.working);
  }

  /// 从计划日开始训练（或继续）。已有进行中的会话时直接返回，防止双击产生孤儿会话。
  Future<void> startFromDay({
    required PlanDay day,
    required List<PlanExercise> planExercises,
  }) async {
    if (planExercises.isEmpty) return; // 空计划日不允许开会话（防零动作孤儿）
    if (hasActive) return;
    // 双击竞态兜底：内存态置 active 之前再查一次库，只放行一个并发调用
    if (await _db.activeSession() != null) return;
    prHit.clear();
    final now = DateTime.now().millisecondsSinceEpoch;
    // 会话与动作一个事务落库（sessionId 先占位，事务内回填真实 id），
    // 消除"会话已落库、动作未落库"的半写窗口。
    final drafts = [
      for (final pe in planExercises)
        SessionExercise(
          sessionId: 0,
          name: pe.name,
          orderIdx: pe.orderIdx,
          kind: pe.kind,
          restSec: pe.restSec,
          rule: pe.rule,
        ),
    ];
    final (s, withIds) = await _db.insertSessionWithExercises(
      Session(
        date: fmtDate(DateTime.now()),
        planDayId: day.id,
        planDayTitle: day.title,
        startedAt: now,
        status: 'active',
      ),
      drafts,
    );
    session = s;
    exercises = withIds;
    setsByEx = {};
    curExIdx = 0;
    curSetIdx = 0;
    workingSetsDone = 0;
    restMs = 0;
    activeMs = 0;
    _phaseSince = DateTime.now(); // 时长统计从这里起表
    await _loadContextForCurrent();
    weightDraft = _recommendFor(currentEx!.name);
    _setPhase(WorkoutPhase.lifting);
    await _enterFocus();
  }

  // ---------- 记录 ----------

  /// 完成一组（kind: warmup/working/failure）。返回是否触发 PR。
  Future<bool> completeSet({
    required double weight,
    required int reps,
    required int rir,
    required String kind,
    String note = '',
  }) async {
    final ex = currentEx;
    if (ex == null) return false;
    final entry = SetEntry(
      sessionExerciseId: ex.id!,
      weightKg: weight,
      reps: reps,
      rir: rir,
      kind: kind,
      doneAt: DateTime.now().millisecondsSinceEpoch,
      note: note,
    );
    final id = await _db.insertSet(entry);
    setsByEx.putIfAbsent(ex.id!, () => []).add(SetEntry.fromMap({
          ...entry.toMap(),
          'id': id,
        }));
    curSetIdx++;
    var pr = false;
    if (kind == SetKind.working) {
      workingSetsDone++;
      pr = isPrWeight(weight, historyBefore[ex.name] ?? []);
      if (pr) prHit.add(ex.name);
    }
    await _vibrate();
    notifyListeners();

    // 判断下一步：休息 or 换动作 or 结束
    final plannedWorking = ex.rule.workingSets;
    if (workingSetsDone >= plannedWorking) {
      // 本动作完成 → 下一个动作（若还有）也进入休息
      if (curExIdx < exercises.length - 1) {
        _advanceToNextExercise();
      } else {
        // 最后一个动作完成：直接结束会话；UI 检测到 !hasActive 后
        // 走 endTraining 展示总结页并回填飞书
        await finish();
        return pr;
      }
    }
    // 无论组间还是练满推进：休息页都能"再来一组"回到刚完成的动作。
    // 组间时 currentEx 未变，startExtraSet 回退到自身是无害幂等操作。
    extraSetExerciseName = ex.name;
    _beginRestFor(ex);
    return pr;
  }

  void _advanceToNextExercise() {
    curExIdx++;
    curSetIdx = 0;
    workingSetsDone = 0;
  }

  /// 跳过当前动作（未完成的组不记录）。最后一个动作时跳过 = 结束训练的替代入口。
  Future<void> skipExercise() async {
    if (session == null || exercises.isEmpty) return;
    if (curExIdx < exercises.length - 1) {
      _advanceToNextExercise();
      await _loadContextForCurrent();
      weightDraft = _recommendFor(currentEx!.name);
      _setPhase(WorkoutPhase.lifting);
    }
  }

  /// 完成后未休息先看下一动作（下一组自动带入上次重量）。
  /// 休息时长：动作级配置（计划里每个动作的 restSec）优先，全局设置兜底。
  void _beginRestFor(SessionExercise justFinished) {
    final sec = justFinished.restSec > 0
        ? justFinished.restSec
        : (justFinished.kind == 'compound'
            ? _settings.restCompoundSec
            : _settings.restAssistanceSec);
    final end = DateTime.now().millisecondsSinceEpoch + sec * 1000;
    _startRestAt(end, notifyUi: true);
    // 预载（下一）动作上下文。推荐重量只在换动作时刷新——
    // 同一动作继续时保留用户手动调过的重量，不再每组被冲回推荐值。
    _loadContextForCurrent().then((_) {
      if (!hasActive) return;
      final next = currentEx;
      if (next == null || next.id != justFinished.id) {
        weightDraft = _recommendFor(next?.name ?? '');
        notifyListeners();
      }
    });
  }

  void _startRestAt(int endAtMs, {required bool notifyUi}) {
    restEndAt = endAtMs;
    restTotalMs = (endAtMs - DateTime.now().millisecondsSinceEpoch).clamp(0, 1 << 31);
    _restNotified = false;
    _setPhase(WorkoutPhase.resting, silent: !notifyUi);
    _prefs.setInt('rest.endAt', endAtMs);
    _prefs.setInt('rest.sessionId', session?.id ?? 0);
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) => _tickFn());
    _updateRemaining();
    // 时间源统一：精确闹钟跟随 restEndAt（含恢复会话后补挂闹钟的场景）
    onRestAlarmChanged?.call(endAtMs);
  }

  void _tickFn() {
    _updateRemaining();
    final now = DateTime.now().millisecondsSinceEpoch;
    if (restEndAt <= now && !_restNotified) {
      _restNotified = true;
      _onRestFinished();
    }
  }

  void _updateRemaining() {
    final now = DateTime.now().millisecondsSinceEpoch;
    restRemainingMs.value = (restEndAt - now).clamp(0, 1 << 31);
  }

  Future<void> _onRestFinished() async {
    await _vibrate();
    if (_settings.soundOn) {
      // 系统提示音（无需音频资源，前台可闻）
      SystemSound.play(SystemSoundType.alert);
    }
    _finishRest();
    notifyListeners();
  }

  void _finishRest() {
    _tick?.cancel();
    _tick = null;
    _prefs.setInt('rest.endAt', 0);
    extraSetExerciseName = null;
    _setPhase(WorkoutPhase.lifting);
    restRemainingMs.value = 0;
  }

  void skipRest() => _finishRest();

  /// 休息中「刚完成的动作再来一组」：回退到该动作进入动作态，
  /// 再完成的组按正式组记录（同样参与渐进判定与 PR）。
  /// 重量继承该动作最后一组的实际重量（手调过的配重不从头再来），
  /// 没有历史组才回落到推荐值。
  Future<void> startExtraSet() async {
    final name = extraSetExerciseName;
    if (name == null || !hasActive) return;
    final idx = exercises.indexWhere((e) => e.name == name);
    if (idx < 0) return;
    _restPaused = false; // 暂停态回退前先解除，避免 resume 语义错乱
    curExIdx = idx;
    final list = setsByEx[exercises[idx].id] ?? const <SetEntry>[];
    workingSetsDone = list.where((e) => e.kind == SetKind.working).length;
    curSetIdx = list.length;
    await _loadContextForCurrent();
    weightDraft = list.isNotEmpty ? list.last.weightKg : _recommendFor(name);
    _finishRest();
    notifyListeners();
  }

  // ---- 休息暂停/继续 ----
  bool _restPaused = false;
  int _restRemainingWhenPaused = 0;

  bool get isRestPaused => _restPaused;

  /// 暂停：冻结剩余时间（记下剩余毫秒并停表）。
  void pauseRest() {
    if (phase != WorkoutPhase.resting || _restPaused) return;
    _restPaused = true;
    _restRemainingWhenPaused = restRemainingMs.value;
    _tick?.cancel();
    _tick = null;
    // 暂停即取消精确闹钟（否则暂停期间到点照响）
    onRestAlarmChanged?.call(null);
    notifyListeners();
  }

  /// 继续：从剩余时间重新起表（经 _startRestAt 自动重挂闹钟）。
  void resumeRest() {
    if (phase != WorkoutPhase.resting || !_restPaused) return;
    _restPaused = false;
    final end =
        DateTime.now().millisecondsSinceEpoch + _restRemainingWhenPaused;
    restTotalMs = _restRemainingWhenPaused;
    _startRestAt(end, notifyUi: true);
  }

  void extendRest(int sec) {
    if (phase != WorkoutPhase.resting || sec == 0) return;
    if (_restPaused) {
      // 暂停态加/减时：只动冻结值与总时长，不写 prefs、不改 restEndAt
      // （否则 resume 用冻结值重算时，加的秒数会被静默丢弃）；
      // 地板 5 秒，减时不把休息直接减没
      _restRemainingWhenPaused =
          (_restRemainingWhenPaused + sec * 1000).clamp(5000, 1 << 31);
      restTotalMs = (restTotalMs + sec * 1000).clamp(1000, 1 << 31);
      restRemainingMs.value = _restRemainingWhenPaused;
      return;
    }
    // 非暂停态：地板 5 秒，防止 -30 把剩余时间减成已过期
    final floorEnd = DateTime.now().millisecondsSinceEpoch + 5000;
    restEndAt =
        (restEndAt + sec * 1000) < floorEnd ? floorEnd : restEndAt + sec * 1000;
    restTotalMs = (restTotalMs + sec * 1000).clamp(1000, 1 << 31);
    _prefs.setInt('rest.endAt', restEndAt);
    _updateRemaining();
    onRestAlarmChanged?.call(restEndAt);
  }

  /// 撤销最后一组（记错时用）。若当前动作还没有组而已完成上一动作，
  /// 回退到上一动作撤销它的最后一组。
  Future<void> undoLastSet() async {
    if (session == null || exercises.isEmpty) return;
    var ex = currentEx;
    var list = setsByEx[ex!.id!];
    if ((list == null || list.isEmpty) && curExIdx > 0) {
      // 已自动推进到下一动作：回退
      curExIdx--;
      ex = exercises[curExIdx];
      list = setsByEx[ex.id!];
      await _loadContextForCurrent();
      // 回退动作的重量 = 它剩余最后一组的实际重量（重记这组时手感不从头再来）
      weightDraft = (list != null && list.isNotEmpty)
          ? list.last.weightKg
          : _recommendFor(ex.name);
    }
    if (list == null || list.isEmpty) return;
    final last = list.last;
    await _db.deleteSet(last.id!);
    list.removeLast();
    curSetIdx = list.length;
    // 计数收敛到 DB 真值：同动作撤销与跨动作回退（_advanceToNextExercise
    // 已把计数归 0，回退后无条件自减会变成 -1）统一按剩余正式组重算。
    workingSetsDone = list.where((e) => e.kind == SetKind.working).length;
    // PR 标记不随单组撤销丢项：仅当剩余正式组中已没有任何一组仍是
    // 历史新高时才清除（逐组重判，任一剩余组仍超历史最佳就保留）。
    if (prHit.contains(ex.name)) {
      final history = historyBefore[ex.name] ?? const <SetEntry>[];
      final anyStillPr = list
          .any((e) => e.kind == SetKind.working && isPrWeight(e.weightKg, history));
      if (!anyStillPr) prHit.remove(ex.name);
    }
    notifyListeners();
  }

  void setWeightDraft(double w) {
    weightDraft = (w * 100).round() / 100;
    // 允许负值 = 辅助器械配重（引体向上/双杠臂屈伸辅助机，配重越大负荷越轻）；
    // 下限 -300kg 防手抖连点把数值打到无意义区间。
    if (weightDraft < -300) weightDraft = -300;
    if (weightDraft > 1000) weightDraft = 1000;
    notifyListeners();
  }

  /// 自重/负重一键切换：有重量（含辅助配重负值）→ 归零（自重）；
  /// 已是自重→回到上次用的重量（无历史则用推荐值），不用记步进点回去。
  void toggleBodyweightDraft() {
    if (weightDraft != 0) {
      setWeightDraft(0);
      return;
    }
    final name = currentEx?.name ?? '';
    final last = lastWorkout[name];
    final w = (last != null && last.isNotEmpty)
        ? last.last.weightKg
        : _recommendFor(name);
    setWeightDraft(w);
  }

  /// 训练中临时加动作：从动作库挑的动作追加到队尾（只进本次会话，不改计划）。
  /// 规则用默认（5-8 次 × 3 组），休息跟随全局偏好（restSec=0）。
  Future<void> appendExercises(List<ExerciseMeta> metas) async {
    if (!hasActive || metas.isEmpty) return;
    var order = exercises.length;
    for (final m in metas) {
      final draft = SessionExercise(
        sessionId: session!.id!,
        name: m.name,
        orderIdx: order++,
        kind: m.isCompound ? 'compound' : 'assistance',
        restSec: 0,
        rule: ProgressionRule.fallback,
      );
      final id = await _db.insertSessionExercise(draft);
      exercises.add(draft.copyWithId(id));
    }
    notifyListeners();
  }

  /// 训练中替换当前动作（仅限还没记过组的动作）：沿用原组次规则/休息/排序，
  /// 只换名字。已记组或队列里已有同名动作时不动作（返回 false）。
  Future<bool> replaceCurrentExercise(ExerciseMeta meta) async {
    final ex = currentEx;
    if (!hasActive || ex == null) return false;
    if (currentSets.isNotEmpty) return false;
    if (meta.name == ex.name) return false;
    if (exercises.any((e) => e.name == meta.name)) return false;
    final updated = SessionExercise(
      id: ex.id,
      sessionId: ex.sessionId,
      name: meta.name,
      orderIdx: ex.orderIdx,
      kind: ex.kind,
      restSec: ex.restSec,
      rule: ex.rule,
    );
    await _db.updateSessionExercise(updated);
    exercises[curExIdx] = updated;
    await _loadContextForCurrent();
    weightDraft = _recommendFor(meta.name);
    notifyListeners();
    return true;
  }

  // ---------- 结束 ----------

  Future<void> finish() async {
    if (session == null) return;
    if (session!.status != 'active') return; // 幂等：自动结束+手动结束不重复
    _finishRest();
    await _db.updateSession(session!.id!, {
      'ended_at': DateTime.now().millisecondsSinceEpoch,
      'status': 'done',
      'rest_ms': restMs,
      'active_ms': activeMs,
    });
    await _exitFocus();
    session = await _db.sessionById(session!.id!);
    WakelockPlus.disable();
    prHit.clear();
    _setPhase(WorkoutPhase.idle);
  }

  Future<void> quit() async {
    if (session == null) return;
    if (session!.status != 'active') return;
    _finishRest();
    await _db.updateSession(session!.id!, {
      'ended_at': DateTime.now().millisecondsSinceEpoch,
      'status': 'quit',
      'rest_ms': restMs,
      'active_ms': activeMs,
    });
    await _exitFocus();
    WakelockPlus.disable();
    session = null;
    prHit.clear();
    _setPhase(WorkoutPhase.idle);
  }

  /// 本次训练汇总（用于结束页与飞书回填）。
  Future<SessionStats> stats() async {
    if (session == null) {
      return const SessionStats(
          volume: 0, totalSets: 0, workingSets: 0, reps: 0, exercises: []);
    }
    final order = await _db.sessionExercises(session!.id!);
    final map = await _db.setsOfSession(session!.id!);
    return sessionStatsFrom(map, order);
  }

  /// 渐进判定建议（结束时展示 + AI 分析包引用）。
  Future<List<String>> verdicts() async {
    final out = <String>[];
    for (final ex in exercises) {
      final sets = setsByEx[ex.id!] ?? [];
      final v = evaluateProgression(
        workingSets: sets,
        currentWeight: sets.isEmpty ? 0 : sets.last.weightKg,
        rule: ex.rule,
      );
      out.add('${ex.name}：${v.reason}');
    }
    return out;
  }

  // ---------- 专注模式钩子（由 FocusService 在 UI 层接线） ----------

  Future<void> Function()? onEnterFocus;
  Future<void> Function()? onExitFocus;

  /// 休息精确闹钟的时间源回调：endAtMs 非 null = （重）挂 endAtMs 的闹钟，
  /// null = 取消。由 App 容器接 NotifyService（开始休息/加时/继续时重挂，
  /// 暂停时取消，恢复会话时补挂）。
  Future<void> Function(int? endAtMs)? onRestAlarmChanged;

  Future<void> _enterFocus() async {
    WakelockPlus.enable();
    await onEnterFocus?.call();
  }

  Future<void> _exitFocus() async {
    await onExitFocus?.call();
  }

  Future<void> _vibrate() async {
    if (!_settings.vibrationOn) return;
    await _focus?.vibrate();
  }

  void _setPhase(WorkoutPhase p, {bool silent = false}) {
    if (phase != p) _accrueTime(); // 相位切换前把上一段时长入桶
    phase = p;
    if (!silent) notifyListeners();
  }

  // 分心提醒（由 FocusService 检测后调用）
  void showFocusBanner(String text) {
    focusBanner.value = text;
    Timer(const Duration(seconds: 5), () {
      if (focusBanner.value == text) focusBanner.value = '';
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    restRemainingMs.dispose();
    focusBanner.dispose();
    super.dispose();
  }
}

/// 内置起始重量查询。
double presetStartOf(String name) {
  for (final list in kBaojiExercisesByWeekday.values) {
    for (final pe in list) {
      if (pe.name == name) return pe.startWeightKg;
    }
  }
  return 20;
}
