import 'package:flutter_test/flutter_test.dart';
import 'package:baoji_timer/presets/body_svg_data.dart';
import 'package:baoji_timer/ui/muscle_body_view.dart';

/// 热力图 SVG 生成的回归测试：锁定正面/背面 viewBox 与分区来源。
/// （防止"背面空白"复发——背面 path 坐标在 x∈[37,72]，viewBox 必须取对应窗口）
void main() {
  test('背面 viewBox 取 x∈[37,72] 窗口（修复背面空白）', () {
    const share = {'背': 1.0};
    final backSvg = MuscleBodyView(share: share, front: false).buildSvg();
    expect(backSvg, contains('viewBox="37 0 35 93"'),
        reason: '背面 path 坐标在 37-72 区间，用正面窗口会整体落在可视区外');
  });

  test('正面 viewBox 取 x∈[0,35] 窗口', () {
    const share = {'胸': 1.0};
    final frontSvg = MuscleBodyView(share: share, front: true).buildSvg();
    expect(frontSvg, contains('viewBox="0 0 35 93"'));
  });

  test('背面渲染的是背面分区（含背阔肌/斜方肌），正面不含', () {
    const share = <String, double>{};
    final backSvg = MuscleBodyView(share: share, front: false).buildSvg();
    final frontSvg = MuscleBodyView(share: share, front: true).buildSvg();
    expect(backSvg, contains(kBackMusclePaths['lats-upper-left']!));
    expect(backSvg, contains(kBackMusclePaths['traps-mid-left']!));
    expect(frontSvg, contains(kFrontMusclePaths['chest-upper-left']!));
    expect(frontSvg.contains(kBackMusclePaths['lats-upper-left']!), isFalse);
  });

  test('SVG 数据完整性：每个分区路径存在且非空', () {
    for (final e in kFrontMusclePaths.entries) {
      expect(e.value.trim(), isNotEmpty, reason: 'front/${e.key} 为空');
    }
    for (final e in kBackMusclePaths.entries) {
      expect(e.value.trim(), isNotEmpty, reason: 'back/${e.key} 为空');
    }
    // 肌群映射引用的 id 都真实存在
    final allIds = {...kFrontMusclePaths.keys, ...kBackMusclePaths.keys};
    for (final entry in kMuscleRegionToSvgIds.entries) {
      for (final id in entry.value) {
        expect(allIds, contains(id),
            reason: '${entry.key} 引用的 $id 不在 SVG 数据中');
      }
    }
  });

  test('着色：有占比的肌群分区带绿色系填充', () {
    final svg = MuscleBodyView(share: {'背': 0.5}, front: false).buildSvg();
    // 背阔肌路径的 fill 应为 lerp 后的绿色系（非纯底色 2A323D）
    final m = RegExp(
            'd="${RegExp.escape(kBackMusclePaths['lats-mid-left']!)}" fill="#([0-9a-f]{6})"')
        .firstMatch(svg);
    expect(m, isNotNull, reason: '背阔肌分区未渲染');
    expect(m!.group(1)!.toUpperCase(), isNot('2A323D'),
        reason: '占比 50% 的背阔肌不应是底色');
  });
}
