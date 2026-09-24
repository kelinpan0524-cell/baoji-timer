import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'history_page.dart';
import 'home_page.dart';
import 'plan_page.dart';
import 'settings_page.dart';
import 'stats_page.dart';
import 'theme.dart';
import 'widgets/common.dart';
import 'widgets/glass.dart';

/// 主框架：底部导航（今日 / 计划 / 历史 / 数据 / 设置）。
/// 液态玻璃壳层：页面氛围光背景 + 悬浮磨砂玻璃导航条。
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

  static const _items = <(IconData, IconData, String)>[
    (Icons.today_outlined, Icons.today, '今日'),
    (Icons.calendar_view_week_outlined, Icons.calendar_view_week, '计划'),
    (Icons.history_outlined, Icons.history, '历史'),
    (Icons.insights_outlined, Icons.insights, '数据'),
    (Icons.settings_outlined, Icons.settings, '设置'),
  ];

  @override
  Widget build(BuildContext context) {
    // 设置入口红点：启动静默检查发现新版时点亮（只提示，不弹窗）
    final s = app(context).settings;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      // 条件渲染（非 IndexedStack）：切 tab 时页面重建并重新查询，
      // 保证训练/装计划后返回对应页面能看到最新数据。
      body: AmbientBackground(
        child: SafeArea(
          top: true,
          bottom: false,
          child: _pages[_index],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: GlassBar(
            child: AnimatedBuilder(
              animation: s,
              builder: (context, _) {
                final hasUpdate = s.pendingUpdate != null;
                return Row(
                  children: [
                    for (var i = 0; i < _items.length; i++)
                      Expanded(
                        child: _NavItem(
                          icon: _items[i].$1,
                          selectedIcon: _items[i].$2,
                          label: _items[i].$3,
                          selected: _index == i,
                          badge: i == 4 && hasUpdate,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _index = i);
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// 导航条目：选中态为发光小药丸（主色 18% 底 + 主色图标文字）；
/// [badge] = 设置项有新版本时的小红点。
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge = false,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppTheme.primary : AppTheme.textDim;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: selected
                ? AppTheme.primary.withValues(alpha: 0.16)
                : Colors.transparent,
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.20),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(selected ? selectedIcon : icon, color: color, size: 22),
                  if (badge)
                    Positioned(
                      top: -2,
                      right: -4,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: AppTheme.danger,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppTheme.bg, width: 1.5),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w400,
                      color: color)),
            ],
          ),
        ),
      ),
    );
  }
}
