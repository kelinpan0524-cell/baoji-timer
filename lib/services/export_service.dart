import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../db/db.dart';
import '../engine/engine.dart';

/// 导出：CSV / JSON 全量 / AI 分析包（Markdown，可直接粘给任何 AI）。
class ExportService {
  ExportService(this._db);

  final Db _db;

  Future<File> _writeTmp(String name, String content) async {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/$name');
    await f.writeAsString(content, flush: true);
    return f;
  }

  Future<void> shareText(String title, String text, {String? filename}) async {
    if (filename != null) {
      final f = await _writeTmp(filename, text);
      await Share.shareXFiles([XFile(f.path)], subject: title, text: title);
    } else {
      await Share.share(text, subject: title);
    }
  }

  String _csv(String v) => '"${v.replaceAll('"', '""')}"';

  /// 动作的实际组间休息（相邻两组 doneAt 之差的平均，>30 分钟的跨动作/中场
  /// 休息剔除）。计划休息秒数带上，AI 才能对比"计划 vs 实际"。
  String _actualRestNote(SessionExercise se, List<SetEntry> sets) {
    if (sets.length < 2) return '';
    final gaps = <int>[];
    for (var i = 1; i < sets.length; i++) {
      final g = sets[i].doneAt - sets[i - 1].doneAt;
      if (g > 0 && g < 30 * 60 * 1000) gaps.add(g);
    }
    if (gaps.isEmpty) return '';
    final avgSec = (gaps.fold(0, (a, b) => a + b) / gaps.length / 1000).round();
    final planned = se.restSec > 0 ? '计划休 ${se.restSec}s' : '休息跟随全局设置';
    return '（$planned · 实际均休 ~${avgSec}s）';
  }

  Future<String> buildCsv() async {
    final sessions = await _db.recentSessions(limit: 100000);
    final buf = StringBuffer(
        'date,plan_day,exercise,weight_kg,reps,rir,kind,done_at\n');
    for (final s in sessions) {
      final ses = await _db.sessionExercises(s.id!);
      final map = await _db.setsOfSession(s.id!);
      for (final se in ses) {
        for (final set in map[se.id!] ?? const <SetEntry>[]) {
          buf.writeln(
              '${s.date},${_csv(s.planDayTitle)},${_csv(se.name)},${set.weightKg},${set.reps},${set.rir},${set.kind},${set.doneAt}');
        }
      }
    }
    return buf.toString();
  }

  Future<String> buildJson() async {
    final all = await _db.exportAllJson();
    return const JsonEncoder.withIndent('  ').convert(all);
  }

  /// 从全量 JSON 恢复（清空后写入）。返回恢复的训练次数；
  /// 缺关键数据段时抛 FormatException，行损坏交给 Db.restoreAll 的事务兜底。
  Future<int> restoreFromJson(Map<String, dynamic> data) async {
    for (final k in const [
      'plans',
      'plan_days',
      'plan_exercises',
      'sessions',
      'session_exercises',
      'sets',
    ]) {
      if (data[k] is! List) {
        throw FormatException('备份缺少必要数据段（$k）');
      }
    }
    await _db.restoreAll(data);
    return (data['sessions'] as List).length;
  }

