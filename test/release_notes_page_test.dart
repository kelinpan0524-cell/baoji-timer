// 更新说明全文页（2026-09-27 Arono 报障修复）：
// b93 起说明变长，更新卡片只截 8 行且无入口看全文。
// 覆盖：全文页能渲染 8 行截断之外的远端内容、可滚动到尾部、
// GitHub alert 语法剥离。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baoji_timer/ui/settings_subpages.dart';

void main() {
  // 造一份远长于 8 行截断的说明（模拟 b93 双语说明的量级）
  final longNotes = [
    '> [!NOTE]',
    '> 覆盖安装不丢数据。',
    '',
    '## ✨ 本次更新',
    ...List.generate(30, (i) => '- 功能第 $i 条：这是一段足够长的更新说明文字，用来验证全文页能完整展示。'),
    '## 尾部段落',
    '这里是说明的最末一行。',
  ].join('\n');

  testWidgets('全文页渲染 8 行截断之外的内容，可滚动到最末一行', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: ReleaseNotesPage(notes: longNotes),
    ));
    // 截断线之外的中段内容在全文页存在
    expect(find.textContaining('功能第 9 条'), findsWidgets);
    // 最末一行初始可能在视口外：滚动后可见
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(find.text('这里是说明的最末一行。'), findsOneWidget);
  });

  testWidgets('GitHub alert 语法剥离，NOTE 内容保留', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: const ReleaseNotesPage(notes: '> [!NOTE]\n> 覆盖安装不丢数据。'),
    ));
    expect(find.textContaining('[!NOTE]'), findsNothing);
    expect(find.textContaining('覆盖安装不丢数据'), findsOneWidget);
  });

  test('cleanReleaseNotes 纯函数：标记替换为图标提示', () {
    expect(cleanReleaseNotes('> [!NOTE]\n> 内容'), startsWith('**ℹ️**'));
    expect(cleanReleaseNotes('普通说明'), '普通说明');
  });
}
