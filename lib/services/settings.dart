import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_release.dart';

/// 应用设置：只存手机本地（shared_preferences）。密钥类字段永不进仓库/日志。
class Settings extends ChangeNotifier {
  Settings(this._prefs) {
    _load();
  }

  final SharedPreferences _prefs;

  // 训练偏好
  int restCompoundSec = 180;
  int restAssistanceSec = 120;
  bool vibrationOn = true;
  bool soundOn = true;

  // AI（OpenAI 兼容）
  String aiBaseUrl = '';
  String aiApiKey = '';
  String aiModel = '';

  // 飞书
  bool larkEnabled = false;
  String larkAppId = '';
  String larkAppSecret = '';
  String larkRefreshToken = '';
  String larkCalendarId = '';
  int larkEventHour = 18; // 日历事件默认开始时刻
  int larkEventMinutes = 30;
  int larkReminderMin = 30;

  // 专注模式
  bool focusDndEnabled = true; // 训练时自动勿扰
  bool focusAppCheckEnabled = true; // 切出分心 App 提醒
  String distractingApps =
      'com.smile.gifmaker,com.kuaishou.app,com.ss.android.ugc.aweme,com.tencent.weishi,com.xingin.xhs,com.sina.weibo,tv.danmaku.bili';

  // 空闲提醒（调研条目 4）：训练态连续超阈值发一次性通知拉回
  bool idleNudgeEnabled = true;
  int idleNudgeMinutes = 10; // 可选 5/10/15/30/60

  // 休息音效四层触发（调研条目 10）：开始/半程/3-2-1 倒数/结束。
  // 整体开关（分层配置 UI 过重，暂不做）；结束音不受此开关影响——
  // 休息到点的提示沿用原有 _onRestFinished 通道（声音+震动）。
  bool restCueEnabled = true;

  // 锁屏时保持显示（调研条目 6，FitoTrack showOnLockScreen）：
  // 系统锁屏后训练计时仍显示在锁屏上（Android 8.1+ setShowWhenLocked）。
  // 默认关：与常亮（训练时屏幕不灭）是两个独立维度。
  bool lockScreenKeepOn = false;

  // 应用更新（GitHub 私仓 Releases）
  String ghUpdateToken = ''; // 只读令牌，与 AI Key 同一本地存放策略
  AppRelease? pendingUpdate; // 运行时状态（发现的新版），不落盘

  void _load() {
    restCompoundSec = _prefs.getInt('${_kprefix}restCompound') ?? 180;
    restAssistanceSec = _prefs.getInt('${_kprefix}restAssist') ?? 120;
    vibrationOn = _prefs.getBool('${_kprefix}vibration') ?? true;
    soundOn = _prefs.getBool('${_kprefix}sound') ?? true;
    aiBaseUrl = _prefs.getString('${_kprefix}aiBaseUrl') ?? '';
    aiApiKey = _prefs.getString('${_kprefix}aiApiKey') ?? '';
    aiModel = _prefs.getString('${_kprefix}aiModel') ?? '';
    larkEnabled = _prefs.getBool('${_kprefix}larkEnabled') ?? false;
    larkAppId = _prefs.getString('${_kprefix}larkAppId') ?? '';
    larkAppSecret = _prefs.getString('${_kprefix}larkSecret') ?? '';
    larkRefreshToken = _prefs.getString('${_kprefix}larkRefresh') ?? '';
    larkCalendarId = _prefs.getString('${_kprefix}larkCalendar') ?? '';
    larkEventHour = _prefs.getInt('${_kprefix}larkHour') ?? 18;
    larkEventMinutes = _prefs.getInt('${_kprefix}larkMin') ?? 30;
    larkReminderMin = _prefs.getInt('${_kprefix}larkRemind') ?? 30;
    focusDndEnabled = _prefs.getBool('${_kprefix}focusDnd') ?? true;
    focusAppCheckEnabled = _prefs.getBool('${_kprefix}focusApp') ?? true;
    distractingApps =
        _prefs.getString('${_kprefix}distract') ?? distractingApps;
    idleNudgeEnabled = _prefs.getBool('${_kprefix}idleNudgeOn') ?? true;
    idleNudgeMinutes = _prefs.getInt('${_kprefix}idleNudgeMin') ?? 10;
    restCueEnabled = _prefs.getBool('${_kprefix}restCue') ?? true;
    lockScreenKeepOn = _prefs.getBool('${_kprefix}lockScreenKeepOn') ?? false;
    ghUpdateToken = _prefs.getString('${_kprefix}ghToken') ?? '';
    larkAccessToken = _prefs.getString('${_kprefix}larkAccess') ?? '';
    larkTokenExpiry = _prefs.getInt('${_kprefix}larkExpiry') ?? 0;
  }

  // token 运行时字段
  String larkAccessToken = '';
  int larkTokenExpiry = 0; // epoch ms

  void set(void Function() change, {bool persist = true}) {
    change();
    if (persist) notifyListeners();
  }

  Future<void> save() async {
    await _prefs.setInt('${_kprefix}restCompound', restCompoundSec);
    await _prefs.setInt('${_kprefix}restAssist', restAssistanceSec);
    await _prefs.setBool('${_kprefix}vibration', vibrationOn);
    await _prefs.setBool('${_kprefix}sound', soundOn);
    await _prefs.setString('${_kprefix}aiBaseUrl', aiBaseUrl);
    await _prefs.setString('${_kprefix}aiApiKey', aiApiKey);
    await _prefs.setString('${_kprefix}aiModel', aiModel);
    await _prefs.setBool('${_kprefix}larkEnabled', larkEnabled);
    await _prefs.setString('${_kprefix}larkAppId', larkAppId);
    await _prefs.setString('${_kprefix}larkSecret', larkAppSecret);
    await _prefs.setString('${_kprefix}larkRefresh', larkRefreshToken);
    await _prefs.setString('${_kprefix}larkCalendar', larkCalendarId);
    await _prefs.setInt('${_kprefix}larkHour', larkEventHour);
    await _prefs.setInt('${_kprefix}larkMin', larkEventMinutes);
    await _prefs.setInt('${_kprefix}larkRemind', larkReminderMin);
    await _prefs.setBool('${_kprefix}focusDnd', focusDndEnabled);
    await _prefs.setBool('${_kprefix}focusApp', focusAppCheckEnabled);
    await _prefs.setString('${_kprefix}distract', distractingApps);
    await _prefs.setBool('${_kprefix}idleNudgeOn', idleNudgeEnabled);
    await _prefs.setInt('${_kprefix}idleNudgeMin', idleNudgeMinutes);
    await _prefs.setBool('${_kprefix}restCue', restCueEnabled);
    await _prefs.setBool('${_kprefix}lockScreenKeepOn', lockScreenKeepOn);
    await _prefs.setString('${_kprefix}ghToken', ghUpdateToken);
    await _prefs.setString('${_kprefix}larkAccess', larkAccessToken);
    await _prefs.setInt('${_kprefix}larkExpiry', larkTokenExpiry);
    notifyListeners();
  }

  bool get aiConfigured => aiBaseUrl.isNotEmpty && aiApiKey.isNotEmpty;

  List<String> get distractingAppsList => distractingApps
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  String debugSummary() => jsonEncode({
    'aiConfigured': aiConfigured,
    'larkEnabled': larkEnabled,
    'larkCalendarConfigured': larkCalendarId.isNotEmpty,
  });
}

// 避免拼错：内部统一用小写前缀常量
const _kprefix = 'set.';
