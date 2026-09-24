import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db/db.dart';
import '../services/ai_service.dart';
import '../services/export_service.dart';
import '../services/focus_service.dart';
import '../services/lark_service.dart';
import '../services/notify_service.dart';
import '../services/plan_repository.dart';
import '../services/session_controller.dart';
import '../services/settings.dart';

/// 全局容器：App 启动时构造一次，经 AppScope 注入整棵 Widget 树。
class AppContainer {
  AppContainer({required this.prefs})
      : settings = Settings(prefs),
        db = Db.instance,
        notify = NotifyService() {
    focus = FocusService(settings);
    planRepo = PlanRepository(db, settings);
    session = SessionController(db, settings, prefs, focus);
    ai = AiService(settings);
    lark = LarkService(settings, db);
    export = ExportService(db);

    // 训练开始/结束 → 专注模式动作
    session.onEnterFocus = _onEnterFocus;
    session.onExitFocus = _onExitFocus;
    // 休息时间源 → 精确闹钟（开始/加时/继续重挂，暂停取消，恢复会话补挂）
    session.onRestAlarmChanged = _onRestAlarmChanged;
  }

  final SharedPreferences prefs;
  final Settings settings;
  final Db db;
  final NotifyService notify;
  late final FocusService focus;
  late final PlanRepository planRepo;
  late final SessionController session;
  late final AiService ai;
  late final LarkService lark;
  late final ExportService export;

  Future<void> init() async {
    // 通知插件初始化不挡首帧（只有进休息倒计时才需要），失败静默重试
    unawaited(notify.init());
    await planRepo.reload();
    await session.restore();
    // 联网补写飞书离线队列（失败静默，下轮再试）
    unawaited(lark.retryPending());
  }

  Future<void> _onEnterFocus() async {
    final f = focus;
    if (settings.focusDndEnabled && await f.isDndAccessGranted()) {
      await f.setDnd(true);
    }
  }

  Future<void> _onExitFocus() async {
    final f = focus;
    if (settings.focusDndEnabled && await f.isDndAccessGranted()) {
      await f.setDnd(false);
    }
  }

  Future<void> _onRestAlarmChanged(int? endAtMs) async {
    if (endAtMs == null) {
      await notify.cancelRestEnd();
    } else {
      await notify.scheduleRestEnd(endAtMs);
    }
  }

  void dispose() {
    session.dispose();
    settings.dispose();
    planRepo.dispose();
  }
}

class AppScope extends InheritedNotifier {
  // ignore: prefer_const_constructors_in_immutables
  AppScope({
    super.key,
    required AppContainer container,
    required super.child,
  })  : _container = container,
        super(notifier: container.settings);

  final AppContainer _container;

  static AppContainer of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found');
    return scope!._container;
  }
}
