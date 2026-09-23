import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/engine.dart';
import '../models/models.dart';
import 'theme.dart';
import 'widgets/common.dart';

/// 训练日编辑器：改标题/星期、动作增删改与排序。所有修改即时保存。
/// 返回值：是否有过修改（调用方据此决定是否刷新与重同步飞书）。
class PlanEditorPage extends StatefulWidget {
  const PlanEditorPage({super.key, required this.day});

  final PlanDay day;

  @override
  State<PlanEditorPage> createState() => _PlanEditorPageState();
}

class _PlanEditorPageState extends State<PlanEditorPage> {
  late PlanDay _day;
  List<PlanExercise> _exercises = [];
  List<ExerciseMeta> _knownMeta = [];
  bool _loading = true;
  bool _dirty = false; // 本次进入是否改过内容
  late final TextEditingController _titleCtrl;
  bool _moving = false; // 排序写库中，防连点丢步

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.day.title);
    // initState 里不能同步读 InheritedWidget，延后一帧再加载
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final c = app(context);
    _exercises = await c.db.dayExercises(_day.id!);
    _knownMeta = await c.db.allExerciseMeta();
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _saveTitle() async {
    final t = _titleCtrl.text.trim();
    if (t.isEmpty || t == _day.title) return;
    final c = app(context);
    _day = PlanDay(
        id: _day.id, planId: _day.planId, weekday: _day.weekday, title: t);
    await c.db.updatePlanDay(_day);
    _dirty = true;
  }

  /// 切星期：目标日空闲则移动；被占则确认后两日内容对调。
  Future<void> _moveToWeekday(int weekday) async {
    if (weekday == _day.weekday) return;
    final c = app(context);
    final messenger = ScaffoldMessenger.of(context);
    final all = await c.db.planDays(_day.planId);
    if (!mounted) return;
    final occupant =
        all.where((d) => d.weekday == weekday && d.id != _day.id).firstOrNull;
    if (occupant != null) {
      final ok = await confirmDialog(
          context, '与周${'一二三四五六日'[weekday - 1]}对调？',
          '「${occupant.title}」已安排在周${'一二三四五六日'[weekday - 1]}，确认后两天的内容将互相交换。');
      if (!ok || !mounted) return;
    }
    if (occupant == null) {
      _day = PlanDay(
          id: _day.id, planId: _day.planId, weekday: weekday, title: _day.title);
      await c.db.updatePlanDay(_day);
    } else {
      await c.db.swapPlanDayWeekdays(_day, occupant);
      _day = PlanDay(
          id: _day.id, planId: _day.planId, weekday: weekday, title: _day.title);
    }
    _dirty = true;
    messenger.showSnackBar(SnackBar(
      content: Text(occupant == null
          ? '已调整到周${'一二三四五六日'[weekday - 1]}'
          : '已与周${'一二三四五六日'[weekday - 1]}「${occupant.title}」对调'),
      backgroundColor: AppTheme.cardHi,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  Future<void> _openExerciseSheet([PlanExercise? existing]) async {
    final result = await showModalBottomSheet<ExerciseFormResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _ExerciseEditSheet(
        initial: existing,
        knownNames: _knownMeta.map((m) => m.name).toList(),
      ),
    );
    if (result == null || !mounted) return;
    final c = app(context);
    ProgressionRule buildRule() => ProgressionRule(
          repsMin: result.repsMin,
          repsMax: result.repsMax,
          incrementKg: result.kind == 'compound' ? 2.5 : 1.25,
          workingSets: result.sets,
          desc: result.kind == 'compound'
              ? '全部正式组达 ${result.repsMax} 次且末组余力≥1 → 加 2.5kg；有组低于 ${result.repsMin} 次 → 减 5%'
              : '全部正式组达 ${result.repsMax} 次且末组余力≥1 → 加 1.25kg',
        );
    if (existing == null) {
      final draft = PlanExercise(
        dayId: _day.id!,
        name: result.name,
        orderIdx: _exercises.length,
        sets: result.sets,
        repsMin: result.repsMin,
        repsMax: result.repsMax,
        restSec: result.restSec,
        kind: result.kind,
        rule: buildRule(),
      );
      await c.db.insertPlanExercise(draft);
      // 新动作名沉淀进动作库（肌群未知时归「其他」）
      if (_knownMeta.every((m) => m.name != result.name)) {
        await c.db.upsertExerciseMeta(ExerciseMeta(
          result.name,
          const MuscleGroups(main: '其他'),
          result.kind == 'compound',
        ));
        _knownMeta = await c.db.allExerciseMeta();
      }
      await _reload(); // 以 DB 为准（order_idx 连续性由重查保证）
    } else {
      // 编辑时同步重建渐进规则：改组数/次数要影响训练引擎的判定
      final updated = existing.copyWith(
        name: result.name,
        sets: result.sets,
        repsMin: result.repsMin,
        repsMax: result.repsMax,
        restSec: result.restSec,
        kind: result.kind,
        rule: buildRule(),
      );
      await c.db.updatePlanExercise(updated);
      await _reload();
    }
    _dirty = true;
    if (mounted) setState(() {});
  }

  Future<void> _removeExercise(PlanExercise ex) async {
    final ok = await confirmDialog(
        context, '删除动作？', '「${ex.name}」将从这一天移除（历史训练记录不受影响）。');
    if (!ok || !mounted) return;
    final c = app(context);
    await c.db.deletePlanExercise(ex.id!);
    // 补齐 order_idx（删除会留空洞，导致后续新增排序错乱）
    final rest =
        _exercises.where((e) => e.id != ex.id).map((e) => e.id!).toList();
    if (rest.isNotEmpty) {
      await c.db.reorderPlanExercises(_day.id!, rest);
    }
    _dirty = true;
    await _reload();
    if (mounted) setState(() {});
  }

  Future<void> _move(int index, int delta) async {
    if (_moving) return; // 写库中防连点丢步
    final j = index + delta;
    if (j < 0 || j >= _exercises.length) return;
    _moving = true;
    // 乐观更新：先改内存再写库，连点不丢步
    final list = [..._exercises];
    final tmp = list[index];
    list[index] = list[j];
    list[j] = tmp;
    setState(() => _exercises = list);
    final c = app(context);
    await c.db.reorderPlanExercises(_day.id!, list.map((e) => e.id!).toList());
    _dirty = true;
    _moving = false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        await _saveTitle(); // 返回前兜底保存标题
        if (!mounted) return;
        navigator.pop(_dirty);
      },
      child: Scaffold(
        backgroundColor: AppTheme.bg,
        appBar: AppBar(
          leading: BackButton(onPressed: () async {
            final navigator = Navigator.of(context);
            await _saveTitle();
            if (!mounted) return;
            navigator.pop(_dirty);
          }),
          title: Text('周${'一二三四五六日'[_day.weekday - 1]} · 编辑训练日'),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      children: [
                        TextField(
                          controller: _titleCtrl,
                          decoration: const InputDecoration(
                              labelText: '训练日标题（自动保存）'),
                          onSubmitted: (_) => _saveTitle(),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Text('安排在',
                                style: TextStyle(
                                    color: AppTheme.textDim, fontSize: 13)),
                            for (var wd = 1; wd <= 7; wd++)
                              ChoiceChip(
                                label: Text('周${'一二三四五六日'[wd - 1]}'),
                                selected: _day.weekday == wd,
                                onSelected: (_) => _moveToWeekday(wd),
                                labelStyle: TextStyle(
                                    fontSize: 12,
                                    color: _day.weekday == wd
                                        ? const Color(0xFF06220F)
                                        : AppTheme.text),
                                selectedColor: AppTheme.primary,
                                backgroundColor: AppTheme.cardHi,
                                side: BorderSide.none,
                              ),
                          ],
                        ),
                        const Divider(height: 28),
                        Row(
                          children: [
                            Text('动作（${_exercises.length}）',
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700)),
                            const Spacer(),
                            TextButton.icon(
                              onPressed: () => _openExerciseSheet(),
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('添加动作'),
                            ),
                          ],
                        ),
                        if (_exercises.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Text('这一天还没有动作，点下方「添加动作」开始编排。',
                                style: TextStyle(color: AppTheme.textDim)),
                          ),
                        for (var i = 0; i < _exercises.length; i++)
                          _exerciseRow(i),
                      ],
                    ),
                  ),
                  // 底部常驻：拇指区添加动作
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                      child: OutlinedButton.icon(
                        onPressed: () => _openExerciseSheet(),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('添加动作'),
                        style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(52)),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _exerciseRow(int i) {
    final e = _exercises[i];
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: Row(
          children: [
            Column(
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: i == 0 ? null : () => _move(i, -1),
                  icon: const Icon(Icons.arrow_upward, size: 18),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: i == _exercises.length - 1
                      ? null
                      : () => _move(i, 1),
                  icon: const Icon(Icons.arrow_downward, size: 18),
                ),
              ],
            ),
            const SizedBox(width: 4),
            Expanded(
              child: InkWell(
                onTap: () => _openExerciseSheet(e),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.name,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(
                          '${e.sets}×${e.repsMin}-${e.repsMax} · 休 ${e.restSec}s · ${e.kind == 'compound' ? '复合' : '辅助'}',
                          style: const TextStyle(
                              color: AppTheme.textDim, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () => _removeExercise(e),
              icon: const Icon(Icons.delete_outline,
                  size: 20, color: AppTheme.danger),
            ),
          ],
        ),
      ),
    );
  }
}

