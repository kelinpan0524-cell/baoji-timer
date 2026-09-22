import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../engine/engine.dart';
import '../presets/baoji_plan.dart';
import 'plan_repository.dart';
import 'settings.dart';

/// OpenAI 兼容 chat/completions 客户端：手机直连，key 只存本地。
class AiService {
  AiService(this._settings);

  final Settings _settings;

  Map<String, ExerciseMeta> metaMap() => {
        for (final m in kBaojiExerciseMeta) m.name: m,
      };

  /// 把用户粘贴的计划文本拆解为结构化计划。
  /// 动作名尽量匹配内置词表；肌群映射走词表 + 关键词兜底。
  Future<List<AiDaySpec>> parsePlan(String text) async {
    if (!_settings.aiConfigured) {
      throw const AiException('未配置 AI 接口，请在设置里填入 Base URL 和 API Key');
    }
    final prompt = _buildPrompt(text);
    final content = await _chat(prompt);
    return _parseResponse(content);
  }

  String _buildPrompt(String planText) {
    final lib = kBaojiExerciseMeta.map((m) => '${m.name}(${m.muscles.main})').join('、');
    return '''
你是力量训练计划解析器。把下面的训练计划文本转换为严格 JSON。要求：
1. 只输出 JSON 数组，不要输出任何其他文字或 markdown 代码块标记。
2. 每个元素是一个训练日：{"weekday": 1-7(周一=1), "title": "训练日名称", "exercises": [...]}
3. 每个 exercise：{"name": "动作名", "sets": 组数, "reps_min": 最少次数, "reps_max": 最多次数, "rest_sec": 组间休息秒数, "kind": "compound或assistance", "main_muscle": "主发力肌群，从 胸/肩/背/手臂/腿/核心 里选一个"}
4. "3×5-8" 表示 sets=3, reps_min=5, reps_max=8；"3组8-12次" 同理。
5. 动作名使用规范中文（参考词表：$lib）。次数字段缺失时用常见默认：复合动作 5-8、辅助动作 8-12；休息缺失时复合 180、辅助 120。
6. 训练计划原文可能提到具体星期，如"周一"对应 weekday=1。

计划原文：
$planText
''';
  }