  /// AI 数据包（纯数据，无提示词）：App 内「AI 教练」的对话上下文。
  /// [bodyWeightKg]：自重容量折算体重——不传/传 0 时自重动作容量记 0
  /// （旧口径）。调用点传 settings.bodyWeightKg 与统计页保持同一容量口径。
  Future<String> buildAiData({int weeks = 8, double bodyWeightKg = 0}) async {
    final now = DateTime.now();
    final from = fmtDate(now.subtract(Duration(days: weeks * 7)));
    final to = fmtDate(now);
    final sessions = await _db.sessionsBetween(from, to);

    final buf = StringBuffer();
    buf.writeln('## 训练概要');
    buf.writeln('- 数据时间范围：$from 至 $to');
    buf.writeln('- 训练次数：${sessions.length} 次');
    if (sessions.isNotEmpty) {
      final span = sessions.last.date == sessions.first.date
          ? sessions.first.date
          : '${sessions.first.date} ~ ${sessions.last.date}';
      buf.writeln('- 时间跨度：$span');
    }
    buf.writeln();
    buf.writeln('## 每次训练明细');
    final byNameVolume = <String, double>{};
    for (final s in sessions) {
      final ses = await _db.sessionExercises(s.id!);
      final map = await _db.setsOfSession(s.id!);
      final stats = sessionStatsFrom(map, ses, bodyWeightKg: bodyWeightKg);
      buf.writeln('### ${s.date} ${s.planDayTitle}');
      final timeNote = s.restMs > 0
          ? '（训练 ${(s.activeMs / 60000).ceil()} 分 · 休息 ${(s.restMs / 60000).ceil()} 分）'
          : '';
      buf.writeln('- 总容量 ${stats.volume.toStringAsFixed(0)}kg · 正式组 ${stats.workingSets} 组 · 时长 ${s.durationMin} 分钟$timeNote');
      for (final se in ses) {
        final sets = map[se.id!] ?? const <SetEntry>[];
        if (sets.isEmpty) continue;
        final desc = sets
            .map((x) => '${x.weightKg}kg×${x.reps}${x.kind == SetKind.warmup ? '(热)' : x.kind == SetKind.failure ? '(失)' : ''}')
            .join(', ');
        buf.writeln('- ${se.name}: $desc${_actualRestNote(se, sets)}');
        byNameVolume[se.name] = (byNameVolume[se.name] ?? 0) +
            sets.fold(
                0.0,
                (a, b) =>
                    a +
                    setVolumeWithBodyweight(b,
                        exerciseName: se.name, bodyWeightKg: bodyWeightKg));
      }
      buf.writeln();
    }
    if (byNameVolume.isNotEmpty) {
      buf.writeln('## 各动作累计容量（kg）');
      final sorted = byNameVolume.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final e in sorted) {
        buf.writeln('- ${e.key}: ${e.value.toStringAsFixed(0)}');
      }
      buf.writeln();
    }
    final body = await _db.bodyMetrics(limit: 60);
    if (body.isNotEmpty) {
      buf.writeln('## 身体数据');
      for (final b in body) {
        final parts = <String>[];
        if (b.weightKg != null) parts.add('体重 ${b.weightKg}kg');
        if (b.waistCm != null) parts.add('腰围 ${b.waistCm}cm');
        if (b.bodyFatPct != null) parts.add('体脂 ${b.bodyFatPct}%');
        if (parts.isNotEmpty) buf.writeln('- ${b.date}: ${parts.join('，')}');
      }
      buf.writeln();
    }
    buf.writeln('## 原始数据（JSON，供核对）');
    final compact = <Map<String, dynamic>>[];
    for (final s in sessions) {
      final ses = await _db.sessionExercises(s.id!);
      final map = await _db.setsOfSession(s.id!);
      compact.add({
        'date': s.date,
        'day': s.planDayTitle,
        'exercises': [
          for (final se in ses)
            {
              'name': se.name,
              'sets': [
                for (final x in map[se.id!] ?? const <SetEntry>[])
                  {'w': x.weightKg, 'r': x.reps, 'rir': x.rir, 'kind': x.kind}
              ],
            }
        ],
      });
    }
    buf.writeln('```json');
    buf.writeln(jsonEncode(compact));
    buf.writeln('```');
    return buf.toString();
  }

  /// AI 分析包：预制教练提示词 + 数据包（buildAiData）。
  /// 目标：直接整段复制给任意大模型，即可获得训练分析与总结。
  Future<String> buildAiPack({int weeks = 8, double bodyWeightKg = 0}) async {
    final buf = StringBuffer();
    buf.writeln('# 训练数据分析请求');
    buf.writeln();
    buf.writeln('你是一位专业力量训练教练。请基于下面的结构化数据分析：');
    buf.writeln('1. 各大项（深蹲/卧推/硬拉/推举）的进步趋势，指出停滞或退步的动作；');
    buf.writeln('2. 训练频率与容量是否足以支撑渐进超负荷；');
    buf.writeln('3. 肌群均衡度（哪个肌群训练量偏低）；');
    buf.writeln('4. 组间休息是否合适：结合"计划休息 vs 实际休息"判断哪些动作休息过长或过短'
        '（参考：增肌复合动作 90-180 秒、辅助动作 60-90 秒、大重量低次数力量组 3-5 分钟）；');
    buf.writeln('5. 给出未来 2-4 周的具体调整建议（加重策略、弱项补强、恢复建议）。');
    buf.writeln();
    buf.write(await buildAiData(weeks: weeks, bodyWeightKg: bodyWeightKg));
    return buf.toString();
  }
}
