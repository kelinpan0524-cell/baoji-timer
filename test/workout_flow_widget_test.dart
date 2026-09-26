// 调研条目 8：一屏一组的页面流 widget 测试。
// 覆盖：起始页（零记录先见计划文案）→ 顶部『第 N/M 组』→ 底部 3px 进度条
// 全程比例 → 保存一组「校验→写库→划线标记→自动翻页」全链 → 休息页插队 →
// 跳页面板（收起面板，已完成组划线锁定）→ 全程无 showDialog。
// 基建同 widget_layout_test.dart：真库（ffi）+ AppContainer 注入；
// DB/会话操作与"UI tap 触发 DB"的链路必须包进 tester.runAsync。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baoji_timer/core/app.dart';
import 'package:baoji_timer/engine/engine.dart';
import 'package:baoji_timer/services/session_controller.dart';
import 'package:baoji_timer/ui/workout_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final binding = TestWidgetsFlutterBinding.instance;
    // 测试环境没有宿主插件：给会碰到的平台通道挂空实现（同 widget_layout_test）
    final pigeonNullReply = ByteData(3)
      ..setUint8(0, 12)
      ..setUint8(1, 1)
      ..setUint8(2, 0);
    binding.defaultBinaryMessenger.setMockMessageHandler(
        'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
        (data) async => pigeonNullReply);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('baoji/focus'), (call) async => null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('dexterous.com/flutter_local_notifications'),
        (call) async => null);
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
    await container.session.restore();
  });

  tearDown(() async {
    // 若挂在休息态：取消 250ms tick 真实定时器，避免 pending timer
    container.session.skipRest();
    await container.db.wipeAll();
    container.dispose();
  });

  Widget host(AppContainer c, Widget home) =>
      AppScope(container: c, child: MaterialApp(home: home));

  void setSurface(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  void expectNoLayoutError(WidgetTester tester) {
    final err = tester.takeException();
    if (err != null) fail('页面布局异常: $err');
  }

  Future<PlanDay> makeDay(String title) async {
    final plan = await container.db.insertPlan(Plan(
        name: '测试计划-$title',
        source: 'manual',
        createdAt: '2026-09-25',
        isActive: 1));
    final dayId = await container.db
        .insertPlanDay(PlanDay(planId: plan.id!, weekday: 3, title: title));
    return PlanDay(id: dayId, planId: plan.id!, weekday: 3, title: title);
  }

  Future<PlanExercise> addEx(PlanDay day, String name, int order,
      {int workingSets = 3, int restSec = 120}) async {
    final pe = PlanExercise(
      dayId: day.id!,
      name: name,
      orderIdx: order,
      sets: workingSets,
      repsMin: 5,
      repsMax: 8,
      restSec: restSec,
      kind: 'compound',
      rule: ProgressionRule(repsMin: 5, repsMax: 8, workingSets: workingSets),
    );
    final id = await container.db.insertPlanExercise(pe);
    return pe.copyWith(id: id);
  }

  /// 造 2 动作 × 各 3 计划组并开会话。
  Future<void> startLifting(WidgetTester tester) async {
    await tester.runAsync(() async {
      final day = await makeDay('推日');
      final a = await addEx(day, '卧推', 0);
      final b = await addEx(day, '划船', 1);
      await container.session.startFromDay(day: day, planExercises: [a, b]);
    });
  }

  /// pump 训练页；零记录会话先落起始页，点「开始训练」进第一记录页。
  /// 末尾补一帧：AnimatedSwitcher 的 outgoing 子树在动画完成的下一帧才移除。
  Future<void> pumpWorkout(WidgetTester tester,
      {bool throughStart = true}) async {
    await tester.pumpWidget(host(container, const WorkoutPage()));
    await tester.pump(const Duration(milliseconds: 20));
    if (throughStart && find.text('开始训练').evaluate().isNotEmpty) {
      await tester.tap(find.text('开始训练'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  LinearProgressIndicator progressBar(WidgetTester tester) =>
      tester.widget<LinearProgressIndicator>(
          find.byKey(const Key('workoutFlowProgress')));

  /// 选余力 2（余力没填写提醒上线后，落库路径需先填余力；
  /// RIR chip 的 '2' 与次数格 3-10、页面指示 '1 / 2' 均不冲突）
  Future<void> pickRir2(WidgetTester tester) async {
    await tester.tap(find.text('2').first);
    await tester.pump(const Duration(milliseconds: 50));
  }

  group('起始页（计划文案 + 大按钮进流程）', () {
    testWidgets('零记录新会话先见起始页：日标题/动作清单/开始训练；进度条 3px 起点为 0',
        (tester) async {
      setSurface(tester, const Size(360, 800));
      await startLifting(tester);
      await tester.pumpWidget(host(container, const WorkoutPage()));
      await tester.pump(const Duration(milliseconds: 20));

      expect(find.text('推日'), findsOneWidget, reason: '计划文案：日标题');
      expect(find.textContaining('2 个动作 · 6 个正式组'), findsOneWidget);
      expect(find.text('卧推'), findsOneWidget, reason: '动作清单');
      expect(find.text('划船'), findsOneWidget);
      expect(find.byKey(const Key('workoutCompleteSet')), findsNothing,
          reason: '起始页不是记录页');

      final bar = progressBar(tester);
      expect(bar.minHeight, 3.0, reason: 'wger 口径：3px 细进度条');
      expect(bar.value, 0);

      await tester.tap(find.text('开始训练'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('workoutCompleteSet')), findsOneWidget,
          reason: '开始后进入第一记录页');
    });

    testWidgets('已有记录时（恢复/返回）不经过起始页，直接落到当前记录页', (tester) async {
      setSurface(tester, const Size(360, 800));
      await startLifting(tester);
      await tester.runAsync(() async {
        await container.session
            .completeSet(weight: 60, reps: 8, rir: 2, kind: SetKind.working);
        container.session.skipRest();
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpWidget(host(container, const WorkoutPage()));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('开始训练'), findsNothing, reason: '有记录不显示起始页');
      expect(find.byKey(const Key('workoutCompleteSet')), findsOneWidget);
      expect(find.text('第 2/3 组'), findsOneWidget, reason: '顶部 N/M 对齐已记 1 组');
    });
  });

  group('保存一组：划线标记 → 自动翻页（核心链路）', () {
    testWidgets('完成本组 → 「已记录」划线章 → 自动翻到休息页 → 跳过休息到第 2 组',
        (tester) async {
      setSurface(tester, const Size(360, 800));
      await startLifting(tester);
      await pumpWorkout(tester);
      expect(find.text('第 1/3 组'), findsOneWidget);
      expect(progressBar(tester).value, 0);

      await tester.runAsync(() async {
        await pickRir2(tester);
        await tester.tap(find.byKey(const Key('workoutCompleteSet')));
        // DB 写组 + 控制器进休息的链路在真实 isolate：给回包时间
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('已记录'), findsOneWidget, reason: '划线标记：盖「已记录」章');
      expect(find.textContaining('kg × '), findsOneWidget,
          reason: '刚存的组带划线展示（默认重量 20kg × 默认次数 5）');

      // 划线窗口（900ms 定时器在 runAsync 的真实区创建）：真实延时等它走完，
      // 再 pump 应用状态机算出的下一页（休息页插队）
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1000)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('组间休息'), findsOneWidget, reason: '自动翻到休息页');
      expect(find.text('已记录'), findsNothing);
      expect(find.text('第 2/3 组'), findsOneWidget, reason: '休息页顶部也是下一组 N/M');
      expect(progressBar(tester).value, closeTo(1 / 6, 1e-6),
          reason: '全程完成比例随保存推进');

      await tester.tap(find.text('跳过休息，直接开练'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('workoutCompleteSet')), findsOneWidget,
          reason: '跳过休息回到第 2 组记录页');
      expect(find.text('第 2/3 组'), findsOneWidget);
      expect(progressBar(tester).value, closeTo(1 / 6, 1e-6));
    });

    testWidgets('热身/力竭组不推进页面（与控制器语义一致）', (tester) async {
      setSurface(tester, const Size(360, 800));
      await startLifting(tester);
      await pumpWorkout(tester);

      await tester.tap(find.text('热身'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('workoutCompleteSet')));
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('已记录'), findsOneWidget, reason: '热身组也盖划线章');
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('组间休息'), findsNothing,
          reason: '热身组不触发休息计时（调研条目 9 规则）');
      expect(find.byKey(const Key('workoutCompleteSet')), findsOneWidget,
          reason: '仍停在原页（只有正式组推进"下一组"）');
      expect(find.text('第 1/3 组'), findsOneWidget);
      expect(progressBar(tester).value, 0, reason: '热身组不计入全程进度');
    });
  });

  group('跳页面板（收起面板，禁弹窗）', () {
    testWidgets('面板列出全程组页：已完成划线锁定、当前标记、可跳到另一动作', (tester) async {
      setSurface(tester, const Size(360, 800));
      await startLifting(tester);
      await pumpWorkout(tester);
      await tester.runAsync(() async {
        await container.session
            .completeSet(weight: 60, reps: 8, rir: 2, kind: SetKind.working);
        container.session.skipRest();
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('第 2/3 组'), findsOneWidget);

      // 顶部『第 N/M 组』chip 打开跳页面板（弹层动画：先 pump() 起帧再推进）
      await tester.tap(find.text('第 2/3 组'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('全程页面 · 点未完成组的行直接跳过去'), findsOneWidget);
      expect(find.text('第 1 组'), findsNWidgets(2), reason: '两动作各一个第 1 组');
      expect(find.text('当前'), findsOneWidget, reason: '卧推第 2 组是当前页');

      // 卧推第 1 组已完成（列表序在前）：划线 + 禁点，tap 不产生跳页
      await tester.tap(find.text('第 1 组').first, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('全程页面 · 点未完成组的行直接跳过去'), findsOneWidget,
          reason: '已完成组锁定：面板仍开着');

      // 划船第 1 组（列表序在后）：可跳。跳转的 DB 续体在真实 isolate，
      // 与 tap 一起包进 runAsync（本文件头部已知坑）
      await tester.runAsync(() async {
        await tester.tap(find.text('第 1 组').last);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('全程页面 · 点未完成组的行直接跳过去'), findsNothing,
          reason: '跳转后面板关闭');
      expect(find.text('划船'), findsOneWidget, reason: '已跳到划船的记录页');
      expect(find.text('第 1/3 组'), findsOneWidget);

      // 红线：全程没有弹窗（Dialog），菜单/跳页全走收起面板
      expect(find.byType(Dialog), findsNothing);
    });
  });

  group('总结页并入页面流', () {
    testWidgets('全程记满：最后一组 UI 保存 → 总结页就地展示，进度条到 1，收工回入口',
        (tester) async {
      setSurface(tester, const Size(360, 800));
      // 双路由宿主：收工 = popUntil 首个路由，能真正退出训练页
      await tester.pumpWidget(AppScope(
        container: container,
        child: MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(
                      builder: (_) => const WorkoutPage())),
                  child: const Text('去训练'),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.runAsync(() async {
        final day = await makeDay('推日');
        final a = await addEx(day, '卧推', 0);
        final b = await addEx(day, '划船', 1);
        await container.session.startFromDay(day: day, planExercises: [a, b]);
        final s = container.session;
        for (var i = 0; i < 5; i++) {
          await s.completeSet(
              weight: 60, reps: 8, rir: 2, kind: SetKind.working);
          if (s.phase == WorkoutPhase.resting) s.skipRest();
        }
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.tap(find.text('去训练'));
      await tester.pumpAndSettle();
      expect(progressBar(tester).value, closeTo(5 / 6, 1e-6));

      await tester.runAsync(() async {
        container.session.setWeightDraft(60);
        await pickRir2(tester);
        await tester.tap(find.text('8'));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tap(find.byKey(const Key('workoutCompleteSet')));
        await Future<void>.delayed(const Duration(milliseconds: 600));
      });
      await tester.pumpAndSettle();

      expect(find.text('训练完成 💪'), findsOneWidget, reason: '总结页是页面流最后一页');
      expect(progressBar(tester).value, 1.0, reason: '全程完成');
      expectNoLayoutError(tester);

      // 收工退出训练页（popUntil 首个路由）
      await tester.tap(find.text('收工'));
      await tester.pumpAndSettle();
      expect(find.text('去训练'), findsOneWidget, reason: '收工回到入口页');
      expect(find.text('训练完成 💪'), findsNothing);
    });
  });

  group('自定义次数直输（2026-09-26 Arono：轻重量高次数 12/15+）', () {
    testWidgets('点「自定义」键入 15 → chip 显示 15 → 完成组落库 reps=15',
        (tester) async {
      // 高屏（折叠屏展开态）：保证次数行完整可见可点
      setSurface(tester, const Size(360, 1200));
      await startLifting(tester);
      await pumpWorkout(tester);
      // 计划 5-8 次：点选范围 3-10，没有 15
      expect(find.text('15'), findsNothing);
      expect(find.text('自定义'), findsOneWidget);

      await pickRir2(tester);
      await tester.tap(find.text('自定义'));
      await tester.pump(); // 先起帧再推进动画，单次 pump(300) 弹层停在屏外
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byType(TextField), '15');
      await tester.tap(find.text('确认'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('自定义'), findsNothing,
          reason: '自定义值生效后 chip 直接显示次数');
      expect(find.text('15'), findsOneWidget, reason: '自定义次数以选中态显示');

      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('workoutCompleteSet')));
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      await tester.pump(const Duration(milliseconds: 100));
      final sets = container.session.setsByEx[container.session.currentEx!.id]!;
      expect(sets.last.reps, 15, reason: '自定义次数落库为真实记录值');
    });

    testWidgets('超出 1-99 的输入被拦下，不关闭弹层', (tester) async {
      setSurface(tester, const Size(360, 1200));
      await startLifting(tester);
      await pumpWorkout(tester);

      await tester.tap(find.text('自定义'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // 2 位上限输入 0：越界值，确认无效
      await tester.enterText(find.byType(TextField), '0');
      await tester.tap(find.text('确认'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('输入次数'), findsOneWidget, reason: '弹层仍开着等改对');
      expect(find.text('请输入 1-99 的次数'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '12');
      await tester.tap(find.text('确认'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('12'), findsOneWidget, reason: '改对后正常生效');
    });
  });

  group('组数+目标显示（2026-09-26 Arono：帮人数组防忘目标）', () {
    testWidgets('动作面板第一行显示「第 1/3 组 · 目标 5-8 次」', (tester) async {
      setSurface(tester, const Size(360, 1200));
      await startLifting(tester);
      await pumpWorkout(tester);
      // 面板大字条（计划 5-8 次）
      expect(find.textContaining('目标 5-8 次'), findsWidgets);
      // 面板条 + 顶部 chip 两处都显示当前组号
      expect(find.textContaining('第 1/3 组'), findsNWidgets(2));
    });

    testWidgets('休息页「下一组」chip 带组号与目标次数', (tester) async {
      setSurface(tester, const Size(360, 1200));
      await startLifting(tester);
      await pumpWorkout(tester);
      await tester.runAsync(() async {
        await pickRir2(tester);
        await tester.tap(find.byKey(const Key('workoutCompleteSet')));
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      // 划线 900ms 定时器在真实时区：runAsync 等它走完再 pump 翻页
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1000)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('下一组 · 卧推 第 2/3 组'), findsOneWidget,
          reason: '休息页能看到接下来的动作、组号、次数');
      expect(find.textContaining('× 5-8 次'), findsOneWidget,
          reason: '休息页同时显示下一组的目标次数，防忘');
    });

    testWidgets('加练态面板显示「加练 第 1 组」且组号不封顶', (tester) async {
      setSurface(tester, const Size(360, 1200));
      // 单动作 1 组：练满即加练态
      await tester.runAsync(() async {
        final day = await makeDay('加练日');
        final a = await addEx(day, '卧推', 0, workingSets: 1);
        await container.session.startFromDay(day: day, planExercises: [a]);
      });
      await tester.pumpWidget(host(container, const WorkoutPage()));
      await tester.pump(const Duration(milliseconds: 20));
      await tester.tap(find.text('开始训练'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.runAsync(() async {
        await pickRir2(tester);
        await tester.tap(find.byKey(const Key('workoutCompleteSet')));
        await Future<void>.delayed(const Duration(milliseconds: 400));
        container.session.startExtraSet();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('加练 第 1 组'), findsWidgets,
          reason: '加练的这一组要显性显示出来（旧 bug：永远显示 1/1）');
      expect(find.textContaining('第 1/1 组'), findsNothing,
          reason: '不再被夹回计划组数');
    });
  });

  group('余力没填写提醒（2026-09-26 Arono：忘了填要提示，不悄悄按默认记）', () {
    testWidgets('第一按只提示不落库；选了余力再按正常记录', (tester) async {
      setSurface(tester, const Size(360, 1200));
      await startLifting(tester);
      await pumpWorkout(tester);

      // 第一按：出现提醒、组不落库
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('workoutCompleteSet')));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('余力没填写'), findsWidgets,
          reason: '余力行高亮提示');
      expect(find.textContaining('按计划默认记'), findsOneWidget,
          reason: '提示里给「再按一次用默认」的出路');
      expect(container.session.setsByEx.values
          .fold<int>(0, (n, l) => n + l.length), 0,
          reason: '第一按不落库');

      // 选余力 1：提醒消失
      await tester.tap(find.text('1').last);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('余力没填写'), findsNothing);

      // 第二按：带所选余力正常记录
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('workoutCompleteSet')));
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      await tester.pump(const Duration(milliseconds: 100));
      final sets = container.session.setsByEx.values.expand((l) => l).toList();
      expect(sets, isNotEmpty, reason: '第二按落库');
      expect(sets.last.rir, 1, reason: '余力取所选值');
    });

    testWidgets('不选余力连按两次：第二按按计划默认落库（不拦人）', (tester) async {
      setSurface(tester, const Size(360, 1200));
      await startLifting(tester);
      await pumpWorkout(tester);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('workoutCompleteSet')));
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await tester.tap(find.byKey(const Key('workoutCompleteSet')));
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      await tester.pump(const Duration(milliseconds: 100));
      final sets = container.session.setsByEx.values.expand((l) => l).toList();
      expect(sets, isNotEmpty, reason: '第二按放行');
      expect(sets.last.rir, 2, reason: '未填时按计划默认 RIR 2 记');
    });
  });
}
