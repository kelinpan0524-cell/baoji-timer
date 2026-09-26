import 'package:flutter/material.dart';

import '../core/app.dart';
import '../engine/engine.dart';
import '../l10n/lang.dart';
import '../l10n/names.dart';
import 'ai_coach_page.dart';
import 'theme.dart';
import 'widgets/common.dart';
import 'workout_page.dart';

/// 首页（今日）：训练进度、今日计划卡、AI 教练入口、上次小结。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _loading = true;
  List<Session> _doneThisWeek = [];
  Session? _lastSession;
  SessionStats? _lastStats;
  PlanDay? _todayDay; // 今天该练什么（排程解析：覆盖行 > 循环 > 星期模板）

  @override
  void initState() {
    super.initState();
    // initState 里不能同步读 InheritedWidget，延后一帧再加载
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    final c = app(context);
    await c.planRepo.reload();
    final now = DateTime.now();
    final monday = mondayOf(now);
    final done = await c.db.sessionsBetween(fmtDate(monday), fmtDate(now));
    final last = await c.db.recentSessions(limit: 1);
    SessionStats? stats;
    if (last.isNotEmpty) {
      final ses = await c.db.sessionExercises(last.first.id!);
      final map = await c.db.setsOfSession(last.first.id!);
      // 容量口径与统计页一致：自重动作按 系数×体重 折算（评审拉齐）
      stats = sessionStatsFrom(map, ses, bodyWeightKg: c.settings.bodyWeightKg);
    }
    final today = await c.planRepo.dayForDate(DateTime.now());
    if (!mounted) return;
    setState(() {
      _doneThisWeek = done;
      _lastSession = last.isEmpty ? null : last.first;
      _lastStats = stats;
      _todayDay = today;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = app(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final repo = c.planRepo;
    final today = DateTime.now();
    final day = _todayDay;
    final active = c.session.hasActive;
    final planName = repo.activePlan?.name;

    return RefreshIndicator(
      onRefresh: _refresh,
      color: AppTheme.primary,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _weekDots(today),
          const SizedBox(height: 16),
          // AI 教练唯一入口（2026-09-26 Arono 需求）：首页置顶一张卡，
          // 不再散落在数据页顶栏 / 设置页里
          _aiCoachCard(context),
          if (repo.activePlan == null)
            _noPlanCard(c)
          else ...[
            Text(dname(planName ?? ''),
                style:
                    const TextStyle(color: AppTheme.textDim, fontSize: 14)),
            const SizedBox(height: 8),
            _todayCard(c, active, day),
          ],
          const SizedBox(height: 16),
          if (_lastSession != null) _lastSummaryCard(c),
        ],
      ),
    );
  }

  /// AI 教练入口卡：问训练数据 / 对话排计划，点开进 AiCoachPage。
  /// 排版贴 SectionCard 视觉，但用主色淡底突出"这是唯一的 AI 入口"。
  Widget _aiCoachCard(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: AppTheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AiCoachPage()),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.smart_toy_outlined, color: AppTheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tx('AI 教练', en: 'AI Coach'),
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                          tx('问训练数据 · 一句话排计划，一键存入 App',
                              en: 'Ask your training data · build a plan in one sentence, save it in one tap'),
                          style: const TextStyle(
                              color: AppTheme.textDim, fontSize: 12)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppTheme.textDim),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _weekDots(DateTime today) {
    final monday = mondayOf(today);
    final doneDates = _doneThisWeek.map((s) => s.date).toSet();
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(7, (i) {
        final d = monday.add(Duration(days: i));
        final label = ['一', '二', '三', '四', '五', '六', '日'][i];
        final isToday = d.weekday == today.weekday;
        final done = doneDates.contains(fmtDate(d));
        return Column(
          children: [
            Text(tx('周$label',
                en: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][i]),
                style: TextStyle(
                    fontSize: 12,
                    color: isToday ? AppTheme.primary : AppTheme.textDim)),
            const SizedBox(height: 6),
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done
                    ? AppTheme.primary
                    : isToday
                        ? AppTheme.accent
                        : AppTheme.cardHi,
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _noPlanCard(AppContainer c) {
    return SectionCard(
      title: tx('还没有训练计划', en: 'No Workout Plan Yet'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              tx('用内置薄肌计划开练，或粘贴自己的计划让 AI 拆解。',
                  en: 'Start with the built-in Baoji Plan, or paste your own plan for AI to parse.'),
              style: const TextStyle(color: AppTheme.textDim)),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              await c.planRepo.installBaojiPlan();
              await _syncLarkDays(c);
              if (mounted) {
                messenger.showSnackBar(SnackBar(
                    content: Text(tx('薄肌计划已就绪', en: 'Baoji Plan is ready')),
                    backgroundColor: AppTheme.cardHi,
                    behavior: SnackBarBehavior.floating));
                _refresh();
              }
            },
            child: Text(tx('一键安装薄肌计划', en: 'Install Baoji Plan')),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () {
              DefaultTabController.maybeOf(context)?.animateTo(1);
            },
            child: Text(tx('去计划页导入', en: 'Import on Plan page')),
          ),
        ],
      ),
    );
  }

  Widget _todayCard(AppContainer c, bool active, PlanDay? day) {
    if (active) {
      final s = c.session;
      return SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 10, height: 10,
                decoration: const BoxDecoration(
                    color: AppTheme.primary, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(tx('训练进行中', en: 'Workout in Progress'),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 8),
            Text(
                tx(
                    '${dname(s.session!.planDayTitle)} · 第 ${s.curExIdx + 1}/${s.exercises.length} 个动作',
                    en: '${dname(s.session!.planDayTitle)} · Exercise ${s.curExIdx + 1}/${s.exercises.length}'),
                style: const TextStyle(color: AppTheme.textDim)),
            const SizedBox(height: 16),
            BigButton(
              label: tx('继续训练', en: 'Resume Workout'),
              height: 72,
              onPressed: () => _openWorkout(context),
            ),
          ],
        ),
      );
    }
    if (day == null) {
      return SectionCard(
        title: tx('今天是休息日', en: 'Rest Day Today'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                tx('恢复也是训练的一部分。想加练或看看本周安排：',
                    en: 'Recovery is part of training. Want an extra session or to check this week:'),
                style: const TextStyle(color: AppTheme.textDim)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        DefaultTabController.maybeOf(context)?.animateTo(1),
                    child: Text(tx('查看计划', en: 'View Plan')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _starting ? null : () => _pickExtraDay(context),
                    child: Text(tx('今天加练', en: 'Extra Workout Today')),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }
    final exs = c.planRepo.exercisesByDayId[day.id] ?? [];
    return SectionCard(
      title: tx('今天该练', en: "Today's Workout"),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(dname(day.title),
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(
              tx('${exs.length} 个动作 · 约 ${_estimateMin(exs)} 分钟',
                  en: '${exs.length} exercises · ~${_estimateMin(exs)} min'),
              style: const TextStyle(color: AppTheme.textDim)),
          const SizedBox(height: 8),
          ...exs.map((e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text('· ${exname(e.name)} ${e.sets}×${e.repsMin}-${e.repsMax}',
                    style: const TextStyle(fontSize: 15)),
              )),
          const SizedBox(height: 16),
          BigButton(
            label: tx('开始训练', en: 'Start Workout'),
            height: 72,
            onPressed: (exs.isEmpty || _starting)
                ? null
                : () => _start(context, day, exs),
          ),
        ],
      ),
    );
  }

  int _estimateMin(List<PlanExercise> exs) {
    var sec = 0;
    for (final e in exs) {
      sec += e.sets * (e.restSec + 45);
    }
    return (sec / 60).ceil();
  }

  Widget _lastSummaryCard(AppContainer c) {
    final s = _lastSession!;
    final st = _lastStats!;
    return SectionCard(
      title: tx('上次训练', en: 'Last Workout'),
      trailing: Text(s.date, style: const TextStyle(color: AppTheme.textDim)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(dname(s.planDayTitle),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(
              tx(
                  '总容量 ${fmtVolume(st.volume)} · ${st.workingSets} 个正式组 · ${s.durationMin} 分钟',
                  en: 'Total volume ${fmtVolume(st.volume)} · ${st.workingSets} working sets · ${s.durationMin} min'),
              style: const TextStyle(color: AppTheme.textDim)),
        ],
      ),
    );
  }

  Future<void> _start(BuildContext context, PlanDay day, List<PlanExercise> exs) async {
    if (_starting) return; // 双击第二击直接忽略（禁用态靠 setState 重建才真实生效）
    final c = app(context);
    if (c.session.hasActive) {
      // 已有进行中的会话：直接继续，防止双击产生孤儿会话
      await _openWorkout(context);
      return;
    }
    setState(() => _starting = true);
    try {
      await c.planRepo.refreshRecommendations(exs.map((e) => e.name));
      await c.session.startFromDay(day: day, planExercises: exs);
      if (!context.mounted) return;
      await _openWorkout(context);
    } finally {
      if (mounted) {
        setState(() => _starting = false);
      } else {
        _starting = false;
      }
    }
  }

  bool _starting = false;

  /// 休息日临时加练：弹出计划里有动作的训练日让用户挑一个开练。
  Future<void> _pickExtraDay(BuildContext context) async {
    final c = app(context);
    final plan = c.planRepo.activePlan;
    if (plan == null) return;
    final days = await c.db.planDays(plan.id!);
    final exByDay =
        await c.db.daysExercisesMap(days.map((d) => d.id!).toList());
    final trainable = [
      for (final d in days)
        if ((exByDay[d.id] ?? const <PlanExercise>[]).isNotEmpty) d,
    ];
    if (!context.mounted) return;
    if (trainable.isEmpty) {
      toast(
          context,
          tx('当前计划还没有编排动作，先去计划页添加',
              en: 'No exercises in this plan yet. Add some on the Plan page first.'));
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          children: [
            Text(tx('加练哪一天的内容？', en: 'Pick a Day to Train'),
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
                tx('加练按该日的完整动作清单开练，记录照常保存。',
                    en: 'Extra sessions run the full exercise list of that day and are saved as usual.'),
                style: const TextStyle(
                    color: AppTheme.textDim, fontSize: 12)),
            const SizedBox(height: 8),
            for (final d in trainable)
              ListTile(
                leading: const Icon(Icons.fitness_center,
                    color: AppTheme.primary),
                title: Text(dname(d.title)),
                subtitle: Text(
                    tx(
                        '${(exByDay[d.id] ?? const <PlanExercise>[]).length} 个动作',
                        en: '${(exByDay[d.id] ?? const <PlanExercise>[]).length} exercises'),
                    style: const TextStyle(fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  _start(context, d, exByDay[d.id!]!);
                },
              ),
          ],
        ),
      ),
    );
  }

  /// 激活计划的未来训练日写入飞书日历（安装/导入计划后调用）。
  Future<void> _syncLarkDays(AppContainer c) async {
    final planId = c.planRepo.activePlan?.id;
    if (planId == null) return;
    final specs = await c.planRepo.larkSpecsForPlan(planId);
    await c.lark.syncUpcomingDays(days: specs);
  }

  Future<void> _openWorkout(BuildContext context) async {
    await Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const WorkoutPage(),
    ));
    if (mounted) _refresh();
  }
}
