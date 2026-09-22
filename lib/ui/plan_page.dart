import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app.dart';
import '../engine/engine.dart';
import '../services/ai_service.dart';
import '../services/lark_service.dart';
import 'theme.dart';
import 'widgets/common.dart';

/// 计划页：周日视图 + 计划切换 + AI 导入。
class PlanPage extends StatefulWidget {
  const PlanPage({super.key});

  @override
  State<PlanPage> createState() => _PlanPageState();
}

class _PlanPageState extends State<PlanPage> {
  bool _loading = true;
  int? _selectedDayId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    await app(context).planRepo.reload();
    if (!mounted) return;
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final c = app(context);
    final repo = c.planRepo;
    if (repo.activePlan == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('还没有计划',
                style: TextStyle(fontSize: 18, color: AppTheme.textDim)),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => _installBaoji(),
              child: const Text('一键安装薄肌计划'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => _showAiImport(),
              child: const Text('粘贴文本 · AI 拆解'),
            ),
          ],
        ),
      );
    }
    final days = repo.days;
    final selected =
        _selectedDayId == null ? null : days.where((d) => d.id == _selectedDayId).firstOrNull;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(repo.activePlan!.name,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            TextButton(
                onPressed: () => _showAiImport(),
                child: const Text('AI 导入新计划')),
          ],
        ),
        const SizedBox(height: 8),
        ...List.generate(7, (i) {
          final wd = i + 1;
          final day = days.where((d) => d.weekday == wd).firstOrNull;
          final exs = day == null
              ? const <PlanExercise>[]
              : (repo.exercisesByDayId[day.id] ?? const <PlanExercise>[]);
          final isToday = DateTime.now().weekday == wd;
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 5),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: day == null ? null : () => setState(() => _selectedDayId = day.id),
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
                                // 计数放标题行右侧，不混入动作名列表
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
                                // 每个动作名整体换行（Wrap），避免中文名在行尾被按字拆断
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 2,
                                  children: [
                                    for (var i = 0; i < exs.length; i++)
                                      Text(
                                        i == exs.length - 1
                                            ? exs[i].name
                                            : '${exs[i].name} ·',
                                        style: const TextStyle(
                                            color: AppTheme.textDim,
                                            fontSize: 13),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
        if (selected != null) _dayDetail(c, selected),
      ],
    );
  }

  Widget _dayDetail(AppContainer c, PlanDay day) {
    final exs = c.planRepo.exercisesByDayId[day.id] ?? [];
    return SectionCard(
      title: day.title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final e in exs)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      '${e.name} — ${e.sets}×${e.repsMin}-${e.repsMax} · 休息 ${e.restSec}s · ${e.kind == 'compound' ? '复合' : '辅助'}',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                  Text('渐进规则：${e.rule.desc}',
                      style: const TextStyle(
                          color: AppTheme.textDim, fontSize: 13)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _installBaoji() async {
    final c = app(context);
    await c.planRepo.installBaojiPlan();
    if (mounted) {
      toast(context, '薄肌计划已安装');
      setState(() => _loading = true);
      _refresh();
    }
  }

  Future<void> _showAiImport() async {
    final c = app(context);
    final ctrl = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('AI 拆解训练计划',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('粘贴你的计划原文（如“周一 卧推 3×5-8 …”），AI 自动识别训练日、动作、组数次数。',
                style: TextStyle(color: AppTheme.textDim, fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              maxLines: 8,
              decoration: const InputDecoration(
                  hintText: '在此粘贴计划文本…'),
            ),
            const SizedBox(height: 12),
            if (!c.settings.aiConfigured)
              const Text('尚未配置 AI 接口：请先到 设置 → AI 配置 填写。',
                  style: TextStyle(color: AppTheme.warn)),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('开始拆解'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    if (!c.settings.aiConfigured) {
      toast(context, '请先在设置里配置 AI 接口');
      return;
    }
    // 拆解中。先取 navigator，异步后再用它关掉，避免跨 async 用 context
    final nav = Navigator.of(context, rootNavigator: true);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final specs = await c.ai.parsePlan(ctrl.text);
      final metaMap = c.ai.metaMap();
      final plan = await c.planRepo.saveAiPlan(
        name: 'AI 计划 ${fmtDate(DateTime.now())}',
        specs: specs,
        metaMap: metaMap,
      );
      // 关掉加载圈（无论后续成功失败都必须关，否则页面卡死）
      if (nav.canPop()) nav.pop();
      // 写飞书日历（未来 14 天内的训练日）
      await _syncUpcomingDays(c);
      if (!mounted) return;
      toast(context, '拆解完成：${specs.length} 个训练日，已启用「${plan.name}」');
      setState(() => _loading = true);
      _refresh();
    } on AiException catch (e) {
      if (nav.canPop()) nav.pop();
      if (mounted) toast(context, e.message);
    } catch (e) {
      if (nav.canPop()) nav.pop();
      if (mounted) toast(context, '拆解失败：$e');
    }
  }

  /// 激活计划的未来 14 天训练日写入飞书日历。
  Future<void> _syncUpcomingDays(AppContainer c) async {
    final repo = c.planRepo;
    final specs = <PlanDaySyncSpec>[];
    for (final day in repo.days) {
      final exs = repo.exercisesByDayId[day.id] ?? [];
      if (exs.isEmpty) continue;
      specs.add(PlanDaySyncSpec(
        planDayId: day.id!,
        weekday: day.weekday,
        title: day.title,
        detail: exs
            .map((e) => '· ${e.name} ${e.sets}×${e.repsMin}-${e.repsMax}')
            .join('\n'),
      ));
    }
    await c.lark.syncUpcomingDays(days: specs);
  }
}
