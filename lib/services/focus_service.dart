import 'package:flutter/services.dart';

import 'settings.dart';

/// Android 原生辅助：勿扰模式、使用情况访问、分心 App 检测、精确闹钟、电池优化。
/// 实现在 android/app/src/main/kotlin/.../MainActivity.kt。
class FocusService {
  static const _channel = MethodChannel('baoji/focus');

  final Settings _settings;
  FocusService(this._settings);

  // ---- 勿扰 ----
  Future<bool> isDndAccessGranted() async =>
      await _channel.invokeMethod<bool>('dndGranted') ?? false;

  /// 当前勿扰档位：0=关闭 1=完全静默 2=仅优先 3=仅闹钟。
  Future<int> currentInterruptionFilter() async =>
      await _channel.invokeMethod<int>('dndFilter') ?? 2;

  Future<void> setDnd(bool on) async {
    try {
      await _channel.invokeMethod('setDnd', {'on': on});
    } on PlatformException {
      // 未授权勿扰访问：静默失败，训练不受影响
    }
  }
  // ---- 使用情况访问（检测切出的 App） ----
  Future<bool> isUsageAccessGranted() async =>
      await _channel.invokeMethod<bool>('usageGranted') ?? false;

  /// 最近 [seconds] 秒内是否用过列在 distractingApps 里的 App。
  /// 返回 (包名, 使用秒数)；没有则 null。
  Future<(String, int)?> recentDistractingApp({int seconds = 90}) async {
    if (!_settings.focusAppCheckEnabled) return null;
    try {
      final r = await _channel.invokeMethod<Map>('recentUsage', {
        'seconds': seconds,
        'packages': _settings.distractingAppsList,
      });
      if (r == null) return null;
      final pkg = r['package'] as String?;
      final sec = (r['seconds'] as num?)?.toInt() ?? 0;
      if (pkg == null || sec <= 0) return null;
      return (pkg, sec);
    } on PlatformException {
      return null;
    }
  }

  // ---- 精确闹钟（休息结束提醒更准时） ----
  Future<bool> canExactAlarm() async =>
      await _channel.invokeMethod<bool>('canExactAlarm') ?? true;

  Future<void> openExactAlarmSettings() async {
    try {
      await _channel.invokeMethod('openExactAlarmSettings');
    } on PlatformException {
      // 部分ROM无此设置页，忽略
    }
  }

  // ---- 电池优化（后台计时可靠性） ----
  Future<bool> isIgnoringBatteryOptimizations() async =>
      await _channel.invokeMethod<bool>('ignoringBattery') ?? true;

  Future<void> requestIgnoreBattery() async {
    try {
      await _channel.invokeMethod('requestIgnoreBattery');
    } on PlatformException {
      // 部分ROM不支持该 Intent，忽略
    }
  }

  // ---- 震动 ----
  Future<void> vibrate({int ms = 120}) async {
    try {
      await _channel.invokeMethod('vibrate', {'ms': ms});
    } on PlatformException {
      // 模拟器/无震动设备：忽略
    }
  }

  // ---- 已安装应用列表（设置页勾选分心 App） ----
  Future<List<String>> installedLauncherApps() async {
    try {
      final r = await _channel.invokeMethod<List>('launcherApps');
      return r?.cast<String>() ?? [];
    } on PlatformException {
      return [];
    }
  }
}
