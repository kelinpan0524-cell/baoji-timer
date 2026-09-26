import 'package:flutter/material.dart';

/// 深色高对比主题（设计规范见 docs/design-spec.md）。
class AppTheme {
  static const bg = Color(0xFF0E1116);
  static const bgDeep = Color(0xFF0A0D11);
  // 整屏状态色（调研条目 11，OpenHIIT 思路的压暗版）：练=暗绿调、歇=暗红调，
  // 不读文字用余光就知道在练还是在歇，不新增信息量。在深色基线 bg 上做
  // 微调变体（亮度几乎不变、只偏色相），保住深色高对比设计基线。
  static const bgLift = Color(0xFF0C1511); // 暗绿调
  static const bgRest = Color(0xFF160E0E); // 暗红调
  static const card = Color(0xFF1A2028);
  static const cardHi = Color(0xFF232B36);
  static const primary = Color(0xFF4ADE80);
  static const danger = Color(0xFFF87171);
  static const accent = Color(0xFF60A5FA);
  static const warn = Color(0xFFFBBF24);
  static const text = Color(0xFFE5E7EB);
  static const textDim = Color(0xFF9CA3AF);

  // ============ 数据分级色（2026-09-26 Arono：按程度分色，不要全绿） ============

  /// 恢复度分级色（pct 0-100）：0=疲劳红 → 60=黄 → 100=满血绿。
  /// 低恢复是"要注意"的信号，用暖色一眼可见；高恢复回归主题绿。
  static Color recoveryColor(double pct) {
    final t = (pct / 100).clamp(0.0, 1.0);
    if (t < 0.6) return Color.lerp(danger, warn, t / 0.6)!;
    return Color.lerp(warn, primary, (t - 0.6) / 0.4)!;
  }

  /// 负荷/容量占比分级色（t 先由调用方归一到 0-1）：0=灰 → 0.45=绿 → 1=琥珀。
  /// 按"列表内最大值"归一后重/轻肌群能拉开色带差距，不再是清一色绿。
  static Color loadColor(double t) {
    final v = t.clamp(0.0, 1.0);
    if (v < 0.45) return Color.lerp(cardHi, primary, v / 0.45)!;
    return Color.lerp(primary, warn, (v - 0.45) / 0.55)!;
  }

  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: bg,
    colorScheme: const ColorScheme.dark(
      primary: primary,
      secondary: accent,
      error: danger,
      surface: card,
      onPrimary: Color(0xFF06220F),
      onSurface: text,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: bg,
      elevation: 0,
      centerTitle: false,
      foregroundColor: text,
    ),
    cardTheme: const CardThemeData(
      color: card,
      elevation: 0,
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: bg,
      indicatorColor: cardHi,
      labelTextStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 12, color: textDim),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? primary : textDim,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: const Color(0xFF06220F),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        minimumSize: const Size.fromHeight(56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: text,
        side: const BorderSide(color: Color(0xFF374151)),
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: card,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: cardHi,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
      // 深色浮层上必须高对比：M3 默认正文/onInverseSurface、action/inversePrimary
      // 是为"深色模式浅色浮层"设计的，配深底 cardHi 会深字压深底看不清。
      contentTextStyle: TextStyle(color: text, fontSize: 14),
      actionTextColor: primary,
      disabledActionTextColor: textDim,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: primary,
      circularTrackColor: cardHi,
    ),
    dividerColor: const Color(0xFF2A323D),
    fontFamily: null,
  );

  /// 等宽数字样式（计时/重量大数字）。
  static TextStyle bigNum(double size, {Color color = text}) => TextStyle(
    fontSize: size,
    fontWeight: FontWeight.w800,
    color: color,
    fontFeatures: const [FontFeature.tabularFigures()],
    height: 1.0,
  );
}
