import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app.dart';
import '../engine/engine.dart';
import '../presets/exercise_library.dart';
import '../services/ai_service.dart';
import 'muscle_body_view.dart';
import 'recovery_card.dart';
import 'theme.dart';
import 'widgets/common.dart';

/// 数据页：概览 / 肌肉 / 身体 三个 Tab + AI 分析包入口。
class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppTheme.bg,
        appBar: AppBar(
          title: const Text('数据'),
          actions: [
            TextButton.icon(
              onPressed: () => _exportAiPack(),
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text('AI 分析包'),
            ),
          ],
          bottom: const TabBar(
            indicatorColor: AppTheme.primary,
            labelColor: AppTheme.text,
            unselectedLabelColor: AppTheme.textDim,
            tabs: [Tab(text: '概览'), Tab(text: '肌肉'), Tab(text: '身体')],
          ),
        ),
        body: const TabBarView(
          children: [_OverviewTab(), _MuscleTab(), _BodyTab()],
        ),
      ),
    );
  }

  Future<void> _exportAiPack() async {
    final c = app(context);
    final pack = await c.export.buildAiPack(bodyWeightKg: c.settings.bodyWeightKg);
    await c.export.shareText('薄肌训练 · AI 分析包', pack, filename: 'ai_analysis_pack.md');
    // 同时尝试复制到剪贴板
    await Clipboard.setData(ClipboardData(text: pack));
    if (mounted) toast(context, '分析包已生成并复制到剪贴板');
  }
}

// ---------------- 概览 ----------------

class _OverviewTab extends StatefulWidget {
  const _OverviewTab();

