import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app.dart';
import '../engine/engine.dart';
import '../services/ai_service.dart';
import '../services/plan_repository.dart';
import 'plan_editor_page.dart';
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
  List<PlanDay> _days = [];
  Map<int, List<PlanExercise>> _exByDay = {};

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
    if (_view == null) {
      _days = [];
      _exByDay = {};
    } else {
      _days = await c.db.planDays(_view!.id!);
      _exByDay = await c.db.daysExercisesMap(_days.map((d) => d.id!).toList());
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
                              fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                      ),
                      const Icon(Icons.expand_more,
                          size: 20, color: AppTheme.textDim),
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
                      child: Row(children: [
                        Icon(Icons.play_circle_outline, size: 18),
                        SizedBox(width: 8),
                        Text('设为使用中'),
                      ])),
                const PopupMenuItem(
                    value: 'rename',
                    child: Row(children: [
                      Icon(Icons.edit_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('重命名'),
                    ])),
                const PopupMenuItem(
                    value: 'duplicate',
                    child: Row(children: [
                      Icon(Icons.copy_all_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('复制一份'),
                    ])),
                const PopupMenuItem(
                    value: 'delete',
                    child: Row(children: [
                      Icon(Icons.delete_outline,
                          size: 18, color: AppTheme.danger),
                      SizedBox(width: 8),
                      Text('删除计划', style: TextStyle(color: AppTheme.danger)),
                    ])),
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
                style: TextStyle(color: AppTheme.warn, fontSize: 13)),
          ),
        ],
        const SizedBox(height: 8),
        ...List.generate(7, (i) {
          final wd = i + 1;
          final day = _days.where((d) => d.weekday == wd).firstOrNull;
          final exs = day == null
              ? const <PlanExercise>[]
              : (_exByDay[day.id] ?? const <PlanExercise>[]);
          final isToday = DateTime.now().weekday == wd;
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 5),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: day == null
                  ? null
                  : () async {
                      final changed = await Navigator.of(context).push(
                          MaterialPageRoute<bool>(
                              builder: (_) => PlanEditorPage(day: day)));
                      // 有修改才刷新；只同步「使用中」的计划（见 _syncLarkDays）
                      if (changed != true) return;
                      if (!context.mounted) return;
                      final container = app(context);
                      await _refresh();
                      await _syncLarkDays(container);
                    },
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    SizedBox(
                      width: 44,
                      child: Text('周${'一二三四五六日'[i]}',
                          style: TextStyle(
                              color: isToday
                                  ? AppTheme.primary
                                  : AppTheme.textDim,
                              fontWeight: FontWeight.w700)),
                    ),
                    Expanded(
                      child: day == null
                          ? const Text('休息',
                              style: TextStyle(color: AppTheme.textDim))
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(day.title,
                                          style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600)),
                                    ),
                                    Text('${exs.length} 个动作',
                                        style: const TextStyle(
                                            color: AppTheme.textDim,
                                            fontSize: 12)),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                if (exs.isEmpty)
                                  const Text('点此编排动作',
                                      style: TextStyle(
                                          color: AppTheme.accent,
                                          fontSize: 13))
                                else
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 2,
                                    children: [
                                      for (var k = 0; k < exs.length; k++)
                                        Text(
                                          k == exs.length - 1
                                              ? exs[k].name
                                              : '${exs[k].name} ·',
                                          style: const TextStyle(
                                              color: AppTheme.textDim,
                                              fontSize: 13),
                                        ),
                                    ],
                                  ),
                              ],
                            ),
                    ),
                    const Icon(Icons.chevron_right,
                        size: 18, color: AppTheme.textDim),
                  ],
                ),
              ),
            ),
          );
        }),
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
                label: const Text('新建空白计划'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('还没有计划',
              style: TextStyle(fontSize: 18, color: AppTheme.textDim)),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final container = app(context);
              await container.planRepo.installBaojiPlan();
              await _syncLarkDays(container);
              if (mounted) {
                messenger.showSnackBar(const SnackBar(
                    content: Text('薄肌计划已安装'),
                    backgroundColor: AppTheme.cardHi,
                    behavior: SnackBarBehavior.floating));
                await _refresh();
              }
            },
            child: const Text('一键安装薄肌计划'),
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
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          children: [
            const Text('切换计划',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('点计划查看/编辑；「使用中」的计划决定每天的训练安排。',
                style: TextStyle(color: AppTheme.textDim, fontSize: 12)),
            const SizedBox(height: 8),
            for (final p in plans)
              ListTile(
                leading: p.id == c.planRepo.activePlan?.id
                    ? const Icon(Icons.check_circle, color: AppTheme.primary)
                    : const Icon(Icons.radio_button_unchecked,
                        color: AppTheme.textDim),
                title: Text(p.name),
                subtitle: Text(
                    '${dayCounts[p.id] ?? 0} 个训练日 · ${exCounts[p.id] ?? 0} 个动作',
                    style: const TextStyle(fontSize: 12)),
                trailing: p.id == _view?.id
                    ? const Text('查看中',
                        style: TextStyle(color: AppTheme.accent, fontSize: 12))
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

  Future<void> _activateViewed() async {
    final c = app(context);
    if (_view == null) return;
    // 原启用计划的未来日程从日历撤下，新计划日程写入
    final oldDays = await c.db.planDays(c.planRepo.activePlan?.id ?? 0);
    await c.db.setActivePlan(_view!.id!);
    await c.planRepo.reload(includeAll: true);
    unawaited(_removeOldEvents(oldDays.map((d) => d.id!).toList()));
    await _syncLarkDays(c);
    if (mounted) {
      toast(context, '已设为使用中「${_view!.name}」');
      await _refresh(view: _view);
    }
  }

  Future<void> _removeOldEvents(List<int> dayIds) async {
    final c = app(context);
    for (final id in dayIds) {
      await c.lark.removePlanDayEvent(id);
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
              child:
                  const Text('取消', style: TextStyle(color: AppTheme.textDim))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child:
                  const Text('保存', style: TextStyle(color: AppTheme.primary))),
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
    final newId =
        await c.planRepo.duplicatePlan(_view!.id!, '${_view!.name}（副本）');
    final plans = await c.db.allPlans();
    final copy = plans.where((p) => p.id == newId).firstOrNull;
    await _refresh(view: copy);
    if (mounted) toast(context, '已复制为副本，可独立编辑不影响原计划');
  }

  Future<void> _deletePlan() async {
    if (_view == null) return;
    final planId = _view!.id!;
    final planName = _view!.name;
    final ok = await confirmDialog(context, '删除「$planName」？',
        '计划的全部训练日和动作将被删除；历史训练记录保留。此操作无法撤销。',
        okLabel: '删除');
    if (!ok || !mounted) return;
    final c = app(context);
    final dayIds = (await c.db.planDays(planId)).map((d) => d.id!).toList();
    await c.planRepo.deletePlanAndFixActive(planId);
    // 撤下该计划在日历上的未来日程（尽力而为）
    unawaited(_removeOldEvents(dayIds));
    _view = null;
    await _refresh();
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
            const Text('创建后可自行编排每周训练日与动作。',
                style: TextStyle(color: AppTheme.textDim, fontSize: 13)),
            const SizedBox(height: 12),
            TextField(controller: ctrl, autofocus: true),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:
                  const Text('取消', style: TextStyle(color: AppTheme.textDim))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child:
                  const Text('创建', style: TextStyle(color: AppTheme.primary))),
        ],
      ),
    );
    if (name == null || !mounted || name.isEmpty) return;
    final c = app(context);
    final plan = await c.db.insertPlan(Plan(
      name: name,
      source: 'manual',
      createdAt: fmtDate(DateTime.now()),
      isActive: 0,
    ));
    for (var wd = 1; wd <= 7; wd++) {
      await c.db
          .insertPlanDay(PlanDay(planId: plan.id!, weekday: wd, title: '训练日'));
    }
    final created =
        (await c.db.allPlans()).where((p) => p.id == plan.id).firstOrNull;
    await _refresh(view: created);
    if (mounted) toast(context, '已创建，点击任意一天开始编排');
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
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('AI 计划',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
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
                          : AppTheme.cardHi),
                  foregroundColor: WidgetStateProperty.resolveWith(
                      (st) => st.contains(WidgetState.selected)
                          ? const Color(0xFF06220F)
                          : AppTheme.textDim),
                  side: const WidgetStatePropertyAll(
                      BorderSide(color: Colors.transparent)),
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
                    hintText: genMode
                        ? '描述你的目标、频率、部位、器械…'
                        : '在此粘贴计划原文…'),
              ),
              const SizedBox(height: 12),
              if (!c.settings.aiConfigured)
                const Text('尚未配置 AI 接口：请先到 设置 → AI 配置 填写。',
                    style: TextStyle(color: AppTheme.warn)),
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
    );
    if (ok != true || !mounted) return;
    if (!c.settings.aiConfigured) {
      toast(context, '请先在设置里配置 AI 接口');
      return;
    }
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
                  const Text('正在让 AI 处理计划…',
                      style: TextStyle(fontSize: 15)),
                  const SizedBox(height: 4),
                  Text('通常 10-30 秒，可关闭稍等',
                      style: TextStyle(
                          color: AppTheme.textDim, fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    try {
      final specs = genMode
          ? await c.ai.designPlanFromDescription(ctrl.text.trim())
          : await c.ai.parsePlan(ctrl.text.trim());
      if (nav.canPop()) nav.pop();

      if (genMode) {
        // 生成模式：先预览，用户同意才保存
        if (!mounted) return;
        final name = await _showPlanPreview(specs);
        if (name == null || !mounted) return;
        final plan = await c.planRepo.saveAiPlan(
          name: name.isEmpty ? 'AI 生成 ${fmtDate(DateTime.now())}' : name,
          specs: specs,
          metaMap: c.ai.metaMap(),
        );
        await _refresh();
        await _syncLarkDays(c);
        if (!mounted) return;
        toast(context, '已保存并设为使用中「${plan.name}」，点任意一天可微调');
      } else {
        // 原文导入：逐字转成计划直接保存
        final plan = await c.planRepo.saveAiPlan(
          name: 'AI 计划 ${fmtDate(DateTime.now())}',
          specs: specs,
          metaMap: c.ai.metaMap(),
        );
        await _refresh();
        await _syncLarkDays(c);
        if (!mounted) return;
        toast(context,
            '拆解完成：${specs.length} 个训练日，已设为使用中「${plan.name}」');
      }
    } on AiException catch (e) {
      if (nav.canPop()) nav.pop();
      if (mounted) toast(context, e.message);
    } catch (e) {
      if (nav.canPop()) nav.pop();
      if (mounted) toast(context, 'AI 请求失败，请重试或换模型（$e）');
    }
  }

  /// 生成结果预览：用户看完点「保存为计划」才落库。返回计划名（放弃返回 null）。
  Future<String?> _showPlanPreview(List<AiDaySpec> specs) async {
    final nameCtrl =
        TextEditingController(text: 'AI 生成 ${fmtDate(DateTime.now())}');
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      isDismissible: false, // 90 秒的成果不能被随手拖没
      enableDrag: false,
      backgroundColor: AppTheme.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.82,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('计划预览（${specs.length} 个训练日）',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: '计划名'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  children: [
                    for (final spec in specs)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              '周${'一二三四五六日'[spec.weekday - 1]} · ${spec.title}',
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.primary)),
                          const SizedBox(height: 4),
                          for (final ex in spec.exercises)
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 2),
                              child: Text(
                                  '· ${ex.name}  ${ex.sets}×${ex.repsMin}-${ex.repsMax} · 休 ${ex.restSec ?? '-'}s',
                                  style: const TextStyle(fontSize: 14)),
                            ),
                          const SizedBox(height: 10),
                        ],
                      ),
                  ],
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final ok = await confirmDialog(
                                ctx, '丢弃刚生成的计划？',
                                '放弃后需要重新让 AI 生成一遍。');
                            if (ok && ctx.mounted) Navigator.pop(ctx);
                          },
                          child: const Text('放弃'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () =>
                              Navigator.pop(ctx, nameCtrl.text.trim()),
                          child: const Text('保存为计划'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ================= 飞书同步 =================

  /// 「使用中」计划的未来 14 天训练日写入飞书日历（编辑/切换/导入后调用）。
  /// 只同步使用中的计划——编辑未启用计划不应把它的日程写上日历。
  /// 同步前清理：有日历记录但已无动作的日子（用户清空了那天）先撤事件。
  Future<void> _syncLarkDays(AppContainer c, {int? planId}) async {
    final target = planId ?? c.planRepo.activePlan?.id;
    if (target == null) return;
    final specs = await c.planRepo.larkSpecsForPlan(target);
    final withEx = specs.map((s) => s.planDayId).toSet();
    for (final sync in await c.db.larkSyncRefsForPlan(target)) {
      if (!withEx.contains(sync.refId)) {
        await c.lark.removePlanDayEvent(sync.refId);
      }
    }
    await c.lark.syncUpcomingDays(days: specs);
  }
}
