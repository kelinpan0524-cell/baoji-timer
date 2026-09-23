import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'theme.dart';

/// 人体肌肉热力图：剪影 + 分区发热。
/// 坐标以"身位"为单位（身长 100），身体宽度约 46，画布上水平居中，
/// 不随容器宽高拉伸变形。
class MuscleBodyPainter extends CustomPainter {
  MuscleBodyPainter(this.share, {required this.front});

  final Map<String, double> share;
  final bool front;

  static const _skin = Color(0xFF2A323D); // 未充血的底色
  static const _outline = Color(0xFF4B5563);
  static const _line = Color(0xFF1A2028); // 身体中线/分隔线

  Color heat(String muscle) {
    final v = (share[muscle] ?? 0).clamp(0.0, 1.0);
    if (v <= 0.005) return _skin;
    // 灰底 → 绿，随占比加深加亮
    final t = math.sqrt(v); // 低占比也有可感知的颜色
    return Color.lerp(_skin, AppTheme.primary, 0.15 + 0.85 * t)!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.height / 104.0;
    final cx = size.width / 2;
    double X(double dx) => cx + dx * u;
    double Y(double dy) => 4 * u + dy * u;

    final fill = Paint()
      ..color = _skin
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = _outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2 * u;

    // ---------- 剪影 ----------
    // 头
    canvas.drawOval(
        Rect.fromCircle(center: Offset(X(0), Y(6)), radius: 6.2 * u), fill);
    canvas.drawOval(
        Rect.fromCircle(center: Offset(X(0), Y(6)), radius: 6.2 * u), stroke);
    // 脖子
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(X(-3), Y(10.5), 6 * u, 5 * u), Radius.circular(2 * u)),
        fill);
    // 躯干（肩宽 → 收腰 → 臀）
    final torso = Path()
      ..moveTo(X(-3), Y(13.5))
      ..lineTo(X(3), Y(13.5))
      ..quadraticBezierTo(X(15.5), Y(14.5), X(15.8), Y(18.5))
      ..quadraticBezierTo(X(15), Y(29), X(11.6), Y(40))
      ..quadraticBezierTo(X(10.6), Y(47), X(12.6), Y(54))
      ..quadraticBezierTo(X(13), Y(57), X(10), Y(57.5))
      ..lineTo(X(-10), Y(57.5))
      ..quadraticBezierTo(X(-13), Y(57), X(-12.6), Y(54))
      ..quadraticBezierTo(X(-10.6), Y(47), X(-11.6), Y(40))
      ..quadraticBezierTo(X(-15), Y(29), X(-15.8), Y(18.5))
      ..quadraticBezierTo(X(-15.5), Y(14.5), X(-3), Y(13.5))
      ..close();
    canvas.drawPath(torso, fill);
    canvas.drawPath(torso, stroke);
    // 手臂（从肩垂下略外张）
    final armL = Path()
      ..moveTo(X(-14.6), Y(17.5))
      ..quadraticBezierTo(X(-19), Y(18), X(-20.4), Y(24))
      ..quadraticBezierTo(X(-21.8), Y(32), X(-21.4), Y(46))
      ..quadraticBezierTo(X(-21.2), Y(49), X(-18.4), Y(48.6))
      ..quadraticBezierTo(X(-17.4), Y(38), X(-16.2), Y(31))
      ..quadraticBezierTo(X(-15.4), Y(25), X(-14.6), Y(17.5))
      ..close();
    final armR = _mirror(armL, cx);
    canvas.drawPath(armL, fill);
    canvas.drawPath(armR, fill);
    canvas.drawPath(armL, stroke);
    canvas.drawPath(armR, stroke);
    // 腿（两条圆头长条）+ 脚
    final legPaint = Paint()
      ..color = _skin
      ..style = PaintingStyle.stroke
      ..strokeCap = ui.StrokeCap.round
      ..strokeWidth = 9.4 * u;
    final outlineLeg = Paint()
      ..color = _outline
      ..style = PaintingStyle.stroke
      ..strokeCap = ui.StrokeCap.round
      ..strokeWidth = 9.4 * u
      ..strokeWidth = 11.4 * u;
    // 先描边再填充，让腿有轮廓
    for (final dx in const [-6.6, 6.6]) {
      canvas.drawLine(Offset(X(dx), Y(58)), Offset(X(dx + (dx > 0 ? 0.8 : -0.8)), Y(94)),
          outlineLeg);
    }
    for (final dx in const [-6.6, 6.6]) {
      canvas.drawLine(Offset(X(dx), Y(58)), Offset(X(dx + (dx > 0 ? 0.8 : -0.8)), Y(94)),
          legPaint);
    }
    // 脚
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(X(-9.4), Y(94.5), 6.4 * u, 4.2 * u),
            Radius.circular(2 * u)),
        fill);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(X(3), Y(94.5), 6.4 * u, 4.2 * u), Radius.circular(2 * u)),
        fill);

    // ---------- 肌肉发热区 ----------
    void limb(String muscle, Offset a, Offset b, double radius) {
      final c = heat(muscle);
      if (c == _skin) return;
      final p = Paint()
        ..color = c
        ..style = PaintingStyle.stroke
        ..strokeCap = ui.StrokeCap.round
        ..strokeWidth = radius * 2 * u;
      canvas.drawLine(a, b, p);
    }

    void block(String muscle, Rect r, double radius) {
      final c = heat(muscle);
      if (c == _skin) return;
      canvas.drawRRect(
          RRect.fromRectAndRadius(r, Radius.circular(radius * u)),
          Paint()..color = c);
    }

    if (front) {
      // 肩（球状包肩）
      limb('肩', Offset(X(-13.6), Y(16.4)), Offset(X(-13.2), Y(20.4)), 4.4);
      limb('肩', Offset(X(13.6), Y(16.4)), Offset(X(13.2), Y(20.4)), 4.4);
      // 胸（两块圆角胸肌 + 中缝）
      block('胸', Rect.fromLTWH(X(-11.4), Y(18.6), 10.6 * u, 9.6 * u), 3.4);
      block('胸', Rect.fromLTWH(X(0.8), Y(18.6), 10.6 * u, 9.6 * u), 3.4);
      canvas.drawLine(Offset(X(0), Y(18.8)), Offset(X(0), Y(27.6)),
          Paint()..color = _line..strokeWidth = 0.9 * u);
      // 手臂（正面：肱二头）
      limb('手臂', Offset(X(-18.6), Y(21)), Offset(X(-19.6), Y(36)), 3.4);
      limb('手臂', Offset(X(18.6), Y(21)), Offset(X(19.6), Y(36)), 3.4);
      // 核心（腹肌块 + 中线）
      block('核心', Rect.fromLTWH(X(-8.6), Y(32), 17.2 * u, 15.4 * u), 4.2);
      canvas.drawLine(Offset(X(0), Y(32.4)), Offset(X(0), Y(47)),
          Paint()..color = _line..strokeWidth = 0.9 * u);
      canvas.drawLine(Offset(X(-8.2), Y(39.4)), Offset(X(8.2), Y(39.4)),
          Paint()..color = _line..strokeWidth = 0.9 * u);
      // 腿（正面：股四头）
      limb('腿', Offset(X(-6.8), Y(60)), Offset(X(-7.4), Y(90)), 5.0);
      limb('腿', Offset(X(6.8), Y(60)), Offset(X(7.4), Y(90)), 5.0);
    } else {
      // 背（上背大板 + 中沟）
      block('背', Rect.fromLTWH(X(-12.8), Y(17.6), 25.6 * u, 24 * u), 6.0);
      canvas.drawLine(Offset(X(0), Y(18)), Offset(X(0), Y(41)),
          Paint()..color = _line..strokeWidth = 1.1 * u);
      // 肩（后束）
      limb('肩', Offset(X(-13.6), Y(16.6)), Offset(X(-13.4), Y(20.2)), 4.2);
      limb('肩', Offset(X(13.6), Y(16.6)), Offset(X(13.4), Y(20.2)), 4.2);
      // 手臂（背面：肱三头）
      limb('手臂', Offset(X(-18.6), Y(22)), Offset(X(-19.4), Y(37)), 3.4);
      limb('手臂', Offset(X(18.6), Y(22)), Offset(X(19.4), Y(37)), 3.4);
      // 腿（背面：腘绳 + 小腿肚）
      limb('腿', Offset(X(-6.8), Y(59)), Offset(X(-7.2), Y(78)), 5.0);
      limb('腿', Offset(X(6.8), Y(59)), Offset(X(7.2), Y(78)), 5.0);
      limb('腿', Offset(X(-7.0), Y(80)), Offset(X(-6.6), Y(91)), 3.8);
      limb('腿', Offset(X(7.0), Y(80)), Offset(X(6.6), Y(91)), 3.8);
    }
  }

  /// 沿垂直中轴镜像路径。
  Path _mirror(Path p, double cx) {
    final bounds = p.getBounds();
    final dx = 2 * cx - (bounds.left + bounds.right);
    return Path()..addPath(p, Offset(dx, 0));
  }

  @override
  bool shouldRepaint(MuscleBodyPainter oldDelegate) =>
      oldDelegate.share != share || oldDelegate.front != front;
}
