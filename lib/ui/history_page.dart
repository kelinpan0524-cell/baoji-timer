import 'package:flutter/material.dart';

import '../engine/engine.dart';
import '../l10n/lang.dart';
import '../l10n/names.dart';
import 'theme.dart';
import 'widgets/common.dart';

/// 日历表头星期缩写（仅展示用；中文单字为键）。
const _weekdayEn = {
  '一': 'Mon',
  '二': 'Tue',
  '三': 'Wed',
  '四': 'Thu',
  '五': 'Fri',
  '六': 'Sat',
  '日': 'Sun',
};

/// 历史页：月历 + 当日训练明细。
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);
  Map<String, List<Session>> _byDate = {};
  bool _loading = true;
  String? _selected;
  // 明细 future 按 session id 缓存：点日期切换不再重查全部卡片
  final Map<int, Future<List<Widget>>> _detailFutures = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final c = app(context);
    final first = _month;
    final last = DateTime(_month.year, _month.month + 1, 0);
    final sessions = await c.db.sessionsBetween(fmtDate(first), fmtDate(last));
    final map = <String, List<Session>>{};
    for (final s in sessions) {
      map.putIfAbsent(s.date, () => []).add(s);
    }
    if (!mounted) return;
    setState(() {
      _byDate = map;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final firstWeekday = DateTime(_month.year, _month.month, 1).weekday;
    final today = fmtDate(DateTime.now());

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: () {
                setState(() {
                  _month = DateTime(_month.year, _month.month - 1, 1);
                  _selected = null; // 切月清空选中，避免跨月残留
                  _loading = true;
                });
                _load();
              },
              icon: const Icon(Icons.chevron_left),
            ),
            const SizedBox(width: 8),
            Text(
              tx('${_month.year} 年 ${_month.month} 月',
                  en: '${_month.year}-${_month.month}'),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: () {
                setState(() {
                  _month = DateTime(_month.year, _month.month + 1, 1);
                  _selected = null;
                  _loading = true;
                });
                _load();
              },
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    for (final w in ['一', '二', '三', '四', '五', '六', '日'])
                      Expanded(
                        child: Center(
                          child: Text(
                            tx('周$w', en: _weekdayEn[w]),
                            style: const TextStyle(
                              color: AppTheme.textDim,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                ..._calendarRows(daysInMonth, firstWeekday, today),
                const SizedBox(height: 6),
                Text(
                  tx('点日期看当天明细 · 长按下方训练卡可删除误记的记录',
                      en: 'Tap a date for details · Long-press a workout card below to delete it'),
                  style: const TextStyle(color: AppTheme.textDim, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        ..._dayDetailSections(),
      ],
    );
  }

  List<Widget> _calendarRows(int daysInMonth, int firstWeekday, String today) {
    final rows = <Widget>[];
    var cell = 1 - (firstWeekday - 1);
    while (cell <= daysInMonth) {
      final cells = <Widget>[];
      for (var i = 0; i < 7; i++, cell++) {
        if (cell < 1 || cell > daysInMonth) {
          cells.add(const Expanded(child: SizedBox(height: 44)));
          continue;
        }
        final d = fmtDate(DateTime(_month.year, _month.month, cell));
        final has = _byDate.containsKey(d);
        final isToday = d == today;
        cells.add(
          Expanded(
            child: GestureDetector(
              onTap: has ? () => _selectDate(d) : null,
              child: Container(
                height: 44,
                margin: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: has
                      ? AppTheme.primary.withValues(alpha: 0.18)
                      : (isToday ? AppTheme.cardHi : null),
                  borderRadius: BorderRadius.circular(10),
                  border: isToday
                      ? Border.all(color: AppTheme.accent, width: 1)
                      : null,
                ),
                child: Center(
                  child: Text(
                    '$cell',
                    style: TextStyle(
                      color: has
                          ? AppTheme.primary
                          : (isToday ? AppTheme.accent : AppTheme.textDim),
                      fontWeight: has || isToday ? FontWeight.w700 : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }
      rows.add(Row(children: cells));
    }
    return rows;
  }

  void _selectDate(String d) {
    setState(() => _selected = d);
  }

  List<Widget> _dayDetailSections() {
    final dates = (_selected != null) ? [_selected!] : _byDate.keys.toList()
      ..sort((a, b) => b.compareTo(a));
    final out = <Widget>[];
    for (final date in dates.take(_selected == null ? 10 : 1)) {
      final sessions = _byDate[date];
      if (sessions == null) continue;
      for (final s in sessions) {
        out.add(_sessionCard(s));
      }
    }
    if (out.isEmpty) {
      out.add(
        Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text(tx('本月还没有训练记录', en: 'No workouts logged this month yet'),
                style: const TextStyle(color: AppTheme.textDim)),
          ),
        ),
      );
    }
    return out;
  }

  Widget _sessionCard(Session s) {
    return FutureBuilder<List<Widget>>(
      future: _detailFutures.putIfAbsent(s.id!, () => _sessionDetailWidgets(s)),
      builder: (context, snap) {
        return SectionCard(
          title: '${s.date} · ${dname(s.planDayTitle)}',
          trailing: Text(
            s.status == 'quit'
                ? tx('已中断', en: 'Interrupted')
                : tx('${s.durationMin} 分钟', en: '${s.durationMin} min'),
            style: const TextStyle(color: AppTheme.textDim, fontSize: 13),
          ),
          // 长按删除误开的训练（配合训练页"放弃本次"，P1-12）；
          // 读屏语义：标签完整朗读 + "双击并按住"提示作为长按的替代路径
          semanticsLabel: tx(
              '${s.date} ${dname(s.planDayTitle)} 的训练记录${s.status == 'quit' ? '，已中断' : ''}',
              en: 'Workout record: ${s.date} ${dname(s.planDayTitle)}${s.status == 'quit' ? ' (interrupted)' : ''}'),
          longPressHint: tx('双击并按住，删除这条训练记录',
              en: 'Double-tap and hold to delete this workout record'),
          onLongPress: () => _deleteSession(s),
          child: snap.hasData
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: snap.data!,
                )
              : const Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
        );
      },
    );
  }

  /// 长按删除单次训练记录（含全部组记录，不可恢复）。
  Future<void> _deleteSession(Session s) async {
    final ok = await confirmDialog(
      context,
      tx('删除这次训练？', en: 'Delete This Workout?'),
      tx(
          '${s.date} · ${dname(s.planDayTitle)} 的全部记录将被删除，用于清理误开的训练。此操作无法撤销。',
          en: 'All records of ${s.date} · ${dname(s.planDayTitle)} will be deleted, to clean up a workout started by mistake. This cannot be undone.'),
      okLabel: tx('删除', en: 'Delete'),
    );
    if (!ok || !mounted) return;
    final c = app(context);
    await c.db.deleteSession(s.id!);
    _detailFutures.remove(s.id!);
    await _load();
    if (mounted) toast(context, tx('已删除', en: 'Deleted'));
  }

  Future<List<Widget>> _sessionDetailWidgets(Session s) async {
    final c = app(context);
    final ses = await c.db.sessionExercises(s.id!);
    final map = await c.db.setsOfSession(s.id!);
    final widgets = <Widget>[];
    // 训练/休息净时长（新版本记录才有；老记录 rest/active 为 0 不显示）
    if (s.restMs > 0 || s.activeMs > 0) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            tx(
              '训练 ${((s.activeMs) / 60000).ceil()} 分 · 休息 ${((s.restMs) / 60000).ceil()} 分'
              '${s.restMs + s.activeMs > 0 ? '（休息占 ${(s.restMs * 100 / (s.restMs + s.activeMs)).round()}%）' : ''}',
              en: 'Workout ${((s.activeMs) / 60000).ceil()} min · Rest ${((s.restMs) / 60000).ceil()} min'
                  '${s.restMs + s.activeMs > 0 ? ' (rest ${(s.restMs * 100 / (s.restMs + s.activeMs)).round()}%)' : ''}',
            ),
            style: const TextStyle(color: AppTheme.textDim, fontSize: 13),
          ),
        ),
      );
    }
    for (final se in ses) {
      final sets = map[se.id!] ?? [];
      if (sets.isEmpty) continue;
      // 组记录带余力（RIR）：60×8 R2；热身/力竭组沿用 (热)/(竭) 标记
      final desc = sets
          .map(
            (x) =>
                '${fmtKg(x.weightKg)}×${x.reps}${x.kind == SetKind.warmup
                    ? tx('(热)', en: '(W)')
                    : x.kind == SetKind.failure
                    ? tx('(竭)', en: '(F)')
                    : ' R${x.rir}'}',
          )
          .join('  ');
      widgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Text(
            '· ${exname(se.name)}:  $desc',
            style: const TextStyle(fontSize: 14),
          ),
        ),
      );
      // 单组备注逐条带出（记了就要看得到）
      final noted = sets.where((x) => x.note.trim().isNotEmpty).toList();
      if (noted.isNotEmpty) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(left: 14, bottom: 2),
            child: Text(
              tx(
                '备注：${noted.map((x) => '${fmtKg(x.weightKg)}kg：${x.note.trim()}').join('；')}',
                en: 'Notes: ${noted.map((x) => '${fmtKg(x.weightKg)}kg: ${x.note.trim()}').join('; ')}',
              ),
              style: const TextStyle(color: AppTheme.textDim, fontSize: 13),
            ),
          ),
        );
      }
    }
    return widgets;
  }
}
