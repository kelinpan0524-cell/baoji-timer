import 'package:flutter_test/flutter_test.dart';
import 'package:baoji_timer/engine/engine.dart';
import 'package:baoji_timer/services/ai_service.dart';
import 'package:baoji_timer/services/settings.dart';
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
}
