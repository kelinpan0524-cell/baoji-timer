import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../engine/engine.dart';
import '../presets/exercise_library.dart';
import 'plan_repository.dart';
import 'settings.dart';

/// OpenAI 兼容 chat/completions 客户端：手机直连，key 只存本地。
class AiService {
  AiService(this._settings);

  final Settings _settings;

  Map<String, ExerciseMeta> metaMap() => {
        for (final m in kExerciseLibrary) m.name: m,
      };

  /// 把用户粘贴的计划文本拆解为结构化计划。
  /// 动作名尽量匹配内置词表；肌群映射走词表 + 关键词兜底。
  Future<List<AiDaySpec>> parsePlan(String text) async {
    if (!_settings.aiConfigured) {
      throw const AiException('未配置 AI 接口，请在设置里填入 Base URL 和 API Key');
    }
    final prompt = _buildPrompt(text);
    final content = await _chat(prompt);
    return parseResponse(content);
  }

  /// 自然语言描述 → 教练设计一份计划（输出与原文导入相同的 JSON 契约）。
  String buildDesignerPrompt(String description) {
    final lib =
        kExerciseLibrary.map((m) => '${m.name}(${m.muscles.main})').join('、');
    return '''
你是专业力量训练教练。根据用户的自然语言描述，设计一份每周力量训练计划，输出严格 JSON：
1. 只输出 JSON 数组，不要输出任何其他文字或 markdown 代码块标记。
2. 每个元素是一个训练日：{"weekday": 1-7(周一=1), "title": "训练日名称", "exercises": [...]}
3. 每个 exercise：{"name": "规范中文动作名", "sets": 组数, "reps_min": 最少次数, "reps_max": 最多次数, "rest_sec": 组间休息秒数, "kind": "compound或assistance", "main_muscle": "胸/肩/背/手臂/腿/核心 之一"}
4. 每周 3-5 个训练日；同一肌群两次训练至少间隔 48 小时；容量安排符合渐进超负荷原则；热身组不写入。
5. rest_sec：复合动作 150-180，辅助动作 90-120。动作名尽量使用参考词表：$lib
6. 用户未说明的部分按增肌最佳实践补全；描述过简时按"每周 3 练、全身均衡"处理；用户明确指定的动作/器械/次数/每周训练天数都尊重用户（如"每周 6 练"或"只要 2 天"照办）。

用户描述：$description
''';
  }

  /// 自然语言生成计划（不落库），返回后由 UI 预览、用户确认再保存。
  Future<List<AiDaySpec>> designPlanFromDescription(String description) async {
    if (!_settings.aiConfigured) {
      throw const AiException('未配置 AI 接口，请在设置里填入 Base URL 和 API Key');
    }
    final content = await _chat(buildDesignerPrompt(description));
    return parseResponse(content);
  }

