// 调研条目 10：休息音效四层触发的区间阈值调度。
// 核心回归点：tick 抖动跳过精确等值点时仍能触发（等值匹配会漏）、
// 每层每段只播一次、窗口重叠时一次只返回一层。
import 'package:flutter_test/flutter_test.dart';
import 'package:baoji_timer/services/rest_cue.dart';

void main() {
  late RestCueScheduler s;

  setUp(() {
    s = RestCueScheduler(); // 默认窗口 900ms
  });

  RestCue? one(int remain, int total) {
    final cues = s.evaluate(remain, total);
    expect(cues.length, lessThanOrEqualTo(1), reason: '一次最多触发一层');
    return cues.isEmpty ? null : cues.first;
  }

  test('进入休息的最初窗口触发 start', () {
    // 120 秒休息，第一 tick 剩余 119750ms（≈ total-250ms tick）
    expect(one(119750, 120000), RestCue.start);
  });

  test('start 只触发一次（该段未播过去重）', () {
    expect(one(119750, 120000), RestCue.start);
    expect(one(119500, 120000), isNull);
    expect(one(119000, 120000), isNull);
  });

  test('半程触发：剩余落入 (half, half-900] 窗口', () {
    final half = 120000 ~/ 2; // 60000
    expect(one(half, 120000), RestCue.half); // 恰在阈值上
    expect(one(half - 800, 120000), isNull); // 已播过
  });

  test('tick 抖动跨过精确阈值仍触发（等值匹配会漏的场景）', () {
    // 模拟系统抖动：前一拍 61500（窗口外），下一拍直接 59800（跳过 60000 等值点）
    expect(one(61500, 120000), isNull);
    expect(one(59800, 120000), RestCue.half);
  });

  test('3-2-1 倒数窗口：剩 3000ms 触发一次', () {
    expect(one(2950, 120000), RestCue.countdown);
    expect(one(2800, 120000), isNull);
  });

  test('结束层：剩余归零触发（tick 晚到也命中，窗口下探到 0）', () {
    expect(one(0, 120000), RestCue.end);
    expect(one(0, 120000), isNull);
  });

  test('窗口之外一律不触发', () {
    // 半程阈值 60000，剩余 50000 在窗口 (60000, 59100] 之外
    expect(one(50000, 120000), isNull);
    // 倒数阈值 3000，剩余 5000 窗口外
    expect(one(5000, 120000), isNull);
  });

  test('reset 后各层重新可触发（进入下一段休息）', () {
    expect(one(119750, 120000), RestCue.start);
    s.reset();
    expect(one(119750, 120000), RestCue.start);
  });

  test('小休息窗口重叠时一次只返回一层（优先级 end>countdown>half>start）', () {
    // 6 秒休息：half 阈值 = countdown 阈值 = 3000，窗口完全重叠
    expect(one(2950, 6000), RestCue.countdown);
    expect(one(2950, 6000), RestCue.half); // 下一次 evaluate 才轮到 half
  });

  test('极短休息（5 秒地板）也不会叠音：单次 evaluate 至多一层', () {
    expect(one(3000, 5000), RestCue.countdown);
    expect(one(2500, 5000), RestCue.half);
    expect(one(0, 5000), RestCue.end);
  });

  test('total<=0 或异常输入安全', () {
    expect(one(0, 0), isNull);
    expect(one(-5, 120000), RestCue.end); // 负剩余归零处理
  });
}
