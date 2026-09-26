import 'package:flutter/material.dart';

import '../engine/engine.dart';
import '../l10n/lang.dart';
import '../l10n/names.dart';
import '../presets/exercise_library.dart';
import 'theme.dart';
import 'widgets/common.dart';

/// 动作库浏览页：按肌群分组的内置动作表，含器械场景（健身房/居家/皆可）
/// 与次级肌群。给编排计划时参考，也是"这个动作练哪"的速查表。
class ExerciseLibraryPage extends StatefulWidget {
  const ExerciseLibraryPage({super.key});

  @override
  State<ExerciseLibraryPage> createState() => _ExerciseLibraryPageState();
}

class _ExerciseLibraryPageState extends State<ExerciseLibraryPage> {
  bool _loading = true;
  List<ExerciseMeta> _metas = [];
  String _filter = '全部'; // 全部 / 肌群 / 场景

  static const _filters = ['全部', ...kMuscleRegions, '健身房', '居家'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final c = app(context);
    // 词表为准（内置库含全部动作），叠加用户沉淀的词表外动作
    final fromDb = await c.db.allExerciseMeta();
    final known = {for (final m in kExerciseLibrary) m.name};
    _metas = [
      ...kExerciseLibrary,
      ...fromDb.where((m) => !known.contains(m.name)),
    ];
    if (!mounted) return;
    setState(() => _loading = false);
  }

