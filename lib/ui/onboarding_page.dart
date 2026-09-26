import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/app.dart';
import '../l10n/lang.dart';
import '../l10n/names.dart';
import '../presets/baoji_plan.dart';
import '../presets/exercise_library.dart';
import 'shell.dart';
import 'theme.dart';
import 'widgets/common.dart';

/// 首次启动引导：3 屏（欢迎 → 权限 → 选起始计划）。
///
/// 交互约定：
/// - 权限屏逐项可点授权/跳系统页，状态实时回显；全部可跳过（设置→权限 随时补）。
/// - 计划屏默认选中「薄肌计划」，也可改选内置模板或「先不选」；
///   点「开始使用」才写库：安装中按钮禁用，失败给提示并停留本页（onboarded 不落盘）。
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage>
    with WidgetsBindingObserver {
  final _controller = PageController();
  int _page = 0;
  int _choice = 0; // 起始计划选项下标（0 = 薄肌计划，最后一个 = 先不选）
  bool _installing = false;

  // 权限状态回显（进权限屏 / 从系统设置页返回时刷新）
  bool _notifGranted = false;
  bool _dndGranted = false;
  bool _usageGranted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 勿扰/使用情况的授权开关在系统专属页，授权后回到 App 刷新勾选态
    if (state == AppLifecycleState.resumed) _refreshPerms();
  }

  Future<void> _refreshPerms() async {
    if (!mounted) return;
    final c = app(context);
    final notif = await Permission.notification.isGranted;
    final dnd = await c.focus.isDndAccessGranted();
    final usage = await c.focus.isUsageAccessGranted();
    if (!mounted) return;
    setState(() {
      _notifGranted = notif;
      _dndGranted = dnd;
      _usageGranted = usage;
    });
  }

  /// 起始计划选项：(标题, 一句话介绍, 安装动作；null = 先不选)。
  List<(String, String, Future<void> Function()?)> _planChoices(
          AppContainer c) =>
      [
        (
          dname(kBaojiPlanName),
          tx('每周三练：推 / 拉 / 腿，四大项自带渐进超负荷，为本 App 量身设计',
              en: 'Three sessions a week: push / pull / legs, with built-in progressive overload on the big four. Designed for this app.'),
          () => c.planRepo.installBaojiPlan(),
        ),
        for (final t in kPlanTemplates)
          (
            dname(t.name),
            dname(t.intro),
            () async {
              await c.planRepo.installTemplate(t);
            },
          ),
        (
          tx('先不选', en: 'Skip for now'),
          tx('直接进入，随时可在「计划」页安装模板或让 AI 导入自己的计划',
              en: 'Jump right in. Install templates from the Plan page later, or have AI import your own plan.'),
          null,
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final c = app(context);
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (i) {
                  setState(() => _page = i);
                  if (i == 1) _refreshPerms();
                },
                children: [
                  _welcome(),
                  _permissions(c),
                  _choosePlan(c),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < 3; i++)
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i == _page
                                ? AppTheme.primary
                                : AppTheme.cardHi,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  BigButton(
                    label: _page < 2
                        ? tx('下一步', en: 'Next')
                        : (_installing
                            ? tx('正在准备计划…', en: 'Preparing plan…')
                            : tx('开始使用', en: 'Get Started')),
                    height: 64,
                    onPressed: _installing
                        ? null
                        : () {
                            if (_page < 2) {
                              _controller.nextPage(
                                  duration: const Duration(milliseconds: 250),
                                  curve: Curves.easeOut);
                            } else {
                              _finish(c);
                            }
                          },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 收尾：装选中的计划（「先不选」直接进），成功才落盘 onboarded 并进主框架。
  /// 失败停在引导页（不标 onboarded），下次启动重走引导，不会卡在半初始化状态。
  Future<void> _finish(AppContainer c) async {
    if (_installing) return;
    final install = _planChoices(c)[_choice].$3;
    if (install == null) {
      await _enterApp(c);
      return;
    }
    setState(() => _installing = true);
    try {
      await install();
      await _enterApp(c);
    } catch (e) {
      if (!mounted) return;
      setState(() => _installing = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tx('计划安装失败，可稍后在「计划」页重试，或先选「先不选」进入',
              en: 'Plan install failed. Retry later from the Plan page, or pick "Skip for now" to continue.')),
          backgroundColor: AppTheme.cardHi,
          behavior: SnackBarBehavior.floating));
    }
  }

  Future<void> _enterApp(AppContainer c) async {
    await c.prefs.setBool('onboarded', true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeShell()));
  }

  // ---------- 第 1 屏：欢迎 ----------

  Widget _welcome() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // unDraw 插画（已按主题绿重染，授权见 assets/illustrations/LICENSE.md）：
          // 比 emoji 更有"有人陪你练"的温度，unDraw 的品牌玩法就是插画随品牌色重染
          SvgPicture.asset(
            'assets/illustrations/personal_trainer.svg',
            height: 230,
            semanticsLabel: tx('两人正在做哑铃训练', en: 'Two people training with dumbbells'),
          ),
          const SizedBox(height: 24),
          Text(tx('薄肌训练计时器', en: 'Baoji Workout Timer'),
              style: const TextStyle(
                  fontSize: 30, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Text(
            tx(
              '一键记录一组 · 组间自动倒计时 · 训练时自动勿扰\n'
              '数据全部存在手机本地，可选同步到飞书日历',
              en: 'Log a set in one tap · auto rest countdown · auto Do Not '
                  'Disturb during workouts\n'
                  'All data stays on your phone, with optional Feishu '
                  'Calendar sync',
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: AppTheme.textDim, fontSize: 15, height: 1.6),
          ),
        ],
      ),
    );
  }

  // ---------- 第 2 屏：权限 ----------

  Widget _permissions(AppContainer c) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tx('需要几个权限', en: 'A Few Permissions Needed'),
              style: const TextStyle(
                  fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(tx('点一下就能授权，也可以全部跳过',
                  en: 'Tap to grant, or skip them all'),
              style:
                  const TextStyle(color: AppTheme.textDim, fontSize: 13)),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _permRow(
                    tx('通知', en: 'Notifications'),
                    tx('锁屏后也能看到组间倒计时和结束提醒（建议开启）',
                        en: 'See the rest countdown and end alert even on the lock screen (recommended)'),
                    granted: _notifGranted,
                    onTap: () async {
                      final s = await Permission.notification.request();
                      if (!mounted) return;
                      setState(() => _notifGranted = s.isGranted);
                    },
                  ),
                  _permRow(
                    tx('勿扰访问', en: 'Do Not Disturb Access'),
                    tx('训练时自动静音消息，结束自动恢复（建议开启）',
                        en: 'Silences messages during workouts and restores them after (recommended)'),
                    granted: _dndGranted,
                    onTap: () async {
                      await c.focus.openDndAccessSettings();
                      await _refreshPerms();
                    },
                  ),
                  _permRow(
                    tx('使用情况访问', en: 'Usage Access'),
                    tx('切去刷视频时回来提醒你（可选，训练防分心用）',
                        en: 'Reminds you when you come back from watching videos (optional, for staying focused)'),
                    granted: _usageGranted,
                    onTap: () async {
                      await c.focus.openUsageAccessSettings();
                      await _refreshPerms();
                    },
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
                tx('每个权限都可以以后在 设置→权限 里单独开启或跳过。',
                    en: 'Every permission can be enabled or skipped later in Settings → Permissions.'),
                style:
                    const TextStyle(color: AppTheme.textDim, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _permRow(String title, String desc,
      {required bool granted, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              granted ? Icons.check_circle : Icons.radio_button_unchecked,
              color: granted ? AppTheme.primary : AppTheme.textDim,
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$title${granted ? tx(' · 已开启', en: ' · On') : ''}',
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(desc,
                      style: const TextStyle(
                          color: AppTheme.textDim, fontSize: 13)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppTheme.textDim, size: 22),
          ],
        ),
      ),
    );
  }

  // ---------- 第 3 屏：选起始计划 ----------

  Widget _choosePlan(AppContainer c) {
    final choices = _planChoices(c);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(tx('选择你的起始计划', en: 'Choose Your Starting Plan'),
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
              tx('装进去的是骨架，每个动作都能在计划编辑器里改',
                  en: 'You install a skeleton; every exercise can be edited in the plan editor'),
              textAlign: TextAlign.center,
              style:
                  const TextStyle(color: AppTheme.textDim, fontSize: 13)),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              children: [
                _planRow(
                  0,
                  choices[0].$1,
                  choices[0].$2,
                  tag: tx('推荐', en: 'Recommended'),
                ),
                for (var i = 1; i < choices.length; i++)
                  _planRow(i, choices[i].$1, choices[i].$2),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _planRow(int index, String title, String desc, {String? tag}) {
    final selected = _choice == index;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: InkWell(
        onTap: () => setState(() => _choice = index),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected ? AppTheme.cardHi : AppTheme.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: selected ? AppTheme.primary : Colors.transparent),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: selected ? AppTheme.primary : AppTheme.textDim,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(title,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w700)),
                        ),
                        if (tag != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.primary,
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(tag,
                                style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF06220F))),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(desc,
                        style: const TextStyle(
                            color: AppTheme.textDim, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
