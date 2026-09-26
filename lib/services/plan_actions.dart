import 'dart:async';

import '../core/app.dart';
import '../engine/engine.dart';
import 'plan_repository.dart';

/// 计划级共享动作（计划页与 AI 教练页共用的"保存 + 日历同步"链路）。
/// 抽出来单一来源：两处入口必须同纪律——落库走 planRepo、
/// 换使用中计划要"撤旧日程 + 写新日程"，不能各写一份漂移。

/// 「撤旧 + 写新」保存 AI 计划并设为使用中：
/// 记下旧使用中计划的训练日 → saveAiPlan 落库并激活 → 撤旧日历日程
/// （尽力而为不阻塞）→ 把新使用中计划写上日历。返回新计划。
Future<Plan> saveAiPlanAndSync(
  AppContainer c, {
  required String name,
  required List<AiDaySpec> specs,
}) async {
  final oldId = c.planRepo.activePlan?.id;
  final oldDayIds = oldId == null
      ? <int>[]
      : (await c.db.planDays(oldId)).map((d) => d.id!).toList();
  final plan = await c.planRepo.saveAiPlan(
    name: name,
    specs: specs,
    metaMap: c.ai.metaMap(),
  );
  unawaited(removePlanDayEvents(c, oldDayIds));
  await syncActivePlanToLark(c);
  return plan;
}

/// 「替换现有计划」：用 AI 确认后的 specs 全量重建目标计划的内容
/// （2026-09-26 Arono：AI 生成的计划可选择修改现有计划而不是只能新建）。
/// 计划行（名称可选改名/排程模式/启用态）保留；若目标是使用中计划，
/// 撤旧训练日日程后按新内容重写日历，非启用计划尽力撤残留日程。
Future<Plan> replacePlanAndSync(
  AppContainer c, {
  required int planId,
  required List<AiDaySpec> specs,
  String? rename,
}) async {
  final oldDayIds =
      (await c.db.planDays(planId)).map((d) => d.id!).toList();
  final plan = await c.planRepo.replacePlanWithSpecs(
    planId,
    specs,
    c.ai.metaMap(),
    rename: rename,
  );
  unawaited(removePlanDayEvents(c, oldDayIds));
  if (c.planRepo.activePlan?.id == planId) {
    await syncActivePlanToLark(c);
  }
  return plan;
}

/// 撤下一批训练日在飞书日历上的日程（尽力而为）。
Future<void> removePlanDayEvents(AppContainer c, List<int> dayIds) async {
  for (final id in dayIds) {
    await c.lark.removePlanDayEvent(id);
  }
}

/// 「使用中」计划的未来 14 天训练日写入飞书日历（编辑/切换/导入后调用）。
/// 只同步使用中的计划——编辑未启用计划不应把它的日程写上日历。
/// 同步前清理：有日历记录但已无动作的日子（用户清空了那天）先撤事件。
Future<void> syncActivePlanToLark(AppContainer c, {int? planId}) async {
  final target = planId ?? c.planRepo.activePlan?.id;
  if (target == null) return;
  final specs = await c.planRepo.larkSpecsForPlan(target);
  final withEx = specs.map((s) => s.planDayId).toSet();
  for (final sync in await c.db.larkSyncRefsForPlan(target)) {
    if (!withEx.contains(sync.refId)) {
      await c.lark.removePlanDayEvent(sync.refId);
    }
  }
  await c.lark.syncUpcomingDays(days: specs);
}
