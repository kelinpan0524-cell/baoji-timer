import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/lang.dart';
import 'theme.dart';

/// 开机画面：接住安卓原生启动屏的接力棒，用一段约 1.2 秒的有限入场动画把
/// 品牌立住——图标缩放淡入、紫罗兰光晕脉冲、应用名上浮，结束后交叉淡出到
/// 首页。全程无交互、不弹窗，符合训练专注红线；动画全部有限时长，可 pumpAndSettle。
class SplashGate extends StatefulWidget {
  const SplashGate({super.key, required this.child});

  /// 开机动画结束后的正式首页（HomeShell 或引导页）。
  final Widget child;

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 380),
      child: _done
          ? widget.child
          : SplashPage(
              key: const ValueKey('splash'),
              onDone: () => setState(() => _done = true),
            ),
    );
  }
}

class SplashPage extends StatefulWidget {
  const SplashPage({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  // 图标：缩放 + 淡入，带一点回弹（easeOutBack），前 45% 播完。
  late final Animation<double> _iconScale = Tween(begin: 0.85, end: 1.0)
      .animate(CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, 0.45, curve: Curves.easeOutBack),
  ));
  late final Animation<double> _iconFade = Tween(begin: 0.0, end: 1.0)
      .animate(CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, 0.4, curve: Curves.easeOut),
  ));

  // 光晕：紫晕从静止亮度先胀后收（sin 半周期），收在柔和常亮态，不闪不灭。
  late final Animation<double> _glow = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.12, 0.7, curve: Curves.easeOut),
  );

  // 文案：标题 + 标语上浮淡入，压轴出现。
  late final Animation<double> _textFade = Tween(begin: 0.0, end: 1.0)
      .animate(CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.35, 0.75, curve: Curves.easeOut),
  ));

  @override
  void initState() {
    super.initState();
    _controller.forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final t = _glow.value;
                final glowAlpha = 0.16 + 0.20 * math.sin(math.pi * t);
                return Opacity(
                  opacity: _iconFade.value,
                  child: Transform.scale(
                    scale: _iconScale.value,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: AppTheme.glow(AppTheme.violet,
                            alpha: glowAlpha, blur: 44),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(26),
                        child: Image.asset(
                          'assets/branding/logo.png',
                          width: 108,
                          height: 108,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            width: 108,
                            height: 108,
                            color: AppTheme.card,
                            alignment: Alignment.center,
                            child: const Icon(Icons.fitness_center,
                                size: 54, color: AppTheme.primary),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            FadeTransition(
              opacity: _textFade,
              child: Transform.translate(
                // 上浮 12px 归位：随文案淡入进度线性收回。
                offset: Offset(0, 12 * (1 - _textFade.value)),
                child: Column(
                  children: [
                    Text(
                      tx('薄肌训练计时器', en: 'Baoji Timer'),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.text,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      tx('专注每一次训练', en: 'Focus on every rep'),
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.textDim,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