  String _buildPrompt(String planText) {
    final lib = kExerciseLibrary.map((m) => '${m.name}(${m.muscles.main})').join('、');
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

  /// Base URL 协议校验（可见于测试）：返回给用户的错误文案，合法返回 null。
  /// 缺 scheme（如 Ollama 官方写法 localhost:11434）单独提示——此时
  /// Uri.tryParse 会把 'localhost' 当 scheme、host 为空，若直接走
  /// "公网必须 https" 分支会误导用户加 https 前缀，反而连不上明文本地服务。
  @visibleForTesting
  static String? baseUrlSchemeError(String base) {
    if (!base.contains('://')) {
      return '地址缺少 http:// 或 https:// 前缀，请补全（局域网自建模型可用 http://）';
    }
    if (!base.startsWith('https://')) {
      // 公网必须 https（Key 在请求头，明文会被中间人截获）；
      // 局域网/本机自建模型（Ollama、LM Studio 等）允许 http。
      // 白名单按数值 IPv4 判定：'10.evil.com' 这类域名形状不能绕过。
      final host = Uri.tryParse(base)?.host ?? '';
      final isPrivate = isLocalHost(host);
      if (!isPrivate) {
        return '公网地址必须 https://（局域网自建模型可用 http）';
      }
    }
    return null;
  }

  Future<String> _chat(String prompt) async {
    var base = _settings.aiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final schemeError = baseUrlSchemeError(base);
    if (schemeError != null) {
      throw AiException(schemeError);
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
        final friendly = switch (resp.statusCode) {
          401 => 'API Key 无效',
          403 => '无访问权限或地区受限',
          429 => '额度不足或被限流，稍后再试',
          _ => 'AI 接口返回 ${resp.statusCode}',
        };
        throw AiException(friendly);
      }
      final dynamic decoded;
      try {
        decoded = jsonDecode(utf8.decode(resp.bodyBytes));
      } on FormatException {
        throw const AiException('AI 返回的不是有效 JSON（网关错误页？），请检查 Base URL');
      }
      final data = decoded as Map<String, dynamic>;
      final choices = data['choices'] as List?;
      if (choices == null || choices.isEmpty) {
        throw const AiException('AI 返回为空');
      }
      final msg = (choices.first as Map)['message'] as Map;
      // 推理类模型可能把文本放 reasoning_content、content 置 null
      final content = (msg['content'] as String?)?.trim() ?? '';
      if (content.isEmpty) {
        throw const AiException('模型没有输出内容（可能被截断或仅推理输出），请换模型或重试');
      }
      return content;
    } on TimeoutException {
      throw const AiException('AI 请求超时，请检查网络或稍后再试');
    } on http.ClientException catch (e) {
      throw AiException('无法连接 AI 接口：${e.message}');
    }
  }

  /// 局域网 http 白名单：localhost 精确匹配 + 数值 IPv4 私有段。
  /// '10.evil.com' 这类域名形状不放行。
  @visibleForTesting
  static bool isLocalHost(String host) {
    if (host == 'localhost' || host == '::1' || host == '0.0.0.0') return true;
    final m = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$')
        .firstMatch(host);
    if (m == null) return false; // 非数值 IP（域名）一律要求 https
    final octets = [
      for (var i = 1; i <= 4; i++) int.parse(m.group(i)!),
    ];
    if (octets.any((o) => o > 255)) return false;
    final a = octets[0], b = octets[1];
    return a == 10 ||
        a == 127 ||
        (a == 192 && b == 168) ||
        (a == 172 && b >= 16 && b <= 31) ||
        (a == 169 && b == 254);
  }

  /// 数字字段安全转换：弱模型常把数字输出成字符串/全角字符。
  static int _asInt(Object? v, int def) {
    if (v is num) return v.toInt();
    if (v is String) {
      final normalized = v.replaceAll('０', '0')
          .replaceAll('１', '1').replaceAll('２', '2')
          .replaceAll('３', '3').replaceAll('４', '4')
          .replaceAll('５', '5').replaceAll('６', '6')
          .replaceAll('７', '7').replaceAll('８', '8')
          .replaceAll('９', '9').trim();
      return int.tryParse(normalized) ?? def;
    }
    return def;
  }

