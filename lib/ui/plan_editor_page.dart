import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/engine.dart';
import '../l10n/lang.dart';
import '../l10n/names.dart';
import 'exercise_picker_page.dart';
import 'theme.dart';
import 'widgets/common.dart';

/// 训练日编辑器：改标题/星期、动作增删改、拖拽排序、复制、肌群标注。
/// 所有修改即时保存；返回值 = 是否有过修改（调用方据此刷新与重同步飞书）。
class PlanEditorPage extends StatefulWidget {
  const PlanEditorPage({super.key, required this.day, this.planName});

  final PlanDay day;
  final String? planName;

  @override
  State<PlanEditorPage> createState() => _PlanEditorPageState();
}

class _PlanEditorPageState extends State<PlanEditorPage> {
  late PlanDay _day = widget.day;
  List<PlanExercise> _exercises = [];
  Map<String, ExerciseMeta> _metaByName = {};
  bool _loading = true;
  bool _dirty = false; // 本次进入是否改过内容
  late final TextEditingController _titleCtrl =
      TextEditingController(text: widget.day.title);

  @override
  void initState() {
    super.initState();
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
    final metas = await c.db.allExerciseMeta();
    _metaByName = {for (final m in metas) m.name: m};
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
          context,
          tx('与周${'一二三四五六日'[weekday - 1]}对调？',
              en: 'Swap with ${const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][weekday - 1]}?'),
          tx('「${dname(occupant.title)}」已安排在周${'一二三四五六日'[weekday - 1]}，确认后两天的内容将互相交换。',
              en: '"${dname(occupant.title)}" is already on ${const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][weekday - 1]}; confirming will swap the contents of the two days.'));
      if (!ok || !mounted) return;
    }
    if (occupant == null) {
      if (!mounted) return;
      // setState 让 AppBar 标题与星期 chips 选中态即时刷新
      setState(() {
        _day = PlanDay(
            id: _day.id,
            planId: _day.planId,
            weekday: weekday,
            title: _day.title);
      });
      await c.db.updatePlanDay(_day);
    } else {
      await c.db.swapPlanDayWeekdays(_day, occupant);
      if (!mounted) return;
      setState(() {
        _day = PlanDay(
            id: _day.id,
            planId: _day.planId,
            weekday: weekday,
            title: _day.title);
      });
    }
    _dirty = true;
    messenger.showSnackBar(SnackBar(
      content: Text(occupant == null
          ? tx('已调整到周${'一二三四五六日'[weekday - 1]}',
              en: 'Moved to ${const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][weekday - 1]}')
          : tx('已与周${'一二三四五六日'[weekday - 1]}「${dname(occupant.title)}」对调',
              en: 'Swapped with ${const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][weekday - 1]} "${dname(occupant.title)}"')),
      backgroundColor: AppTheme.cardHi,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  /// 从动作库挑选：搜索/筛选/多选，确认后批量追加到当天（参数用合理默认，
  /// 之后点开单个动作微调）。
  Future<void> _pickFromLibrary() async {
    final picked = await Navigator.of(context).push<List<ExerciseMeta>>(
      MaterialPageRoute(
        builder: (_) => ExercisePickerPage(
          existingNames: _exercises.map((e) => e.name).toSet(),
        ),
      ),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    final c = app(context);
    var order = _exercises.length;
    for (final m in picked) {
      final isCompound = m.isCompound;
      await c.db.insertPlanExercise(PlanExercise(
        dayId: _day.id!,
        name: m.name,
        orderIdx: order++,
        sets: isCompound ? 4 : 3,
        repsMin: isCompound ? 6 : 8,
        repsMax: isCompound ? 10 : 12,
        restSec: isCompound ? 150 : 90,
        kind: isCompound ? 'compound' : 'assistance',
        rule: ProgressionRule(
          repsMin: isCompound ? 6 : 8,
          repsMax: isCompound ? 10 : 12,
          incrementKg: isCompound ? 2.5 : 1.25,
          workingSets: isCompound ? 4 : 3,
        ),
      ));
    }
    _dirty = true;
    await _reload();
    if (mounted) {
      toast(context,
          tx('已添加 ${picked.length} 个动作，点开可微调组数',
              en: 'Added ${picked.length} exercises; tap one to adjust sets'));
    }
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
        knownMetas: _metaByName.values.toList(),
        initialMuscle:
            existing == null ? null : _metaByName[existing.name]?.muscles.main,
      ),
    );
    if (result == null || !mounted) return;
    final c = app(context);
    final rule = ProgressionRule(
      repsMin: result.repsMin,
      repsMax: result.repsMax,
      incrementKg: result.kind == 'compound' ? 2.5 : 1.25,
      workingSets: result.sets,
      desc: result.kind == 'compound'
          ? tx('全部正式组达 ${result.repsMax} 次且末组余力≥1 → 加 2.5kg；有组低于 ${result.repsMin} 次 → 减 5%',
              en: 'All working sets reach ${result.repsMax} reps with ≥1 in reserve on the last set → add 2.5kg; any set below ${result.repsMin} reps → reduce 5%')
          : tx('全部正式组达 ${result.repsMax} 次且末组余力≥1 → 加 1.25kg',
              en: 'All working sets reach ${result.repsMax} reps with ≥1 in reserve on the last set → add 1.25kg'),
    );

    // 肌群/场景标注写回动作库（保留既有次要肌群），热力图与动作库才正确
    Future<void> saveMeta() async {
      final old = _metaByName[result.name];
      final meta = ExerciseMeta(
        result.name,
        MuscleGroups(
            main: result.muscle, secondary: old?.muscles.secondary ?? []),
        result.kind == 'compound',
        result.equipment,
      );
      await c.db.upsertExerciseMeta(meta);
      _metaByName[result.name] = meta;
    }

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
        rule: rule,
      );
      await c.db.insertPlanExercise(draft);
      await saveMeta();
    } else {
      // 编辑时同步重建渐进规则：改组数/次数要影响训练引擎的判定
      final updated = existing.copyWith(
        name: result.name,
        sets: result.sets,
        repsMin: result.repsMin,
        repsMax: result.repsMax,
        restSec: result.restSec,
        kind: result.kind,
        rule: rule,
      );
      await c.db.updatePlanExercise(updated);
      await saveMeta();
    }
    _dirty = true;
    await _reload();
    if (mounted) setState(() {});
  }

  /// 复制动作：同配置插到末尾，名字加「副本」提示改名。
  Future<void> _copyExercise(PlanExercise ex) async {
    final c = app(context);
    await c.db.insertPlanExercise(
      ex.copyWith(
          id: null,
          name: tx('${ex.name}（副本）', en: '${ex.name} (copy)'),
          orderIdx: _exercises.length),
    );
    _dirty = true;
    await _reload();
    if (mounted) {
      toast(context,
          tx('已复制「${exname(ex.name)}」，记得改动作名',
              en: '"${exname(ex.name)}" copied; remember to rename it'));
    }
  }

  /// 删除动作：立即生效 + 可撤销（比确认弹窗顺手）。
  Future<void> _removeExercise(PlanExercise ex) async {
    final c = app(context);
    final index = _exercises.indexOf(ex);
    final snapshot = ex.copyWith();
    await c.db.deletePlanExercise(ex.id!);
    final rest =
        _exercises.where((e) => e.id != ex.id).map((e) => e.id!).toList();
    if (rest.isNotEmpty) {
      await c.db.reorderPlanExercises(_day.id!, rest);
    }
    _dirty = true;
    await _reload();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(
      content: Text(tx('已删除「${exname(snapshot.name)}」', en: '"${exname(snapshot.name)}" deleted')),
      backgroundColor: AppTheme.cardHi,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 4),
      action: SnackBarAction(
        label: tx('撤销', en: 'Undo'),
        textColor: AppTheme.primary,
        onPressed: () async {
          final restored = snapshot.copyWith(id: null, orderIdx: 0);
          final newId = await c.db.insertPlanExercise(restored);
          final ids = _exercises.map((e) => e.id!).toList();
          ids.insert(index.clamp(0, ids.length), newId);
          await c.db.reorderPlanExercises(_day.id!, ids);
          _dirty = true;
          await _reload();
          if (mounted) setState(() {});
        },
      ),
    ));
  }

  /// 拖拽排序落库（onReorderItem 的 newIndex 已由框架修正）。
  Future<void> _onReorderItem(int oldIndex, int newIndex) async {
    final list = [..._exercises];
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    setState(() => _exercises = list);
    final c = app(context);
    await c.db.reorderPlanExercises(_day.id!, list.map((e) => e.id!).toList());
    _dirty = true;
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
          title: Text(tx('周${'一二三四五六日'[_day.weekday - 1]} · 编辑训练日',
              en: '${const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][_day.weekday - 1]} · Edit training day')),
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
                          decoration: InputDecoration(
                              labelText: tx('训练日标题（自动保存）',
                                  en: 'Training day title (auto-saves)')),
                          onSubmitted: (_) => _saveTitle(),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(tx('安排在', en: 'Scheduled on'),
                                style: const TextStyle(
                                    color: AppTheme.textDim, fontSize: 13)),
                            for (var wd = 1; wd <= 7; wd++)
                              ChoiceChip(
                                label: Text(tx('周${'一二三四五六日'[wd - 1]}',
                                    en: const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][wd - 1])),
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
                            Text(
                                tx('动作（${_exercises.length}）',
                                    en: 'Exercises (${_exercises.length})'),
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(width: 8),
                            Text(tx('长按拖动排序', en: 'Long-press to reorder'),
                                style: const TextStyle(
                                    color: AppTheme.textDim, fontSize: 12)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        if (_exercises.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Text(
                                tx('这一天还没有动作，点下方「添加动作」开始编排。',
                                    en: 'No exercises yet for this day; tap "Add exercise" below to start.'),
                                style: const TextStyle(
                                    color: AppTheme.textDim)),
                          )
                        else
                          ReorderableListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            buildDefaultDragHandles: false,
                            onReorderItem: _onReorderItem,
                            proxyDecorator: (child, index, animation) =>
                                Material(
                              elevation: 4,
                              borderRadius: BorderRadius.circular(16),
                              color: AppTheme.cardHi,
                              child: child,
                            ),
                            itemCount: _exercises.length,
                            itemBuilder: (BuildContext ctx, int i) =>
                                _exerciseRow(i,
                                    key: ValueKey(_exercises[i].id)),
                          ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                  // 底部常驻：拇指区双入口（从动作库挑选 / 手动填写）
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () => _pickFromLibrary(),
                              icon: const Icon(Icons.library_books, size: 18),
                              label: Text(tx('从动作库选', en: 'Pick from library')),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(52),
                                backgroundColor: AppTheme.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _openExerciseSheet(),
                              icon: const Icon(Icons.edit, size: 18),
                              label: Text(tx('手动填写', en: 'Enter manually')),
                              style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(52)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _exerciseRow(int i, {required Key key}) {
    final e = _exercises[i];
    final muscle = _metaByName[e.name]?.muscles.main;
    return Card(
      key: key,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ReorderableDelayedDragStartListener(
        index: i,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openExerciseSheet(e),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
            child: Row(
              children: [
                const SizedBox(
                    width: 32,
                    height: 44,
                    child: Icon(Icons.drag_indicator,
                        size: 20, color: AppTheme.textDim)),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(exname(e.name),
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(
                            '${e.sets}×${e.repsMin}-${e.repsMax} · ${tx('休 ${e.restSec}s', en: 'Rest ${e.restSec}s')} · ${e.kind == 'compound' ? tx('复合', en: 'Compound') : tx('辅助', en: 'Assistance')}'
                            '${muscle != null ? ' · ${mname(muscle)}' : ''}',
                            style: const TextStyle(
                                color: AppTheme.textDim, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: tx('复制', en: 'Copy'),
                  onPressed: () => _copyExercise(e),
                  icon: const Icon(Icons.content_copy,
                      size: 19, color: AppTheme.textDim),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: tx('删除', en: 'Delete'),
                  onPressed: () => _removeExercise(e),
                  icon: const Icon(Icons.delete_outline,
                      size: 20, color: AppTheme.danger),
                ),
              ],
            ),
          ),
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
  final String muscle; // 主肌群（写回动作库，供热力图归类）
  final String equipment; // 器械场景 gym/home/both（写回动作库）
  const ExerciseFormResult({
    required this.name,
    required this.sets,
    required this.repsMin,
    required this.repsMax,
    required this.restSec,
    required this.kind,
    required this.muscle,
    this.equipment = 'both',
  });
}

class _ExerciseEditSheet extends StatefulWidget {
  const _ExerciseEditSheet({
    this.initial,
    required this.knownMetas,
    this.initialMuscle,
  });

  final PlanExercise? initial;
  final List<ExerciseMeta> knownMetas;
  final String? initialMuscle;

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
  late String? _muscle =
      widget.initialMuscle ?? widget.initial?.name ?? '';
  String? _nameError;
  late String _equipment =
      widget.knownMetas.firstWhere((m) => m.name == widget.initial?.name,
              orElse: () => const ExerciseMeta('', MuscleGroups(main: '其他'), false))
          .equipment;

  List<String> get _suggestions {
    final q = _nameCtrl.text.trim();
    // 空时展示词表前几个，帮助发现与统一命名
    if (q.isEmpty) {
      return widget.knownMetas.take(8).map((m) => m.name).toList();
    }
    return widget.knownMetas
        .map((m) => m.name)
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
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.initial == null
                ? tx('添加动作', en: 'Add exercise')
                : tx('编辑动作', en: 'Edit exercise'),
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            TextField(
              controller: _nameCtrl,
              autofocus: widget.initial == null,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: tx('动作名', en: 'Exercise name'),
                errorText: _nameError,
              ),
            ),
            if (suggestions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final n in suggestions)
                      ActionChip(
                        label:
                            Text(exname(n), style: const TextStyle(fontSize: 12)),
                        backgroundColor: AppTheme.cardHi,
                        side: BorderSide.none,
                        onPressed: () {
                          _nameCtrl.text = n;
                          // 选词表动作时带出其肌群
                          final meta = widget.knownMetas
                              .where((m) => m.name == n)
                              .firstOrNull;
                          setState(
                              () => _muscle = meta?.muscles.main ?? _muscle);
                        },
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            // 快捷预设：一键填组数/次数/休息
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final preset in [
                  (tx('力量 3×5', en: 'Strength 3×5'), 3, 5, 5, 180),
                  (tx('增肌 3×8-12', en: 'Hypertrophy 3×8-12'), 3, 8, 12, 120),
                  (tx('耐力 2×15', en: 'Endurance 2×15'), 2, 15, 20, 75),
                ])
                  ActionChip(
                    label: Text(preset.$1,
                        style: const TextStyle(fontSize: 12)),
                    backgroundColor: AppTheme.cardHi,
                    side: BorderSide.none,
                    onPressed: () => setState(() {
                      _sets = preset.$2;
                      _repsMin = preset.$3;
                      _repsMax = preset.$4;
                      _restSec = preset.$5;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            _stepper(tx('组数', en: 'Sets'), _sets, 1, 8, 1,
                (v) => setState(() => _sets = v)),
            _stepper(tx('次数下限', en: 'Min reps'), _repsMin, 1, _repsMax, 1,
                (v) => setState(() => _repsMin = v)),
            _stepper(tx('次数上限', en: 'Max reps'), _repsMax, _repsMin, 30, 1,
                (v) => setState(() => _repsMax = v)),
            _stepper(tx('组间休息（秒）', en: 'Rest between sets (s)'), _restSec,
                15, 600, 15, (v) => setState(() => _restSec = v)),
            // 休息快捷档：不用从 15 一档一档点到 180
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final sec in const [45, 60, 90, 120, 180, 240, 300])
                  ActionChip(
                    label: Text(
                        sec >= 60
                            ? tx('${sec ~/ 60} 分${sec % 60 == 0 ? '' : ' ${sec % 60} 秒'}',
                                en: '${sec ~/ 60} min${sec % 60 == 0 ? '' : ' ${sec % 60} s'}')
                            : tx('$sec 秒', en: '$sec s'),
                        style: TextStyle(
                            fontSize: 12,
                            color: _restSec == sec
                                ? AppTheme.primary
                                : AppTheme.textDim,
                            fontWeight: _restSec == sec
                                ? FontWeight.w700
                                : FontWeight.w400)),
                    backgroundColor:
                        _restSec == sec ? AppTheme.primary.withValues(alpha: 0.15) : AppTheme.cardHi,
                    side: BorderSide.none,
                    onPressed: () =>
                        setState(() => _restSec = sec),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(tx('主肌群', en: 'Main muscle'),
                      style: const TextStyle(
                          color: AppTheme.textDim, fontSize: 13)),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Wrap(
                    spacing: 5,
                    runSpacing: 4,
                    children: [
                      for (final m in kMuscleRegions)
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _muscle = m);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: _muscle == m
                                  ? AppTheme.accent
                                  : AppTheme.cardHi,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                                tx(m,
                                    en: const {
                                      '胸': 'Chest',
                                      '肩': 'Shoulders',
                                      '背': 'Back',
                                      '手臂': 'Arms',
                                      '腿': 'Legs',
                                      '核心': 'Core',
                                      '其他': 'Other',
                                    }[m] ?? m),
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: _muscle == m
                                        ? const Color(0xFF06220F)
                                        : AppTheme.textDim)),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(tx('场景', en: 'Setting'),
                      style: const TextStyle(
                          color: AppTheme.textDim, fontSize: 13)),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Wrap(
                    spacing: 5,
                    runSpacing: 4,
                    children: [
                      for (final eq in [
                        ('both', tx('都可以', en: 'Both')),
                        ('gym', tx('健身房', en: 'Gym')),
                        ('home', tx('居家', en: 'Home')),
                      ])
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _equipment = eq.$1);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: _equipment == eq.$1
                                  ? AppTheme.accent
                                  : AppTheme.cardHi,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(eq.$2,
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: _equipment == eq.$1
                                        ? const Color(0xFF06220F)
                                        : AppTheme.textDim)),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _kindChip(tx('复合', en: 'Compound'), 'compound'),
                const SizedBox(width: 8),
                _kindChip(tx('辅助', en: 'Assistance'), 'assistance'),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                final name = _nameCtrl.text.trim();
                if (name.isEmpty) {
                  setState(() =>
                      _nameError = tx('请填写动作名', en: 'Please enter an exercise name'));
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
                    muscle: (_muscle == null || _muscle!.isEmpty)
                        ? '其他'
                        : _muscle!,
                    equipment: _equipment,
                  ),
                );
              },
              child: Text(tx('保存', en: 'Save')),
            ),
          ],
        ),
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
