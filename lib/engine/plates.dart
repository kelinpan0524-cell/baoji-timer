/// 杠铃片速配（2026-09-26 Arono）：按目标总重算每边挂片组合。
/// 贪心从大到小配片（wger/LibreFit 同思路）；配不平时给出每边余量，
/// UI 明示"配不平"而不是硬凑。纯函数无副作用。
library;

/// 常见杠铃片规格（kg，降序；健身房最普遍的一套）。
const kPlateSizes = <double>[25, 20, 15, 10, 5, 2.5, 1.25];

/// 标准奥杆重量（kg）。
const kStandardBarKg = 20.0;

class PlateBreakdown {
  /// 每边挂片（从大到小，含重复片，如 [20, 5, 2.5]）。
  final List<double> perSide;

  /// 是否恰好配平（false = 库存片凑不出，差 leftover）。
  final bool exact;

  /// 每边未配平的余量（kg，exact 时为 0）。
  final double leftoverPerSide;

  const PlateBreakdown({
    required this.perSide,
    required this.exact,
    required this.leftoverPerSide,
  });
}

/// 目标总重 [totalKg]（含杆）→ 每边挂片组合。
/// 总重不超过杆重（自重/空杆）返回空组合、exact=true。
/// 浮点按 0.01kg 精度截断，避免 0.1+0.2 类误差产生假余量。
PlateBreakdown platesForLoad(
  double totalKg, {
  double barKg = kStandardBarKg,
  List<double> inventory = kPlateSizes,
}) {
  var side = (totalKg - barKg) / 2;
  side = (side * 100).roundToDouble() / 100;
  if (side <= 0) {
    return const PlateBreakdown(perSide: [], exact: true, leftoverPerSide: 0);
  }
  final out = <double>[];
  var rest = side;
  for (final p in inventory) {
    while (rest >= p - 0.005) {
      out.add(p);
      rest = ((rest - p) * 100).roundToDouble() / 100;
    }
  }
  final exact = rest < 0.005;
  return PlateBreakdown(
    perSide: out,
    exact: exact,
    leftoverPerSide: exact ? 0 : rest,
  );
}