  List<ExerciseMeta> get _filtered {
    if (_filter == '全部') return _metas;
    if (_filter == '健身房') {
      return _metas.where((m) => m.equipment != 'home').toList();
    }
    if (_filter == '居家') {
      return _metas.where((m) => m.equipment != 'gym').toList();
    }
    return _metas.where((m) => m.muscles.main == _filter).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: Text(tx('动作库', en: 'Exercise Library'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 筛选
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Row(
                    children: [
                      for (final f in _filters)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(
                                f == '全部'
                                    ? tx('全部', en: 'All')
                                    : f == '健身房'
                                        ? tx('健身房', en: 'Gym')
                                        : f == '居家'
                                            ? tx('居家', en: 'Home')
                                            : mname(f), // 肌群名是数据，显示层翻译
                                style: const TextStyle(fontSize: 12)),
                            selected: _filter == f,
                            onSelected: (_) => setState(() => _filter = f),
                            labelStyle: TextStyle(
                                fontSize: 12,
                                color: _filter == f
                                    ? const Color(0xFF06220F)
                                    : AppTheme.text),
                            selectedColor: AppTheme.primary,
                            backgroundColor: AppTheme.cardHi,
                            side: BorderSide.none,
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    itemCount: _filtered.length,
                    itemBuilder: (ctx, i) {
                      final m = _filtered[i];
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _showDetail(m),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(exname(m.name),
                                          style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 2),
                                      Text(
                                        tx(
                                          '主练 ${mname(m.muscles.main)}'
                                          '${m.muscles.secondary.isEmpty ? '' : ' · 兼练 ${m.muscles.secondary.map(mname).join('/')}'}'
                                          ' · ${m.isCompound ? '复合' : '单关节'}',
                                          en: 'Main ${mname(m.muscles.main)}'
                                              '${m.muscles.secondary.isEmpty ? '' : ' · Secondary ${m.muscles.secondary.map(mname).join('/')}'}'
                                              ' · ${m.isCompound ? 'Compound' : 'Isolation'}',
                                        ),
                                        style: const TextStyle(
                                            color: AppTheme.textDim,
                                            fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                                _equipmentTag(m),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _equipmentTag(ExerciseMeta m) {
    final color = switch (m.equipment) {
      'gym' => AppTheme.accent,
      'home' => AppTheme.warn,
      _ => AppTheme.textDim,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(eqname(m.equipmentLabel),
          style: TextStyle(fontSize: 11, color: color)),
    );
  }

  /// 动作详情：元信息 + 历史最佳（1RM/最大重量）+ 最近几次训练记录。
  Future<void> _showDetail(ExerciseMeta m) async {
    final c = app(context);
    final rows = await c.db.sessionRowsBetween(
        '0000-01-01', fmtDate(DateTime.now()));
    // 该动作按日期分组的正式组（同一 session 只取一次日期）
    final byDate = <String, List<SetEntry>>{};
    var curSid = -1;
    var curDate = '';
    double bestRm = 0, bestW = 0;
    String bestRmDesc = '';
    for (final r in rows) {
      if ((r['name'] as String?) != m.name) continue;
      final sid = (r['session_id'] as num).toInt();
      if (sid != curSid) {
        curSid = sid;
        curDate = (r['date'] as String?) ?? '';
      }
      final w = (r['weight_kg'] as num?)?.toDouble();
      final reps = (r['reps'] as num?)?.toInt();
      if (w == null || reps == null) continue;
      if (((r['kind'] as String?) ?? '') != SetKind.working) continue;
      byDate.putIfAbsent(curDate, () => []).add(SetEntry(
        sessionExerciseId: 0,
        weightKg: w,
        reps: reps,
        rir: (r['rir'] as num?)?.toInt() ?? 2,
        kind: SetKind.working,
        doneAt: (r['done_at'] as num?)?.toInt() ?? 0,
      ));
      final rm = estimate1RM(w, reps);
      if (rm > bestRm) {
        bestRm = rm;
        bestRmDesc =
            tx('${fmtKg(w)}kg × $reps 次', en: '${fmtKg(w)}kg × $reps reps');
      }
      if (w > bestW) bestW = w;
    }
    final dates = byDate.keys.toList()..sort((a, b) => b.compareTo(a));
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
            Text(exname(m.name),
                style: const TextStyle(
                    fontSize: 19, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              tx(
                '主练 ${mname(m.muscles.main)}'
                '${m.muscles.secondary.isEmpty ? '' : ' · 兼练 ${m.muscles.secondary.map(mname).join('/')}'}'
                ' · ${m.isCompound ? '复合动作' : '单关节动作'} · ${eqname(m.equipmentLabel)}',
                en: 'Main ${mname(m.muscles.main)}'
                    '${m.muscles.secondary.isEmpty ? '' : ' · Secondary ${m.muscles.secondary.map(mname).join('/')}'}'
                    ' · ${m.isCompound ? 'Compound' : 'Isolation'} · ${eqname(m.equipmentLabel)}',
              ),
              style: const TextStyle(color: AppTheme.textDim, fontSize: 13),
            ),
            const SizedBox(height: 14),
            if (dates.isEmpty)
              Text(
                  tx('还没练过这个动作——加进计划后，这里会显示历史最好成绩。',
                      en: 'Never trained this exercise yet — add it to a plan and your bests will show up here.'),
                  style: const TextStyle(color: AppTheme.textDim))
            else ...[
              Row(children: [
                _bestCell(tx('估算 1RM', en: 'Est. 1RM'), '${fmtKg(bestRm)}kg'),
                _bestCell(tx('最佳一组', en: 'Best set'), bestRmDesc),
                _bestCell(tx('最大重量', en: 'Max weight'), '${fmtKg(bestW)}kg'),
              ]),
              const SizedBox(height: 14),
              Text(tx('最近训练', en: 'Recent Workouts'),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              for (final d in dates.take(3))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text(
                    tx(
                        '$d：${byDate[d]!.map((x) => '${fmtKg(x.weightKg)}×${x.reps}').join('  ')}',
                        en: '$d: ${byDate[d]!.map((x) => '${fmtKg(x.weightKg)}×${x.reps}').join('  ')}'),
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              if (dates.length > 3)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                      tx('共 ${dates.length} 次练过，更多见历史页',
                          en: 'Trained ${dates.length} times in total — see History for more'),
                      style: const TextStyle(
                          color: AppTheme.textDim, fontSize: 12)),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _bestCell(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value,
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primary)),
          ),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(color: AppTheme.textDim, fontSize: 12)),
        ],
      ),
    );
  }
}
