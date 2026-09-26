// 全量测试的统一前置（flutter test 自动套用）：
// 把测试平台语言钉成中文——项目测试基线是中文界面断言，而 Flutter 测试
// 环境默认系统语言是 en_US，「跟随系统」会被解析成英文导致批量假失败。
// 注意：框架在每个用例结束后会清掉测试平台的 override 值，
// 所以必须在 setUp 里逐用例重新钉，不能只在入口钉一次。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher.localeTestValue =
        const Locale('zh');
  });
  await testMain();
}
