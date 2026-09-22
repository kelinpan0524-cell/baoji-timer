import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app.dart';
import '../engine/engine.dart';
import '../presets/baoji_plan.dart';
import '../services/ai_service.dart';
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
    final pack = await c.export.buildAiPack();
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

class _BigFour {
  static const lifts = ['杠铃深蹲', '杠铃卧推', '杠铃硬拉', '站姿推举'];
}

class _OverviewTabState extends State<_OverviewTab> {
  String _selectedLift = _BigFour.lifts[1];
  Future<_OverviewData>? _future;

  @override
  void initState() {
    super.initState();
    // 缓存 future：切 chip 等 setState 不再触发全量重查
    _future = _load(app(context));
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
                          titlesData: const FlTitlesData(show: false),
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
              title: '四大项 1RM 进阶',
              child: Column(
                children: [
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final lift in _BigFour.lifts)
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

  /// 单次 JOIN 拉全部明细后内存聚合，避免逐 session 查询的 N+1。
  Future<_OverviewData> _load(AppContainer c) async {
    final now = DateTime.now();
    final from = fmtDate(now.subtract(const Duration(days: 365)));
    final rows = await c.db.sessionRowsBetween(from, fmtDate(now));
    final weekly = <int, double>{}; // 周一epoch天 -> 容量
    final setsByName = <String, List<SetEntry>>{};
    final big4 = <String, List<FlSpot>>{};
    final sessionIds = <int>[];
    for (final lift in _BigFour.lifts) {
      big4[lift] = [];
    }
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
        doneAt: 0,
      );
      final name = (r['name'] as String?) ?? '';
      final date = (r['date'] as String?) ?? '';
      setsByName.putIfAbsent(name, () => []).add(entry);
      if (kind == SetKind.working) {
        final weekKey =
            mondayOf(parseDate(date)).millisecondsSinceEpoch ~/ 86400000;
        weekly[weekKey] = (weekly[weekKey] ?? 0) + entry.volume;
        if (_BigFour.lifts.contains(name)) {
          final rm = estimate1RM(weight, reps);
          final list = big4[name]!;
          final idx = sessionIds.indexOf(sid).toDouble();
          if (list.isEmpty || rm > list.last.y) {
            list.add(FlSpot(idx, rm));
          }
        }
      }
    }
    final keys = weekly.keys.toList()..sort();
    return _OverviewData(
      weeklyVolume: [
        for (var i = 0; i < keys.length; i++)
          FlSpot(i.toDouble(), weekly[keys[i]]!),
      ],
      big4: big4,
      setsByName: setsByName,
    );
  }
}

class _OverviewData {
  final List<FlSpot> weeklyVolume;
  final Map<String, List<FlSpot>> big4;
  final Map<String, List<SetEntry>> setsByName;
  _OverviewData(
      {required this.weeklyVolume, required this.big4, required this.setsByName});
}

// ---------------- 肌肉 ----------------

class _MuscleTab extends StatefulWidget {
  const _MuscleTab();

  @override
  State<_MuscleTab> createState() => _MuscleTabState();
}

class _MuscleTabState extends State<_MuscleTab> {
  late final Future<Map<String, double>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load(app(context));
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
            SectionCard(
              title: '本周肌群容量占比',
              child: Column(
                children: [
                  SizedBox(
                    height: 260,
                    child: CustomPaint(
                      painter: _BodyHeatmapPainter(share),
                      child: const SizedBox.expand(),
                    ),
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
    final metaMap = <String, ExerciseMeta>{};
    // 动作元数据以库内为准（内置 + AI 计划沉淀）
    for (final m in kBaojiExerciseMeta) {
      metaMap[m.name] = m;
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
    );
  }
}

Color _heatColor(double v) {
  // 0 → 深灰，1 → 亮绿
  final t = v.clamp(0.0, 1.0);
  return Color.lerp(const Color(0xFF232B36), AppTheme.primary, t)!;
}

class _BodyHeatmapPainter extends CustomPainter {
  _BodyHeatmapPainter(this.share);

  final Map<String, double> share;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    // 人体分区近似：正面视角，头/胸/肩/臂/背(提示色)/腿/核心
    final w = size.width;
    final h = size.height;

    Rect r(double x, double y, double ww, double hh) =>
        Rect.fromLTWH(x * w, y * h, ww * w, hh * h);

    void drawRegion(String muscle, Rect rect, {double radius = 10}) {
      paint.color = _heatColor(share[muscle] ?? 0);
      canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(radius)), paint);
    }

    // 头
    paint.color = const Color(0xFF232B36);
    canvas.drawCircle(Offset(w * 0.5, h * 0.07), w * 0.08, paint);
    // 肩（左右）
    drawRegion('肩', r(0.24, 0.15, 0.16, 0.10), radius: 14);
    drawRegion('肩', r(0.60, 0.15, 0.16, 0.10), radius: 14);
    // 胸
    drawRegion('胸', r(0.34, 0.15, 0.32, 0.14));
    // 臂（左右）
    drawRegion('手臂', r(0.12, 0.27, 0.10, 0.28), radius: 16);
    drawRegion('手臂', r(0.78, 0.27, 0.10, 0.28), radius: 16);
    // 背（正面看不到，画中上提示）
    drawRegion('背', r(0.36, 0.30, 0.28, 0.10), radius: 12);
    // 核心
    drawRegion('核心', r(0.38, 0.42, 0.24, 0.12));
    // 腿
    drawRegion('腿', r(0.36, 0.56, 0.12, 0.36), radius: 16);
    drawRegion('腿', r(0.52, 0.56, 0.12, 0.36), radius: 16);
    // 其他
    drawRegion('其他', r(0.80, 0.88, 0.001, 0.001), radius: 0);
  }

  @override
  bool shouldRepaint(_BodyHeatmapPainter oldDelegate) =>
      oldDelegate.share != share;
}

// ---------------- 身体 ----------------

class _BodyTab extends StatefulWidget {
  const _BodyTab();

  @override
  State<_BodyTab> createState() => _BodyTabState();
}

class _BodyTabState extends State<_BodyTab> {
  final _weightCtrl = TextEditingController();
  final _waistCtrl = TextEditingController();
  final _fatCtrl = TextEditingController();
  late final Future<List<BodyMetric>> _future;

  @override
  void initState() {
    super.initState();
    _future = app(context).db.bodyMetrics();
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
