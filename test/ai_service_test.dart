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
  });

  group('局域网 http 白名单', () {
    // _chat 是私有方法；这里通过公开提示词间接验证类可用，
    // 实际 http 白名单行为由模拟器 E2E（10.0.2.2 mock 服务器）覆盖。
    test('settings 未配置时 aiConfigured 为 false', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = Settings(await SharedPreferences.getInstance());
      expect(settings.aiConfigured, isFalse);
    });
  });
}
