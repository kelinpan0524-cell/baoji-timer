import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/app.dart';
import 'shell.dart';
import 'theme.dart';
import 'widgets/common.dart';

/// 首次启动引导：3 屏（欢迎 → 权限说明 → 选计划）。
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _controller = PageController();
  int _page = 0;

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
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  _welcome(),
                  _permissions(),
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
                    label: _page == 2 ? '开始使用' : '下一步',
                    height: 64,
                    onPressed: () async {
                      if (_page == 1) {
                        // 顺手请求通知权限（勿扰/使用情况要去系统设置，留到设置页）
                        await Permission.notification.request();
                      }
                      if (_page < 2) {
                        await _controller.nextPage(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOut);
                      } else {
                        await c.prefs.setBool('onboarded', true);
                        if (context.mounted) {
                          Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                  builder: (_) => const HomeShell()));
                        }
                      }
                    },
                  ),
                  if (_page == 1)
                    TextButton(
                      onPressed: () async {
                        await c.prefs.setBool('onboarded', true);
                        if (context.mounted) {
                          Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                  builder: (_) => const HomeShell()));
                        }
                      },
                      child: const Text('跳过，稍后在设置里配',
                          style: TextStyle(color: AppTheme.textDim)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _welcome() {
    return const Padding(
      padding: EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('🏋️', style: TextStyle(fontSize: 72)),
          SizedBox(height: 24),
          Text('薄肌训练计时器',
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
          SizedBox(height: 12),
          Text(
            '一键记录一组 · 组间自动倒计时 · 训练时自动勿扰\n'
            '数据全部存在手机本地，可选同步到飞书日历',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textDim, fontSize: 15, height: 1.6),
          ),
        ],
      ),
    );
  }

  Widget _permissions() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('需要几个权限',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(height: 20),
          _perm('通知', '锁屏后也能看到组间倒计时和结束提醒（建议开启）'),
          _perm('勿扰访问', '训练时自动静音消息，结束自动恢复（建议开启）'),
          _perm('使用情况访问', '切去刷视频时回来提醒你（可选，训练防分心用）'),
          const SizedBox(height: 16),
          const Text('每个权限都可以以后在 设置→权限 里单独开启或跳过。',
              style: TextStyle(color: AppTheme.textDim, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _perm(String title, String desc) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_outline,
              color: AppTheme.primary, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w600)),
                Text(desc,
                    style: const TextStyle(
                        color: AppTheme.textDim, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _choosePlan(AppContainer c) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('选择你的计划',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(height: 24),
          OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 88)),
            onPressed: () async {
              await c.planRepo.installBaojiPlan();
            },
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('用内置薄肌计划（推荐）',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                SizedBox(height: 4),
                Text('每周三练：推 / 拉 / 腿，自带渐进超负荷',
                    style: TextStyle(color: AppTheme.textDim, fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 88)),
            onPressed: () async {
              // 先用内置占位，进入后可在计划页导入
              if (c.planRepo.activePlan == null) {
                await c.planRepo.installBaojiPlan();
              }
            },
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('稍后自己导入',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                SizedBox(height: 4),
                Text('计划页可粘贴文本让 AI 拆解',
                    style: TextStyle(color: AppTheme.textDim, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
