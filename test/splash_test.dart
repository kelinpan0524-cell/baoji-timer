import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:baoji_timer/ui/splash_page.dart';

void main() {
  testWidgets('开机动画播完交叉淡出到首页', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: SplashGate(child: SizedBox.expand(key: Key('home'))),
    ));

    // 动画进行中：停在开机画面
    expect(find.byType(SplashPage), findsOneWidget);
    expect(find.byKey(const Key('home')), findsNothing);

    await tester.pumpAndSettle();

    // 播完：交叉淡出到正式首页
    expect(find.byType(SplashPage), findsNothing);
    expect(find.byKey(const Key('home')), findsOneWidget);
  });
}
