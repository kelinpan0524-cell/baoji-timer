import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:baoji_timer/engine/engine.dart';
import 'package:baoji_timer/services/ai_service.dart';
import 'package:baoji_timer/services/settings.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AiService ai;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    ai = AiService(Settings(prefs));
  });

  group('自然语言生成提示词', () {
    test('包含用户描述与 JSON 契约要素', () {
      final prompt = ai.buildDesignerPrompt('每周四练，练背、胸、腿，增肌');
      expect(prompt.contains('每周四练，练背、胸、腿，增肌'), isTrue,
          reason: '用户描述要进提示词');
      expect(prompt.contains('weekday'), isTrue);
      expect(prompt.contains('main_muscle'), isTrue);
      expect(prompt.contains('渐进超负荷'), isTrue);
      expect(prompt.contains('JSON'), isTrue);
    });

    test('原文导入与描述生成的提示词不同', () {
      // 两个模式的提示词必须可区分（解析契约相同、指令不同）
      final designer = ai.buildDesignerPrompt('练背');
      // _buildPrompt 私有，用 designer 与已知解析提示词的关键差异断言
      expect(designer.contains('设计一份每周力量训练计划'), isTrue);
      expect(designer.contains('训练计划文本转换为'), isFalse);
    });

    test('未配置 AI 时生成/拆解都给出可读错误', () async {
      expect(
        () => ai.designPlanFromDescription('练背'),
        throwsA(isA<AiException>()),
      );
      expect(() => ai.parsePlan('周一 卧推 3×5-8'), throwsA(isA<AiException>()));
    });

    test('设计提示词尊重用户指定的训练天数', () {
      final prompt = ai.buildDesignerPrompt('每周 6 练');
      expect(prompt.contains('每周 6 练'), isTrue);
      expect(prompt.contains('训练天数都尊重用户'), isTrue);
    });
  });

  group('局域网 http 白名单', () {
    test('数值私有 IP 放行，域名形状不放行', () {
      expect(AiService.isLocalHost('10.0.2.2'), isTrue);
      expect(AiService.isLocalHost('192.168.1.10'), isTrue);
      expect(AiService.isLocalHost('172.16.0.1'), isTrue);
      expect(AiService.isLocalHost('127.0.0.1'), isTrue);
      expect(AiService.isLocalHost('localhost'), isTrue);
      // 域名形状不能绕过
      expect(AiService.isLocalHost('10.evil.com'), isFalse);
      expect(AiService.isLocalHost('192.168.evil.com'), isFalse);
      expect(AiService.isLocalHost('evil.com'), isFalse);
      expect(AiService.isLocalHost('2130706433'), isFalse);
      // 越界段
      expect(AiService.isLocalHost('10.0.0.999'), isFalse);
    });

    test('settings 未配置时 aiConfigured 为 false', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = Settings(await SharedPreferences.getInstance());
      expect(settings.aiConfigured, isFalse);
    });
  });

  group('parseResponse 集中清洗（防弱模型输出毒化）', () {
    test('weekday 越界的训练日被丢弃（不再 RangeError/幽灵日）', () {
      // 全部越界 → 抛可读异常，而不是渲染崩或落幽灵日
      expect(
        () => ai.parseResponse(
            '[{"weekday":0,"title":"x","exercises":[{"name":"卧推","sets":3,"reps_min":5,"reps_max":8}]},'
            '{"weekday":8,"title":"y","exercises":[{"name":"划船","sets":3,"reps_min":5,"reps_max":8}]}]'),
        throwsA(isA<AiException>()),
      );
      // 部分越界 → 只保留合法日
      final specs = ai.parseResponse(
          '[{"weekday":0,"title":"x","exercises":[{"name":"卧推","sets":3,"reps_min":5,"reps_max":8}]},'
          '{"weekday":3,"title":"y","exercises":[{"name":"划船","sets":3,"reps_min":5,"reps_max":8}]}]');
      expect(specs.length, 1);
      expect(specs.first.weekday, 3);
    });

    test('数字为字符串/全角也能解析；sets/reps/rest 钳制与交换', () {
      final specs = ai.parseResponse(
          '[{"weekday":"1","title":"推","exercises":[{"name":"卧推","sets":"４","reps_min":"12","reps_max":"8","rest_sec":"999"}]}]');
      expect(specs.length, 1);
      expect(specs.first.weekday, 1);
      final ex = specs.first.exercises.first;
      expect(ex.sets, 4);
      expect(ex.repsMin, 8, reason: '倒挂自动交换');
      expect(ex.repsMax, 12);
      expect(ex.restSec, 600);
    });

    test('两个训练日同 weekday 自动合并到一天', () {
      final specs = ai.parseResponse(
          '[{"weekday":1,"title":"A","exercises":[{"name":"卧推","sets":3,"reps_min":5,"reps_max":8}]},'
          '{"weekday":1,"title":"B","exercises":[{"name":"划船","sets":3,"reps_min":5,"reps_max":8}]}]');
      expect(specs.length, 1, reason: '保持一周一天不变量');
      expect(specs.first.exercises.length, 2);
    });

    test('markdown 围栏与前后散文都能容错', () {
      final specs = ai.parseResponse(
          '好的，方案如下：\n```json\n[{"weekday":2,"title":"腿","exercises":[{"name":"深蹲","sets":3,"reps_min":5,"reps_max":8}]}]\n```\n以上。');
      expect(specs.length, 1);
      expect(specs.first.weekday, 2);
    });

    test('空 name 的动作被跳过，全空抛可读异常', () {
      expect(
        () => ai.parseResponse('[{"weekday":1,"title":"x","exercises":[{"name":"","sets":3,"reps_min":5,"reps_max":8}]}]'),
        throwsA(isA<AiException>()),
      );
    });
  });

  group('名称归一收紧（A3-2：泛称不被吸成长变体）', () {
    test('「卧推」保留原名，不落成「上斜杠铃卧推（轻）」等最长变体', () {
      final specs = ai.parseResponse(
          '[{"weekday":1,"title":"推","exercises":[{"name":"卧推","sets":3,"reps_min":5,"reps_max":8}]}]');
      expect(specs.first.exercises.first.name, '卧推',
          reason: '2 字泛称低于 3 字门槛，反向匹配不放行，走沉淀兜底');
    });

    test('「划船」「深蹲」等泛称同样保留原名', () {
      final specs = ai.parseResponse(
          '[{"weekday":3,"title":"背","exercises":[{"name":"划船","sets":3,"reps_min":5,"reps_max":8},{"name":"深蹲","sets":3,"reps_min":5,"reps_max":8}]}]');
      expect(specs.first.exercises[0].name, '划船',
          reason: '不落成「弹力带坐姿划船」');
      expect(specs.first.exercises[1].name, '深蹲',
          reason: '不落成「哑铃高脚杯深蹲」');
    });

    test('「杠铃卧推」精确命中词表，归一不变', () {
      final specs = ai.parseResponse(
          '[{"weekday":1,"title":"推","exercises":[{"name":"杠铃卧推","sets":3,"reps_min":5,"reps_max":8}]}]');
      expect(specs.first.exercises.first.name, '杠铃卧推');
    });

    test('完整词表名（含变体前缀）正向包含仍归一到词表', () {
      // 输入含完整词表名：归一到对应词表动作
      final specs = ai.parseResponse(
          '[{"weekday":1,"title":"推","exercises":[{"name":"杠铃卧推 5x5","sets":3,"reps_min":5,"reps_max":8}]}]');
      expect(specs.first.exercises.first.name, '杠铃卧推');
    });
  });

  group('rest_sec 缺失视作缺失（A3-3：让用户休息偏好兜底生效）', () {
    test('缺失 rest_sec → restSec 为 null', () {
      final specs = ai.parseResponse(
          '[{"weekday":2,"title":"腿","exercises":[{"name":"杠铃深蹲","sets":3,"reps_min":5,"reps_max":8}]}]');
      expect(specs.first.exercises.first.restSec, isNull,
          reason: 'saveAiPlan 的 defaultRestSec 才能按用户偏好兜底');
    });

    test('rest_sec 为 0 视为缺失 → null（不再落 0 脏数据）', () {
      final specs = ai.parseResponse(
          '[{"weekday":2,"title":"腿","exercises":[{"name":"杠铃深蹲","sets":3,"reps_min":5,"reps_max":8,"rest_sec":0}]}]');
      expect(specs.first.exercises.first.restSec, isNull);
    });

    test('rest_sec 正常值保留（150）', () {
      final specs = ai.parseResponse(
          '[{"weekday":2,"title":"腿","exercises":[{"name":"杠铃深蹲","sets":3,"reps_min":5,"reps_max":8,"rest_sec":150}]}]');
      expect(specs.first.exercises.first.restSec, 150);
    });
  });

  group('解析异常归一为 AiException（A3-4）', () {
    test('非法 JSON（title 未加引号）抛 AiException 中文归一文案', () {
      expect(
        () => ai.parseResponse('[{weekday:1,"title":"推","exercises":[]}]'),
        throwsA(isA<AiException>().having((e) => e.message, 'message',
            'AI 返回格式无法解析，请重试或换模型')),
      );
    });

    test('exercises 是字符串：该日被丢弃后抛「没有解析出任何训练日」', () {
      expect(
        () => ai.parseResponse(
            '[{"weekday":1,"title":"推","exercises":"卧推 3组"}]'),
        throwsA(isA<AiException>()
            .having((e) => e.message, 'message', '没有解析出任何训练日，请检查文本')),
      );
    });

    test('item 是数字：跳过后抛「没有解析出任何训练日」', () {
      expect(
        () => ai.parseResponse('[1]'),
        throwsA(isA<AiException>()
            .having((e) => e.message, 'message', '没有解析出任何训练日，请检查文本')),
      );
    });

    test('title 是数字：回退「训练日」，不抛 TypeError', () {
      final specs = ai.parseResponse(
          '[{"weekday":1,"title":123,"exercises":[{"name":"杠铃卧推","sets":3,"reps_min":5,"reps_max":8}]}]');
      expect(specs.first.title, '训练日');
    });
  });

  group('Base URL scheme 校验（A3-5）', () {
    test('Ollama 官方写法缺 scheme：提示补前缀而非误报公网', () {
      expect(AiService.baseUrlSchemeError('localhost:11434'),
          '地址缺少 http:// 或 https:// 前缀，请补全（局域网自建模型可用 http://）');
    });

    test('局域网 http 合法 → null', () {
      expect(AiService.baseUrlSchemeError('http://10.0.0.5:8080'), isNull);
    });

    test('公网 http 仍拦截 → 公网文案', () {
      expect(AiService.baseUrlSchemeError('http://evil.com'),
          '公网地址必须 https://（局域网自建模型可用 http）');
    });

    test('https 公网合法 → null', () {
      expect(AiService.baseUrlSchemeError('https://api.x.com/v1'), isNull);
    });
  });

  group('JSON 三层容错（调研条目 12）', () {
    test('第①层：直接解析纯 JSON 数组', () {
      final list = ai.extractJsonPayload('[{"weekday":1,"title":"推"}]');
      expect(list, isA<List>());
      expect((list.first as Map)['weekday'], 1);
    });

    test('第②层：剥 ```json 代码围栏（带前后散文）', () {
      final list = ai.extractJsonPayload(
          '好的，方案如下：\n```json\n[{"weekday":2}]\n```\n以上。');
      expect((list.first as Map)['weekday'], 2);
    });

    test('第②层变体：无 json 标记的裸代码围栏', () {
      final list = ai.extractJsonPayload('```\n[{"weekday":3}]\n```');
      expect((list.first as Map)['weekday'], 3);
    });

    test('第③层：括号配平扫描——围栏残缺也能截出完整数组', () {
      // 围栏未闭合（第②层失败），前后有散文（第①层失败）
      final list = ai.extractJsonPayload(
          '计划如下：\n```json\n[{"weekday":1,"title":"推","exercises":[{"name":"杠铃卧推","sets":3}]}]，祝训练愉快');
      expect((list.first as Map)['weekday'], 1);
    });

    test('第③层：字符串内的括号不干扰配平（字符串感知）', () {
      final list = ai.extractJsonPayload(
          '输出：[{"title":"腿（股四头）日"},{"title":"x"}] 尾部垃圾]]');
      expect(list.length, 2);
    });

    test('三层全失败 → AiException 中文归一文案', () {
      expect(
        () => ai.extractJsonPayload('完全不是 JSON 的输出'),
        throwsA(isA<AiException>()),
      );
      expect(
        () => ai.extractJsonPayload('[{weekday:1}]'),
        throwsA(isA<AiException>()),
      );
    });
  });

  group('动作名六级匹配级联（调研条目 12）', () {
    test('L1 精确英文：Bench Press → 杠铃卧推（大小写/空格归一）', () {
      final m = ai.matchExerciseNames(['Bench Press']).first;
      expect(m.level, 1);
      expect(m.name, '杠铃卧推');
      expect(m.needsConfirm, isFalse);
    });

    test('L2 精确中文：词表全名直接命中', () {
      final m = ai.matchExerciseNames(['上斜杠铃卧推']).first;
      expect(m.level, 2);
      expect(m.name, '上斜杠铃卧推');
    });

    test('L3 同义词表：倒蹬 → 腿举（倒蹬机）、引体 → 引体向上', () {
      expect(ai.matchExerciseNames(['倒蹬']).first.name, '腿举（倒蹬机）');
      expect(ai.matchExerciseNames(['倒蹬']).first.level, 3);
      expect(ai.matchExerciseNames(['引体']).first.name, '引体向上');
    });

    test('L4 词序无关：卧推杠铃 → 杠铃卧推', () {
      final m = ai.matchExerciseNames(['卧推杠铃']).first;
      expect(m.level, 4);
      expect(m.name, '杠铃卧推');
    });

    test('L5 强包含：杠铃卧推 5x5 → 杠铃卧推；泛称仍不被吸成长变体', () {
      final hit = ai.matchExerciseNames(['杠铃卧推 5x5']).first;
      expect(hit.level, 5);
      expect(hit.name, '杠铃卧推');
      // A3-2 收紧语义保留：2 字泛称不自动落成长变体
      final miss = ai.matchExerciseNames(['卧推']).first;
      expect(miss.name, '卧推', reason: '泛称保留原名');
      expect(miss.needsConfirm, isTrue, reason: '泛称进人工确认');
    });

    test('L6 模糊级：score<0.15 且整批覆盖率≥0.5 才自动命中', () {
      // 批内 1/2 确定命中 → coverage 0.5 达标；错别字 1/7 ≈ 0.14 < 0.15
      final matches = ai.matchExerciseNames(['杠铃卧推', '哑铃颈后臂屈仲']);
      expect(matches[0].level, 2);
      expect(matches[1].level, 6);
      expect(matches[1].name, '哑铃颈后臂屈伸');
      expect(matches[1].needsConfirm, isFalse);
    });

    test('L6 门控：覆盖率 <0.5 时即使 score 达标也不自动命中', () {
      // 单独一个近似名：coverage 0，不许模糊自动命中
      final m = ai.matchExerciseNames(['哑铃颈后臂屈仲']).first;
      expect(m.needsConfirm, isTrue);
      expect(m.name, '哑铃颈后臂屈仲', reason: '保留原名等人工确认');
      expect(m.candidates, isNotEmpty, reason: '给 top5 候选');
    });

    test('L6 门控：score ≥0.15 不自动命中，candidates 按相似度排序 top5', () {
      final m = ai.matchExerciseNames(['杠铃卧推', '坐姿划般']).last;
      // 坐姿划般 vs 坐姿划船：错 1/4 字 = 0.25
      expect(m.needsConfirm, isTrue);
      expect(m.candidates.length, lessThanOrEqualTo(5));
      expect(m.candidates.first, '坐姿划船', reason: 'top1 是最像的坐姿划船');
    });

    test('完全对不上的名字保留原名且给候选', () {
      final m = ai.matchExerciseNames(['杠铃卧推', '神秘星球动作']).last;
      expect(m.name, '神秘星球动作');
      expect(m.needsConfirm, isTrue);
      expect(m.level, 0);
    });
  });

  group('parseResponse 集成匹配元数据（调研条目 12 落库前确认的数据源）', () {
    test('精确命中动作 needsConfirm=false、rawName 保留 AI 原文', () {
      final specs = ai.parseResponse(
          '[{"weekday":1,"title":"推","exercises":[{"name":"杠铃卧推","sets":3,"reps_min":5,"reps_max":8}]}]');
      final ex = specs.first.exercises.first;
      expect(ex.needsConfirm, isFalse);
      expect(ex.rawName, '杠铃卧推');
      expect(ex.candidates, isEmpty);
    });

    test('泛称动作 needsConfirm=true、候选非空，保存侧可用原名沉淀', () {
      final specs = ai.parseResponse(
          '[{"weekday":1,"title":"推","exercises":[{"name":"卧推","sets":3,"reps_min":5,"reps_max":8}]}]');
      final ex = specs.first.exercises.first;
      expect(ex.needsConfirm, isTrue);
      expect(ex.name, '卧推', reason: '未确认前保留原名');
      expect(ex.rawName, '卧推');
      expect(ex.candidates, isNotEmpty);
    });
  });

  group('localInsights 依赖真实 doneAt 分天（A6-2 旁证）', () {
    SetEntry setOf(int doneAt, double w) => SetEntry(
          sessionExerciseId: 1,
          weightKg: w,
          reps: 5,
          kind: SetKind.working,
          doneAt: doneAt,
        );

    test('跨天且后一天 1RM 降幅超 10% → 产出提醒', () {
      final day1 = 1758640000000; // 固定基准日
      final day3 = day1 + 2 * 86400000; // 两天后，跨天
      final insights = localInsights({
        '杠铃深蹲': [
          setOf(day1, 100), // 1RM ≈ 116.7
          setOf(day3, 60), // 1RM = 70，降幅 > 10%
        ],
      });
      expect(insights, isNotEmpty);
      expect(insights.first, contains('杠铃深蹲'));
      expect(insights.first, contains('下降'));
    });

    test('doneAt 全 0 → 永远只有一天 → 产不出提醒（固化回归认知）', () {
      final insights = localInsights({
        '杠铃深蹲': [setOf(0, 100), setOf(0, 60)],
      });
      expect(insights, isEmpty);
    });
  });

  group('AI 教练：人设与消息组装', () {
    test('人设包含身份、数据为准与安全边界要素', () {
      expect(AiService.kCoachPersona.contains('薄肌教练'), isTrue);
      expect(AiService.kCoachPersona.contains('以数据为准'), isTrue);
      expect(AiService.kCoachPersona.contains('不做医疗诊断'), isTrue);
      expect(AiService.kCoachPersona.contains('渐进超负荷'), isTrue);
    });

    test('一键复盘指令覆盖各分析维度', () {
      final p = AiService.kAnalysisInstruction;
      expect(p.contains('渐进超负荷'), isTrue);
      expect(p.contains('肌群均衡'), isTrue);
      expect(p.contains('计划休息 vs 实际休息'), isTrue);
      expect(p.contains('调整建议'), isTrue);
    });

    test('buildCoachMessages：人设开头、数据包独立段、用户输入在末尾', () {
      final msgs = ai.buildCoachMessages('DATA-PACK',
          history: const [AiMessage('assistant', '上次回答')],
          userText: '我练得怎么样？');
      expect(msgs.length, 4);
      expect(msgs[0].role, 'system');
      expect(msgs[0].content, AiService.kCoachPersona);
      expect(msgs[1].role, 'system');
      expect(msgs[1].content.contains('DATA-PACK'), isTrue);
      expect(msgs[2].role, 'assistant');
      expect(msgs[2].content, '上次回答');
      expect(msgs[3].role, 'user');
      expect(msgs[3].content, '我练得怎么样？');
    });

    test('未配置时 chat() 抛可读错误（教练对话绝不静默回落本地）', () {
      expect(
        () => ai.chat(const [AiMessage('user', '你好')]),
        throwsA(isA<AiException>().having(
            (e) => e.message, 'message',
            contains('未配置 AI 接口'))),
      );
    });
  });

  group('连接测试与多轮对话（http 注入 + 本机模拟服务器）', () {
    // flutter_test 会拦截测试内所有 HttpClient 请求（一律回 400），因此：
    // - 各失败分支用 http/testing MockClient 注入 AiService（无 socket，确定性）；
    // - 真实连通性用 HttpOverrides.runZoned 放行 socket + 本机 HttpServer 验证
    //   （没有真实 API Key——Key 只存手机本地——这是本机/CI 能做的最实连接测试）。
    Future<AiService> serviceWith(http.Client client) async {
      SharedPreferences.setMockInitialValues({
        'set.aiBaseUrl': 'http://127.0.0.1:1',
        'set.aiApiKey': 'sk-test',
        'set.aiModel': 'test-model',
      });
      final prefs = await SharedPreferences.getInstance();
      return AiService(Settings(prefs), httpClient: client);
    }

    // http.Response(String) 默认 latin1，中文必须走 utf8 字节
    http.Response jsonResponse(Map<String, dynamic> body, [int status = 200]) =>
        http.Response.bytes(utf8.encode(jsonEncode(body)), status,
            headers: {'content-type': 'application/json; charset=utf-8'});

    test('testConnection 成功：带 Bearer 头与 model，返回模型回复', () async {
      String? auth;
      Map<String, dynamic>? sent;
      final svc = await serviceWith(MockClient((req) async {
        auth = req.headers['authorization'];
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        return jsonResponse({
          'choices': [
            {
              'message': {'role': 'assistant', 'content': '连接正常'}
            }
          ]
        });
      }));
      final (ms, reply) = await svc.testConnection();
      expect(reply, '连接正常');
      expect(ms >= 0, isTrue);
      expect(auth, 'Bearer sk-test');
      expect(sent!['model'], 'test-model');
    });

    test('教练多轮对话：system 人设+数据包在前，历史与用户输入按序重发', () async {
      List<dynamic>? roles;
      final svc = await serviceWith(MockClient((req) async {
        roles = (jsonDecode(req.body)['messages'] as List)
            .map((m) => m['role'])
            .toList();
        return jsonResponse({
          'choices': [
            {
              'message': {'role': 'assistant', 'content': '根据数据，胸落后了'}
            }
          ]
        });
      }));
      final reply = await svc.chat(svc.buildCoachMessages('近8周数据',
          history: const [AiMessage('assistant', '上次说练背')], userText: '弱项是啥'));
      expect(reply, '根据数据，胸落后了');
      expect(roles, ['system', 'system', 'assistant', 'user']);
    });

    test('401 → 归一为「API Key 无效」', () async {
      final svc = await serviceWith(
          MockClient((req) async => http.Response('{"error":"bad"}', 401)));
      await expectLater(
        svc.testConnection(),
        throwsA(isA<AiException>()
            .having((e) => e.message, 'message', 'API Key 无效')),
      );
    });

    test('200 但返回网关错误页 → 归一为「不是有效 JSON」', () async {
      final svc = await serviceWith(
          MockClient((req) async => http.Response('<html>502</html>', 200)));
      await expectLater(
        svc.testConnection(),
        throwsA(isA<AiException>().having((e) => e.message, 'message',
            contains('AI 返回的不是有效 JSON'))),
      );
    });

    test('choices 里 content 为空 → 归一为「模型没有输出内容」', () async {
      final svc = await serviceWith(MockClient((req) async => jsonResponse({
            'choices': [
              {
                'message': {'role': 'assistant', 'content': ''}
              }
            ]
          })));
      await expectLater(
        svc.testConnection(),
        throwsA(isA<AiException>().having(
            (e) => e.message, 'message',
            contains('模型没有输出内容'))),
      );
    });

    test('真实 socket 连通：本机 HttpServer + runZoned 放行，走生产 IOClient 路径',
        () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((req) async {
        await utf8.decoder.bind(req).join();
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({
          'choices': [
            {
              'message': {'role': 'assistant', 'content': '连接正常'}
            }
          ]
        }));
        await req.response.close();
      });
      SharedPreferences.setMockInitialValues({
        'set.aiBaseUrl': 'http://127.0.0.1:${server.port}',
        'set.aiApiKey': 'sk-test',
        'set.aiModel': 'test-model',
      });
      final prefs = await SharedPreferences.getInstance();
      final svc = AiService(Settings(prefs)); // 不注入：走生产 http.post
      // flutter_test 装了"一律 400"的全局 HttpOverrides（只写不可读）。
      // 摘除后造真 HttpClient（本文件独立 isolate，后续用例不依赖假客户端）；
      // runZoned 的 createHttpClient 回调里直接 new HttpClient() 会递归
      // 自引用爆栈，所以必须在 zone 外把真 client 造好再交进去。
      HttpOverrides.global = null;
      final realClient = HttpClient();
      final (ms, reply) = await HttpOverrides.runZoned(
        () => svc.testConnection(),
        createHttpClient: (_) => realClient,
      );
      expect(reply, '连接正常');
      expect(ms >= 0, isTrue);
    });
  });

  group('对话式排计划', () {
    test('契约包含 JSON 结构、多轮「完整输出」规则与参考词表', () {
      final p = AiService.planChatContract();
      expect(p.contains('```json'), isTrue);
      expect(p.contains('"weekday"'), isTrue);
      // 调整后必须重新输出完整计划（不是只给改动项）——多轮排计划的关键
      expect(p.contains('完整'), isTrue);
      expect(p.contains('间隔 48 小时'), isTrue);
      // 参考词表进契约：动作名才能落在内置词表上
      expect(p.contains('杠铃卧推'), isTrue);
    });

    test('buildPlanChatMessages：人设+排计划契约合并、数据包独立、历史与输入在尾', () {
      final msgs = ai.buildPlanChatMessages('DATA-PACK',
          history: const [AiMessage('assistant', '上次')],
          userText: 'u');
      expect(msgs.length, 4);
      expect(msgs[0].role, 'system');
      expect(msgs[0].content.contains('薄肌教练'), isTrue, reason: '人设保留');
      expect(msgs[0].content.contains('排计划模式'), isTrue, reason: '契约叠加');
      expect(msgs[1].role, 'system');
      expect(msgs[1].content.contains('DATA-PACK'), isTrue);
      expect(msgs[2].content, '上次');
      expect(msgs[3].role, 'user');
      expect(msgs[3].content, 'u');
    });

    test('tryExtractPlan：思路 + json 围栏 + 说明 的教练回复可提取出计划', () {
      final reply = '好的，按每周三练设计，推拉腿分化，胸肩放在推日：\n'
          '```json\n'
          '[{"weekday":1,"title":"推日","exercises":[{"name":"杠铃卧推","sets":3,"reps_min":5,"reps_max":8,"rest_sec":180,"kind":"compound","main_muscle":"胸"}]}]\n'
          '```\n'
          '想调整随时说，比如「腿日加哈克深蹲」。';
      final specs = ai.tryExtractPlan(reply);
      expect(specs, isNotNull);
      expect(specs!.length, 1);
      expect(specs.first.title, '推日');
      expect(specs.first.exercises.first.name, '杠铃卧推');
      expect(specs.first.exercises.first.restSec, 180);
    });

    test('tryExtractPlan：纯文字轮次（AI 问澄清）返回 null 不抛错', () {
      expect(ai.tryExtractPlan('你想每周练几天？家里有哑铃吗？'), isNull);
    });

    test('tryExtractPlan：无围栏裸 JSON 也能提取（三层容错第①层）', () {
      final specs = ai.tryExtractPlan(
          '[{"weekday":2,"title":"拉日","exercises":[{"name":"引体向上","sets":3,"reps_min":5,"reps_max":8}]}]');
      expect(specs, isNotNull);
      expect(specs!.first.title, '拉日');
    });
  });
}