  Future<String> _chat(String prompt) async {
    var base = _settings.aiBaseUrl.trim().replaceAll(RegExp(r'/+\$'), '');
    if (!base.startsWith('https://')) {
      // API Key 走 Authorization 头，明文 http 会被中间人截获
      throw const AiException('Base URL 必须以 https:// 开头');
    }
    final url = '$base/chat/completions';
    try {
      final resp = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${_settings.aiApiKey}',
            },
            body: jsonEncode({
              'model': _settings.aiModel,
              'messages': [
                {'role': 'user', 'content': prompt}
              ],
              'temperature': 0.2,
            }),
          )
          .timeout(const Duration(seconds: 90));
      if (resp.statusCode != 200) {
        throw AiException('AI 接口返回 ${resp.statusCode}：${resp.body.length > 200 ? '${resp.body.substring(0, 200)}…' : resp.body}');
      }
      final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final choices = data['choices'] as List?;
      if (choices == null || choices.isEmpty) {
        throw const AiException('AI 返回为空');
      }
      final msg = (choices.first as Map)['message'] as Map;
      return (msg['content'] as String?) ?? '';
    } on TimeoutException {
      throw const AiException('AI 请求超时，请检查网络或稍后再试');
    } on http.ClientException catch (e) {
      throw AiException('无法连接 AI 接口：${e.message}');
    }
  }

  List<AiDaySpec> _parseResponse(String content) {
    var text = content.trim();
    // 容错：剥掉 markdown 代码块
    final fence = RegExp(r'```(?:json)?([\s\S]*?)```').firstMatch(text);
    if (fence != null) text = fence.group(1)!.trim();
    final start = text.indexOf('[');
    final end = text.lastIndexOf(']');
    if (start < 0 || end <= start) {
      throw const AiException('AI 返回格式无法解析，请重试或换模型');
    }
    final list = jsonDecode(text.substring(start, end + 1)) as List;
    final specs = <AiDaySpec>[];
    for (final item in list) {
      final day = Map<String, dynamic>.from(item as Map);
      final weekday = (day['weekday'] as num?)?.toInt() ?? 1;
      final title = (day['title'] as String?) ?? '训练日';
      final exList = <AiExerciseSpec>[];
      for (final raw in (day['exercises'] as List?) ?? []) {
        final ex = Map<String, dynamic>.from(raw as Map);
        final name = _normalizeName((ex['name'] as String?) ?? '');
        if (name.isEmpty) continue;
        exList.add(AiExerciseSpec(
          name: name,
          sets: (ex['sets'] as num?)?.toInt() ?? 3,
          repsMin: (ex['reps_min'] as num?)?.toInt() ?? 5,
          repsMax: (ex['reps_max'] as num?)?.toInt() ?? 8,
          restSec: (ex['rest_sec'] as num?)?.toInt(),
          kind: ex['kind'] as String?,
          mainMuscle: ex['main_muscle'] as String?,
        ));
      }
      if (exList.isNotEmpty) specs.add(AiDaySpec(weekday, title, exList));
    }
    if (specs.isEmpty) throw const AiException('没有解析出任何训练日，请检查文本');
    return specs;
  }

  /// 名称归一 + 内置词表模糊匹配（包含式，更长的词优先避免误命中）。
  String _normalizeName(String raw) {
    final rawTrim = raw.trim();
    if (rawTrim.isEmpty) return rawTrim;
    for (final m in _sortedMeta) {
      if (m.name == rawTrim) return m.name;
    }
    for (final m in _sortedMeta) {
      final core = m.name.replaceAll(RegExp(r'[（(].*[)）]'), '');
      if (rawTrim.contains(core) || core.contains(rawTrim)) return m.name;
    }
    return rawTrim;
  }

  /// 名称越长越具体，优先匹配（"上斜杠铃卧推"不应命中"杠铃卧推"）。
  static final List<ExerciseMeta> _sortedMeta = [
    ...kBaojiExerciseMeta.toList()..sort((a, b) => b.name.length.compareTo(a.name.length)),
  ];
}

class AiException implements Exception {
  final String message;
  const AiException(this.message);
  @override
  String toString() => message;
}

/// 智能建议（免费、本地规则生成，不调 AI）：
/// 基于近几次数据的异常提示，用于数据页展示，也拼进 AI 分析包。
List<String> localInsights(Map<String, List<SetEntry>> setsByName) {
  final out = <String>[];
  setsByName.forEach((name, sets) {
    final daily = dailyBest1Rm(sets.where((s) => s.kind == SetKind.working).toList());
    if (daily.length >= 2) {
      final last = daily.last;
      final prev = daily[daily.length - 2];
      if (last < prev * 0.9) {
        out.add('$name 最近表现比上次下降超过 10%，考虑是否休息不足或动作变形');
      }
    }
    if (daily.length >= 4) {
      final window = daily.sublist(daily.length - 4);
      if (window.last <= window.first && window.every((v) => v <= window.first * 1.01)) {
        out.add('$name 连续 3 次未进步，建议检查组间休息时长与睡眠恢复');
      }
    }
  });
  return out;
}

/// 按天取最佳 1RM 序列（时间升序）。
@visibleForTesting
List<double> dailyBest1Rm(List<SetEntry> sets) {
  final byDay = <int, double>{};
  for (final s in sets) {
    final d = s.doneAt ~/ 86400000;
    final rm = estimate1RM(s.weightKg, s.reps);
    if (rm > (byDay[d] ?? 0)) byDay[d] = rm;
  }
  final keys = byDay.keys.toList()..sort();
  return keys.map((k) => byDay[k]!).toList();
}
