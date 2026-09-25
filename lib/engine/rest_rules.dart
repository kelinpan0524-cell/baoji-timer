import '../models/models.dart';

/// 休息时长规则（调研条目 9，docs/open-source-research-2026-09-25.md）：
/// - LiftLog 的结果分档：达标给标准休息、未达标给更长休息；
/// - Flexify 的两条：热身组不触发计时、逐动作覆盖休息时长；
/// - Strong 的热身/正式组分设休息同方向。
///
/// 设计约束（AGENTS.md）：休息规则保持可预期可配置——分档只按
/// 「刚完成那组是否达标」二分，倍率固定，不做 Fitbod 式的不可持久动态推荐。

/// 刚完成那组的结果档位。
enum RestTier {
  /// 热身组：不触发休息计时（Flexify 规则）。
  none,

  /// 达标正式组：给标准休息。
  standard,

  /// 未达标正式组 / 力竭组：给更长休息（LiftLog 的 failureRest 思路）。
  extended,
}

/// 未达标档放大系数：×1.5 后向上取整到 30 秒网格，
/// 结果仍落在可预期的整档上（180→270、120→180、60→90）。
const kRestExtendedFactor = 1.5;

/// 休息秒数的取整网格与上限（上限与 AI 解析 rest_sec 钳制一致）。
const kRestGridSec = 30;
const kRestMaxSec = 600;

/// 按刚完成那组的结果定档。
/// [kind] 该组类型（warmup/working/failure）；[reps] 该组次数；
/// [repsMax] 该动作次数上限（达到即视为达标）。
RestTier restTierForSet({
  required String kind,
  required int reps,
  required int repsMax,
}) {
  if (kind == SetKind.warmup) return RestTier.none;
  if (kind == SetKind.failure) return RestTier.extended;
  return reps >= repsMax ? RestTier.standard : RestTier.extended;
}

/// 标准休息 → 未达标休息：×1.5 向上取 30 秒网格，下限不低于原值。
int extendRestSec(int baseSec) =>
    (((baseSec * kRestExtendedFactor) / kRestGridSec).ceil() * kRestGridSec)
        .clamp(baseSec, kRestMaxSec);

/// 综合入口：刚完成一组后该歇多久（秒）。0 = 不触发计时（热身组）。
///
/// [overriddenSec] 逐动作覆盖（计划里该动作配置的 rest_sec，>0 生效，
/// Flexify 的「逐动作覆盖休息时长」）；[baseSec] 覆盖未配置时的全局基础值
/// （按 compound/assistance 区分的用户偏好，engine.defaultRestSec 的产物）。
int restSecondsAfterSet({
  required String kind,
  required int reps,
  required int repsMax,
  required int baseSec,
  int? overriddenSec,
}) {
  final tier = restTierForSet(kind: kind, reps: reps, repsMax: repsMax);
  if (tier == RestTier.none) return 0;
  final base = (overriddenSec != null && overriddenSec > 0)
      ? overriddenSec
      : baseSec.clamp(5, kRestMaxSec);
  return tier == RestTier.extended ? extendRestSec(base) : base;
}
