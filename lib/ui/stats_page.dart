import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app.dart';
import '../engine/engine.dart';
import '../l10n/lang.dart';
import '../l10n/names.dart';
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
          title: Text(tx('数据', en: 'Stats')),
          actions: [
            TextButton.icon(
              onPressed: () => _exportAiPack(),
              icon: const Icon(Icons.ios_share, size: 18),
              label: Text(tx('分析包', en: 'Analysis Pack')),
            ),
          ],
          bottom: TabBar(
            indicatorColor: AppTheme.primary,
            labelColor: AppTheme.text,
            unselectedLabelColor: AppTheme.textDim,
            tabs: [
              Tab(text: tx('概览', en: 'Overview')),
              Tab(text: tx('肌肉', en: 'Muscles')),
              Tab(text: tx('身体', en: 'Body')),
            ],
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
    final pack = await c.export.buildAiPack(
        bodyWeightKg: c.settings.bodyWeightKg, planRepo: c.planRepo);
    await c.export.shareText(
        tx('薄肌训练 · AI 分析包', en: 'Baoji · AI Analysis Pack'),
        pack,
        filename: 'ai_analysis_pack.md');
    // 同时尝试复制到剪贴板
    await Clipboard.setData(ClipboardData(text: pack));
    if (mounted) {
      toast(context,
          tx('分析包已生成并复制到剪贴板',
              en: 'Analysis pack generated and copied to clipboard'));
    }
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

  /// 训练趋势卡（wger 统计维度借鉴）：周/月粒度 × 容量/组数/强度指标
  String _granularity = 'week';
  String _metric = 'volume';

  @override
  void initState() {
    super.initState();
    // initState 里不能同步读 InheritedWidget，延后一帧
    // （缓存 future：切 chip 等 setState 不再触发全量重查）
    // setState 块体写法：箭头闭包会把 Future 返回给 setState，
    // debug 断言直接抛「callback argument returned a Future」
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _future = _load(app(context));
        });
      }
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
        if (d.weekTrend.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.insights, size: 48, color: AppTheme.textDim),
                const SizedBox(height: 12),
                Text(tx('完成第一次训练后，这里会显示进步曲线',
                    en: 'Progress curves appear after your first workout'),
                    style: const TextStyle(color: AppTheme.textDim)),
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
              // 统计维度升级（wger 借鉴）：周/月粒度 × 容量/组数/强度一图切换
              title: tx(
                  _granularity == 'week' ? '训练趋势（周）' : '训练趋势（月）',
                  en: _granularity == 'week'
                      ? 'Training Trend (weekly)'
                      : 'Training Trend (monthly)'),
              child: Column(
                children: [
                  Row(
                    children: [
                      SegmentedButton<String>(
                        segments: [
                          ButtonSegment(
                              value: 'week', label: Text(tx('周', en: 'Week'))),
                          ButtonSegment(
                              value: 'month',
                              label: Text(tx('月', en: 'Month'))),
                        ],
                        selected: {_granularity},
                        onSelectionChanged: (sel) =>
                            setState(() => _granularity = sel.first),
                        showSelectedIcon: false,
                        style: const ButtonStyle(
                          visualDensity: VisualDensity.compact,
                          side: WidgetStatePropertyAll(
                              BorderSide(color: Colors.transparent)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Wrap(
                          spacing: 6,
                          children: [
                            for (final (m, label) in [
                              ('volume', tx('容量', en: 'Volume')),
                              ('sets', tx('组数', en: 'Sets')),
                              ('intensity', tx('强度', en: 'Intensity')),
                            ])
                              ChoiceChip(
                                label: Text(label,
                                    style: const TextStyle(fontSize: 12)),
                                selected: _metric == m,
                                onSelected: (_) =>
                                    setState(() => _metric = m),
                                selectedColor: AppTheme.primary,
                                backgroundColor: AppTheme.cardHi,
                                side: BorderSide.none,
                                labelStyle: TextStyle(
                                    fontSize: 12,
                                    color: _metric == m
                                        ? const Color(0xFF06220F)
                                        : AppTheme.text),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    tx(
                        _metric == 'volume'
                            ? '正式组总容量（kg）· 自重按系数折算'
                            : _metric == 'sets'
                                ? '正式组组数'
                                : '平均强度 = 组重量 ÷ 该动作窗口内最佳 1RM（%）',
                        en: _metric == 'volume'
                            ? 'Total working-set volume (kg)'
                            : _metric == 'sets'
                                ? 'Working sets count'
                                : 'Avg intensity = set weight ÷ best 1RM (%)'),
                    style:
                        const TextStyle(color: AppTheme.textDim, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 200,
                    child: _trendPoints(d).length < 2
                        ? Center(
                            child: Text(
                                tx('数据还少，再练几次就能看到趋势',
                                    en: 'Not enough data yet — a few more workouts will show the trend'),
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
                                        _trendLabel(d, v.toInt()),
                                  ),
                                ),
                              ),
                              lineBarsData: [
                                LineChartBarData(
                                  spots: _trendPoints(d),
                                  isCurved: true,
                                  color: AppTheme.primary,
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
              // 标题收短（2026-09-26 Arono：原标题带括号说明折成四行），
              // 说明降级为卡内小字
              title: tx('主力动作 1RM', en: 'Top Lifts 1RM'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tx('按训练容量自动选前 4 · 纵轴 kg · 横轴训练日期 · 每天取当日最佳',
                        en: 'Top 4 by volume · y-axis kg · x-axis date · daily best'),
                    style: const TextStyle(
                        color: AppTheme.textDim, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final lift in d.topLifts)
                        ChoiceChip(
                          label: Text(exname(lift)),
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
                    child: _buildRmChart(d),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SectionCard(
              title: tx('组间休息趋势（分钟 / 次）',
                  en: 'Rest Between Sets Trend (min / session)'),
              child: SizedBox(
                height: 180,
                child: d.restMinutes.length < 2
                    ? Center(
                        child: Text(
                            tx('完成几次训练后，这里显示每次训练的休息总时长趋势',
                                en: 'Rest time per workout appears here after a few workouts'),
                            style: const TextStyle(color: AppTheme.textDim)))
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
                title: tx('智能提醒', en: 'Smart Tips'),
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

  /// 当前粒度的桶键（升序）
  List<int> _trendKeys(_OverviewData d) {
    final keys = (_granularity == 'week' ? d.weekTrend : d.monthTrend)
        .keys
        .toList()
      ..sort();
    return keys;
  }

  List<FlSpot> _trendPoints(_OverviewData d) {
    final map = _granularity == 'week' ? d.weekTrend : d.monthTrend;
    final keys = _trendKeys(d);
    final metric = switch (_metric) {
      'sets' => TrendMetric.sets,
      'intensity' => TrendMetric.intensity,
      _ => TrendMetric.volume,
    };
    return [
      for (var i = 0; i < keys.length; i++)
        FlSpot(i.toDouble(), (map[keys[i]] ?? TrendAcc()).metricValue(metric))
    ];
  }

  /// 趋势图 x 轴刻度：约 5 个日期标签（周桶显示周一、月桶显示一号）
  Widget _trendLabel(_OverviewData d, int i) {
    final keys = _trendKeys(d);
    if (i < 0 || i >= keys.length) return const SizedBox.shrink();
    final step = (keys.length / 5).ceil();
    if (i % step != 0 && i != keys.length - 1) {
      return const SizedBox.shrink();
    }
    final dt = DateTime.fromMillisecondsSinceEpoch(keys[i] * 86400000);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        _granularity == 'week' ? '${dt.month}/${dt.day}' : '${dt.month}月',
        style: const TextStyle(color: AppTheme.textDim, fontSize: 10),
      ),
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

  /// 主力动作 1RM 图（wger 每日最佳口径）：x 轴日期（训练日），
  /// y = 该动作当天的最高 1RM 估值—— dips 也能诚实显示。
  /// 不足两天时给友好空态：告诉用户已经记了几天、当前 1RM 多少。
  Widget _buildRmChart(_OverviewData d) {
    final lift = _selectedLift;
    final byDate = lift == null ? null : d.rmByDate[lift];
    final keys = (byDate?.keys.toList() ?? <int>[])..sort();
    final pts = [
      for (var i = 0; i < keys.length; i++)
        FlSpot(i.toDouble(), byDate![keys[i]]!)
    ];
    if (lift == null || pts.length < 2) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              lift == null
                  ? tx('练几次之后，这里自动选出你的主力动作',
                      en: 'Top lifts are picked automatically after a few workouts')
                  : tx('${exname(lift)}：已记 ${keys.length} 天',
                      en: '${exname(lift)}: ${keys.length} days logged'),
              style: const TextStyle(fontSize: 14),
            ),
            if (pts.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  tx('当前 1RM ≈ ${fmtKg(pts.last.y)} kg · 再练几场出进步趋势',
                      en: 'Current 1RM ≈ ${fmtKg(pts.last.y)} kg · keep training to see the trend'),
                  style: const TextStyle(
                      color: AppTheme.textDim, fontSize: 13),
                ),
              ),
          ],
        ),
      );
    }
    final maxY = pts.map((p) => p.y).reduce((a, b) => a > b ? a : b);
    final minY = pts.map((p) => p.y).reduce((a, b) => a < b ? a : b);
    final leftInterval = (((maxY - minY) / 3).clamp(2.5, 50.0)).toDouble();
    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: (pts.length / 6).clamp(1, 100).toDouble(),
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= keys.length) return const SizedBox.shrink();
                final dt =
                    DateTime.fromMillisecondsSinceEpoch(keys[i] * 86400000);
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('${dt.month}/${dt.day}',
                      style: const TextStyle(
                          color: AppTheme.textDim, fontSize: 10)),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              interval: leftInterval,
              getTitlesWidget: (v, _) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(
                  fmtKg(v),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      color: AppTheme.textDim, fontSize: 10),
                ),
              ),
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: pts,
            isCurved: false,
            color: AppTheme.accent,
            barWidth: 3,
            dotData: const FlDotData(show: true),
          ),
        ],
      ),
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
    final weekT = <int, TrendAcc>{};
    final monthT = <int, TrendAcc>{};
    final setsByName = <String, List<SetEntry>>{};
    // 每日最佳 1RM（wger 口径）：动作 → 训练日(epoch天) → 当天最高估值
    final dailyBest = DailyBest1Rm();
    // 动作在窗口内的历史最佳 1RM（强度分母；按行序递增 = 时间上"截至当时"）
    final bestRm = <String, double>{};
    for (final r in rows) {
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
        final d = parseDate(date);
        final vol = setVolumeWithBodyweight(entry,
            exerciseName: name, bodyWeightKg: bodyWeight);
        final rm = estimate1RM(weight, reps);
        if (rm > (bestRm[name] ?? 0)) bestRm[name] = rm;
        dailyBest.add(name, d, rm);
        // 强度 = 组重量 ÷ 该动作截至当时的最佳 1RM（自重/辅助配重无意义不计）
        final best = bestRm[name]!;
        final intensity = weight > 0 && best > 0 ? weight / best : null;
        weekT
            .putIfAbsent(trendKeyOf(d, TrendGranularity.week), TrendAcc.new)
            .add(setVolume: vol, intensity: intensity);
        monthT
            .putIfAbsent(trendKeyOf(d, TrendGranularity.month), TrendAcc.new)
            .add(setVolume: vol, intensity: intensity);
      }
    }
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
      weekTrend: weekT,
      monthTrend: monthT,
      topLifts: topLifts.take(4).toList(),
      restMinutes: restMinutes,
      restDates: restDates,
      rmByDate: dailyBest.byExercise,
      setsByName: setsByName,
    );
  }
}

class _OverviewData {
  /// 周/月粒度的趋势桶（key 见 trendKeyOf）
  final Map<int, TrendAcc> weekTrend;
  final Map<int, TrendAcc> monthTrend;

  /// 近一年正式组容量前 4 的动作名（动态"四大项"）
  final List<String> topLifts;

  /// 每次训练的休息净时长（分钟，老记录为空）+ 对应日期
  final List<FlSpot> restMinutes;
  final List<String> restDates;

  /// 每日最佳 1RM：动作 → 训练日(epoch天) → 当天最高估值
  final Map<String, Map<int, double>> rmByDate;
  final Map<String, List<SetEntry>> setsByName;

  _OverviewData({
    required this.weekTrend,
    required this.monthTrend,
    required this.topLifts,
    required this.restMinutes,
    required this.restDates,
    required this.rmByDate,
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

  /// 统计窗口（wger 统计维度借鉴）：本周 / 本月
  String _period = 'week';

  @override
  void initState() {
    super.initState();
    // initState 里不能同步读 InheritedWidget，延后一帧
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _future = _load(app(context));
        });
      }
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
        // 色带归一基准：列表内最大占比（重肌群→琥珀端、轻肌群→灰端）。
        // 2026-09-26 Arono：容量颜色按程度分档，不再清一色绿
        final maxShare = share.values.fold(0.0, math.max);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            // 肌群恢复度（点名条目四）：只进数据页，不进训练中三要素
            // （2026-09-25 从计划页挪到数据页，计划页只管"练什么"）
            const MuscleRecoveryCard(),
            SectionCard(
              title: tx(
                  _period == 'week' ? '本周肌群容量占比' : '本月肌群容量占比',
                  en: _period == 'week'
                      ? "This Week's Muscle Volume Share"
                      : "This Month's Muscle Volume Share"),
              child: Column(
                children: [
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(
                          value: 'week', label: Text(tx('本周', en: 'Week'))),
                      ButtonSegment(
                          value: 'month', label: Text(tx('本月', en: 'Month'))),
                    ],
                    selected: {_period},
                    onSelectionChanged: (sel) {
                      setState(() => _period = sel.first);
                      _future = _load(app(context));
                    },
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      side: WidgetStatePropertyAll(
                          BorderSide(color: Colors.transparent)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(
                          value: true, label: Text(tx('正面', en: 'Front'))),
                      ButtonSegment(
                          value: false, label: Text(tx('背面', en: 'Back'))),
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
                    child: MuscleBodyView(
                      share: share,
                      front: _front,
                      ramp: (v) => maxShare <= 0
                          ? AppTheme.cardHi
                          : AppTheme.loadColor(v / maxShare),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...kMuscleRegions.map((r) {
                    final v = share[r] ?? 0;
                    final color = maxShare <= 0
                        ? AppTheme.cardHi
                        : AppTheme.loadColor(v / maxShare);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          // FittedBox：大字号/窄屏下名称与百分比整体缩放，
                          // 数字绝不被折行（如"30"拆成两行）
                          SizedBox(
                            width: 44,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(mname(r),
                                  maxLines: 1,
                                  style: const TextStyle(fontSize: 14)),
                            ),
                          ),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: total == 0 ? 0 : v,
                                minHeight: 10,
                                backgroundColor: AppTheme.cardHi,
                                valueColor:
                                    AlwaysStoppedAnimation(color),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 52,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text('${(v * 100).toStringAsFixed(0)}%',
                                  maxLines: 1,
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                      color: total == 0
                                          ? AppTheme.textDim
                                          : color,
                                      fontSize: 13)),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  if ((share['肩'] ?? 0) < 0.15 || (share['背'] ?? 0) < 0.15)
                    Text(
                        tx('提示：肩、背容量偏低——薄肌计划的目标是肩背偏重，注意补齐。',
                            en: 'Tip: Shoulder and back volume are low — the Baoji plan emphasizes shoulders and back, so catch up on them.'),
                        style:
                            const TextStyle(color: AppTheme.warn, fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // 上下肢分布（wger 的 upper/lower 口径）：七分区归并成
            // 上肢（胸肩背手臂）/ 下肢（腿）/ 核心+其他 三条，一眼看结构
            SectionCard(
              title: tx(
                  _period == 'week' ? '上下肢分布（本周）' : '上下肢分布（本月）',
                  en: _period == 'week'
                      ? 'Upper/Lower Split (this week)'
                      : 'Upper/Lower Split (this month)'),
              child: Builder(builder: (_) {
                final groups = regionGroupShare(share);
                const order = ['上肢', '下肢', '核心'];
                final hint = groups['下肢'] ?? 0;
                return Column(
                  children: [
                    for (final g in order)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 44,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  tx(g,
                                      en: switch (g) {
                                        '上肢' => 'Upper',
                                        '下肢' => 'Lower',
                                        _ => 'Core',
                                      }),
                                  maxLines: 1,
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                            ),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: groups[g] ?? 0,
                                  minHeight: 10,
                                  backgroundColor: AppTheme.cardHi,
                                  valueColor: AlwaysStoppedAnimation(
                                      AppTheme.loadColor(groups[g] ?? 0)),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 52,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  '${((groups[g] ?? 0) * 100).toStringAsFixed(0)}%',
                                  maxLines: 1,
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (hint < 0.25)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          tx('提示：下肢容量不足四分之一——练上不练下，力量和体态都会失衡。',
                              en: 'Tip: Lower-body work is under a quarter of volume — don\'t skip leg day.'),
                          style: const TextStyle(
                              color: AppTheme.warn, fontSize: 13),
                        ),
                      ),
                  ],
                );
              }),
            ),
          ],
        );
      },
    );
  }

  Future<Map<String, double>> _load(AppContainer c) async {
    final now = DateTime.now();
    final from = _period == 'week'
        ? mondayOf(now)
        : DateTime(now.year, now.month, 1);
    final sessions = await c.db.sessionsBetween(fmtDate(from), fmtDate(now));
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
      if (mounted) {
        setState(() {
          _future = app(context).db.bodyMetrics();
        });
      }
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
              title: tx('体重趋势', en: 'Body Weight Trend'),
              child: SizedBox(
                height: 180,
                child: weights.length < 2
                    ? Center(
                        child: Text(tx('每周固定时间记一次体重',
                            en: 'Weigh in at the same time each week'),
                            style: const TextStyle(color: AppTheme.textDim)))
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
              title: tx('记录今天', en: 'Log Today'),
              child: Column(
                children: [
                  TextField(
                    controller: _weightCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                        labelText:
                            tx('体重 (kg)', en: 'Body Weight (kg)')),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _waistCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                        labelText:
                            tx('腰围 (cm，可选)', en: 'Waist (cm, optional)')),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _fatCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                        labelText:
                            tx('体脂率 (%，可选)', en: 'Body Fat (%, optional)')),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () async {
                      final w = double.tryParse(_weightCtrl.text);
                      final waist = double.tryParse(_waistCtrl.text);
                      final fat = double.tryParse(_fatCtrl.text);
                      if (w == null && waist == null && fat == null) {
                        toast(this.context,
                            tx('至少填一项', en: 'Fill in at least one field'));
                        return;
                      }
                      // 防呆区间（wger measurements/limits 口径）：超界直接拦，
                      // 防手滑多敲一位把曲线打飞（单位填错也拦得住）
                      final err = validateBodyMetric(
                          weightKg: w, waistCm: waist, bodyFatPct: fat);
                      if (err != null) {
                        toast(this.context, err);
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
                        toast(this.context, tx('已记录', en: 'Saved'));
                        setState(() {
                          _future = app(this.context).db.bodyMetrics();
                        });
                      }
                    },
                    child: Text(tx('保存', en: 'Save')),
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
