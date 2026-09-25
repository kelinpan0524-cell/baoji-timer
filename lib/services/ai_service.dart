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
  /// sets/reps/rest 钳制、reps 倒挂交换、同 weekday 合并、
  /// 动作名六级匹配级联（调研条目 12）。
  /// jsonDecode 与字段强转的异常统一归一为 AiException，
  /// 让 UI 侧走中文友好文案而不是英文原始报错。
  @visibleForTesting
  List<AiDaySpec> parseResponse(String content) {
    final list = extractJsonPayload(content);
    final specs = <AiDaySpec>[];
    final byWeekday = <int, int>{}; // weekday -> specs 下标（同日合并）
    try {
      // pass 1：提取有效日结构（清洗规则与旧版一致）
      final days = <(int, String, List<Map<String, dynamic>>)>[];
      for (final item in list) {
        if (item is! Map) continue;
        final day = Map<String, dynamic>.from(item);
        final weekday = _asInt(day['weekday'], 0);
        if (weekday < 1 || weekday > 7) continue; // 越界日丢弃
        final rawTitle = day['title'];
        final title = rawTitle is String ? rawTitle : '训练日';
        final rawList = day['exercises'];
        if (rawList is! List) continue;
        final exItems = [
          for (final raw in rawList)
            if (raw is Map) Map<String, dynamic>.from(raw),
        ];
        days.add((weekday, title, exItems));
      }
      // pass 2：动作名六级匹配（覆盖率按整批计算，先收集全部原始名）
      final rawNames = [
        for (final d in days)
          for (final ex in d.$3)
            if (ex['name'] is String && (ex['name'] as String).trim().isNotEmpty)
              ex['name'] as String,
      ];
      final matches = matchExerciseNames(rawNames);
      var mi = 0;
      // pass 3：组装 specs（数字清洗 + 同 weekday 合并）
      for (final d in days) {
        final (weekday, title, exItems) = d;
        final exList = <AiExerciseSpec>[];
        for (final ex in exItems) {
          final rawNameValue = ex['name'];
          // 空名跳过（与 pass2 的收集条件一致，不消耗匹配下标）
          final rawTrim =
              rawNameValue is String ? rawNameValue.trim() : '';
          if (rawTrim.isEmpty) continue;
          final match = matches[mi++];
          final name = match.name;
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
            rawName: rawNameValue is String ? rawNameValue : name,
            needsConfirm: match.needsConfirm,
            candidates: match.candidates,
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
      // 字段强转的 TypeError 等统一归一，避免英文原始报错透传到 UI
      throw const AiException('AI 返回格式无法解析，请重试或换模型');
    }
  }

  // ================= JSON 三层容错（调研条目 12） =================

  /// ① 直接解析整段 → ② 剥 ```json 代码围栏 → ③ 括号配平扫描。
  /// LLM 输出裹代码围栏/夹带前后散文是最常见翻车点，三层逐级放宽；
  /// 三层都取不到合法 JSON 数组才抛 AiException。
  @visibleForTesting
  List<dynamic> extractJsonPayload(String content) {
    final text = content.trim();
    // ① 直接解析
    final direct = _decodeArray(text);
    if (direct != null) return direct;
    // ② 代码围栏（可能有多段，逐段尝试）
    for (final m in RegExp(r'```(?:json)?\s*([\s\S]*?)```').allMatches(text)) {
      final inner = _decodeArray(m.group(1)!.trim());
      if (inner != null) return inner;
    }
    // ③ 括号配平扫描：字符串感知（忽略字符串内的括号），取第一个配平的数组
    final sliced = _balancedSlice(text);
    if (sliced != null) {
      final v = _decodeArray(sliced);
      if (v != null) return v;
    }
    throw const AiException('AI 返回格式无法解析，请重试或换模型');
  }

  List<dynamic>? _decodeArray(String s) {
    if (!s.startsWith('[')) return null;
    try {
      final v = jsonDecode(s);
      return v is List ? v : null;
    } catch (_) {
      return null;
    }
  }

  /// 括号配平扫描：从第一个 `[` 起扫描，字符串（含转义）内的括号不计数，
  /// depth 归零即认为找到完整数组边界。
  String? _balancedSlice(String text) {
    final start = text.indexOf('[');
    if (start < 0) return null;
    var depth = 0;
    var inStr = false;
    var esc = false;
    for (var i = start; i < text.length; i++) {
      final ch = text[i];
      if (inStr) {
        if (esc) {
          esc = false;
        } else if (ch == r'\') {
          esc = true;
        } else if (ch == '"') {
          inStr = false;
        }
        continue;
      }
      if (ch == '"') {
        inStr = true;
      } else if (ch == '[') {
        depth++;
      } else if (ch == ']') {
        depth--;
        if (depth == 0) return text.substring(start, i + 1);
      }
    }
    return null;
  }

  // ================= 动作名六级匹配级联（调研条目 12） =================
  //
  // L1 精确英文（英文别名表，大小写/连写归一）
  // L2 精确中文（词表全名相等）
  // L3 同义词表（中文口语别名 → 规范名）
  // L4 词序无关（去标点空白后字符多重集相等：「卧推杠铃」→「杠铃卧推」）
  // L5 强包含（输入含完整词表名；反向包含保留 A3-2 的 ≥3 字门槛）
  // L6 模糊匹配（编辑距离 score<0.15 且整批确定级覆盖率 ≥0.5 才自动命中，
  //    否则给 top5 候选进预览页人工确认——workout-timer 的自动命中口径）

  /// 同义词/英文别名表（→ 词表规范名）。只收无歧义映射；「卧推」「划船」
  /// 「深蹲」「弯举」「推肩」这类泛称刻意不放——歧义交给预览页人工确认，
  /// 保持 A3-2 收紧语义（泛称不被吸到最长变体）。
  @visibleForTesting
  static const kExerciseAliases = <String, String>{
    // 中文别名
    '平板卧推': '杠铃卧推',
    '杠铃推胸': '杠铃卧推',
    '上斜卧推': '上斜杠铃卧推',
    '引体': '引体向上',
    '正手引体': '引体向上',
    '引体向上（正手）': '引体向上',
    '引体向上(正手)': '引体向上',
    '背阔肌下拉': '高位下拉',
    '倒蹬': '腿举（倒蹬机）',
    '腿举': '腿举（倒蹬机）',
    '蝴蝶机': '坐姿夹胸（蝴蝶机）',
    '蝴蝶机夹胸': '坐姿夹胸（蝴蝶机）',
    '高脚杯深蹲': '哑铃高脚杯深蹲',
    '农夫行走': '哑铃农夫行走',
    '农夫走': '哑铃农夫行走',
    '侧平举': '哑铃侧平举',
    '前平举': '哑铃前平举',
    '罗马尼亚硬拉': '罗马尼亚硬拉',
    '臀推': '杠铃臀桥',
    '仰卧起坐': '卷腹',
    '波比': '波比跳',
    '立卧撑': '波比跳',
    '登山者': '登山跑',
    '登山式': '登山跑',
    '俄罗斯旋转': '俄罗斯转体',
    '壶铃摇摆': '壶铃摆荡',
    '单臂划船': '哑铃单臂划船',
    '飞鸟': '哑铃飞鸟',
    '提踵': '站姿提踵',
    '腿弯举': '腿弯举（腘绳肌）',
    '腿屈伸': '腿屈伸（股四头）',
    '哈克蹲': '哈克深蹲',
    '保加利亚蹲': '保加利亚分腿蹲',
    // 英文别名（键统一小写）
    'bench press': '杠铃卧推',
    'incline bench press': '上斜杠铃卧推',
    'push up': '俯卧撑',
    'push-up': '俯卧撑',
    'pushup': '俯卧撑',
    'pull up': '引体向上',
    'pull-up': '引体向上',
    'pullup': '引体向上',
    'chin up': '引体向上',
    'deadlift': '杠铃硬拉',
    'overhead press': '站姿推举',
    'ohp': '站姿推举',
    'lateral raise': '哑铃侧平举',
    'lat pulldown': '高位下拉',
    'barbell row': '杠铃划船',
    'leg press': '腿举（倒蹬机）',
    'leg curl': '腿弯举（腘绳肌）',
    'leg extension': '腿屈伸（股四头）',
    'calf raise': '站姿提踵',
    'hip thrust': '杠铃臀桥',
    'goblet squat': '哑铃高脚杯深蹲',
    'farmer walk': '哑铃农夫行走',
    'farmers walk': '哑铃农夫行走',
    'burpee': '波比跳',
    'burpees': '波比跳',
    'plank': '平板支撑',
    'russian twist': '俄罗斯转体',
    'mountain climber': '登山跑',
    'mountain climbers': '登山跑',
    'kettlebell swing': '壶铃摆荡',
    'dip': '双杠臂屈伸',
    'dips': '双杠臂屈伸',
    'bulgarian split squat': '保加利亚分腿蹲',
    'rdl': '罗马尼亚硬拉',
    'crunch': '卷腹',
    'sit up': '卷腹',
    'sit-up': '卷腹',
    'situp': '卷腹',
  };

  /// 一条动作名的匹配结果。
  /// （文件内声明于 AiService 之外，见文件末尾的 ExerciseMatch 类。）

  /// 批量匹配：先逐名跑 L1-L5（确定级），用确定级命中率算整批覆盖率，
  /// 未命中的再走 L6（模糊级受覆盖率门控）。
  @visibleForTesting
  List<ExerciseMatch> matchExerciseNames(List<String> raws) {
    final base = <ExerciseMatch?>[
      for (final raw in raws) _matchLevel1to5(raw),
    ];
    final determined = base.whereType<ExerciseMatch>().length;
    final coverage = raws.isEmpty ? 0.0 : determined / raws.length;
    return [
      for (var i = 0; i < raws.length; i++)
        base[i] ?? _fuzzyMatch(raws[i], coverage),
    ];
  }

  ExerciseMatch _hit(String name, int level) => ExerciseMatch(
        name: name,
        level: level,
        needsConfirm: false,
        candidates: const [],
        score: 0,
      );

  ExerciseMatch? _matchLevel1to5(String raw) {
    final key = raw.trim();
    if (key.isEmpty) return null;
    final lower = key.toLowerCase();
    final alias = kExerciseAliases[lower] ?? kExerciseAliases[key];
    if (alias != null) {
      // 纯 ASCII 视为 L1（英文精确），否则 L3（同义词表）
      return _hit(alias, RegExp(r'^[a-z0-9\s\-+()]+$').hasMatch(lower) ? 1 : 3);
    }
    for (final m in _sortedMeta) {
      if (m.name == key) return _hit(m.name, 2);
    }
    // L4 词序无关：去标点/空白后字符多重集相等
    final norm = _stripForOrder(key);
    if (norm.length >= 2) {
      for (final m in _sortedMeta) {
        if (_sameCharMultiset(norm, _stripForOrder(m.name))) {
          return _hit(m.name, 4);
        }
      }
    }
    // L5 强包含：输入含完整词表名（含变体注记），或词表核心名含输入
    // （≥3 字门槛，A3-2 收紧语义：泛称不落成长变体）
    ExerciseMeta? best;
    var bestDiff = -1;
    for (final m in _sortedMeta) {
      final core = m.name.replaceAll(RegExp(r'[（(].*[)）]'), '');
      final hit = key.contains(core) ||
          (core.contains(key) && key.length >= 3);
      if (!hit) continue;
      final diff = (core.length - key.length).abs();
      if (best == null || diff < bestDiff) {
        best = m;
        bestDiff = diff;
      }
    }
    if (best != null) return _hit(best.name, 5);
    return null;
  }

  ExerciseMatch _fuzzyMatch(String raw, double coverage) {
    final key = raw.trim();
    final scored = <(String, double)>[];
    for (final m in _sortedMeta) {
      final a = _stripForOrder(key);
      final b = _stripForOrder(m.name);
      final d = a.isEmpty ? b.length : _levenshtein(a, b);
      scored.add((m.name, d / (a.isEmpty ? 1 : a.length)));
    }
    scored.sort((x, y) => x.$2.compareTo(y.$2));
    final top = scored.take(5).map((e) => e.$1).toList();
    final bestScore = scored.isEmpty ? 1.0 : scored.first.$2;
    if (bestScore < 0.15 && coverage >= 0.5) {
      return ExerciseMatch(
        name: scored.first.$1,
        level: 6,
        needsConfirm: false,
        candidates: const [],
        score: bestScore,
      );
    }
    return ExerciseMatch(
      name: key,
      level: 0,
      needsConfirm: true,
      candidates: top,
      score: bestScore,
    );
  }

  /// 词序无关比较用的归一：去空白与中英文标点。
  String _stripForOrder(String s) =>
      s.replaceAll(RegExp(r'[\s，。、,.\-—（）()\[\]【】/×xX·:：]'), '');

  bool _sameCharMultiset(String a, String b) {
    if (a.length != b.length) return false;
    final counts = <String, int>{};
    for (var i = 0; i < a.length; i++) {
      counts[a[i]] = (counts[a[i]] ?? 0) + 1;
      counts[b[i]] = (counts[b[i]] ?? 0) - 1;
    }
    return counts.values.every((v) => v == 0);
  }

  /// 经典 Levenshtein DP（输入都是短动作名，O(n·m) 足够）。
  int _levenshtein(String a, String b) {
    final prev = List<int>.generate(b.length + 1, (i) => i);
    final cur = List<int>.filled(b.length + 1, 0);
    for (var i = 1; i <= a.length; i++) {
      cur[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        cur[j] = [
          prev[j] + 1,
          cur[j - 1] + 1,
          prev[j - 1] + cost,
        ].reduce((x, y) => x < y ? x : y);
      }
      for (var j = 0; j <= b.length; j++) {
        prev[j] = cur[j];
      }
    }
    return prev[b.length];
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

/// 一条动作名的匹配结果（六级级联，见 matchExerciseNames 注释）。
class ExerciseMatch {
  final String name;
  final int level; // 1..6 = 命中级；0 = 未自动命中（保留原名待确认）
  final bool needsConfirm;
  final List<String> candidates; // top5（按编辑距离升序）
  final double score; // 编辑距离率（越小越像）

  const ExerciseMatch({
    required this.name,
    required this.level,
    required this.needsConfirm,
    required this.candidates,
    required this.score,
  });
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
