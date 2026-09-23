import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app.dart';
import '../theme.dart';

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
    final card = Card(
      child: Padding(
        padding: padding ?? const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title != null)
              Row(
                children: [
                  Text(title!,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.text)),
                  const Spacer(),
                  ?trailing,
                ],
              ),
            if (title != null) const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
    // 长按删除等场景（历史页训练卡）
    if (onLongPress == null) return card;
    return InkWell(onLongPress: onLongPress, child: card);
  }
}

/// 训练页超大按钮（≥88dp）。
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
    return SizedBox(
      height: height,
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: const Color(0xFF06220F),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        child: Text(label,
            style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w800)),
      ),
    );
  }
}

/// 重量步进大按钮。
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
          child: OutlinedButton(
            onPressed: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 60),
              backgroundColor: AppTheme.cardHi,
              side: BorderSide.none,
              padding: EdgeInsets.zero,
            ),
            child: Text(label,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.text)),
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
