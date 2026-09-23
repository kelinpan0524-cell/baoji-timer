import 'package:flutter_test/flutter_test.dart';
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
}
