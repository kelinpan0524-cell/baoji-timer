import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../presets/body_svg_data.dart';
import 'theme.dart';

/// 解剖级人体肌肉热力图：正面/背面 SVG，按肌群容量占比着色。
/// SVG 路径数据来自 vulovix/body-muscles（Apache 2.0）。
class MuscleBodyView extends StatelessWidget {
  const MuscleBodyView({
    super.key,
    required this.share,
    required this.front,
    this.ramp,
  });

  /// 肌群 → 本周容量占比（0-1）。
  final Map<String, double> share;
  final bool front;

  /// 自定义着色（入参为该肌群占比 0-1）：恢复度视图传红黄绿分级、
  /// 容量视图传负荷分级；缺省沿用 sqrt 绿色渐变（既有语义）。
  final Color Function(double share)? ramp;

  static const _skin = Color(0xFF2A323D);
  static const _line = Color(0xFF151A21); // 肌肉分隔线

  /// 原库两视图共用一个坐标系：正面在 x∈[0,35]，背面在 x∈[37,72]。
  /// viewBox 必须按视图取对应窗口，否则背面整体落在可视区外（空白）。
  static const _viewBoxFront = '0 0 35 93';
  static const _viewBoxBack = '37 0 35 93';

  /// 灰底 → 着色，随占比加深（sqrt 让低占比也可感知）。
  Color _heat(String region) {
    final v = (share[region] ?? 0).clamp(0.0, 1.0);
    if (v <= 0.005) return _skin;
    if (ramp != null) return ramp!(v);
    final t = math.sqrt(v);
    return Color.lerp(_skin, AppTheme.primary, 0.15 + 0.85 * t)!;
  }

  /// 生成完整 SVG 字符串（可见于测试：锁定正面/背面 viewBox 与分区来源）。
  @visibleForTesting
  String buildSvg() {
    final paths = front ? kFrontMusclePaths : kBackMusclePaths;
    // 肌肉 id → 所属 App 肌群（反向索引）
    final idToRegion = <String, String>{};
    kMuscleRegionToSvgIds.forEach((region, ids) {
      for (final id in ids) {
        idToRegion[id] = region;
      }
    });
    final buf = StringBuffer(
        '<svg xmlns="http://www.w3.org/2000/svg" '
      'viewBox="${front ? _viewBoxFront : _viewBoxBack}">');
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
      buildSvg(),
      fit: BoxFit.contain,
    );
  }
}
