import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/engine.dart';
import '../services/session_controller.dart';
import 'exercise_picker_page.dart';
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

  /// 休息开始/结束时挂接通知。精确结束提醒不在这里挂：时间源统一走
  /// SessionController.onRestAlarmChanged 回调（开始/加时/继续/暂停统一重排，
  /// 见 App 容器接线），页面只负责常驻倒计时文案。
  void _syncPhaseSideEffects(WorkoutPhase phase) {
    if (_lastPhase == phase) return;
    final old = _lastPhase;
    _lastPhase = phase;
    final c = app(context);
    final s = c.session;
    if (phase == WorkoutPhase.resting) {
      c.notify.showOngoing(s.restEndAt);
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
                      // 600dp 断点：更窄的屏（手机竖屏/分屏小窗）用紧凑面板，
                      // 压大数字字号并收起备注行，给「完成本组」留出空间。
                      final narrow = cons.maxWidth < 600;
                      Widget content = s.phase == WorkoutPhase.resting
                          ? const _RestView()
                          : _LiftView(s: s, compact: narrow);
                      // 窄屏/中屏：操作区最大宽度 560，单手可达
                      if (!wide) {
                        content = Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 560),
                            child: content,
                          ),
                        );
                      }
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
  const _LiftView({required this.s, this.compact = false});

  final SessionController s;

  /// <600dp 窄屏：压缩面板（大数字字号降档、隐藏备注行）。
  final bool compact;

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
        // 单栏：信息区 + 操作面板装进同一滚动区。内容装得下时用 min-height
        // 撑满视口（信息居中、面板贴底，与原布局一致）；装不下（横屏 ~360dp
        // 可用高、系统大字号）时整体可滚动，「完成本组」不再被挤出屏幕。
        return Column(
          children: [
            _TopBar(s: s),
            Expanded(
              child: LayoutBuilder(
                builder: (context, viewport) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minHeight: viewport.maxHeight),
                    child: IntrinsicHeight(
                      child: Column(
                        children: [
                          Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 20),
                              child: _ExerciseInfo(s: s, ex: ex),
                            ),
                          ),
                          _ActionPanel(
                              s: s,
                              ex: ex,
                              key: ValueKey(ex.id),
                              compact: compact),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
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

  /// 两击确认后给三个出口：继续练 / 放弃本次（不留记录）/ 结束并保存。
  Future<void> _showEndOptions() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.play_arrow, color: AppTheme.primary),
              title: const Text('继续训练'),
              onTap: () => Navigator.pop(ctx, 'continue'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppTheme.danger),
              title: const Text('放弃本次（不留记录）'),
              subtitle: const Text('误开的训练用这个，历史不会多一次',
                  style: TextStyle(fontSize: 12)),
              onTap: () => Navigator.pop(ctx, 'quit'),
            ),
            ListTile(
              leading: const Icon(Icons.check_circle, color: AppTheme.primary),
              title: const Text('结束并保存'),
              onTap: () => Navigator.pop(ctx, 'finish'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'finish') {
      await endTraining(context);
    } else if (choice == 'quit') {
      final c = app(context);
      final navigator = Navigator.of(context);
      await c.session.quit();
      if (!mounted) return;
      navigator.pop(); // 退出训练页回首页
    }
  }

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
            onPressed: () => _showExerciseAdjustSheet(context),
            child: const Text('换/加动作',
                style: TextStyle(color: AppTheme.textDim, fontSize: 14)),
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
                _showEndOptions();
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

  /// 训练中临时调整动作：加动作到队尾 / 替换当前动作（器械被占时用）。
  /// 只影响本次训练，不改计划；当前动作已记组时不可替换（防串名）。
  Future<void> _showExerciseAdjustSheet(BuildContext context) async {
    final s = widget.s;
    final canReplace = s.currentSets.isEmpty;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.playlist_add, color: AppTheme.primary),
              title: const Text('添加动作到队尾'),
              subtitle: const Text('从动作库挑选，只进本次训练',
                  style: TextStyle(fontSize: 12)),
              onTap: () => Navigator.pop(ctx, 'append'),
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz, color: AppTheme.accent),
              title: Text(canReplace
                  ? '替换当前动作（${s.currentEx?.name ?? ''}）'
                  : '替换当前动作'),
              subtitle: Text(
                  canReplace
                      ? '沿用原组次规则，只换动作名'
                      : '当前动作已记组，不能替换；可改用"跳过动作"',
                  style: const TextStyle(fontSize: 12)),
              onTap: canReplace ? () => Navigator.pop(ctx, 'replace') : null,
            ),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    // 替换时把当前动作也标为已存在，防止挑到它自己
    final existing = s.exercises.map((e) => e.name).toSet();
    final picked = await Navigator.of(context).push<List<ExerciseMeta>>(
      MaterialPageRoute(
        builder: (_) => ExercisePickerPage(existingNames: existing),
      ),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    if (choice == 'append') {
      await s.appendExercises(picked);
      s.showFocusBanner('已加 ${picked.length} 个动作到队尾');
    } else {
      final ok = await s.replaceCurrentExercise(picked.first);
      if (ok) {
        s.showFocusBanner('已换成 ${picked.first.name}');
      } else {
        messenger.showSnackBar(SnackBar(
            content: const Text('替换失败：该动作已在本次训练里'),
            backgroundColor: AppTheme.cardHi,
            behavior: SnackBarBehavior.floating));
      }
    }
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
    // 计划组练满后（加练态）进度行换成加练计数，不再显示"第 5 / 4 组"
    final extraNo = s.workingSetsDone - ex.rule.workingSets + 1;
    final progressText = s.workingSetsDone >= ex.rule.workingSets
        ? '已练满 ${ex.rule.workingSets} 组 · 加练第 $extraNo 组 · 目标 ${ex.rule.repsMin}-${ex.rule.repsMax} 次'
        : '第 ${s.workingSetsDone + 1} / ${ex.rule.workingSets} 组 · 目标 ${ex.rule.repsMin}-${ex.rule.repsMax} 次 · RIR ${ex.rule.rirTarget}';
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
        Text(progressText,
            style: const TextStyle(color: AppTheme.accent, fontSize: 16)),
        const SizedBox(height: 12),
        Text(lastText,
            style: const TextStyle(color: AppTheme.textDim, fontSize: 15)),
        if (s.currentSets.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: GestureDetector(
              onTap: () => s.undoLastSet(),
              child: const Text('↩ 撤销上一组',
                  style:
                      TextStyle(color: AppTheme.textDim, fontSize: 13)),
            ),
          ),
      ],
    );
  }
}

