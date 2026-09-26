import 'package:flutter/material.dart';

import '../l10n/lang.dart';
import 'history_page.dart';
import 'home_page.dart';
import 'plan_page.dart';
import 'settings_page.dart';
import 'stats_page.dart';
import 'theme.dart';
import 'widgets/common.dart';

/// 主框架：底部导航（今日 / 计划 / 历史 / 数据 / 设置）。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _pages = <Widget>[
    HomePage(),
    PlanPage(),
    HistoryPage(),
    StatsPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final s = app(context).settings;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      // 条件渲染（非 IndexedStack）：切 tab 时页面重建并重新查询，
      // 保证训练/装计划后返回对应页面能看到最新数据。
      body: SafeArea(
        top: true,
        bottom: false,
        child: _pages[_index],
      ),
      bottomNavigationBar: AnimatedBuilder(
        // 设置入口红点：启动静默检查发现新版时点亮（只提示，不弹窗）
        animation: s,
        builder: (context, _) {
          final hasUpdate = s.pendingUpdate != null;
          return NavigationBar(
            selectedIndex: _index,
            height: 68,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: [
              NavigationDestination(
                  icon: const Icon(Icons.today_outlined),
                  selectedIcon: const Icon(Icons.today),
                  label: tx('今日', en: 'Today')),
              NavigationDestination(
                  icon: const Icon(Icons.calendar_view_week_outlined),
                  selectedIcon: const Icon(Icons.calendar_view_week),
                  label: tx('计划', en: 'Plan')),
              NavigationDestination(
                  icon: const Icon(Icons.history_outlined),
                  selectedIcon: const Icon(Icons.history),
                  label: tx('历史', en: 'History')),
              NavigationDestination(
                  icon: const Icon(Icons.insights_outlined),
                  selectedIcon: const Icon(Icons.insights),
                  label: tx('数据', en: 'Stats')),
              NavigationDestination(
                icon: _badge(hasUpdate, Icons.settings_outlined),
                selectedIcon: _badge(hasUpdate, Icons.settings),
                label: tx('设置', en: 'Settings'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _badge(bool visible, IconData icon) => Badge(
        isLabelVisible: visible,
        child: Icon(icon),
      );
}
