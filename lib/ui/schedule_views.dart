import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/engine.dart';
import '../l10n/lang.dart';
import '../l10n/names.dart';
import 'plan_editor_page.dart';
import 'theme.dart';
import 'widgets/common.dart';

/// 日期化排程视图：3 日 / 周 / 月三种粒度。
///
/// - 长按拖动"有训练的日子"到目标日期 = 移动过去（目标已有训练则互换）；
///   今天做前天/后天的训练、把训练延后到明天，都是一拖或菜单一键的事。
/// - 点空白日期：从模板日添加训练 / 标记休息；点已有日期：提前/延后/改休息/
///   清除自定义（回到计划规则默认）。
/// - 手动改动写 plan_schedule 覆盖行，没动过的日子跟随计划的星期/循环规则。
class ScheduleViews extends StatefulWidget {
  const ScheduleViews({
    super.key,
    required this.plan,
    required this.onChanged,
  });

  final Plan plan;

  /// 任何排程改动后回调（外层负责刷新与飞书重同步）。
  final VoidCallback onChanged;

  @override
  State<ScheduleViews> createState() => _ScheduleViewsState();
}

enum _Mode { d3, week, month }

/// 星期缩写映射（仅展示用；中文单字为键）。
const _weekdayEn = {
  '一': 'Mon',
  '二': 'Tue',
  '三': 'Wed',
  '四': 'Thu',
  '五': 'Fri',
  '六': 'Sat',
  '日': 'Sun',
};

class _CellData {
  final PlanDay? day;
  final bool overridden; // 该日有手动覆盖行
  final bool explicitRest; // 覆盖行为"显式休息"

  const _CellData({this.day, this.overridden = false, this.explicitRest = false});
}

class _ScheduleViewsState extends State<ScheduleViews> {
  _Mode _mode = _Mode.week;
  DateTime _anchor = DateTime.now(); // 3日/周视图的窗口起点；月视图取所在月
  Map<String, _CellData>? _cells;
  List<PlanDay>? _templates;

  DateTime get _windowStart {
    final a = DateTime(_anchor.year, _anchor.month, _anchor.day);
    if (_mode == _Mode.month) return DateTime(_anchor.year, _anchor.month, 1);
    return a;
  }