/// 重量键盘输入层：点重量数字 / 休息页「直接输入重量」唤起。
/// 只在用户主动点按时出现、划掉或点空白处即取消，不属于训练中打断弹窗；
/// 正数=负重，0=自重，负数=辅助器械配重。
Future<void> showWeightInputSheet(BuildContext context, SessionController s) {
  final ctrl = TextEditingController(text: fmtKg(s.weightDraft));
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.card,
    builder: (sheetCtx) => StatefulBuilder(
      builder: (sheetCtx, setSheetState) {
        void submit() {
          final v = double.tryParse(ctrl.text.trim().replaceAll(',', '.'));
          if (v == null) {
            setSheetState(() {}); // 刷新 errorText 提示
            return;
          }
          HapticFeedback.selectionClick();
          s.setWeightDraft(v);
          Navigator.pop(sheetCtx);
        }

        final invalid =
            double.tryParse(ctrl.text.trim().replaceAll(',', '.')) == null;
        return Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('输入重量（kg）',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                const Text('正数 = 负重；0 = 自重；负数 = 辅助器械配重（如 -30）',
                    style: TextStyle(color: AppTheme.textDim, fontSize: 13)),
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true, signed: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'^-?\d{0,3}(\.\d{0,2})?$')),
                    LengthLimitingTextInputFormatter(7),
                  ],
                  onSubmitted: (_) => submit(),
                  style: AppTheme.bigNum(30),
                  decoration: InputDecoration(
                    hintText: '如 62.5',
                    errorText: invalid ? '请输入数字，如 62.5 或 -30' : null,
                  ),
                ),
                const SizedBox(height: 16),
                BigButton(
                  label: '确认',
                  height: 64,
                  onPressed: submit,
                ),
                TextButton(
                  onPressed: () => Navigator.pop(sheetCtx),
                  child: const Text('取消',
                      style: TextStyle(color: AppTheme.textDim)),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _ActionPanel extends StatefulWidget {
  const _ActionPanel({
    super.key,
    required this.s,
    required this.ex,
    this.compact = false,
  });

  final SessionController s;
  final SessionExercise ex;

  /// <600dp 窄屏压缩：重量大数字 84→56、收起备注行；
  /// 步进按钮与「完成本组」高度不动（冻结基线）。
  final bool compact;

  @override
  State<_ActionPanel> createState() => _ActionPanelState();
}

class _ActionPanelState extends State<_ActionPanel> {
  String _kind = SetKind.working;
  int? _reps;
  int? _rir;
  String _note = '';
  bool _noteOpen = false;
  bool _saving = false; // 防抖：力竭手抖双击不能记两组
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
    final compact = widget.compact;
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
              // Flexible+FittedBox：键盘可输任意值（999.5 / 辅 300），
              // 数字放不下时等比缩小而不是溢出裁切；放得下保持原字号
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      showWeightInputSheet(context, s);
                    },
                    onLongPress: () => s.setWeightDraft(0),
                    // 负值=辅助配重（辅30），0=自重，正值=常规负重（fmtLoad 统一口径）；
                    // 点按弹数字键盘直输，长按清零（老入口保留）
                    child: Text(fmtLoad(s.weightDraft),
                        key: const ValueKey('weightDraftNum'),
                        style: AppTheme.bigNum(
                            compact || s.weightDraft <= 0 ? 56 : 84)),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 6, bottom: 10),
                child: Text('kg',
                    style: TextStyle(
                        color: AppTheme.textDim,
                        fontSize: 20,
                        fontWeight: FontWeight.w600)),
              ),
              // 自重/负重一键切换（长按清零的老入口保留，这里给可见入口）
              Padding(
                padding: const EdgeInsets.only(left: 12, bottom: 12),
                child: Tooltip(
                  message: '自重/辅助动作点这里：在自重和上次重量间切换；'
                      '点大数字可直接键入重量（负值 = 辅助器械配重，如 -30）',
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      s.toggleBodyweightDraft();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: s.weightDraft == 0
                            ? AppTheme.accent
                            : AppTheme.cardHi,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(s.weightDraft == 0 ? '自重' : '自重?',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: s.weightDraft == 0
                                  ? const Color(0xFF06220F)
                                  : AppTheme.textDim)),
                    ),
                  ),
                ),
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
              Tooltip(
                message: '余力(RIR) = 做完这组还能再做几次，不确定就用计划默认值',
                child: const Text('余力 ',
                    style: TextStyle(color: AppTheme.textDim, fontSize: 14)),
              ),
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
          // 备注入口（默认收起，PRD P0 字段：单组备注）；
          // <600dp 窄屏压缩时整段收起，给完成按钮留高度。
          if (!compact) ...[
            const SizedBox(height: 8),
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
          ],
          const SizedBox(height: 12),
          // key 仅供 widget 测试定位（test/widget_layout_test.dart），无行为含义。
          // 计划组练满后按钮变成"加练一组"（加练组按正式组记录），不再是死灰按钮。
          BigButton(
            key: const Key('workoutCompleteSet'),
            label: doneAll ? '加练一组（正式组）' : '完成本组',
            color: _kind == SetKind.failure ? AppTheme.warn : AppTheme.primary,
            onPressed: _saving
                ? null
                : () async {
                    _saving = true;
                    HapticFeedback.mediumImpact();
                    final reps = _reps ?? ex.rule.repsMin;
                    final pr = await s.completeSet(
                      weight: s.weightDraft,
                      reps: reps,
                      rir: _rir ?? ex.rule.rirTarget,
                      kind: _kind,
                      note: _note,
                    );
                    _saving = false;
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

class _RestView extends StatefulWidget {
  const _RestView();

  @override
  State<_RestView> createState() => _RestViewState();
}

class _RestViewState extends State<_RestView> {
  bool _weightOpen = false; // 展开"下一组重量"步进（休息中可调重量）
  static const _steps = [0.5, 1.25, 2.5, 5.0];

  @override
  Widget build(BuildContext context) {
    final c = app(context);
    final s = c.session;
    final ex = s.currentEx;
    final isLastEx = s.curExIdx >= s.exercises.length - 1;
    final plannedWorking = ex?.rule.workingSets ?? 0;
    final nextText = s.workingSetsDone >= plannedWorking
        ? (isLastEx ? '准备结束训练' : '下一个动作：${s.exercises[s.curExIdx + 1].name}')
        : '下一组：${fmtLoad(s.weightDraft)}${s.weightDraft != 0 ? 'kg' : ''} × ${ex?.rule.repsMin}-${ex?.rule.repsMax} 次（点击可改重量）';

    // 上半（倒计时）+ 底部操作区装进同一滚动区：装得下时 min-height 撑满
    // 视口（操作区贴底，与原布局一致）；横屏/矮屏装不下时可滚动，
    // 「跳过休息，直接开练」不再被挤出屏幕。
    return LayoutBuilder(
      builder: (context, viewport) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: viewport.maxHeight),
          child: IntrinsicHeight(
            child: Column(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('组间休息',
                          style: TextStyle(
                              color: AppTheme.textDim, fontSize: 18)),
                      const SizedBox(height: 8),
                      ValueListenableBuilder<int>(
                        valueListenable: s.restRemainingMs,
                        builder: (context, ms, _) {
                          final remain = (ms / 1000).ceil();
                          final frac = s.restTotalMs <= 0
                              ? 1.0
                              : ms / s.restTotalMs;
                          final color = frac > 0.2
                              ? AppTheme.primary
                              : (frac > 0 ? AppTheme.warn : AppTheme.danger);
                          return Text(
                            fmtDuration(remain),
                            style: AppTheme.bigNum(
                              // 下限 56（原 72）：横屏/矮屏下先给底部操作区
                              // 留出空间，数字仍远大于页内其他文字（18/24 号），
                              // 保持屏内最大元素。
                              (MediaQuery.of(context).size.height *
                                      (_isWide(context) ? 0.20 : 0.15))
                                  .clamp(56.0, 260.0),
                              color: color,
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      // 点"下一组"展开重量步进：休息中就能调下一组重量
                      GestureDetector(
                        onTap: () =>
                            setState(() => _weightOpen = !_weightOpen),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppTheme.cardHi,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(nextText,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: AppTheme.text, fontSize: 18)),
                        ),
                      ),
                      if (_weightOpen) ...[
                        const SizedBox(height: 10),
                        // 键盘直输入口：步进微调之外的整段重量输入
                        OutlinedButton(
                          onPressed: () {
                            HapticFeedback.selectionClick();
                            showWeightInputSheet(context, s);
                          },
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                          child: const Text('直接输入重量',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(height: 6),
                        Row(children: [
                          for (final step in _steps)
                            WeightStepButton(
                                delta: step,
                                onTap: () => s
                                    .setWeightDraft(s.weightDraft + step)),
                        ]),
                        const SizedBox(height: 6),
                        Row(children: [
                          for (final step in _steps)
                            WeightStepButton(
                                delta: -step,
                                onTap: () => s
                                    .setWeightDraft(s.weightDraft - step)),
                        ]),
                        const SizedBox(height: 4),
                        TextButton(
                          onPressed: () => s.toggleBodyweightDraft(),
                          child: Text(
                              s.weightDraft == 0
                                  ? '当前：自重'
                                  : (s.weightDraft < 0
                                      ? '当前：辅 ${fmtKg(-s.weightDraft)}（点切自重）'
                                      : '改为自重'),
                              style: const TextStyle(
                                  color: AppTheme.textDim, fontSize: 13)),
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  decoration: const BoxDecoration(
                    color: AppTheme.card,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 组间/练满都常显：休息中觉得状态好就回刚完成的动作再来一组
                      if (s.extraSetExerciseName != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                HapticFeedback.selectionClick();
                                c.notify.cancelRest();
                                s.startExtraSet();
                              },
                              icon: const Icon(Icons.replay,
                                  size: 18, color: AppTheme.primary),
                              label: Text(
                                  '再来一组 · ${s.extraSetExerciseName}（继承上次重量）',
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.primary)),
                            ),
                          ),
                        ),
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 64,
                              child: OutlinedButton(
                                onPressed: () {
                                  HapticFeedback.selectionClick();
                                  s.extendRest(-30);
                                  // 精确闹钟由控制器 onRestAlarmChanged 回调随
                                  // restEndAt 统一重排；暂停态 restEndAt 不更新
                                  // （加时改的是冻结值），只即时刷新常驻倒计时文案。
                                  if (!s.isRestPaused) {
                                    c.notify.showOngoing(s.restEndAt);
                                  }
                                },
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: AppTheme.cardHi,
                                  side: BorderSide.none,
                                ),
                                child: const Text('-30 秒',
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700)),
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
                                  s.extendRest(30);
                                  if (!s.isRestPaused) {
                                    c.notify.showOngoing(s.restEndAt);
                                  }
                                },
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: AppTheme.cardHi,
                                  side: BorderSide.none,
                                ),
                                child: const Text('+30 秒',
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700)),
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
                                  s.isRestPaused
                                      ? s.resumeRest()
                                      : s.pauseRest();
                                },
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: AppTheme.cardHi,
                                  side: BorderSide.none,
                                  foregroundColor: s.isRestPaused
                                      ? AppTheme.primary
                                      : AppTheme.text,
                                ),
                                child: Text(s.isRestPaused ? '继续' : '暂停',
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700)),
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
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600)),
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
            ),
          ),
        ),
      ),
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
  // 净时长（训练/休息分桶）在 finish 落库后回读
  final restMin = ((s.session?.restMs ?? 0) / 60000).ceil();
  final activeMin = ((s.session?.activeMs ?? 0) / 60000).ceil();
  final summaryBuf = StringBuffer();
  summaryBuf.writeln(
      '$title 完成：总容量 ${fmtVolume(stats.volume)}，${stats.workingSets} 个正式组，${stats.exercises.length} 个动作，总时长 $durationMin 分钟（训练 $activeMin / 休息 $restMin）。');
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
      activeMin: activeMin,
      restMin: restMin,
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
    required this.activeMin,
    required this.restMin,
  });

  final SessionStats stats;
  final List<String> verdicts;
  final String title;
  final List<String> prNames;
  final int durationMin;
  final int activeMin;
  final int restMin;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        // 非惰性滚动（SingleChildScrollView）：总结页内容一页半以内，全部
        // 构建没开销，且保证「收工」永远可被 find/ensureVisible 命中——
        // ListView 惰性构建在大字号下会把按钮留出构建边界。
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
              Text(
                  durationMin > 0
                      ? (activeMin > 0 || restMin > 0
                          ? '总时长 $durationMin 分钟 · 训练 $activeMin 分 · 休息 $restMin 分'
                          : '训练时长 $durationMin 分钟')
                      : '训练完成',
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
      ),
    );
  }

  Widget _statCell(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          // 360dp 屏每格仅约 104 逻辑像素，"9999kg" 在字体缩放或小屏下
          // 放不下：FittedBox 等比缩字，避免溢出/与邻格重叠。
          FittedBox(
            fit: BoxFit.scaleDown,
            child:
                Text(value, style: AppTheme.bigNum(30, color: AppTheme.primary)),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: AppTheme.textDim)),
        ],
      ),
    );
  }
}
