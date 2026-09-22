import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/engine.dart';
import '../services/session_controller.dart';
import 'theme.dart';
import 'widgets/common.dart';

/// 训练页（全屏）：动作态 / 休息态；折叠屏（≥840dp）双栏。
/// 训练中不弹窗：结束训练用两击确认。
class WorkoutPage extends StatefulWidget {
  const WorkoutPage({super.key});

  @override
  State<WorkoutPage> createState() => _WorkoutPageState();
}

class _WorkoutPageState extends State<WorkoutPage>
    with WidgetsBindingObserver {
  WorkoutPhase? _lastPhase;
  Timer? _distractTimer;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WidgetsBinding.instance.addObserver(this);
      _distractTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _checkDistractingApp();
      // 常驻通知的"约 X 分 Y 秒"文案每 30s 刷新一次
      final c = app(context);
      if (c.session.hasActive && c.session.phase == WorkoutPhase.resting) {
        c.notify.showOngoing(c.session.restEndAt);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 训练中切去别的 App 再回来：查最近 90 秒是否刷了分心 App
    if (state == AppLifecycleState.resumed) {
      _checkDistractingApp();
    }
  }

  Future<void> _checkDistractingApp() async {
    if (!mounted) return;
    final c = app(context);
    final s = c.session;
    if (!s.hasActive) return;
    final hit = await c.focus.recentDistractingApp();
    if (hit == null || !mounted) return;
    final (pkg, sec) = hit;
    s.showFocusBanner('刚切去${_friendlyName(pkg)}玩了 $sec 秒，回来继续！');
  }

  String _friendlyName(String pkg) {
    const known = {
      'com.smile.gifmaker': '抖音',
      'com.ss.android.ugc.aweme': '抖音',
      'com.kuaishou.app': '快手',
      'com.xingin.xhs': '小红书',
      'com.sina.weibo': '微博',
      'tv.danmaku.bili': 'B站',
      'com.tencent.weishi': '微视',
    };
    return known[pkg] ?? '分心 App';
  }

  @override
  void deactivate() {
    // 系统返回退出训练页时清掉休息通知与精确闹钟，避免离开后照响
    if (app(context).session.hasActive) {
      app(context).notify.cancelRest();
    }
    super.deactivate();
  }

  @override
  void dispose() {
    _distractTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  /// 休息开始/结束时挂接通知（常驻倒计时 + 精确结束提醒）。
  void _syncPhaseSideEffects(WorkoutPhase phase) {
    if (_lastPhase == phase) return;
    final old = _lastPhase;
    _lastPhase = phase;
    final c = app(context);
    final s = c.session;
    if (phase == WorkoutPhase.resting) {
      c.notify.showOngoing(s.restEndAt);
      c.notify.scheduleRestEnd(s.restEndAt);
    }
    if (old == WorkoutPhase.resting && phase != WorkoutPhase.resting) {
      c.notify.cancelRest();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = app(context);
    final s = c.session;
    _syncPhaseSideEffects(s.phase);

    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        _syncPhaseSideEffects(s.phase);
        if (!s.hasActive) {
          return const Scaffold(
              backgroundColor: AppTheme.bg,
              body: Center(child: Text('本次训练已结束')));
        }
        return Scaffold(
          backgroundColor: AppTheme.bg,
          body: SafeArea(
            top: false,
            child: Column(
              children: [
                ValueListenableBuilder<String>(
                  valueListenable: s.focusBanner,
                  builder: (context, msg, _) => msg.isEmpty
                      ? const SizedBox.shrink()
                      : Container(
                          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppTheme.warn.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(children: [
                            const Icon(Icons.warning_amber_rounded,
                                color: AppTheme.warn, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                                child: Text(msg,
                                    style: const TextStyle(
                                        color: AppTheme.warn, fontSize: 14))),
                          ]),
                        ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, cons) {
                      final wide = cons.maxWidth >= 840;
                      final narrow = cons.maxWidth < 600;
                      Widget content = s.phase == WorkoutPhase.resting
                          ? const _RestView()
                          : _LiftView(s: s);
                      // 窄屏/中屏：操作区最大宽度 560，单手可达
                      if (!wide) {
                        content = Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 560),
                            child: content,
                          ),
                        );
                      }
                      if (narrow) return content;
                      return content;
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ================= 动作态 =================

class _LiftView extends StatelessWidget {
  const _LiftView({required this.s});

  final SessionController s;

  @override
  Widget build(BuildContext context) {
    final ex = s.currentEx;
    if (ex == null) return const SizedBox.shrink();
    // 折叠屏/平板横屏（≥840dp）：左信息右操作双栏
    return LayoutBuilder(
      builder: (context, cons) {
        final wide = cons.maxWidth >= 840;
        if (wide) {
          return Column(
            children: [
              _TopBar(s: s),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(child: _ExerciseInfo(s: s, ex: ex)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SingleChildScrollView(
                          child:
                              _ActionPanel(s: s, ex: ex, key: ValueKey(ex.id)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }
        return Column(
          children: [
            _TopBar(s: s),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _ExerciseInfo(s: s, ex: ex),
              ),
            ),
            _ActionPanel(s: s, ex: ex, key: ValueKey(ex.id)),
          ],
        );
      },
    );
  }
}

class _TopBar extends StatefulWidget {
  const _TopBar({required this.s});

  final SessionController s;

  @override
  State<_TopBar> createState() => _TopBarState();
}

class _TopBarState extends State<_TopBar> {
  bool _endArmed = false;
  Timer? _disarm;

  void _armEnd() {
    _disarm?.cancel();
    setState(() => _endArmed = true);
    HapticFeedback.selectionClick();
    _disarm = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _endArmed = false);
    });
  }

  @override
  void dispose() {
    _disarm?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLastEx =
        widget.s.curExIdx >= widget.s.exercises.length - 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(widget.s.session!.planDayTitle,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppTheme.textDim, fontSize: 14)),
          ),
          TextButton(
            onPressed: () {
              HapticFeedback.selectionClick();
              widget.s.skipExercise();
            },
            child: Text(isLastEx ? '已是最后一个' : '跳过动作',
                style: TextStyle(
                    color: isLastEx
                        ? AppTheme.textDim.withValues(alpha: 0.4)
                        : AppTheme.textDim,
                    fontSize: 14)),
          ),
          TextButton(
            onPressed: () {
              if (_endArmed) {
                _disarm?.cancel();
                endTraining(context);
              } else {
                _armEnd();
              }
            },
            child: Text(
              _endArmed ? '再点一次确认结束' : '结束训练',
              style: TextStyle(
                color: _endArmed ? AppTheme.danger : AppTheme.textDim,
                fontSize: 14,
                fontWeight: _endArmed ? FontWeight.w800 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExerciseInfo extends StatelessWidget {
  const _ExerciseInfo({required this.s, required this.ex});

  final SessionController s;
  final SessionExercise ex;

  @override
  Widget build(BuildContext context) {
    final last = s.lastWorkout[ex.name] ?? const <SetEntry>[];
    final lastText = last.isEmpty
        ? '首次训练这个动作'
        : '上次：${last.map((e) => '${fmtKg(e.weightKg)}kg×${e.reps}').join('  ')}';
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${s.curExIdx + 1} / ${s.exercises.length}',
            style: const TextStyle(color: AppTheme.textDim, fontSize: 15)),
        const SizedBox(height: 4),
        Text(ex.name,
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(
            '第 ${s.workingSetsDone + 1} / ${ex.rule.workingSets} 组 · 目标 ${ex.rule.repsMin}-${ex.rule.repsMax} 次 · RIR ${ex.rule.rirTarget}',
            style: const TextStyle(color: AppTheme.accent, fontSize: 16)),
        const SizedBox(height: 12),
        Text(lastText,
            style: const TextStyle(color: AppTheme.textDim, fontSize: 15)),
      ],
    );
  }
}

class _ActionPanel extends StatefulWidget {
  const _ActionPanel({super.key, required this.s, required this.ex});

  final SessionController s;
  final SessionExercise ex;

  @override
  State<_ActionPanel> createState() => _ActionPanelState();
}

class _ActionPanelState extends State<_ActionPanel> {
  String _kind = SetKind.working;
  int? _reps;
  int? _rir;
  String _note = '';
  bool _noteOpen = false;
  late final _noteCtrl = TextEditingController();
  static const _steps = [0.5, 1.25, 2.5, 5.0];

  @override
  void didUpdateWidget(_ActionPanel old) {
    super.didUpdateWidget(old);
    if (old.ex.id != widget.ex.id) {
      _reps = null;
      _kind = SetKind.working;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final ex = widget.ex;
    final repsChoices = <int>{
      for (var r = (ex.rule.repsMin - 2).clamp(1, 99);
          r <= ex.rule.repsMax + 2;
          r++)
        r,
    }.toList()
      ..sort();
    final doneAll = s.workingSetsDone >= ex.rule.workingSets;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              GestureDetector(
                onLongPress: () => s.setWeightDraft(0),
                child: Text(s.weightDraft <= 0 ? '自重' : fmtKg(s.weightDraft),
                    style: AppTheme.bigNum(s.weightDraft <= 0 ? 56 : 84)),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 6, bottom: 10),
                child: Text('kg',
                    style: TextStyle(
                        color: AppTheme.textDim,
                        fontSize: 20,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(children: [
            for (final step in _steps)
              WeightStepButton(
                  delta: step, onTap: () => s.setWeightDraft(s.weightDraft + step)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            for (final step in _steps)
              WeightStepButton(
                  delta: -step,
                  onTap: () => s.setWeightDraft(s.weightDraft - step)),
          ]),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _kindChip('热身', SetKind.warmup),
              const SizedBox(width: 8),
              _kindChip('正式', SetKind.working),
              const SizedBox(width: 8),
              _kindChip('力竭', SetKind.failure),
            ],
          ),
          const SizedBox(height: 8),
          // RIR（余力）：默认用计划目标值，可点选覆盖
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('余力 ',
                  style: TextStyle(color: AppTheme.textDim, fontSize: 14)),
              for (var r = 0; r <= 4; r++)
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _rir = (_rir == r) ? null : r);
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: _rir == r ? AppTheme.accent : AppTheme.cardHi,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('$r',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: _rir == r
                                ? const Color(0xFF06220F)
                                : AppTheme.textDim)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final r in repsChoices)
                ChoiceChip(
                  label: Text('$r'),
                  selected: _reps == r,
                  labelStyle: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color:
                          _reps == r ? const Color(0xFF06220F) : AppTheme.text),
                  selectedColor: AppTheme.primary,
                  backgroundColor: AppTheme.cardHi,
                  side: BorderSide.none,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  onSelected: (_) {
                    HapticFeedback.selectionClick();
                    setState(() => _reps = r);
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
          // 备注入口（默认收起，PRD P0 字段：单组备注）
          GestureDetector(
            onTap: () => setState(() => _noteOpen = !_noteOpen),
            child: Text(_note.isEmpty && !_noteOpen
                ? '+ 备注（可选）'
                : '备注：${_note.isEmpty ? "编辑" : _note}',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13,
                    color: _note.isEmpty
                        ? AppTheme.textDim
                        : AppTheme.accent)),
          ),
          if (_noteOpen)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: TextField(
                controller: _noteCtrl,
                autofocus: false,
                maxLines: 1,
                onChanged: (v) => _note = v,
                decoration: const InputDecoration(
                    hintText: '这组的感受/状态（可选）',
                    isDense: true),
              ),
            ),
          const SizedBox(height: 12),
          BigButton(
            label: doneAll ? '本动作已完成 ✓' : '完成本组',
            color: doneAll
                ? AppTheme.cardHi
                : (_kind == SetKind.failure ? AppTheme.warn : AppTheme.primary),
            onPressed: doneAll
                ? null
                : () async {
                    HapticFeedback.mediumImpact();
                    final reps = _reps ?? ex.rule.repsMin;
                    final pr = await s.completeSet(
                      weight: s.weightDraft,
                      reps: reps,
                      rir: _rir ?? ex.rule.rirTarget,
                      kind: _kind,
                      note: _note,
                    );
                    _noteCtrl.clear();
                    _note = '';
                    if (_noteOpen) setState(() => _noteOpen = false);
                    if (!context.mounted) return;
                    // 最后一个动作的最后一组：状态机已自动结束，走完整收尾
                    // （总结页 + 渐进建议 + 飞书回填）
                    if (!s.hasActive) {
                      await endTraining(context);
                      return;
                    }
                    if (pr) s.showFocusBanner('🏆 ${ex.name} 重量新高 PR！');
                  },
          ),
        ],
      ),
    );
  }

  Widget _kindChip(String label, String kind) {
    final sel = _kind == kind;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _kind = kind);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: sel ? AppTheme.accent : AppTheme.cardHi,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: sel ? const Color(0xFF06220F) : AppTheme.textDim)),
      ),
    );
  }
}

