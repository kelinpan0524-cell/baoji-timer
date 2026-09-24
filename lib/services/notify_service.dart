import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// 通知：休息结束提醒（锁屏/切后台也能响）。
class NotifyService {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _restChannel = AndroidNotificationChannel(
    'rest_timer',
    '组间休息提醒',
    description: '组间休息结束的提醒（声音+震动）',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );

  static const _ongoingChannel = AndroidNotificationChannel(
    'rest_ongoing',
    '休息倒计时',
    description: '休息期间的静默常驻通知',
    importance: Importance.low,
    playSound: false,
    enableVibration: false,
  );

  Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_restChannel);
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_ongoingChannel);
    _ready = true;
  }

  /// 休息中：常驻通知显示结束时刻（静默）。
  Future<void> showOngoing(int endAtMs) async {
    if (!_ready) return;
    final remain =
        ((endAtMs - DateTime.now().millisecondsSinceEpoch) / 1000).ceil();
    await _plugin.show(
      1,
      '组间休息中',
      '约 ${remain ~/ 60}分${remain % 60}秒后开始下一组',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _ongoingChannel.id,
          _ongoingChannel.name,
          channelDescription: _ongoingChannel.description,
          ongoing: true,
          onlyAlertOnce: true,
          importance: Importance.low,
          priority: Priority.low,
        ),
      ),
    );
  }

  /// 预约休息结束的精确提醒。
  Future<void> scheduleRestEnd(int endAtMs) async {
    if (!_ready) return;
    await _plugin.zonedSchedule(
      2,
      '休息结束',
      '下一组，开干！',
      tz.TZDateTime.from(
        DateTime.fromMillisecondsSinceEpoch(endAtMs),
        tz.local,
      ),
      NotificationDetails(
        android: AndroidNotificationDetails(
          _restChannel.id,
          _restChannel.name,
          channelDescription: _restChannel.description,
          importance: Importance.max,
          priority: Priority.max,
          fullScreenIntent: false,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> cancelRest() async {
    if (!_ready) return;
    await _plugin.cancel(1);
    await _plugin.cancel(2);
  }

  /// 只取消休息结束的精确提醒（id=2），不动常驻倒计时（id=1）。
  /// 休息暂停时调用：暂停期间到点不应照响。
  Future<void> cancelRestEnd() async {
    if (!_ready) return;
    await _plugin.cancel(2);
  }
}
