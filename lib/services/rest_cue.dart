/// 组间休息音效四层触发调度（调研条目 10）。
///
/// 四层提示音：开始（进入休息）/ 半程 / 3-2-1 倒数（剩 3 秒）/ 结束。
/// 触发一律用**区间阈值判断**而非等值匹配——修掉 OpenHIIT 的坑：
/// 它对剩余微秒做等值比较，系统抖动或 tick 合并时会精确跳过触发点漏播。
/// 这里每层给一个 [windowMs] 宽的触发窗口（剩余时间落入阈值下方窗口内
/// 且该层未播过 → 触发），250ms tick 下窗口足够宽不漏、播过即去重不重。
///
/// 纯逻辑无副作用：输入剩余/总毫秒，输出本次应触发的层（每次最多一层，
/// 优先级 结束 > 倒数 > 半程 > 开始，避免小休息时窗口重叠叠音）。
library;

enum RestCue { start, half, countdown, end }

class RestCueScheduler {
  RestCueScheduler({this.windowMs = 900});

  /// 触发窗口宽度：需要 > tick 间隔（250ms）才不漏触发，
  /// 又要远小于各层阈值间距，避免正常休息时长下一次跨越多层。
  final int windowMs;

  final Set<RestCue> _played = {};

  /// 进入/恢复/加时休息时调用：各层重新可触发
  /// （加时后半程重新计算、重新经过即重播，符合直觉）。
  void reset() => _played.clear();

  /// 按剩余时间判断本拍应触发的层（最多一层；无则空表）。
  /// 窗口命中但该层已播过时**继续检查更低优先级的层**——极短休息时
  /// 半程与倒数窗口重叠，倒数先播后半程仍在窗口内不应被吞掉。
  List<RestCue> evaluate(int remainMs, int totalMs) {
    if (totalMs <= 0) return const [];
    if (remainMs < 0) remainMs = 0;

    // 结束：剩余归零（窗口下探到 0，tick 晚到也能触发）；
    // end 已播则直接空表（不再落穿检查更低的层，防极短休息误播 half）。
    if (remainMs <= 0) {
      return _played.add(RestCue.end)
          ? <RestCue>[RestCue.end]
          : const <RestCue>[];
    }

    // 倒数（剩 3 秒）
    if (remainMs <= 3000 && remainMs > 3000 - windowMs) {
      if (_played.add(RestCue.countdown)) {
        return <RestCue>[RestCue.countdown];
      }
    }

    // 半程（剩余过半）。暂停后恢复/加时由 reset 重置，恢复后剩余已
    // 深入半程以下时窗口已错过——不补播，避免恢复瞬间连响。
    final half = totalMs / 2;
    if (remainMs <= half && remainMs > half - windowMs) {
      if (_played.add(RestCue.half)) return <RestCue>[RestCue.half];
    }

    // 开始（进入休息后的最初窗口）
    if (remainMs > totalMs - windowMs && remainMs <= totalMs) {
      if (_played.add(RestCue.start)) return <RestCue>[RestCue.start];
    }

    return const [];
  }
}