  @override
  State<_OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<_OverviewTab> {
  String? _selectedLift;
  Future<_OverviewData>? _future;

  @override
  void initState() {
    super.initState();
    // initState 里不能同步读 InheritedWidget，延后一帧
    // （缓存 future：切 chip 等 setState 不再触发全量重查）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _future = _load(app(context)));
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_OverviewData>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final d = snap.data!;
        if (d.weeklyVolume.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.insights, size: 48, color: AppTheme.textDim),
                SizedBox(height: 12),
                Text('完成第一次训练后，这里会显示进步曲线',
                    style: TextStyle(color: AppTheme.textDim)),
              ],
            ),
          );
        }
        final insights = localInsights(d.setsByName);
        // 所选动作不在本年度数据里（如新装/换计划）时重置到容量第一的动作
        if (d.topLifts.isEmpty) {
          _selectedLift = null;
        } else if (!_selectedLiftIn(d)) {
          _selectedLift = d.topLifts.first;
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            SectionCard(
              title: '每周训练容量（kg）',
              child: SizedBox(
                height: 200,
                child: d.weeklyVolume.length < 2
                    ? Center(
                        child: Text('数据还少，再练几次就能看到趋势',
                            style: TextStyle(color: AppTheme.textDim)))
                    : LineChart(
                        LineChartData(
                          gridData: const FlGridData(show: false),
                          borderData: FlBorderData(show: false),
                          titlesData: FlTitlesData(
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 22,
                                getTitlesWidget: (v, _) =>
                                    _weekLabel(d, v.toInt()),
                              ),
                            ),
                          ),
                          lineBarsData: [
                            LineChartBarData(
                              spots: d.weeklyVolume,
                              isCurved: true,
                              color: AppTheme.primary,
                              barWidth: 3,
                              dotData: const FlDotData(show: true),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            SectionCard(
              title: '主力动作 1RM 进阶（按训练容量自动选前 4）',
              child: Column(
                children: [
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final lift in d.topLifts)
                        ChoiceChip(
                          label: Text(lift),
                          selected: _selectedLift == lift,
                          onSelected: (_) =>
                              setState(() => _selectedLift = lift),
                          labelStyle: TextStyle(
                              color: _selectedLift == lift
                                  ? const Color(0xFF06220F)
                                  : AppTheme.text),
                          selectedColor: AppTheme.primary,
                          backgroundColor: AppTheme.cardHi,
                          side: BorderSide.none,
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 200,
                    child: (d.big4[_selectedLift] ?? []).length < 2
                        ? Center(
                            child: Text('$_selectedLift 数据不足（至少 2 次）',
                                style:
                                    TextStyle(color: AppTheme.textDim)))
                        : LineChart(
                            LineChartData(
                              gridData: const FlGridData(show: false),
                              borderData: FlBorderData(show: false),
                              titlesData: const FlTitlesData(show: false),
                              lineBarsData: [
                                LineChartBarData(
                                  spots: d.big4[_selectedLift]!,
                                  isCurved: false,
                                  color: AppTheme.accent,
                                  barWidth: 3,
                                  dotData: const FlDotData(show: true),
                                ),
                              ],
                            ),
                          ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SectionCard(
              title: '组间休息趋势（分钟 / 次）',
              child: SizedBox(
                height: 180,
                child: d.restMinutes.length < 2
                    ? const Center(
                        child: Text('完成几次训练后，这里显示每次训练的休息总时长趋势',
                            style: TextStyle(color: AppTheme.textDim)))
                    : LineChart(
                        LineChartData(
                          gridData: const FlGridData(show: false),
                          borderData: FlBorderData(show: false),
                          titlesData: FlTitlesData(
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 22,
                                getTitlesWidget: (v, _) =>
                                    _restLabel(d, v.toInt()),
                              ),
                            ),
                          ),
                          lineBarsData: [
                            LineChartBarData(
                              spots: d.restMinutes,
                              isCurved: true,
                              color: AppTheme.warn,
                              barWidth: 3,
                              dotData: const FlDotData(show: true),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
            if (insights.isNotEmpty) ...[
              const SizedBox(height: 12),
              SectionCard(
                title: '智能提醒',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final i in insights)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text('⚠️ $i',
                            style:
                                const TextStyle(color: AppTheme.warn)),
                      ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  bool _selectedLiftIn(_OverviewData d) => d.topLifts.contains(_selectedLift);

  /// 周容量 x 轴刻度：约 5 个日期标签，避免拥挤
  Widget _weekLabel(_OverviewData d, int i) {
    if (i < 0 || i >= d.weekKeys.length) return const SizedBox.shrink();
    final step = (d.weekKeys.length / 5).ceil();
    if (i % step != 0 && i != d.weekKeys.length - 1) {
      return const SizedBox.shrink();
    }
    final dt = DateTime.fromMillisecondsSinceEpoch(d.weekKeys[i] * 86400000);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text('${dt.month}/${dt.day}',
          style: const TextStyle(color: AppTheme.textDim, fontSize: 10)),
    );
  }

  /// 组间休息趋势的 x 轴日期标签（约 5 个，避免拥挤）
  Widget _restLabel(_OverviewData d, int i) {
    if (i < 0 || i >= d.restDates.length) return const SizedBox.shrink();
    final step = (d.restDates.length / 5).ceil();
    if (i % step != 0 && i != d.restDates.length - 1) {
      return const SizedBox.shrink();
    }
    final dt = parseDate(d.restDates[i]);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text('${dt.month}/${dt.day}',
          style: const TextStyle(color: AppTheme.textDim, fontSize: 10)),
    );
  }

  /// 单次 JOIN 拉全部明细后内存聚合，避免逐 session 查询的 N+1。
  Future<_OverviewData> _load(AppContainer c) async {
    final now = DateTime.now();
    final from = fmtDate(now.subtract(const Duration(days: 365)));
    final rows = await c.db.sessionRowsBetween(from, fmtDate(now));
    // 自重容量折算（点名条目二）：引体/俯卧撑类按 系数×体重 计入容量；
    // 体重未设（0）时自动回旧口径（自重记 0）。
    final bodyWeight = c.settings.bodyWeightKg;
    // 休息趋势：按会话取休息净时长（老记录为 0 跳过）
    final sessionsForRest = await c.db.sessionsBetween(from, fmtDate(now));
    final restMinutes = <FlSpot>[];
    final restDates = <String>[];
    for (var i = 0; i < sessionsForRest.length; i++) {
      final s = sessionsForRest[i];
      if (s.restMs <= 0) continue;
      restMinutes.add(FlSpot(restMinutes.length.toDouble(), s.restMs / 60000));
      restDates.add(s.date);
    }
    final weekly = <int, double>{}; // 周一epoch天 -> 容量
    final setsByName = <String, List<SetEntry>>{};
    final big4 = <String, List<FlSpot>>{};
    final sessionIds = <int>[];
    var curSession = -1;
    for (final r in rows) {
      final sid = (r['session_id'] as num).toInt();
      if (sid != curSession) {
        curSession = sid;
        sessionIds.add(sid);
      }
      final weight = (r['weight_kg'] as num?)?.toDouble();
      final reps = (r['reps'] as num?)?.toInt();
      if (weight == null || reps == null) continue; // 无组的动作行
      final kind = (r['kind'] as String?) ?? SetKind.working;
      final entry = SetEntry(
        sessionExerciseId: (r['se_id'] as num).toInt(),
        weightKg: weight,
        reps: reps,
        rir: (r['rir'] as num?)?.toInt() ?? 2,
        kind: kind,
        doneAt: (r['done_at'] as num?)?.toInt() ?? 0,
      );
      final name = (r['name'] as String?) ?? '';
      final date = (r['date'] as String?) ?? '';
      setsByName.putIfAbsent(name, () => []).add(entry);
      if (kind == SetKind.working) {
        final weekKey =
            mondayOf(parseDate(date)).millisecondsSinceEpoch ~/ 86400000;
        weekly[weekKey] = (weekly[weekKey] ?? 0) +
            setVolumeWithBodyweight(entry,
                exerciseName: name, bodyWeightKg: bodyWeight);
        // 所有动作都算 1RM 序列，"主力动作"由容量排序动态选出
        final rm = estimate1RM(weight, reps);
        final list = big4.putIfAbsent(name, () => <FlSpot>[]);
        final idx = sessionIds.indexOf(sid).toDouble();
        if (list.isEmpty || rm > list.last.y) {
          list.add(FlSpot(idx, rm));
        }
      }
    }
    final keys = weekly.keys.toList()..sort();
    // 主力动作 = 近一年正式组容量前 4（不再写死杠铃四大项名）
    final volumeByName = <String, double>{};
    for (final e in setsByName.entries) {
      volumeByName[e.key] = e.value
          .where((s) => s.kind == SetKind.working)
          .fold(
              0.0,
              (a, b) => a + setVolumeWithBodyweight(b,
                  exerciseName: e.key, bodyWeightKg: bodyWeight));
    }
    final topLifts = volumeByName.keys.where((k) => volumeByName[k]! > 0)
        .toList()
      ..sort((a, b) => volumeByName[b]!.compareTo(volumeByName[a]!));
    return _OverviewData(
      weeklyVolume: [
        for (var i = 0; i < keys.length; i++)
          FlSpot(i.toDouble(), weekly[keys[i]]!),
      ],
      weekKeys: keys,
      topLifts: topLifts.take(4).toList(),
      restMinutes: restMinutes,
      restDates: restDates,
      big4: big4,
      setsByName: setsByName,
    );
  }
}

class _OverviewData {
  final List<FlSpot> weeklyVolume;

  /// 与 weeklyVolume 下标对应的周一（epoch 天），供 x 轴日期标签用
  final List<int> weekKeys;

  /// 近一年正式组容量前 4 的动作名（动态"四大项"）
  final List<String> topLifts;

  /// 每次训练的休息净时长（分钟，老记录为空）+ 对应日期
  final List<FlSpot> restMinutes;
  final List<String> restDates;
  final Map<String, List<FlSpot>> big4;
  final Map<String, List<SetEntry>> setsByName;
  _OverviewData({
    required this.weeklyVolume,
    required this.weekKeys,
    required this.topLifts,
    required this.restMinutes,
    required this.restDates,
    required this.big4,
    required this.setsByName,
  });
}

// ---------------- 肌肉 ----------------

class _MuscleTab extends StatefulWidget {
  const _MuscleTab();

  @override
  State<_MuscleTab> createState() => _MuscleTabState();
}

class _MuscleTabState extends State<_MuscleTab> {
  Future<Map<String, double>>? _future;
  bool _front = true;

  @override
  void initState() {
    super.initState();
    // initState 里不能同步读 InheritedWidget，延后一帧
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _future = _load(app(context)));
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, double>>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final share = snap.data!;
        final total = share.values.fold(0.0, (a, b) => a + b);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            // 肌群恢复度（点名条目四）：只进计划页/统计页，不进训练中三要素
            const MuscleRecoveryCard(),
            SectionCard(
              title: '本周肌群容量占比',
              child: Column(
                children: [
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('正面')),
                      ButtonSegment(value: false, label: Text('背面')),
                    ],
                    selected: {_front},
                    onSelectionChanged: (sel) =>
                        setState(() => _front = sel.first),
                    showSelectedIcon: false,
                    style: ButtonStyle(
                      backgroundColor:
                          WidgetStateProperty.resolveWith((states) =>
                              states.contains(WidgetState.selected)
                                  ? AppTheme.primary
                                  : AppTheme.cardHi),
                      foregroundColor:
                          WidgetStateProperty.resolveWith((states) =>
                              states.contains(WidgetState.selected)
                                  ? const Color(0xFF06220F)
                                  : AppTheme.textDim),
                      side: const WidgetStatePropertyAll(
                          BorderSide(color: Colors.transparent)),
                      shape: const WidgetStatePropertyAll(
                          RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.all(Radius.circular(10)))),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 300,
                    child: MuscleBodyView(share: share, front: _front),
                  ),
                  const SizedBox(height: 16),
                  ...kMuscleRegions.map((r) {
                    final v = share[r] ?? 0;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          SizedBox(
                              width: 44,
                              child: Text(r,
                                  style: const TextStyle(fontSize: 14))),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: total == 0 ? 0 : v,
                                minHeight: 10,
                                backgroundColor: AppTheme.cardHi,
                                valueColor: AlwaysStoppedAnimation(
                                    _heatColor(total == 0 ? 0 : v)),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 52,
                            child: Text('${(v * 100).toStringAsFixed(0)}%',
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                    color: AppTheme.textDim, fontSize: 13)),
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  if ((share['肩'] ?? 0) < 0.15 || (share['背'] ?? 0) < 0.15)
                    const Text(
                        '提示：肩、背容量偏低——薄肌计划的目标是肩背偏重，注意补齐。',
                        style: TextStyle(color: AppTheme.warn, fontSize: 13)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Future<Map<String, double>> _load(AppContainer c) async {
    final monday = mondayOf(DateTime.now());
    final sessions = await c.db
        .sessionsBetween(fmtDate(monday), fmtDate(DateTime.now()));
    final metaMap = {for (final m in kExerciseLibrary) m.name: m};
    // 内置词表 + DB 沉淀合并（与动作库页同口径）：
    // AI 计划/编辑器沉淀的词表外动作才能在热力图与占比里正确归类
    final known = metaMap.keys.toSet();
    for (final m in await c.db.allExerciseMeta()) {
      if (!known.contains(m.name)) metaMap[m.name] = m;
    }
    final byName = <String, List<SetEntry>>{};
    for (final s in sessions) {
      final ses = await c.db.sessionExercises(s.id!);
      final map = await c.db.setsOfSession(s.id!);
      for (final se in ses) {
        byName.putIfAbsent(se.name, () => []).addAll(map[se.id!] ?? []);
      }
    }
    return muscleLoadShare(
      byName.entries
          .map((e) => MapEntry(
              e.key, e.value.where((x) => x.kind == SetKind.working).toList()))
          .toList(),
      metaMap,
      bodyWeightKg: c.settings.bodyWeightKg,
    );
  }
}

Color _heatColor(double v) {
  // 0 → 深灰，1 → 亮绿
  final t = v.clamp(0.0, 1.0);
  return Color.lerp(const Color(0xFF232B36), AppTheme.primary, t)!;
}
// ---------------- 身体 ----------------

class _BodyTab extends StatefulWidget {
  const _BodyTab();

  @override
  State<_BodyTab> createState() => _BodyTabState();
}

class _BodyTabState extends State<_BodyTab>
    with AutomaticKeepAliveClientMixin {
  final _weightCtrl = TextEditingController();
  final _waistCtrl = TextEditingController();
  final _fatCtrl = TextEditingController();
  Future<List<BodyMetric>>? _future;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // initState 里不能同步读 InheritedWidget，延后一帧
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _future = app(context).db.bodyMetrics());
    });
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    _waistCtrl.dispose();
    _fatCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin 必需
    final c = app(context);
    return FutureBuilder<List<BodyMetric>>(
      future: _future,
      builder: (context, snap) {
        final data = snap.data ?? const <BodyMetric>[];
        final weights = <FlSpot>[];
        for (var i = 0; i < data.length; i++) {
          if (data[i].weightKg != null) {
            weights.add(FlSpot(i.toDouble(), data[i].weightKg!));
          }
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            SectionCard(
              title: '体重趋势',
              child: SizedBox(
                height: 180,
                child: weights.length < 2
                    ? const Center(
                        child: Text('每周固定时间记一次体重',
                            style: TextStyle(color: AppTheme.textDim)))
                    : LineChart(
                        LineChartData(
                          gridData: const FlGridData(show: false),
                          borderData: FlBorderData(show: false),
                          titlesData: const FlTitlesData(show: false),
                          lineBarsData: [
                            LineChartBarData(
                              spots: weights,
                              isCurved: true,
                              color: AppTheme.accent,
                              barWidth: 3,
                            ),
                          ],
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            SectionCard(
              title: '记录今天',
              child: Column(
                children: [
                  TextField(
                    controller: _weightCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: '体重 (kg)'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _waistCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: '腰围 (cm，可选)'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _fatCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: '体脂率 (%，可选)'),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () async {
                      final w = double.tryParse(_weightCtrl.text);
                      final waist = double.tryParse(_waistCtrl.text);
                      final fat = double.tryParse(_fatCtrl.text);
                      if (w == null && waist == null && fat == null) {
                        toast(this.context, '至少填一项');
                        return;
                      }
                      await c.db.upsertBodyMetric(BodyMetric(
                        date: fmtDate(DateTime.now()),
                        weightKg: w,
                        waistCm: waist,
                        bodyFatPct: fat,
                      ));
                      _weightCtrl.clear();
                      _waistCtrl.clear();
                      _fatCtrl.clear();
                      if (mounted) {
                        toast(this.context, '已记录');
                        setState(() => _future = app(this.context).db.bodyMetrics());
                      }
                    },
                    child: const Text('保存'),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
