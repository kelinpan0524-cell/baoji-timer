import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme.dart';

/// 液态玻璃组件库（OPPO 流体/Aquamorphic 方向）：
/// 深色底 + 低透明彩色氛围光 + 半透明玻璃表面（顶部高光描边、柔和下沉投影）。
///
/// 性能约定：玻璃卡片一律静态绘制（渐变+描边+投影），不用 BackdropFilter——
/// 长列表里每个 saveLayer 都贵。只有全局唯一的悬浮导航栏用真模糊
/// （[GlassBar]），它盖在氛围光上才有"磨砂"效果可挖。

/// 页面氛围背景：底色纵深渐变 + 三团静态流体光晕。
/// 静态（无动画）：训练中不抢眼、不费电，符合防分心红线。
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppTheme.bg, AppTheme.bgDeep],
            ),
          ),
        ),
        const _Orb(
            alignment: Alignment(-1.1, -1.0),
            radius: 340,
            color: AppTheme.orbMint,
            alpha: 0.14),
        const _Orb(
            alignment: Alignment(1.2, -0.6),
            radius: 300,
            color: AppTheme.orbBlue,
            alpha: 0.11),
        const _Orb(
            alignment: Alignment(0.2, 1.15),
            radius: 380,
            color: AppTheme.orbViolet,
            alpha: 0.09),
        child,
      ],
    );
  }
}

class _Orb extends StatelessWidget {
  const _Orb({
    required this.alignment,
    required this.radius,
    required this.color,
    required this.alpha,
  });

  final Alignment alignment;
  final double radius;
  final Color color;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: IgnorePointer(
        child: Container(
          width: radius,
          height: radius,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            // 径向渐变淡出，不用 ImageFilter.blur（每个模糊都是一级渲染管线）
            gradient: RadialGradient(
              colors: [color.withValues(alpha: alpha), Colors.transparent],
              stops: const [0.0, 0.7],
            ),
          ),
        ),
      ),
    );
  }
}

/// 玻璃容器：半透明填充（顶部微亮）+ 渐变描边（顶边高光）+ 柔和投影。
/// 卡片、底部操作面板通用。
class GlassContainer extends StatelessWidget {
  const GlassContainer({
    super.key,
    required this.child,
    this.margin,
    this.padding,
    this.borderRadius = 20,
    this.topOnly = false,
    this.strength = 1.0,
    this.shadow = true,
  });

  final Widget child;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;

  /// true = 只圆顶边（训练页底部操作面板贴屏底用）。
  final bool topOnly;

  /// 整体透明度强度（1.0 默认；信息层级越低越小）。
  final double strength;
  final bool shadow;

  BorderRadius get _radius => topOnly
      ? BorderRadius.vertical(top: Radius.circular(borderRadius))
      : BorderRadius.circular(borderRadius);

  @override
  Widget build(BuildContext context) {
    final r = _radius;
    // 几何必须与旧 Card 完全一致（margin 16 + padding 16），高光用 1px 顶边
    // 渐变亮线画出来、不占布局——加边框占位会让卡片内容区收窄，360dp 大字号
    // 下把标题行挤溢出（widget_layout_test 总结页 1.6 倍字号回归）。
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: shadow ? AppTheme.cardShadow : null,
        gradient: AppTheme.glassFill(strength: strength),
        // 底色托底，保证在任意背景下可读（氛围光只负责透上来一点颜色）
        color: AppTheme.card.withValues(alpha: 0.72),
      ),
      child: ClipRRect(
        borderRadius: r,
        child: Padding(
          padding: padding ?? EdgeInsets.zero,
          child: child,
        ),
      ),
    );
  }
}

/// 玻璃卡片（SectionCard 的默认形态）。
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.margin,
    this.padding,
    this.strength = 1.0,
  });

  final Widget child;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;
  final double strength;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: padding ?? const EdgeInsets.all(16),
      strength: strength,
      child: child,
    );
  }
}

/// 悬浮玻璃条（全局底部导航用）：真磨砂（BackdropFilter）+ 渐变描边。
/// 全 App 只此一处用 BackdropFilter，渲染开销可控。
class GlassBar extends StatelessWidget {
  const GlassBar({
    super.key,
    required this.child,
    this.height = 64,
    this.borderRadius = 24,
  });

  final Widget child;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(borderRadius);
    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: AppTheme.cardShadow,
      ),
      child: Container(
        padding: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          borderRadius: r,
          gradient: AppTheme.glassBorder(strength: 0.9),
        ),
        child: ClipRRect(
          borderRadius: r - BorderRadius.circular(1),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                gradient: AppTheme.glassFill(strength: 1.1),
                color: AppTheme.bg.withValues(alpha: 0.55),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// 流体渐变主按钮：薄荷→青渐变 + 同色外发光。
/// 禁用/完成态（[flat]=true 或 onPressed=null）退回平面 cardHi，不发光。
class FluidButton extends StatelessWidget {
  const FluidButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color = AppTheme.primary,
    this.height = 88,
    this.fontSize = 24,
    this.flat = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final double height;
  final double fontSize;

  /// 平面模式（完成态/次要动作）：无渐变无光晕。
  final bool flat;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final gradient = enabled && !flat && color == AppTheme.primary;
    final bg = gradient ? null : (flat ? AppTheme.cardHi : color);
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: gradient ? AppTheme.primaryGradient : null,
        color: bg,
        boxShadow: gradient
            ? AppTheme.glow(color)
            : (enabled && !flat
                ? AppTheme.glow(color, strength: 0.7)
                : null),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(20),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w800,
                color: gradient || (!flat && enabled)
                    ? const Color(0xFF06220F)
                    : AppTheme.textDim,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
