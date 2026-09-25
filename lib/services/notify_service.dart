import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'rest_cue.dart';
import 'session_controller.dart' show TrainingCard;

/// 通知与通知栏训练卡（调研条目 1/2/3/4）：
/// - 休息结束精确提醒（系统闹钟，锁屏/杀进程也响）——休息态原有能力保留；
/// - 训练卡常驻通知（原生前台服务承载，当前动作/本组目标/剩余时间+进度，
///   休息态带暂停/±10 秒按钮，点通知回训练页）；
/// - 双通道互斥：人在屏上时休息到点只走屏内提示（由 App 容器按生命周期
///   取消/重挂精确提醒），人离开前台才由系统提醒；
/// - 空闲提醒：训练态连续超阈值的一次性系统通知（每段只提醒一次）。
class NotifyService {
  NotifyService() {
    // 原生前台服务转发的通知栏按钮动作（暂停/继续/±10 秒）
    _trainingChannel.setMethodCallHandler((call) async {
      if (call.method == 'notifAction') {
        final args = call.arguments;
        final action = args is Map ? args['action'] as String? : null;
        if (action != null && action.isNotEmpty) onNotifAction?.call(action);
      }
      return null;
    });
  }

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// 前台服务通道（Dart → Kotlin：启停与内容推送；Kotlin → Dart：按钮动作）
  static const _trainingChannel = MethodChannel('baoji/training');

  /// 通知栏按钮动作回调（App 容器接到 SessionController）
  void Function(String action)? onNotifAction;

  static const _restChannel = AndroidNotificationChannel(
    'rest_timer',
    '组间休息提醒',
    description: '组间休息结束的提醒（声音+震动，勿扰下穿透）',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );

  static const _idleChannel = AndroidNotificationChannel(
    'idle_reminder',
    '空闲提醒',
    description: '训练中放下手机太久时的一次性拉回提醒',
    importance: Importance.defaultImportance,
    playSound: true,
    enableVibration: true,
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
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_restChannel);
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_idleChannel);
    _ready = true;
    // rest_timer 的勿扰穿透由原生侧在通道首次创建时设置（bypassDnd 只在
    // 创建时生效），这里无需也不应重复设置。
  }

  // ---------- 训练卡（前台服务，条目 1/3） ----------

  /// 启动或幂等更新训练卡通知。内容与按钮语义由 [TrainingCard] 描述。
  Future<void> showTrainingCard(TrainingCard card) async {
    try {
      await _trainingChannel.invokeMethod('start', card.toMap());
    } on PlatformException {
      // 原生侧异常不拖垮训练
    } on MissingPluginException {
      // 测试环境/非 Android 平台
    }
  }

  /// 结束训练：停掉前台服务与常驻通知。
  Future<void> stopTrainingCard() async {
    try {
      await _trainingChannel.invokeMethod('stop');
    } on PlatformException {
      // 同上
    } on MissingPluginException {
      // 同上
    }
  }

  // ---------- 休息音效四层（条目 10） ----------

  /// 播放一层休息提示音（开始/半程/3-2-1 倒数）。原生用 ToneGenerator
  /// 按层选不同音调（复用现有 'baoji/training' 通道，零新增依赖、零音频资源）；
  /// 只在屏内/前台服务场景播，触发时机与去重由 RestCueScheduler 决定。
  Future<void> playRestCue(RestCue cue) async {
    try {
      await _trainingChannel.invokeMethod('cue', {'cue': cue.name});
    } on PlatformException {
      // 原生侧异常不拖垮训练
    } on MissingPluginException {
      // 测试环境/非 Android 平台
    }
  }

  /// 锁屏时保持显示（条目 6，FitoTrack showOnLockScreen）：
  /// Android 8.1+ setShowWhenLocked/setTurnScreenOn，训练开始/结束切换。
  Future<void> setLockScreenDisplay(bool on) async {
    try {
      await _trainingChannel.invokeMethod('setLockScreenDisplay', {'on': on});
    } on PlatformException {
      // 同上
    } on MissingPluginException {
      // 同上
    }
  }

  // ---------- 休息结束精确提醒（原有能力，条目 2 双通道的系统侧） ----------

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

  /// 只取消休息结束的精确提醒（id=2）。
  /// 休息暂停/提前跳过/人在屏上时调用：到点不应再由系统提醒。
  Future<void> cancelRestEnd() async {
    if (!_ready) return;
    await _plugin.cancel(2);
  }

  // ---------- 空闲提醒（条目 4） ----------

  /// 训练态连续超阈值的一次性拉回通知（独立 id=20，不覆盖休息提醒）。
  /// 是否真发由 App 容器判断：人在屏上时走 App 内横幅，不进这里。
  Future<void> showIdleNudge(int minutes) async {
    if (!_ready) return;
    await _plugin.show(
      20,
      '该回来练了',
      '你已运动 $minutes 分钟，下一组等你很久了',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _idleChannel.id,
          _idleChannel.name,
          channelDescription: _idleChannel.description,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
    );
  }

  Future<void> cancelIdleNudge() async {
    if (!_ready) return;
    await _plugin.cancel(20);
  }
}