  DateTime get _windowEnd {
    final s = _windowStart;
    return switch (_mode) {
      _Mode.d3 => s.add(const Duration(days: 2)),
      _Mode.week => s.add(const Duration(days: 6)),
      _Mode.month => DateTime(s.year, s.month + 1, 0),
    };
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void didUpdateWidget(ScheduleViews old) {
    super.didUpdateWidget(old);
    if (old.plan.id != widget.plan.id) {
      _anchor = DateTime.now();
      _reload();
    }
  }

  Future<void> _reload() async {
    final c = app(context);
    final plan = widget.plan;
    if (plan.id == null) return;
    final entries = await c.db.scheduleEntries(
        plan.id!, fmtDate(_windowStart), fmtDate(_windowEnd));
    final byDate = {for (final e in entries) e.date: e};
    final cells = <String, _CellData>{};
    for (var d = _windowStart;
        !d.isAfter(_windowEnd);
        d = d.add(const Duration(days: 1))) {
      final key = fmtDate(d);
      final ov = byDate[key];
      if (ov != null) {
        final day =
            ov.dayId == null ? null : await c.db.planDayById(ov.dayId!);
        cells[key] = _CellData(
            day: day, overridden: true, explicitRest: ov.dayId == null);
      } else {
        final day = await c.planRepo.dayForDateOn(plan, d);
        cells[key] = _CellData(day: day);
      }
    }
    _templates = await c.db.planDays(plan.id!);
    if (!mounted) return;
    setState(() => _cells = cells);
  }

  Future<void> _shift(int days) async {
    setState(() {
      _anchor = switch (_mode) {
        _Mode.month => DateTime(_anchor.year, _anchor.month + days, 1),
        _ => _windowStart.add(Duration(days: days)),
      };
      _cells = null;
    });
    await _reload();
  }

  Future<void> _goToday() async {
    setState(() {
      _anchor = DateTime.now();
      _cells = null;
    });
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final cells = _cells;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: SegmentedButton<_Mode>(
                segments: [
                  ButtonSegment(
                      value: _Mode.d3, label: Text(tx('3 日', en: '3 Days'))),
                  ButtonSegment(
                      value: _Mode.week, label: Text(tx('一周', en: 'Week'))),
                  ButtonSegment(
                      value: _Mode.month, label: Text(tx('一月', en: 'Month'))),
                ],
                selected: {_mode},
                onSelectionChanged: (s) {
                  setState(() {
                    _mode = s.first;
                    _cells = null;
                  });
                  _reload();
                },
                showSelectedIcon: false,
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
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
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: () => _shift(_mode == _Mode.month ? -1 : -_step),
              icon: const Icon(Icons.chevron_left),
              tooltip: tx('往前', en: 'Back'),
            ),
            TextButton(
              onPressed: _goToday,
              child: Text(tx('今天', en: 'Today'),
                  style: const TextStyle(fontSize: 13)),
            ),
            IconButton(
              onPressed: () => _shift(_mode == _Mode.month ? 1 : _step),
              icon: const Icon(Icons.chevron_right),
              tooltip: tx('往后', en: 'Forward'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _windowLabel(),
          style: const TextStyle(color: AppTheme.textDim, fontSize: 12),
        ),
        const SizedBox(height: 6),
        if (cells == null)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
                child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2))),
          )
        else if (_mode == _Mode.month)
          _monthGrid(cells)
        else
          _dayList(cells, days: _mode == _Mode.d3 ? 3 : 7),
        const SizedBox(height: 4),
        Text(
            tx('长按拖动挪训练：拖到空日子＝移动，拖到有训练的日子＝互换。点日期管理当天安排。',
                en: 'Long-press and drag a workout: drop on an empty day to move it, drop on a workout day to swap. Tap a day to manage it.'),
            style: const TextStyle(color: AppTheme.textDim, fontSize: 11)),
      ],
    );
  }

  int get _step => _mode == _Mode.d3 ? 3 : 7;

  /// 「9月24日」式短日期，拖拽反馈文案用。
  String _md(DateTime d) =>
      tx('${d.month}月${d.day}日', en: '${d.month}/${d.day}');

  String _windowLabel() {
    final s = _windowStart;
    final e = _windowEnd;
    if (_mode == _Mode.month) {
      return tx('${s.year} 年 ${s.month} 月', en: '${s.year}-${s.month}');
    }
    if (_mode == _Mode.week && s.month == e.month) {
      return '${s.month}/${s.day} - ${e.day}';
    }
    return '${s.month}/${s.day} - ${e.month}/${e.day}';
  }

  // ---------------- 3日 / 周：逐日卡片 ----------------

  Widget _dayList(Map<String, _CellData> cells, {required int days}) {
    final today = fmtDate(DateTime.now());
    return Column(
      children: [
        for (var i = 0; i < days; i++)
          _dayTile(
            _windowStart.add(Duration(days: i)),
            cells[fmtDate(_windowStart.add(Duration(days: i)))] ??
                const _CellData(),
            isToday: fmtDate(_windowStart.add(Duration(days: i))) == today,
          ),
      ],
    );
  }

  Widget _dayTile(DateTime d, _CellData cell, {required bool isToday}) {
    final label = tx('周${'一二三四五六日'[d.weekday - 1]} ${d.month}/${d.day}',
        en:
            '${_weekdayEn['一二三四五六日'[d.weekday - 1]]} ${d.month}/${d.day}');
    final status = cell.day != null
        ? dname(cell.day!.title)
        : (cell.explicitRest
            ? tx('休息（手动设置）', en: 'Rest (manual)')
            : tx('休息', en: 'Rest'));
    final tile = Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cell.day != null
            ? AppTheme.primary.withValues(alpha: 0.10)
            : AppTheme.card.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: isToday
            ? Border.all(color: AppTheme.accent, width: 1)
            : Border.all(color: Colors.transparent, width: 1),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isToday ? AppTheme.accent : AppTheme.textDim)),
          ),
          Expanded(
            child: Text(
              status,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: cell.day != null ? AppTheme.primary : AppTheme.textDim,
              ),
            ),
          ),
          if (cell.overridden)
            Text(tx('自定义', en: 'Custom'),
                style: const TextStyle(color: AppTheme.warn, fontSize: 11)),
          Icon(Icons.drag_indicator,
              size: 18,
              color: cell.day != null
                  ? AppTheme.textDim
                  : AppTheme.textDim.withValues(alpha: 0.3)),
        ],
      ),
    );
    return _wrapDragAndTarget(d, cell, tile);
  }

  // ---------------- 月：日历网格 ----------------

  Widget _monthGrid(Map<String, _CellData> cells) {
    final first = _windowStart;
    final daysInMonth = DateTime(first.year, first.month + 1, 0).day;
    final firstWeekday = first.weekday;
    final today = fmtDate(DateTime.now());
    final rows = <Widget>[];
    // 星期表头
    rows.add(Row(
      children: [
        for (final w in ['一', '二', '三', '四', '五', '六', '日'])
          Expanded(
            child: Center(
                child: Text(tx('周$w', en: _weekdayEn[w]),
                    style: const TextStyle(
                        color: AppTheme.textDim, fontSize: 10))),
          ),
      ],
    ));
    var cell = 1 - (firstWeekday - 1);
    while (cell <= daysInMonth) {
      final row = <Widget>[];
      for (var i = 0; i < 7; i++, cell++) {
        if (cell < 1 || cell > daysInMonth) {
          row.add(const Expanded(child: SizedBox(height: 52)));
          continue;
        }
        final d = DateTime(first.year, first.month, cell);
        final key = fmtDate(d);
        row.add(Expanded(
          child: _monthCell(
            d,
            cells[key] ?? const _CellData(),
            isToday: key == today,
          ),
        ));
      }
      rows.add(Row(children: row));
    }
    return Column(children: rows);
  }

  Widget _monthCell(DateTime d, _CellData cell, {required bool isToday}) {
    final title = cell.day?.title;
    final short = title == null
        ? (cell.explicitRest ? tx('休', en: 'Rest') : '')
        : (title.length > 3 ? title.substring(0, 3) : title);
    final inner = Container(
      height: 52,
      margin: const EdgeInsets.all(1.5),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      decoration: BoxDecoration(
        color: cell.day != null
            ? AppTheme.primary.withValues(alpha: 0.15)
            : (cell.explicitRest
                ? AppTheme.warn.withValues(alpha: 0.10)
                : AppTheme.card.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(9),
        border: isToday
            ? Border.all(color: AppTheme.accent, width: 1)
            : Border.all(color: Colors.transparent),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('${d.day}',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: isToday || cell.day != null
                      ? FontWeight.w800
                      : FontWeight.w400,
                  color: isToday
                      ? AppTheme.accent
                      : cell.day != null
                          ? AppTheme.primary
                          : AppTheme.textDim)),
          if (short.isNotEmpty)
            Text(short,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: TextStyle(
                    fontSize: 9,
                    color: cell.explicitRest
                        ? AppTheme.warn
                        : AppTheme.primary.withValues(alpha: 0.9))),
        ],
      ),
    );
    return _wrapDragAndTarget(d, cell, inner);
  }

  /// 拖拽改期 + 点按管理：有训练的日子可长按拖走；所有格子都能接收。
  Widget _wrapDragAndTarget(DateTime d, _CellData cell, Widget child) {
    Widget w = DragTarget<DateTime>(
      key: ValueKey('target-${fmtDate(d)}-${widget.plan.id}'),
      onWillAcceptWithDetails: (details) => details.data != d,
      onAcceptWithDetails: (details) async {
        HapticFeedback.selectionClick();
        final from = details.data;
        final messenger = ScaffoldMessenger.of(context);
        final c = app(context);
        await c.planRepo.moveScheduleDay(widget.plan, from, d);
        widget.onChanged();
        await _reload();
        // 放下后的肉眼确认：空目标＝移动，有训练的目标＝互换
        final fromTitle =
            dname(_cells?[fmtDate(from)]?.day?.title ?? tx('训练', en: 'Workout'));
        final msg = cell.day == null
            ? tx('已移动：${_md(from)}「$fromTitle」→ ${_md(d)}（原日期改休息）',
                en: 'Moved: ${_md(from)} "$fromTitle" → ${_md(d)} (original day becomes rest)')
            : tx('已互换：${_md(from)}「$fromTitle」⇄ ${_md(d)}「${dname(cell.day!.title)}」',
                en: 'Swapped: ${_md(from)} "$fromTitle" ⇄ ${_md(d)} "${dname(cell.day!.title)}"');
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text(msg),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: tx('撤销', en: 'Undo'),
              onPressed: () async {
                messenger.hideCurrentSnackBar();
                if (!mounted) return;
                final c2 = app(context);
                await c2.planRepo.moveScheduleDay(widget.plan, d, from);
                widget.onChanged();
                await _reload();
              },
            ),
          ));
      },
      // 悬停高亮：琥珀＝目标有训练（将互换），绿＝空日期（将移动）。
      // 用 Stack 叠边框而不是改格子本体，避免影响原有布局尺寸。
      builder: (ctx, cand, _) {
        final hovering = cand.isNotEmpty;
        final hl = cell.day != null ? AppTheme.warn : AppTheme.primary;
        return Stack(children: [
          child,
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: hovering ? hl.withValues(alpha: 0.10) : null,
                  border:
                      Border.all(color: hovering ? hl : Colors.transparent, width: 2),
                ),
              ),
            ),
          ),
        ]);
      },
    );
    if (cell.day != null) {
      w = LongPressDraggable<DateTime>(
        data: d,
        delay: const Duration(milliseconds: 120),
        feedback: Material(
          color: Colors.transparent,
          child: Chip(
            backgroundColor: AppTheme.primary,
            label: Text(
              dname(cell.day!.title),
              style: const TextStyle(
                  color: Color(0xFF06220F), fontWeight: FontWeight.w700),
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.35, child: child),
        onDragStarted: () => HapticFeedback.mediumImpact(),
        child: GestureDetector(onTap: () => _showDaySheet(d, cell), child: w),
      );
    } else {
      w = GestureDetector(onTap: () => _showDaySheet(d, cell), child: w);
    }
    return w;
  }

  // ---------------- 日期操作菜单 ----------------

  Future<void> _showDaySheet(DateTime d, _CellData cell) async {
    final c = app(context);
    final plan = widget.plan;
    final templates = _templates ?? await c.db.planDays(plan.id!);
    final dateLabel =
        tx('${d.month}月${d.day}日', en: '${d.month}/${d.day}');
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
            Text('$dateLabel · ${cell.day != null ? dname(cell.day!.title) : tx('休息', en: 'Rest')}',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              cell.overridden
                  ? tx('这天有手动调整（会覆盖计划规则）',
                      en: 'Manually adjusted (overrides plan rules)')
                  : tx('这天按计划规则自动排的',
                      en: 'Scheduled automatically by the plan'),
              style: const TextStyle(color: AppTheme.textDim, fontSize: 12),
            ),
            const SizedBox(height: 8),
            if (cell.day != null) ...[
              ListTile(
                leading:
                    const Icon(Icons.edit_calendar, color: AppTheme.primary),
                title: Text(tx('编辑这天的动作', en: "Edit This Day's Exercises")),
                onTap: () async {
                  Navigator.pop(ctx);
                  final changed = await Navigator.of(context).push(
                    MaterialPageRoute<bool>(
                        builder: (_) =>
                            PlanEditorPage(day: cell.day!)),
                  );
                  if (changed == true) {
                    widget.onChanged();
                    await _reload();
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.arrow_forward),
                title: Text(tx('延后到明天', en: 'Move to Tomorrow')),
                onTap: () => _move(ctx, d, d.add(const Duration(days: 1))),
              ),
              ListTile(
                leading: const Icon(Icons.arrow_back),
                title: Text(tx('提前到昨天', en: 'Move to Yesterday')),
                onTap: () =>
                    _move(ctx, d, d.subtract(const Duration(days: 1))),
              ),
              ListTile(
                leading: const Icon(Icons.event_busy, color: AppTheme.warn),
                title: Text(tx('这天改成休息', en: 'Make This a Rest Day')),
                onTap: () async {
                  Navigator.pop(ctx);
                  await c.planRepo.setOverride(plan, d, null);
                  widget.onChanged();
                  await _reload();
                },
              ),
            ] else ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(tx('从模板日里挑一个放到这天：',
                    en: 'Pick a template day to place here:'),
                    style:
                        const TextStyle(color: AppTheme.textDim, fontSize: 13)),
              ),
              for (final t in templates)
                ListTile(
                  leading: const Icon(Icons.fitness_center,
                      color: AppTheme.primary),
                  title: Text(dname(t.title)),
                  subtitle: Text(
                      tx('模板 · 周${'一二三四五六日'[t.weekday - 1]}',
                          en:
                              'Template · ${_weekdayEn['一二三四五六日'[t.weekday - 1]]}'),
                      style: const TextStyle(fontSize: 12)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await c.planRepo.setOverride(plan, d, t.id);
                    widget.onChanged();
                    await _reload();
                  },
                ),
            ],
            if (cell.overridden)
              ListTile(
                leading: const Icon(Icons.settings_backup_restore),
                title: Text(tx('清除自定义（跟随计划规则）',
                    en: 'Clear Custom (Follow Plan)')),
                onTap: () async {
                  Navigator.pop(ctx);
                  await c.planRepo.clearOverride(plan, d);
                  widget.onChanged();
                  await _reload();
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _move(BuildContext sheetCtx, DateTime from, DateTime to) async {
    Navigator.pop(sheetCtx);
    final c = app(context);
    await c.planRepo.moveScheduleDay(widget.plan, from, to);
    widget.onChanged();
    await _reload();
    if (mounted) {
      toast(context,
          tx('已${to.isAfter(from) ? '延后' : '提前'}到 ${to.month}/${to.day}',
              en: '${to.isAfter(from) ? 'Postponed to' : 'Moved up to'} ${to.month}/${to.day}'));
    }
  }
}
