import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../db/db.dart';
import '../engine/engine.dart';
import '../l10n/lang.dart';
import 'plan_repository.dart';
import 'settings.dart';

/// 练前本地提醒（2026-09-26 Arono 拍板）：训练日到了设定时刻还没练，
/// 发一条本地通知轻轻叫一声。与飞书日历提醒互补——不配飞书的用户
/// 也有"该练了"的兜底；全部本地调度，不碰无服务器红线。
///
/// 调度策略：每次 reschedule 全量重排未来 8 天的提醒（id 30-37 先清后排），
/// 已练完的当天跳过、已过点的时刻不补。触发时机：App 启动、计划/排程变化
/// （PlanRepository 监听）、训练结束/放弃（onSessionClosed）、设置项改动。
/// 条件"还没练"在重排时评估，之后当天练完会由 onSessionClosed 再触发重排，
/// 已预约的当天提醒随即取消。
class TrainingReminderService {
  TrainingReminderService(this._db, this._planRepo, this._settings);

  final Db _db;
  final PlanRepository _planRepo;
  final Settings _settings;

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// 提醒通知 id 段（与休息结束 2 / 空闲 20 不冲突）。
  static const idBase = 30;

  /// 未来排程天数。
  static const horizonDays = 8;

  static final _channel = AndroidNotificationChannel(
    'train_reminder',
    tx('练前提醒', en: 'Training day reminder'),
    description: tx(
      '训练日到了设定时刻还没练时的一声轻提醒',
      en: 'A gentle nudge when a training day arrives and you have not trained yet',
    ),
    importance: Importance.defaultImportance,
    playSound: true,
    enableVibration: true,
  );

  Future<void> init() async {
    if (_ready) return;
    // 时区库幂等初始化（NotifyService 也做一次；两处 init 时序不保证）
    tzdata.initializeTimeZones();
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);
    _ready = true;
  }

  /// 全量重排未来 [horizonDays] 天的练前提醒。失败静默（通知插件异常/
  /// 测试环境数据库已关等都不拖累调用方，下次触发再重排）。
  Future<void> reschedule() async {
    try {
      await init();
      for (var i = 0; i < horizonDays; i++) {
        await _plugin.cancel(idBase + i);
      }
      if (!_settings.trainReminderOn) return;

      final now = DateTime.now();
      // 解析未来 8 天哪些是训练日（复用首页同款 dayForDate：手动覆盖 >
      // 循环推导 > 星期模板）；空模板日（无动作）不算训练日。
      final days = <({DateTime date, String title})>[];
      for (var i = 0; i < horizonDays; i++) {
        final d = now.add(Duration(days: i));
        final day = await _planRepo.dayForDate(d);
        if (day == null) continue;
        final exs = await _db.dayExercises(day.id!);
        if (exs.isEmpty) continue;
        days.add((date: d, title: day.title));
      }
      final trainedToday = (await _db.sessionsOnDate(fmtDate(now)))
          .any((s) => s.status == 'done');

      final items = buildReminderSchedule(
        days: days,
        now: now,
        minutesOfDay: _settings.trainReminderMinOfDay,
        trainedToday: trainedToday,
      );
      for (var i = 0; i < items.length; i++) {
        await _scheduleOne(idBase + i, items[i]);
      }
    } catch (_) {
      // 全量静默（与 SessionController.restore 同口径）：测试环境插件未
      // mock 抛 Error、通知权限被拒、数据库已关等都不拖累调用方，
      // 下次重排再试。提醒排不上是体验问题，绝不能变成崩溃。
    }
  }

  Future<void> _scheduleOne(
      int id, ({int fireAtMs, String title}) item) async {
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channel.id,
        _channel.name,
        channelDescription: _channel.description,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
    );
    final title = tx('今天该练了', en: 'Training day');
    final body = tx('「${item.title}」等你开练，练完记得打卡',
        en: '"${item.title}" is waiting — go get it done');
    final when =
        tz.TZDateTime.from(DateTime.fromMillisecondsSinceEpoch(item.fireAtMs), tz.local);
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        when,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } on PlatformException {
      // 无精确闹钟权限：降级非精确（练前提醒容忍几分钟漂移）
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        when,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }
}

/// 纯函数：从已解析的训练日清单算出该排哪些提醒（可单测）。
/// 规则：今天已练 → 跳过今天；到点时刻已过（留 1 分钟余量）→ 不补当天。
@visibleForTesting
List<({int fireAtMs, String title})> buildReminderSchedule({
  required List<({DateTime date, String title})> days,
  required DateTime now,
  required int minutesOfDay,
  required bool trainedToday,
}) {
  final out = <({int fireAtMs, String title})>[];
  for (final d in days) {
    final isToday = d.date.year == now.year &&
        d.date.month == now.month &&
        d.date.day == now.day;
    if (isToday && trainedToday) continue;
    final fire = DateTime(
        d.date.year, d.date.month, d.date.day, minutesOfDay ~/ 60, minutesOfDay % 60);
    if (!fire.isAfter(now.add(const Duration(minutes: 1)))) continue;
    out.add((fireAtMs: fire.millisecondsSinceEpoch, title: d.title));
  }
  return out;
}
