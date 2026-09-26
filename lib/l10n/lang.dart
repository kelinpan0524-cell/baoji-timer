import 'dart:ui';

/// 应用语言。
/// 中文是源语言：所有文案内联写在代码里（tx 第一参），切换英文时按 en 参显示；
/// 没提供 en 译法的文案自动回落中文，保证任何时刻界面无 key 穿帮。
enum LangPref { system, zh, en }

/// 全局已解析语言（供通知/前台服务/导出等不在 Widget 树里的代码读取）。
/// UI 侧在 MaterialApp builder 里随生效语言同步；服务侧读静态值即可。
class Lang {
  Lang._();

  static bool _en = false;

  static bool get isEn => _en;

  static void setResolved(bool en) => _en = en;

  /// 把偏好 + 系统语言解析成具体语言码（'zh' / 'en'）。
  static String resolve(LangPref pref, Locale? systemLocale) {
    switch (pref) {
      case LangPref.zh:
        return 'zh';
      case LangPref.en:
        return 'en';
      case LangPref.system:
        final code = systemLocale?.languageCode.toLowerCase();
        return code == 'en' ? 'en' : 'zh';
    }
  }
}

/// 文案翻译：中文为源语言直接内联，`en` 给英文译法。
///
/// ```dart
/// Text(tx('第 $n 组', en: 'Set $n'))
/// ```
/// 中文界面返回原文（与历史行为逐字节一致，测试断言不受影响）；
/// 英文界面返回 en 译法，缺省回落中文。
String tx(String zh, {String? en}) => Lang.isEn ? (en ?? zh) : zh;
