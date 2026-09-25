// 调研条目 5：长按 2 秒结束训练按钮。
// 覆盖：2 秒填满触发 / 松手取消 / 进度不足 30% 教手势回调 /
// 读屏（accessibleNavigation）退化单击直通的无障碍替代路径。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baoji_timer/ui/workout_page.dart';

Widget host({
  bool accessible = false,
  required VoidCallback onConfirmed,
  VoidCallback? onShortRelease,
}) {
  return MediaQuery(
    data: MediaQueryData(accessibleNavigation: accessible),
    child: MaterialApp(
      home: Scaffold(
        body: Center(
          child: HoldToEndButton(
            onConfirmed: onConfirmed,
            onShortRelease: onShortRelease,
          ),
        ),
      ),
    ),
  );
}

Future<TestGesture> pressDown(WidgetTester tester) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byType(HoldToEndButton)),
  );
  // 越过框架长按判定（kLongPressTimeout 500ms）后 onLongPressStart 才到，
  // 计时从这一刻起算——各用例的时长都是判定之后的净按住时长
  await tester.pump(const Duration(milliseconds: 600));
  return gesture;
}

void main() {
  testWidgets('按住满 2 秒：环形进度填满即触发（无需等松手）', (tester) async {
    var confirmed = 0;
    await tester.pumpWidget(
      host(
        accessible: false,
        onConfirmed: () => confirmed++,
        onShortRelease: () => fail('满进度不应触发教手势'),
      ),
    );
    final gesture = await pressDown(tester);
    await tester.pump(const Duration(milliseconds: 900));
    expect(confirmed, 0); // 半途未触发
    await tester.pump(const Duration(milliseconds: 1200)); // 累计 2.1 秒
    expect(confirmed, 1); // 填满即触发
    await gesture.up();
    await tester.pump();
    expect(confirmed, 1); // 不重复触发
  });

  testWidgets('按住 0.5 秒（进度 <30%）松手：取消 + 教手势回调', (tester) async {
    var confirmed = 0;
    var hinted = 0;
    await tester.pumpWidget(
      host(
        accessible: false,
        onConfirmed: () => confirmed++,
        onShortRelease: () => hinted++,
      ),
    );
    final gesture = await pressDown(tester);
    // 判定后 100ms 已走 2 个 tick，再加 400ms → elapsed 500ms（25% < 30%）
    await tester.pump(const Duration(milliseconds: 400));
    await gesture.up();
    await tester.pump();
    expect(confirmed, 0);
    expect(hinted, 1);
  });

  testWidgets('按住 1.2 秒（进度 >30%）松手：取消但不教手势（用户主动放弃）', (tester) async {
    var confirmed = 0;
    var hinted = 0;
    await tester.pumpWidget(
      host(
        accessible: false,
        onConfirmed: () => confirmed++,
        onShortRelease: () => hinted++,
      ),
    );
    final gesture = await pressDown(tester);
    await tester.pump(
      const Duration(milliseconds: 1100),
    ); // elapsed 1200ms（60%）
    await gesture.up();
    await tester.pump();
    expect(confirmed, 0);
    expect(hinted, 0);
  });

  testWidgets('读屏开启（TalkBack）：单击直接触发，长按手势退场', (tester) async {
    var confirmed = 0;
    await tester.pumpWidget(
      host(
        accessible: true,
        onConfirmed: () => confirmed++,
        onShortRelease: () => fail('无障碍路径不应有教手势'),
      ),
    );
    await tester.tap(find.byType(HoldToEndButton));
    await tester.pump();
    expect(confirmed, 1);
    expect(find.text('结束训练'), findsOneWidget);
  });

  testWidgets('语义标签：按钮朗读"结束训练"并带长按提示', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    await tester.pumpWidget(host(accessible: false, onConfirmed: () {}));
    final semantics = tester.getSemantics(find.byType(HoldToEndButton));
    // 外层 Semantics.label 与内部 Text 的语义合并后成对出现
    expect(semantics.label, contains('结束训练'));
    expect(semantics.hint, '长按两秒打开结束选项');
    semanticsHandle.dispose();
  });
}