// ================= 休息态 =================

class _RestView extends StatelessWidget {
  const _RestView();

  @override
  Widget build(BuildContext context) {
    final c = app(context);
    final s = c.session;
    final ex = s.currentEx;
    final isLastEx = s.curExIdx >= s.exercises.length - 1;
    final plannedWorking = ex?.rule.workingSets ?? 0;
    final nextText = s.workingSetsDone >= plannedWorking
        ? (isLastEx ? '准备结束训练' : '下一个动作：${s.exercises[s.curExIdx + 1].name}')
        : '下一组：${fmtWeight(s.weightDraft)}${s.weightDraft > 0 ? 'kg' : ''} × ${ex?.rule.repsMin}-${ex?.rule.repsMax} 次';

    return Column(
      children: [
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('组间休息',
                  style: TextStyle(color: AppTheme.textDim, fontSize: 18)),
              const SizedBox(height: 8),
              ValueListenableBuilder<int>(
                valueListenable: s.restRemainingMs,
                builder: (context, ms, _) {
                  final remain = (ms / 1000).ceil();
                  final frac =
                      s.restTotalMs <= 0 ? 1.0 : ms / s.restTotalMs;
                  final color = frac > 0.2
                      ? AppTheme.primary
                      : (frac > 0 ? AppTheme.warn : AppTheme.danger);
                  return Text(
                    fmtDuration(remain),
                    style: AppTheme.bigNum(
                      (MediaQuery.of(context).size.height *
                              (_isWide(context) ? 0.20 : 0.15))
                          .clamp(72.0, 260.0),
                      color: color,
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              Text(nextText,
                  style: const TextStyle(color: AppTheme.text, fontSize: 18)),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          decoration: const BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 64,
                      child: OutlinedButton(
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          s.extendRest(30);
                          c.notify.cancelRest();
                          c.notify.showOngoing(s.restEndAt);
                          c.notify.scheduleRestEnd(s.restEndAt);
                        },
                        style: OutlinedButton.styleFrom(
                          backgroundColor: AppTheme.cardHi,
                          side: BorderSide.none,
                        ),
                        child: const Text('+30 秒',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 64,
                      child: OutlinedButton(
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          s.isRestPaused ? s.resumeRest() : s.pauseRest();
                        },
                        style: OutlinedButton.styleFrom(
                          backgroundColor: AppTheme.cardHi,
                          side: BorderSide.none,
                          foregroundColor:
                              s.isRestPaused ? AppTheme.primary : AppTheme.text,
                        ),
                        child: Text(s.isRestPaused ? '继续' : '暂停',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 64,
                      child: OutlinedButton(
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          s.undoLastSet();
                        },
                        style: OutlinedButton.styleFrom(
                          backgroundColor: AppTheme.cardHi,
                          side: BorderSide.none,
                          foregroundColor: AppTheme.textDim,
                        ),
                        child: const Text('撤销',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              BigButton(
                label: '跳过休息，直接开练',
                height: 80,
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  c.notify.cancelRest();
                  s.skipRest();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  bool _isWide(BuildContext context) =>
      MediaQuery.of(context).size.width >= 840;
}

// ================= 结束 + 总结 =================

bool _endTrainingInFlight = false;

Future<void> endTraining(BuildContext context) async {
  if (_endTrainingInFlight) return;
  _endTrainingInFlight = true;
  try {
    await _doEndTraining(context);
  } finally {
    _endTrainingInFlight = false;
  }
}

Future<void> _doEndTraining(BuildContext context) async {
  final c = app(context);
  final s = c.session;
  final stats = await s.stats();
  final verdicts = await s.verdicts();
  final date = s.session?.date ?? fmtDate(DateTime.now());
  final title = s.session?.planDayTitle ?? '';
  final prNames = s.prHit.toList();
  final durationMin = s.session?.durationMin ?? 0;
  await s.finish();
  c.notify.cancelRest();
  final summaryBuf = StringBuffer();
  summaryBuf.writeln(
      '$title 完成：总容量 ${fmtVolume(stats.volume)}，${stats.workingSets} 个正式组，${stats.exercises.length} 个动作。');
  for (final v in verdicts) {
    summaryBuf.writeln('- $v');
  }
  unawaited(c.lark
      .backfillSessionSummary(date: date, summary: summaryBuf.toString()));

  if (!context.mounted) return;
  await Navigator.of(context).pushReplacement(MaterialPageRoute(
    builder: (_) => _SummaryPage(
      stats: stats,
      verdicts: verdicts,
      title: title,
      prNames: prNames,
      durationMin: durationMin,
    ),
  ));
}

class _SummaryPage extends StatelessWidget {
  const _SummaryPage({
    required this.stats,
    required this.verdicts,
    required this.title,
    required this.prNames,
    required this.durationMin,
  });

  final SessionStats stats;
  final List<String> verdicts;
  final String title;
  final List<String> prNames;
  final int durationMin;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 24),
            const Text('训练完成 💪',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.textDim, fontSize: 16)),
            const SizedBox(height: 24),
            Row(
              children: [
                _statCell('总容量', fmtVolume(stats.volume)),
                _statCell('正式组', '${stats.workingSets}'),
                _statCell('动作数', '${stats.exercises.length}'),
              ],
            ),
            const SizedBox(height: 8),
            Text('训练时长 $durationMin 分钟',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.textDim)),
            const SizedBox(height: 24),
            if (prNames.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.warn.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text('🏆 PR 突破：${prNames.join('、')}',
                    style: const TextStyle(
                        color: AppTheme.warn,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 16),
            ],
            SectionCard(
              title: '渐进建议（下次训练）',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final v in verdicts)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child:
                          Text('· $v', style: const TextStyle(fontSize: 15)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            BigButton(
              label: '收工',
              height: 72,
              onPressed: () =>
                  Navigator.of(context).popUntil((r) => r.isFirst),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statCell(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: AppTheme.bigNum(30, color: AppTheme.primary)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: AppTheme.textDim)),
        ],
      ),
    );
  }
}
