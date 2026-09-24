import 'package:flutter/material.dart';

/// 深色高对比主题（设计规范见 docs/design-spec.md）。
/// 2026-09-24 起叠加「液态玻璃」质感：底色不变，新增渐变/高光/氛围光常量，
/// 玻璃拟态组件见 ui/widgets/glass.dart。
class AppTheme {
  static const bg = Color(0xFF0E1116);
  static const bgDeep = Color(0xFF0A0D11);
  static const card = Color(0xFF1A2028);
  static const cardHi = Color(0xFF232B36);
  static const primary = Color(0xFF4ADE80);
  static const danger = Color(0xFFF87171);
  static const accent = Color(0xFF60A5FA);
  static const warn = Color(0xFFFBBF24);
  static const text = Color(0xFFE5E7EB);
  static const textDim = Color(0xFF9CA3AF);

  /// 流体氛围光（页面背景里的彩色光晕，低透明度，不影响文字对比度）。
  static const orbMint = Color(0xFF34D399);
  static const orbBlue = Color(0xFF3B82F6);
  static const orbViolet = Color(0xFF8B5CF6);

  /// 主操作渐变（薄荷 → 青），用于完成组/开始训练等主按钮。
  static const primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF6EE7A8), Color(0xFF34D399)],
  );

  /// 玻璃表面填充：顶部微亮、底部更透，模拟液体高光。
  static LinearGradient glassFill({double strength = 1.0}) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.10 * strength),
          Colors.white.withValues(alpha: 0.04 * strength),
        ],
      );

  /// 玻璃描边渐变：顶边高光（液态玻璃的标志性反光），四周渐隐。
  static LinearGradient glassBorder({double strength = 1.0}) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.28 * strength),
          Colors.white.withValues(alpha: 0.05 * strength),
        ],
      );

  /// 主按钮光晕（外发光），颜色跟随按钮主色。
  static List<BoxShadow> glow(Color color, {double strength = 1.0}) => [
        BoxShadow(
          color: color.withValues(alpha: 0.28 * strength),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.35),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ];

  /// 玻璃卡片投影：只有柔和下沉阴影，不带色。
  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.30),
          blurRadius: 20,
          offset: const Offset(0, 10),
        ),
      ];

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
          iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
                color: states.contains(WidgetState.selected) ? primary : textDim,
              )),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: const Color(0xFF06220F),
            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            minimumSize: const Size.fromHeight(56),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: text,
            side: const BorderSide(color: Color(0xFF374151)),
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: card,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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

  /// 大数字加同色微光晕（训练页倒计时/重量）。
  static TextStyle bigNumGlow(double size, {Color color = text}) =>
      bigNum(size, color: color).copyWith(
        shadows: [
          Shadow(color: color.withValues(alpha: 0.45), blurRadius: 28),
        ],
      );
}
