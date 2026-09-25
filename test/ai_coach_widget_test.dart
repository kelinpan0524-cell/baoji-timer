// AI 教练页 widget 冒烟：页面骨架渲染、排计划模式开关。
// AI 请求链路（成功/失败分支、消息序、真实 socket 连通）在
// ai_service_test.dart 已覆盖；这里只锁 UI 不崩 + 模式切换生效。
// 基建同 widget_layout_test：ffi 真库 + AppContainer 注入。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baoji_timer/core/app.dart';
import 'package:baoji_timer/ui/ai_coach_page.dart';
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
      child: const MaterialApp(home: AiCoachPage()),
    ));
    // 数据包加载挂在 postFrameCallback：多泵几帧让 ffi 查询落地
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('未配置：显示配置引导，不崩', (tester) async {
    await pumpPage(tester);
    expect(find.textContaining('还没配置 AI 接口'), findsOneWidget);
    expect(find.text('AI 教练'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('排计划模式开关：标题与状态行切换，一键复盘按钮让位', (tester) async {
    await pumpPage(tester);
    expect(find.text('AI 教练'), findsOneWidget);

    await tester.tap(find.byTooltip('排计划模式（对话安排计划）'));
    await tester.pump();

    expect(find.text('AI 教练 · 排计划'), findsOneWidget);
    // 排计划模式下隐藏一键复盘入口（两个 AI 行为不混用）
    expect(find.byTooltip('一键阶段复盘'), findsNothing);
    expect(tester.takeException(), isNull);

    // 再点一次退出，恢复问答模式标题
    await tester.tap(find.byTooltip('退出排计划模式'));
    await tester.pump();
    expect(find.text('AI 教练'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
