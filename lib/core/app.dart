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
  AppContainer({required this.prefs, Db? db})
      : settings = Settings(prefs),
        db = db ?? Db.instance,
        notify = NotifyService() {
    focus = FocusService(settings);
    planRepo = PlanRepository(this.db, settings);
    session = SessionController(this.db, settings, prefs, focus);
    ai = AiService(settings);
    lark = LarkService(settings, this.db);
    export = ExportService(this.db);

    // 训练开始/结束 → 专注模式动作
    session.onEnterFocus = _onEnterFocus;
    session.onExitFocus = _onExitFocus;
    // 休息时间源 → 精确闹钟（开始/加时/继续重挂，暂停取消，恢复会话补挂）
    session.onRestAlarmChanged = _onRestAlarmChanged;
    // 训练卡 → 前台服务常驻通知（会话进行中常驻，结束自动停）
    session.onCardChanged = (card) {
      if (card.active) {
        unawaited(notify.showTrainingCard(card));
      } else {
        unawaited(notify.stopTrainingCard());
      }
    };
    // 通知栏遥控按钮（暂停/继续/±10 秒）→ 会话状态机
    notify.onNotifAction = _onNotifAction;
    // 空闲提醒：人在屏上走 App 内横幅，离开前台才发系统通知
    session.onIdleNudge = (minutes) async {
      if (_inForeground) {
        session.showFocusBanner('你已运动 $minutes 分钟了，回来继续！');
      } else {
        await notify.showIdleNudge(minutes);
      }
    };
    // 生命周期：条目 2 双通道互斥——人在屏上时休息到点只走屏内提示，
    // 离开前台才交回系统精确提醒；两通道互不重复。
    WidgetsBinding.instance.addObserver(_LifecycleHook(this));
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

  bool _inForeground = true;

  void _onNotifAction(String action) {
    final s = session;
    if (!s.hasActive) return;
    switch (action) {
      case 'pause':
        s.pauseRest();
      case 'resume':
        s.resumeRest();
      case 'minus10':
        s.extendRest(-10);
      case 'plus10':
        s.extendRest(10);
    }
  }

  void onAppLifecycleChanged(AppLifecycleState state) {
    final fg = state == AppLifecycleState.resumed;
    if (fg == _inForeground) return;
    _inForeground = fg;
    final s = session;
    if (s.hasActive &&
        s.phase == WorkoutPhase.resting &&
        !s.isRestPaused &&
        s.restEndAt > 0) {
      // 屏内提示接管 / 交回系统提醒（暂停态闹钟本就取消，不重复处理）
      s.onRestAlarmChanged?.call(fg ? null : s.restEndAt);
    }
  }

  Future<void> init() async {
    // 通知插件初始化不挡首帧（只有进休息倒计时才需要），失败静默重试
    unawaited(notify.init().catchError((Object e) {}));
    await ensureFirstRunSeeded();
    await planRepo.reload();
    await session.restore();
    // 联网补写飞书离线队列（失败静默，下轮再试）
    unawaited(lark.retryPending());
  }

  /// 首启播种：动作库为空时写入全量 74 动作的肌群/器械标注。
  /// 只按"表为空"判断、不做每次启动重写——exercise_meta 的 upsert 是整行
  /// REPLACE，老用户在编辑器里改过的肌群标注不能被启动时静默重置；
  /// 引导页选了「先不选」的用户也由此拿到完整动作库（挑选页/热力图可用）。
  Future<void> ensureFirstRunSeeded() async {
    if (await db.exerciseMetaCount() == 0) {
      await planRepo.seedExerciseLibrary();
    }
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

/// App 全局生命周期探针：前台/后台状态供提醒双通道互斥使用。
class _LifecycleHook with WidgetsBindingObserver {
  _LifecycleHook(this._c);

  final AppContainer _c;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _c.onAppLifecycleChanged(state);
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