// ================= 动作编辑表单 =================

class ExerciseFormResult {
  final String name;
  final int sets;
  final int repsMin;
  final int repsMax;
  final int restSec;
  final String kind;
  const ExerciseFormResult({
    required this.name,
    required this.sets,
    required this.repsMin,
    required this.repsMax,
    required this.restSec,
    required this.kind,
  });
}

class _ExerciseEditSheet extends StatefulWidget {
  const _ExerciseEditSheet({this.initial, required this.knownNames});

  final PlanExercise? initial;
  final List<String> knownNames;

  @override
  State<_ExerciseEditSheet> createState() => _ExerciseEditSheetState();
}

class _ExerciseEditSheetState extends State<_ExerciseEditSheet> {
  late final _nameCtrl =
      TextEditingController(text: widget.initial?.name ?? '');
  late int _sets = widget.initial?.sets ?? 3;
  late int _repsMin = widget.initial?.repsMin ?? 8;
  late int _repsMax = widget.initial?.repsMax ?? 12;
  late int _restSec = (widget.initial?.restSec ?? 0) > 0
      ? widget.initial!.restSec
      : 120;
  late String _kind = widget.initial?.kind ?? 'assistance';
  String? _nameError;

  List<String> get _suggestions {
    final q = _nameCtrl.text.trim();
    if (q.isEmpty) return const [];
    return widget.knownNames
        .where((n) => n != q && n.contains(q))
        .take(6)
        .toList();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = _suggestions;
    return Padding(
      padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.initial == null ? '添加动作' : '编辑动作',
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          TextField(
            controller: _nameCtrl,
            autofocus: widget.initial == null,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: '动作名',
              errorText: _nameError,
            ),
          ),
          if (suggestions.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final n in suggestions)
                  ActionChip(
                    label: Text(n, style: const TextStyle(fontSize: 12)),
                    backgroundColor: AppTheme.cardHi,
                    side: BorderSide.none,
                    onPressed: () {
                      _nameCtrl.text = n;
                      setState(() {});
                    },
                  ),
              ],
            ),
          const SizedBox(height: 10),
          _stepper(
              '组数', _sets, 1, 8, 1, (v) => setState(() => _sets = v)),
          _stepper('次数下限', _repsMin, 1, _repsMax, 1,
              (v) => setState(() => _repsMin = v)),
          _stepper('次数上限', _repsMax, _repsMin, 30, 1,
              (v) => setState(() => _repsMax = v)),
          _stepper('组间休息（秒）', _restSec, 15, 600, 15,
              (v) => setState(() => _restSec = v)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _kindChip('复合', 'compound'),
              const SizedBox(width: 8),
              _kindChip('辅助', 'assistance'),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              final name = _nameCtrl.text.trim();
              if (name.isEmpty) {
                setState(() => _nameError = '请填写动作名');
                return;
              }
              HapticFeedback.selectionClick();
              Navigator.pop(
                context,
                ExerciseFormResult(
                  name: name,
                  sets: _sets,
                  repsMin: _repsMin,
                  repsMax: _repsMax,
                  restSec: _restSec,
                  kind: _kind,
                ),
              );
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Widget _stepper(String label, int value, int min, int max, int step,
      ValueChanged<int> on) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        IconButton(
          onPressed: value - step < min ? null : () => on(value - step),
          icon: const Icon(Icons.remove_circle_outline),
        ),
        SizedBox(
            width: 52,
            child: Text('$value',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16))),
        IconButton(
          onPressed: value + step > max ? null : () => on(value + step),
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
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
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
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
