import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app.dart';
import '../theme.dart';
import 'glass.dart';

/// 通用小组件。

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.title,
    this.trailing,
    this.padding,
    this.onLongPress,
  });

  final Widget child;
  final String? title;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final card = GlassCard(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null)
            Row(
              children: [
                // Flexible：系统大字号下长标题允许换行，不会把 Row 顶出横向溢出
                Flexible(
                  child: Text(title!,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.text)),
                ),
                const Spacer(),
                ?trailing,
              ],
            ),
          if (title != null) const SizedBox(height: 12),
          child,
        ],
      ),
    );
    // 长按删除等场景（历史页训练卡）
    if (onLongPress == null) return card;
    return InkWell(onLongPress: onLongPress, child: card);
  }
}

/// 训练页超大按钮（≥88dp）。主色走流体渐变 + 外发光（glass.dart FluidButton）。
class BigButton extends StatelessWidget {
  const BigButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color = AppTheme.primary,
    this.height = 88,
    this.fontSize = 24,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final double height;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    // key 不内传：只留在 BigButton 上，避免同一 key 命中两层 widget
    return FluidButton(
      label: label,
      onPressed: onPressed,
      color: color,
      height: height,
      fontSize: fontSize,
      // 完成态/占位（cardHi）不发光不渐变，退回平面
      flat: color == AppTheme.cardHi,
    );
  }
}

/// 重量步进大按钮（玻璃小药丸）。
class WeightStepButton extends StatelessWidget {
  const WeightStepButton({
    super.key,
    required this.delta,
    required this.onTap,
  });

  final double delta;
  final VoidCallback onTap;

  String get label =>
      '${delta > 0 ? '+' : '-'}${delta.abs() == delta.abs().roundToDouble() ? delta.abs().toStringAsFixed(0) : delta.abs().toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '')}';

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: SizedBox(
          height: 60,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                onTap();
              },
              borderRadius: BorderRadius.circular(16),
              child: Ink(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: AppTheme.glassFill(strength: 0.9),
                  color: AppTheme.cardHi.withValues(alpha: 0.85),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.10)),
                ),
                child: Center(
                  child: Text(label,
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.text)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String fmtKg(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');

/// 自重动作（0kg）显示"自重"而不是"0"。
String fmtWeight(double v) => v <= 0 ? '自重' : fmtKg(v);

/// 训练页重量显示：负值 = 辅助器械配重（辅30 = 辅助 30kg，配重越大越轻），
/// 0 = 自重，正值 = 常规负重。
String fmtLoad(double v) {
  if (v < 0) return '辅 ${fmtKg(-v)}';
  if (v == 0) return '自重';
  return fmtKg(v);
}

String fmtDuration(int totalSeconds) {
  final m = totalSeconds ~/ 60;
  final s = totalSeconds % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

String fmtVolume(double v) {
  if (v >= 10000) return '${(v / 1000).toStringAsFixed(1)}t';
  return '${v.toStringAsFixed(0)}kg';
}

/// App 级确认弹窗（非训练页使用）。
Future<bool> confirmDialog(BuildContext context, String title, String content,
    {String okLabel = '确认'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: AppTheme.card,
      title: Text(title),
      content: Text(content, style: const TextStyle(color: AppTheme.textDim)),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消', style: TextStyle(color: AppTheme.textDim))),
        TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(okLabel, style: const TextStyle(color: AppTheme.danger))),
      ],
    ),
  );
  return r == true;
}

/// 通用轻提示。
void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg),
    backgroundColor: AppTheme.cardHi,
    behavior: SnackBarBehavior.floating,
    // 抬高到底部导航/常驻按钮之上，避免遮挡可点区域
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
    duration: const Duration(seconds: 2),
  ));
}

/// 读取容器快捷方式。
AppContainer app(BuildContext context) => AppScope.of(context);
