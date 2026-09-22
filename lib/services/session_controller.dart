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
  Future<void> restore() async {
    final active = await _db.activeSession();
    if (active == null) return;
    final ok = await _loadSession(active.id!);
    if (!ok) return;
    final restEnd = _prefs.getInt('rest.endAt') ?? 0;
    final sid = _prefs.getInt('rest.sessionId') ?? 0;
    if (sid == active.id && restEnd > DateTime.now().millisecondsSinceEpoch) {
      _startRestAt(restEnd, notifyUi: false);
    } else {
      _setPhase(WorkoutPhase.lifting);
    }
  }

  Future<bool> _loadSession(int sessionId) async {
    final s = await _db.sessionById(sessionId);
    if (s == null || s.status != 'active') return false;
    session = s;
    exercises = await _db.sessionExercises(sessionId);
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
      final next = last.last.weightKg + v.deltaKg;
      if (next > 0) return round05(next);
      return round05(last.last.weightKg);
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
    if (hasActive) return;
    prHit.clear();
    final now = DateTime.now().millisecondsSinceEpoch;
    session = await _db.insertSession(Session(
      date: fmtDate(DateTime.now()),
      planDayId: day.id,
      planDayTitle: day.title,
      startedAt: now,
      status: 'active',
    ));
    exercises = [];
    for (final pe in planExercises) {
      final draft = SessionExercise(
        sessionId: session!.id!,
        name: pe.name,
        orderIdx: pe.orderIdx,
        kind: pe.kind,
        restSec: pe.restSec,
        rule: pe.rule,
      );
      final id = await _db.insertSessionExercise(draft);
      exercises.add(draft.copyWithId(id));
    }
    setsByEx = {};
    curExIdx = 0;
    curSetIdx = 0;
    workingSetsDone = 0;
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
    // 预载下一动作上下文并推荐重量
    _loadContextForCurrent().then((_) {
      weightDraft = _recommendFor(currentEx!.name);
      notifyListeners();
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
    _setPhase(WorkoutPhase.lifting);
    restRemainingMs.value = 0;
  }

  void skipRest() => _finishRest();

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
    notifyListeners();
  }

  /// 继续：从剩余时间重新起表。
  void resumeRest() {
    if (phase != WorkoutPhase.resting || !_restPaused) return;
    _restPaused = false;
    final end =
        DateTime.now().millisecondsSinceEpoch + _restRemainingWhenPaused;
    restTotalMs = _restRemainingWhenPaused;
    _startRestAt(end, notifyUi: true);
  }

  void extendRest(int sec) {
    if (phase != WorkoutPhase.resting) return;
    restEndAt += sec * 1000;
    restTotalMs += sec * 1000;
    _prefs.setInt('rest.endAt', restEndAt);
    _updateRemaining();
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
      weightDraft = _recommendFor(ex.name);
    }
    if (list == null || list.isEmpty) return;
    final last = list.last;
    await _db.deleteSet(last.id!);
    list.removeLast();
    curSetIdx = list.length;
    if (last.kind == SetKind.working) workingSetsDone--;
    prHit.remove(ex.name);
    notifyListeners();
  }

  void setWeightDraft(double w) {
    weightDraft = (w * 100).round() / 100;
    if (weightDraft < 0) weightDraft = 0;
    notifyListeners();
  }

  // ---------- 结束 ----------

  Future<void> finish() async {
    if (session == null) return;
    if (session!.status != 'active') return; // 幂等：自动结束+手动结束不重复
    _finishRest();
    await _db.updateSession(session!.id!, {
      'ended_at': DateTime.now().millisecondsSinceEpoch,
      'status': 'done',
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
