import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../presets/body_svg_data.dart';
import 'theme.dart';

/// 解剖级人体肌肉热力图：正面/背面 SVG，按肌群容量占比着色。
/// SVG 路径数据来自 vulovix/body-muscles（Apache 2.0）。
class MuscleBodyView extends StatelessWidget {
  const MuscleBodyView({super.key, required this.share, required this.front});

  /// 肌群 → 本周容量占比（0-1）。
  final Map<String, double> share;
  final bool front;

  static const _skin = Color(0xFF2A323D);
  static const _line = Color(0xFF151A21); // 肌肉分隔线
  static const _viewBox = '0 0 35 93';

  /// 灰底 → 绿，随占比加深（sqrt 让低占比也可感知）。
  Color _heat(String region) {
    final v = (share[region] ?? 0).clamp(0.0, 1.0);
    if (v <= 0.005) return _skin;
    final t = math.sqrt(v);
    return Color.lerp(_skin, AppTheme.primary, 0.15 + 0.85 * t)!;
  }

  String _buildSvg() {
    final paths = front ? kFrontMusclePaths : kBackMusclePaths;
    // 肌肉 id → 所属 App 肌群（反向索引）
    final idToRegion = <String, String>{};
    kMuscleRegionToSvgIds.forEach((region, ids) {
      for (final id in ids) {
        idToRegion[id] = region;
      }
    });
    final buf = StringBuffer(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="$_viewBox">');
    // 先画描边底（分隔线），再画分区填充
    for (final e in paths.entries) {
      final region = idToRegion[e.key];
      final fill = region == null ? _skin : _heat(region);
      buf.writeln(
          '<path d="${e.value}" fill="#${_hex(fill)}" stroke="#${_hex(_line)}" stroke-width="0.18"/>');
    }
    buf.write('</svg>');
    return buf.toString();
  }

  static String _hex(Color c) =>
      c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2);

  @override
  Widget build(BuildContext context) {
    return SvgPicture.string(
      _buildSvg(),
      fit: BoxFit.contain,
    );
  }
}
