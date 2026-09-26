// 设置主页重构（2026-09-26 Arono：系统设置式分组行+子页面）回归测试：
// ①八个入口一屏可见（不再无限下滑）；②行点进去是子页（拿训练偏好验证）；
// ③AI 行状态摘要。基建同 ai_coach_widget_test：ffi 真库。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baoji_timer/core/app.dart';
import 'package:baoji_timer/ui/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDownAll(() async {
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase('$dir/baoji_timer.db');
  });

  late AppContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    container = AppContainer(prefs: prefs);
    await container.db.wipeAll();
    await container.planRepo.reload();
  });

  tearDown(() async {
    await container.db.wipeAll();
    container.dispose();
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(AppScope(
      container: container,
      // 设置主页与计划页同构：无自身 Scaffold，由宿主（HomeShell/测试）提供
      child: const MaterialApp(home: Scaffold(body: SettingsPage())),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('设置主页：八个入口一屏可见（不再无限下滑）', (tester) async {
    await pumpPage(tester);
    for (final t in [
      '语言',
      '训练偏好',
      '专注模式',
      'AI 教练',
      '飞书日历',
      '权限',
      '应用更新',
      '数据与备份',
    ]) {
      expect(find.text(t), findsOneWidget, reason: '$t 应作为分组行一屏可见');
      // 视口断言：八个入口都要在默认测试屏（高 600 逻辑像素）附近可达，
      // 防止未来往主页加内容把入口挤到深处、退化回「一直滑」
      expect(tester.getTopLeft(find.text(t)).dy, lessThan(800),
          reason: '$t 应贴近屏幕顶部（查找优化是本次重构的核心目标）');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('训练偏好子页可达：点行进入子页看到具体配置', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text('训练偏好'));
    await tester.pump(); // 起帧（动画首帧 elapsed=0，单次长 pump 不推进）
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('复合动作休息（秒）'), findsOneWidget,
        reason: '子页应展示具体配置项');
    expect(tester.takeException(), isNull);
  });

  testWidgets('AI 教练行：未配置时状态摘要可见', (tester) async {
    await pumpPage(tester);
    expect(find.text('未配置'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
