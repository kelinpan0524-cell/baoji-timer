import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app.dart';
import '../engine/engine.dart';
import '../presets/baoji_plan.dart';
import '../presets/exercise_library.dart';
import '../services/ai_service.dart';
import '../services/plan_actions.dart';
import '../services/plan_repository.dart';
import 'exercise_library_page.dart';
import 'plan_editor_page.dart';
import 'plan_preview_sheet.dart';
import 'schedule_views.dart';
import 'theme.dart';
import 'widgets/common.dart';

/// 计划页：多计划管理（查看/切换/重命名/复制/删除）+ 周视图 + AI 导入。
/// 点击某个训练日进入编辑器，可人工调整动作与组数次数。
class PlanPage extends StatefulWidget {
  const PlanPage({super.key});

  @override
  State<PlanPage> createState() => _PlanPageState();
}

class _PlanPageState extends State<PlanPage> {
  bool _loading = true;
  List<Plan> _plans = [];
  Plan? _view; // 正在查看的计划（可为未启用计划）
  int? _trainableN; // 查看计划里「有动作」的模板日数（循环排程警示用）

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh({Plan? view}) async {
    final c = app(context);
    await c.planRepo.reload(includeAll: true);
    _plans = c.planRepo.allPlansCache;
    _view = view ??
        (_view == null
            ? c.planRepo.activePlan
            : _plans.where((p) => p.id == _view!.id).firstOrNull ??
                c.planRepo.activePlan);

    final vid = _view?.id;
    if (vid != null && _view!.isCycle) {
      final n = await c.planRepo.trainableDayCount(vid);
      if (!mounted) return;
      _trainableN = n;
    } else {
      _trainableN = null;
    }

    if (!mounted) return;
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_plans.isEmpty) {
      return _emptyState();
    }
    final active = app(context).planRepo.activePlan;
    final viewingActive = _view?.id == active?.id;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Row(
          children: [
            // 计划切换器
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => _showPlanSwitcher(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          '${_view?.name ?? '无计划'}'
                          '（${viewingActive ? '使用中' : '未启用'}）',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.expand_more,
                        size: 20,
                        color: AppTheme.textDim,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'activate') {
                  _activateViewed();
                } else if (v == 'rename') {
                  _renamePlan();
                } else if (v == 'duplicate') {
                  _duplicatePlan();
                } else if (v == 'delete') {
                  _deletePlan();
                }
              },
              itemBuilder: (_) => [
                if (!viewingActive)
                  const PopupMenuItem(
                    value: 'activate',
                    child: Row(
                      children: [
                        Icon(Icons.play_circle_outline, size: 18),
                        SizedBox(width: 8),
                        Text('设为使用中'),
                      ],
                    ),
                  ),
                const PopupMenuItem(
                  value: 'rename',
                  child: Row(
                    children: [
                      Icon(Icons.edit_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('重命名'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'duplicate',
                  child: Row(
                    children: [
                      Icon(Icons.copy_all_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('复制一份'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(
                        Icons.delete_outline,
                        size: 18,
                        color: AppTheme.danger,
                      ),
                      SizedBox(width: 8),
                      Text('删除计划', style: TextStyle(color: AppTheme.danger)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        Text(
          _sourceLabel(_view?.source),
          style: const TextStyle(color: AppTheme.textDim, fontSize: 12),
        ),
        if (!viewingActive) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.warn.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              '此计划未启用：编辑不会影响今天的训练，设为使用中后才生效。',
              style: TextStyle(color: AppTheme.warn, fontSize: 13),
            ),
          ),
        ],
        const SizedBox(height: 8),
        // 排程模式 + 模板日编辑（日期化的排程视图见下方 ScheduleViews）
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _showPatternSheet,
                icon: const Icon(Icons.event_repeat, size: 18),
                label: Text(
                  _view?.isCycle == true
                      ? '循环：练${_view!.cycleTrain}休${_view!.cycleRest}'
                      : '按星期排程',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _showTemplateDaysSheet,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('编辑模板日',
                    overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
        ),
        // 循环连练天数小于有动作的训练日数 = 多出的模板日永远排不上（静默搁浅）
        if (_view?.isCycle == true &&
            _trainableN != null &&
            _trainableN! > _view!.cycleTrain)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: InkWell(
              onTap: _showPatternSheet,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                child: Text(
                  '⚠ 连练${_view!.cycleTrain}天 < 计划的 $_trainableN 个训练日：'
                  '多出的训练日永远排不上，点此把连练改为 $_trainableN',
                  style: const TextStyle(color: AppTheme.warn, fontSize: 12),
                ),
              ),
            ),
          ),
        const SizedBox(height: 10),
        // 日期化排程：3日/周/月视图 + 拖拉改期（手动改动写覆盖行）
        if (_view != null)
          ScheduleViews(
            plan: _view!,
            onChanged: _onScheduleChanged,
          ),
        const SizedBox(height: 8),
        // 添加计划三入口：模板（推荐）/ AI / 空白
        FilledButton.tonalIcon(
          onPressed: () => _showTemplatePicker(),
          icon: const Icon(Icons.library_books, size: 18),
          label: const Text('从模板添加（三分化 / 五分化 / 功能性 / 居家）'),
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.cardHi,
            foregroundColor: AppTheme.text,
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _showAiImport(),
                icon: const Icon(Icons.auto_awesome, size: 16),
                label: const Text('AI 拆解导入'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _createBlankPlan(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('新建空白'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ExerciseLibraryPage()),
            ),
            icon: const Icon(Icons.fitness_center, size: 16),
            label: const Text('浏览动作库（肌群 · 居家/健身房）'),
          ),
        ),
      ],
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            '还没有计划',
            style: TextStyle(fontSize: 18, color: AppTheme.textDim),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final container = app(context);
              await container.planRepo.installBaojiPlan();
              await syncActivePlanToLark(container);
              if (mounted) {
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('薄肌计划已安装'),
                    backgroundColor: AppTheme.cardHi,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                await _refresh();
              }
            },
            child: const Text('一键安装薄肌计划'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => _showTemplatePicker(),
            child: const Text('从模板添加计划'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => _showAiImport(),
            child: const Text('粘贴文本 · AI 拆解'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => _createBlankPlan(),
            child: const Text('新建空白计划'),
          ),
        ],
      ),
    );
  }

  String _sourceLabel(String? source) {
    switch (source) {
      case 'preset':
        return '内置计划 · 点任意训练日可人工调整';
      case 'ai':
        return 'AI 拆解计划 · 建议逐日校对后使用';
      case 'copy':
        return '复制计划';
      default:
        return '自定义计划';
    }
  }

  // ================= 排程模式与模板日 =================

  /// 排程视图改动后：刷新缓存并重同步飞书日历。
  Future<void> _onScheduleChanged() async {
    final container = app(context);
    await _refresh();
    await syncActivePlanToLark(container);
  }

  /// 切换排程模式：按星期（固定周几）/ 循环（练 N 休 M，如"隔两天休息一天"）。
  /// 手动改期过的覆盖行保留，不受模式切换影响。
  Future<void> _showPatternSheet() async {
    final plan = _view;
    if (plan == null || plan.id == null) return;
    final trainableN = await app(context).planRepo.trainableDayCount(plan.id!);
    if (!mounted) return;
    bool cycle = plan.isCycle;
    // 首次设置连练天数：默认对齐计划的训练日数，避免 3 天计划被默认的 2 静默搁浅
    int train = plan.cycleTrain > 0
        ? plan.cycleTrain
        : (trainableN > 0 ? trainableN.clamp(1, 7).toInt() : 2);
    int rest = plan.cycleRest > 0 ? plan.cycleRest : 1;
    DateTime start = plan.patternStart.isNotEmpty
        ? parseDate(plan.patternStart)
        : DateTime.now();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('排程方式',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              const Text('改的是"没有手动调整过的日子"怎么排；已手动改期的日子保持不变。',
                  style: TextStyle(color: AppTheme.textDim, fontSize: 12)),
              const SizedBox(height: 12),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('按星期')),
                  ButtonSegment(value: true, label: Text('循环练休')),
                ],
                selected: {cycle},
                onSelectionChanged: (s) => setSheet(() => cycle = s.first),
                showSelectedIcon: false,
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.resolveWith((st) =>
                      st.contains(WidgetState.selected)
                          ? AppTheme.primary
                          : AppTheme.cardHi),
                  foregroundColor: WidgetStateProperty.resolveWith((st) =>
                      st.contains(WidgetState.selected)
                          ? const Color(0xFF06220F)
                          : AppTheme.textDim),
                  side: const WidgetStatePropertyAll(
                      BorderSide(color: Colors.transparent)),
                ),
              ),
              const SizedBox(height: 14),
              if (cycle) ...[
                _numStepper('连练天数', train, 1, 7, setSheet, (v) => train = v),
                _numStepper('休息天数', rest, 1, 7, setSheet, (v) => rest = v),
                Text('循环示例：练 $train 休 $rest —— 从起始日开始每 ${train + rest} 天一轮。',
                    style:
                        const TextStyle(color: AppTheme.textDim, fontSize: 12)),
                if (trainableN > 1 && train < trainableN)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '⚠ 计划有 $trainableN 个有动作的训练日，连练 $train 会让 '
                      '${trainableN - train} 个训练日永远排不上（建议连练 $trainableN）',
                      style:
                          const TextStyle(color: AppTheme.warn, fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('起始日  ',
                        style: TextStyle(color: AppTheme.textDim)),
                    TextButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: start,
                          firstDate:
                              DateTime.now().subtract(const Duration(days: 365)),
                          lastDate:
                              DateTime.now().add(const Duration(days: 365)),
                        );
                        if (picked != null) setSheet(() => start = picked);
                      },
                      child: Text('${start.year}/${start.month}/${start.day}'),
                    ),
                  ],
                ),
              ] else
                const Text(
                    '按星期模式：训练跟固定周几走（编辑模板日里改）。日期视图里也可以临时把某天挪走。',
                    style: TextStyle(color: AppTheme.textDim, fontSize: 12)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('保存'),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    await app(context).planRepo.updateSchedulePattern(
          planId: plan.id!,
          pattern: cycle ? 'cycle' : 'weekly',
          // 起始日始终存所选值：之前 patternStart 已存在时会丢弃新选的日期
          patternStart: cycle ? fmtDate(start) : plan.patternStart,
          cycleTrain: train,
          cycleRest: rest,
        );
    await _refresh();
    if (mounted) {
      final stranded = cycle && trainableN > 1 && train < trainableN;
      toast(context,
          cycle ? (stranded ? '已保存，但连练 $train < $trainableN 个训练日，多出的训练日排不上' : '已切为循环练$train休$rest') : '已切为按星期排程');
    }
  }

  Widget _numStepper(String label, int value, int min, int max,
      void Function(void Function()) setSheet, ValueChanged<int> on) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        IconButton(
          onPressed: value - 1 < min ? null : () => setSheet(() => on(value - 1)),
          icon: const Icon(Icons.remove_circle_outline),
        ),
        SizedBox(
            width: 44,
            child: Text('$value', textAlign: TextAlign.center)),
        IconButton(
          onPressed: value + 1 > max ? null : () => setSheet(() => on(value + 1)),
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }

  /// 模板日编辑：星期是"模板槽位"，具体哪天练由排程（星期/循环/手动改期）决定。
  Future<void> _showTemplateDaysSheet() async {
    final plan = _view;
    if (plan == null || plan.id == null) return;
    final c = app(context);
    final days = await c.db.planDays(plan.id!);
    final exMap = await c.db.daysExercisesMap(days.map((d) => d.id!).toList());
    if (!mounted) return;
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
            const Text('模板日',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text(
                '这里是计划的内容骨架；具体哪天练哪个由排程决定（按星期/循环/手动拖动）。',
                style: TextStyle(color: AppTheme.textDim, fontSize: 12)),
            const SizedBox(height: 8),
            for (final d in days)
              ListTile(
                leading: const Icon(Icons.fitness_center,
                    color: AppTheme.primary),
                title: Text(d.title),
                subtitle: Text(
                    '周${'一二三四五六日'[d.weekday - 1]} · ${(exMap[d.id] ?? const <PlanExercise>[]).length} 个动作',
                    style: const TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () async {
                  Navigator.pop(ctx);
                  if (!mounted) return;
                  final changed = await Navigator.of(context).push(
                    MaterialPageRoute<bool>(
                        builder: (_) => PlanEditorPage(day: d)),
                  );
                  if (changed == true && mounted) {
                    await _refresh();
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  // ================= 计划级操作 =================

  Future<void> _showPlanSwitcher() async {
    final c = app(context);
    final dayCounts = await c.db.planDayCounts();
    final exCounts = await c.db.planExerciseCounts();
    final plans = await c.db.allPlans();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          children: [
            const Text(
              '切换计划',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              '点计划查看/编辑；「使用中」的计划决定每天的训练安排。',
              style: TextStyle(color: AppTheme.textDim, fontSize: 12),
            ),
            const SizedBox(height: 8),
            for (final p in plans)
              ListTile(
                leading: p.id == c.planRepo.activePlan?.id
                    ? const Icon(Icons.check_circle, color: AppTheme.primary)
                    : const Icon(
                        Icons.radio_button_unchecked,
                        color: AppTheme.textDim,
                      ),
                title: Text(p.name),
                subtitle: Text(
                  '${dayCounts[p.id] ?? 0} 个训练日 · ${exCounts[p.id] ?? 0} 个动作',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: p.id == _view?.id
                    ? const Text(
                        '查看中',
                        style: TextStyle(color: AppTheme.accent, fontSize: 12),
                      )
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _view = p);
                  _refresh(view: p);
                },
              ),
          ],
        ),
      ),
    );
  }

  /// 「撤旧 + 写新」唯一入口：更换使用中计划的全部路径（切换/安装/保存）都走这里。
  /// 先记下旧使用中计划的训练日 → 执行 action（action 内须完成切换并 reload，
  /// 使 activePlan 已指向新计划）→ 撤下旧计划的日历日程 → 把新使用中计划写上日历。
  /// 撤旧/写新由 plan_actions 统一实现（与 AI 教练排计划共用，勿另写一份）。
  Future<T> _switchActivePlanAndSync<T>(
    AppContainer c,
    Future<T> Function() action,
  ) async {
    final oldId = c.planRepo.activePlan?.id;
    final oldDayIds = oldId == null
        ? <int>[]
        : (await c.db.planDays(oldId)).map((d) => d.id!).toList();
    final result = await action();
    unawaited(removePlanDayEvents(c, oldDayIds));
    await syncActivePlanToLark(c);
    return result;
  }

  Future<void> _activateViewed() async {
    final c = app(context);
    if (_view == null) return;
    final view = _view!;
    await _switchActivePlanAndSync(c, () async {
      await c.db.setActivePlan(view.id!);
      await c.planRepo.reload(includeAll: true);
    });
    if (mounted) {
      toast(context, '已设为使用中「${view.name}」');
      await _refresh(view: view);
    }
  }

  Future<void> _renamePlan() async {
    if (_view == null) return;
    final ctrl = TextEditingController(text: _view!.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: const Text('重命名计划'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消', style: TextStyle(color: AppTheme.textDim)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('保存', style: TextStyle(color: AppTheme.primary)),
          ),
        ],
      ),
    );
    if (name == null || !mounted || name.isEmpty) return;
    final c = app(context);
    await c.db.renamePlan(_view!.id!, name);
    await _refresh();
    if (mounted) toast(context, '已重命名');
  }

  Future<void> _duplicatePlan() async {
    if (_view == null) return;
    final c = app(context);
    final newId = await c.planRepo.duplicatePlan(
      _view!.id!,
      '${_view!.name}（副本）',
    );
    final plans = await c.db.allPlans();
    final copy = plans.where((p) => p.id == newId).firstOrNull;
    await _refresh(view: copy);
    if (mounted) toast(context, '已复制为副本，可独立编辑不影响原计划');
  }

  Future<void> _deletePlan() async {
    if (_view == null) return;
    final planId = _view!.id!;
    final planName = _view!.name;
    final ok = await confirmDialog(
      context,
      '删除「$planName」？',
      '计划的全部训练日和动作将被删除；历史训练记录保留。此操作无法撤销。',
      okLabel: '删除',
    );
    if (!ok || !mounted) return;
    final c = app(context);
    final dayIds = (await c.db.planDays(planId)).map((d) => d.id!).toList();
    await c.planRepo.deletePlanAndFixActive(planId);
    // 撤下该计划在日历上的未来日程（尽力而为）
    unawaited(removePlanDayEvents(c, dayIds));
    _view = null;
    await _refresh();
    // 删除后自动顶上的新使用中计划，把它的日程补写上日历
    if (c.planRepo.activePlan != null) {
      await syncActivePlanToLark(c);
    }
    if (mounted) toast(context, '已删除');
  }

  Future<void> _createBlankPlan() async {
    final ctrl = TextEditingController(text: '我的计划');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: const Text('新建空白计划'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '创建后可自行编排每周训练日与动作。',
              style: TextStyle(color: AppTheme.textDim, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(controller: ctrl, autofocus: true),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消', style: TextStyle(color: AppTheme.textDim)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('创建', style: TextStyle(color: AppTheme.primary)),
          ),
        ],
      ),
    );
    if (name == null || !mounted || name.isEmpty) return;
    final c = app(context);
    final plan = await c.db.insertPlan(
      Plan(
        name: name,
        source: 'manual',
        createdAt: fmtDate(DateTime.now()),
        isActive: 0,
      ),
    );
    for (var wd = 1; wd <= 7; wd++) {
      await c.db.insertPlanDay(
        PlanDay(planId: plan.id!, weekday: wd, title: '训练日'),
      );
    }
    final created =
        (await c.db.allPlans()).where((p) => p.id == plan.id).firstOrNull;
    await _refresh(view: created);
    if (mounted) toast(context, '已创建，点击任意一天开始编排');
  }

  // ================= 模板选择 =================

  Future<void> _showTemplatePicker() async {
    final c = app(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          children: [
            const Text(
              '选择计划模板',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              '安装后可逐日修改动作与组数；同模板重复安装不会重复建。',
              style: TextStyle(color: AppTheme.textDim, fontSize: 12),
            ),
            const SizedBox(height: 12),
            _templateCard(
              ctx,
              name: kBaojiPlanName,
              intro: '每周三练（推/拉/腿），四大项渐进超负荷，为本 App 量身设计',
              note: '适合按邵艾伦薄肌计划训练的人',
              install: () async {
                final plan = await _switchActivePlanAndSync(
                  c,
                  () => c.planRepo.installBaojiPlan(),
                );
                return '已安装并设为使用中「${plan.name}」，可在编辑器微调';
              },
            ),
            for (final t in kPlanTemplates)
              _templateCard(
                ctx,
                name: t.name,
                intro: t.intro,
                note: t.note,
                install: () async {
                  final (plan, created) = await _switchActivePlanAndSync(
                    c,
                    () => c.planRepo.installTemplate(t),
                  );
                  return created
                      ? '已安装并设为使用中「${plan.name}」，可在编辑器微调'
                      : '已存在同名模板计划，已设为使用中（未重复安装）';
                },
              ),
          ],
        ),
      ),
    );
    if (mounted) {
      await _refresh(view: null);
    }
  }

  Widget _templateCard(
    BuildContext ctx, {
    required String name,
    required String intro,
    required String note,
    required Future<String> Function() install, // 返回 SnackBar 文案
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          final navigator = Navigator.of(ctx);
          final messenger = ScaffoldMessenger.of(ctx);
          final message = await install();
          navigator.pop();
          messenger.showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: AppTheme.cardHi,
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.add_circle_outline,
                    size: 20,
                    color: AppTheme.primary,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(intro, style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 4),
              Text(
                '适合：$note',
                style: const TextStyle(color: AppTheme.textDim, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ================= AI 导入 =================

  Future<void> _showAiImport() async {
    final c = app(context);
    final ctrl = TextEditingController();
    bool genMode = false; // false=原文导入 true=描述生成
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AI 计划',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('原文导入')),
                    ButtonSegment(value: true, label: Text('描述生成')),
                  ],
                  selected: {genMode},
                  onSelectionChanged: (s) => setSheet(() => genMode = s.first),
                  showSelectedIcon: false,
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith(
                      (st) => st.contains(WidgetState.selected)
                          ? AppTheme.primary
                          : AppTheme.cardHi,
                    ),
                    foregroundColor: WidgetStateProperty.resolveWith(
                      (st) => st.contains(WidgetState.selected)
                          ? const Color(0xFF06220F)
                          : AppTheme.textDim,
                    ),
                    side: const WidgetStatePropertyAll(
                      BorderSide(color: Colors.transparent),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  genMode
                      ? '用大白话描述你想要什么，AI 直接设计计划。例："每周四练，练背、胸、腿，增肌，家里只有哑铃"。'
                      : '粘贴现成计划原文（如"周一 卧推 3×5-8 …"），AI 逐字转成结构化计划。',
                  style: const TextStyle(color: AppTheme.textDim, fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl,
                  maxLines: genMode ? 4 : 8,
                  decoration: InputDecoration(
                    hintText: genMode ? '描述你的目标、频率、部位、器械…' : '在此粘贴计划原文…',
                  ),
                ),
                const SizedBox(height: 12),
                if (!c.settings.aiConfigured)
                  const Text(
                    '尚未配置 AI 接口：请先到 设置 → AI 配置 填写。',
                    style: TextStyle(color: AppTheme.warn),
                  ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: ctrl.text.trim().isEmpty
                      ? null
                      : () => Navigator.pop(ctx, true),
                  child: Text(genMode ? '生成计划' : '开始拆解'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    // 无 Key 不再前置拦截（评审修复）：AI 服务层会给出可读错误，
    // 走下方「AI 不可用回落本地」路径，预览页明示本地模式与失败原因。
    final nav = Navigator.of(context, rootNavigator: true);
    showDialog(
      context: context,
      barrierDismissible: false, // 可手动关闭，后台请求继续
      builder: (_) => PopScope(
        canPop: true,
        child: Center(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 14),
                  const Text('正在让 AI 处理计划…', style: TextStyle(fontSize: 15)),
                  const SizedBox(height: 4),
                  Text(
                    '通常 10-30 秒，可关闭稍等',
                    style: TextStyle(color: AppTheme.textDim, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    List<AiDaySpec>? specs;
    var localMode = false;
    var aiError = '';
    try {
      // 未配置 Key 由服务层抛可读错误（AiService.parsePlan/designPlanFromDescription
      // 的 aiConfigured 检查），统一进回落路径，避免此处维护第二份拦截逻辑。
      specs = genMode
          ? await c.ai.designPlanFromDescription(ctrl.text.trim())
          : await c.ai.parsePlan(ctrl.text.trim());
    } on AiException catch (e) {
      aiError = e.message;
    } catch (e) {
      aiError = 'AI 请求失败，请重试或换模型（$e）';
    }
    if (nav.canPop()) nav.pop();

    // 调研条目 13：AI 不可用（无 Key/无网/失败）→ 自动回落 engine 本地
    // 规则生成，预览页明示「本地模式」；描述里实在提不出可用动作才报错。
    if (specs == null) {
      final local = localPlanFromDescription(ctrl.text.trim());
      if (local.isEmpty) {
        if (mounted) {
          toast(context, aiError.isEmpty ? '本地生成失败，请重试' : aiError);
        }
        return;
      }
      specs = [
        for (final d in local)
          AiDaySpec(
            d.weekday,
            d.title,
            [
              for (final ex in d.exercises)
                AiExerciseSpec(
                  name: ex.name,
                  rawName: ex.name,
                  sets: ex.sets,
                  repsMin: ex.repsMin,
                  repsMax: ex.repsMax,
                  restSec: ex.restSec,
                  kind: ex.kind,
                  mainMuscle: ex.mainMuscle,
                ),
            ],
          ),
      ];
      localMode = true;
    }
    if (!mounted) return;

    // 调研条目 12：无论哪种来源都先进预览页逐动作确认，确认后才落库。
    // 回落时带上 AI 失败原因摘要（评审修复）：自配 API 的用户能看出
    // 是 Key 错还是网络错，而不是只见笼统的「AI 不可用」。
    final picked = await showPlanPreviewSheet(
      context,
      specs,
      localMode: localMode,
      aiError: localMode ? aiError : '',
    );
    if (picked == null || !mounted) return;
    final (name, confirmed) = picked;
    final plan = await _switchActivePlanAndSync(
      c,
      () => c.planRepo.saveAiPlan(
        // 评审修复：本地模式空名回退「本地计划」而非「AI 生成/AI 计划」，
        // 名字不误导产物来源。
        name: name.isEmpty
            ? (localMode
                ? '本地计划 ${fmtDate(DateTime.now())}'
                : (genMode
                    ? 'AI 生成 ${fmtDate(DateTime.now())}'
                    : 'AI 计划 ${fmtDate(DateTime.now())}'))
            : name,
        specs: confirmed,
        metaMap: c.ai.metaMap(),
      ),
    );
    await _refresh();
    if (!mounted) return;
    toast(
      context,
      localMode
          ? '本地模式已生成「${plan.name}」（AI 不可用），请逐日校对'
          : '已保存并设为使用中「${plan.name}」，点任意一天可微调',
    );
  }

  /// 生成结果预览与逐动作候选确认已抽到 plan_preview_sheet.dart
  /// （与 AI 教练「排计划模式」共用同一确认纪律）。

  // ================= 飞书同步 =================
  // 撤旧日程/写新日程由 plan_actions.dart 统一实现（勿在页面再留副本）。
}
