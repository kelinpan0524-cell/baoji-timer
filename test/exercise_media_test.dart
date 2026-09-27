// 动作图文解析（2026-09-27）测试：
// - 要点完整性：内置动作库 122 条全部有非空 cue（新写的 105 + 原 16）
// - 映射完整性：kExerciseImageIdMap 的键都是内置动作；映射的 216 张图片
//   资产全部真的打包进来了（AssetManifest 校验，防「改了映射忘跑管道」）
// - 解析段渲染：有图动作显示 起始/结束姿势 + 要点；无图无要点显示兜底文案
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baoji_timer/presets/exercise_library.dart';
import 'package:baoji_timer/presets/exercise_media.dart';
import 'package:baoji_timer/ui/exercise_detail_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('要点完整性：全部内置动作都有动作要点', () {
    final missing = [
      for (final m in kExerciseLibrary)
        if (m.cue.trim().isEmpty) m.name,
    ];
    expect(missing, isEmpty,
        reason: '以下动作缺要点：$missing（补齐后本测试守护不回退）');
  });

  test('映射完整性：映射键 ∈ 内置动作库；映射 id 唯一性正常（复用合法）', () {
    final names = {for (final m in kExerciseLibrary) m.name};
    final unknown = kExerciseImageIdMap.keys
        .where((k) => !names.contains(k))
        .toList();
    expect(unknown, isEmpty, reason: '映射表里有动作库外的名字：$unknown');
    // 复用是合法的（如 上斜杠铃卧推（轻） 复用 上斜卧推），只要求键都有效
    expect(kExerciseImageIdMap.length, greaterThan(100));
  });

  test('资产完整性：映射到的图片文件全部打进 assets', () async {
    // flutter test 的资产包里没有 AssetManifest.json，直接逐张加载验证
    // （共 216 张、约 3.4MB，秒级完成；改了映射忘跑转换脚本会被抓住）
    final missing = <String>[];
    final seen = <String>{};
    for (final name in kExerciseImageIdMap.keys) {
      for (final p in exerciseImageAssets(name)) {
        if (!seen.add(p)) continue;
        try {
          await rootBundle.load(p);
        } on Exception {
          missing.add(p);
        }
      }
    }
    expect(seen.length, 218, reason: '唯一资产数应为 109 动作 × 2 张');
    expect(missing, isEmpty, reason: '以下图片资产缺失（重跑转换脚本）：$missing');
  });

  testWidgets('解析段：有图动作显示 起始/结束姿势 与要点', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(
          children: exerciseMediaSection(
              '杠铃卧推', libraryMetaByName('杠铃卧推')),
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('起始姿势'), findsOneWidget);
    expect(find.text('结束姿势'), findsOneWidget);
    expect(find.text('动作要点'), findsOneWidget);
    expect(find.byType(Image), findsNWidgets(2));
    // 要点文本确实带出了内容（非空且含常见错误提示）
    expect(find.textContaining('常见错误'), findsOneWidget);
  });

  testWidgets('解析段：无图无要点的词表外动作显示兜底文案', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(
          children: exerciseMediaSection('某个AI编的动作', null),
        ),
      ),
    ));
    expect(find.textContaining('还没有图文解析'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });
}