  /// AI 输出集中清洗（可见于测试）：weekday 越界丢日、数字安全转换、
  /// sets/reps/rest 钳制、reps 倒挂交换、同 weekday 合并。
  /// jsonDecode 与字段强转的异常统一归一为 AiException，
  /// 让 UI 侧走中文友好文案而不是英文原始报错。
  @visibleForTesting
  List<AiDaySpec> parseResponse(String content) {
    var text = content.trim();
    // 容错：剥掉 markdown 代码块
    final fence = RegExp(r'```(?:json)?([\s\S]*?)```').firstMatch(text);
    if (fence != null) text = fence.group(1)!.trim();
    final start = text.indexOf('[');
    final end = text.lastIndexOf(']');
    if (start < 0 || end <= start) {
      throw const AiException('AI 返回格式无法解析，请重试或换模型');
    }
    try {
      final list = jsonDecode(text.substring(start, end + 1)) as List;
      final specs = <AiDaySpec>[];
      final byWeekday = <int, int>{}; // weekday -> specs 下标（同日合并）
      for (final item in list) {
        if (item is! Map) continue;
        final day = Map<String, dynamic>.from(item);
        final weekday = _asInt(day['weekday'], 0);
        if (weekday < 1 || weekday > 7) continue; // 越界日丢弃
        final rawTitle = day['title'];
        final title = rawTitle is String ? rawTitle : '训练日';
        final exList = <AiExerciseSpec>[];
        final rawList = day['exercises'];
        if (rawList is! List) continue;
        for (final raw in rawList) {
          if (raw is! Map) continue;
          final ex = Map<String, dynamic>.from(raw);
          final rawName = ex['name'];
          final name = _normalizeName(rawName is String ? rawName : '');
          if (name.isEmpty) continue;
          var sets = _asInt(ex['sets'], 3).clamp(1, 20);
          var repsMin = _asInt(ex['reps_min'], 5).clamp(1, 50);
          var repsMax = _asInt(ex['reps_max'], 8).clamp(1, 50);
          if (repsMin > repsMax) {
            final t = repsMin;
            repsMin = repsMax;
            repsMax = t;
          }
          // 缺失或 0 都视为缺失：让 saveAiPlan 的 defaultRestSec
          // 按用户休息偏好兜底，DB 不落 rest_sec=0 脏数据
          final rs = _asInt(ex['rest_sec'], 0);
          final rawKind = ex['kind'];
          final rawMuscle = ex['main_muscle'];
          exList.add(AiExerciseSpec(
            name: name,
            sets: sets,
            repsMin: repsMin,
            repsMax: repsMax,
            restSec: rs <= 0 ? null : rs.clamp(0, 600),
            kind: rawKind is String ? rawKind : null,
            mainMuscle: rawMuscle is String ? rawMuscle : null,
          ));
        }
        if (exList.isEmpty) continue;
        final existing = byWeekday[weekday];
        if (existing == null) {
          byWeekday[weekday] = specs.length;
          specs.add(AiDaySpec(weekday, title, exList));
        } else {
          // 同 weekday 的两个训练日合并到一天（保持"一周一天"不变量）
          final old = specs[existing];
          specs[existing] = AiDaySpec(old.weekday, old.title, [
            ...old.exercises,
            ...exList,
          ]);
        }
      }
      if (specs.isEmpty) throw const AiException('没有解析出任何训练日，请检查文本');
      return specs;
    } on AiException {
      rethrow;
    } catch (_) {
      // jsonDecode 的 FormatException、字段强转的 TypeError 等
      // 统一归一，避免英文原始报错透传到 UI
      throw const AiException('AI 返回格式无法解析，请重试或换模型');
    }
  }

  /// 名称归一 + 内置词表匹配：先精确匹配；模糊轮收集候选后取
  /// 「与输入长度最接近」者，避免泛称被吸到最长变体。
  /// 反向包含（词表名含输入）设 3 字门槛，挡住「卧推」「划船」这类
  /// 泛称落成「上斜杠铃卧推（轻）」「弹力带坐姿划船」；无候选保留
  /// 原名，走 exercise_meta 沉淀兜底。
  String _normalizeName(String raw) {
    final rawTrim = raw.trim();
    if (rawTrim.isEmpty) return rawTrim;
    for (final m in _sortedMeta) {
      if (m.name == rawTrim) return m.name;
    }
    ExerciseMeta? best;
    var bestDiff = -1;
    for (final m in _sortedMeta) {
      final core = m.name.replaceAll(RegExp(r'[（(].*[)）]'), '');
      final hit = rawTrim.contains(core) ||
          (core.contains(rawTrim) && rawTrim.length >= 3);
      if (!hit) continue;
      final diff = (core.length - rawTrim.length).abs();
      if (best == null || diff < bestDiff) {
        best = m;
        bestDiff = diff;
      }
    }
    return best?.name ?? rawTrim;
  }

  /// 词表快照。长度降序仅影响同长度差的并列候选谁先命中
  /// （更具体的变体优先）；「卧推」等短泛称不再因降序被吸成长变体。
  static final List<ExerciseMeta> _sortedMeta = [
    ...kExerciseLibrary.toList()..sort((a, b) => b.name.length.compareTo(a.name.length)),
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
