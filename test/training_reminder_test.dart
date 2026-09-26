// 练前提醒排程纯函数（buildReminderSchedule）：
// 今天已练跳过今天、已过点不补、未来训练日全排上、时刻按「一天内分钟数」拆分。
import 'package:baoji_timer/services/training_reminder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final base = DateTime(2026, 9, 26, 10, 0); // 周六 10:00

  ({DateTime date, String title}) day(int offset, [String title = '推日']) =>
      (date: base.add(Duration(days: offset)), title: title);

  test('未来训练日全部排上，时刻按分钟数拆分', () {
    final items = buildReminderSchedule(
      days: [day(0), day(1, '拉日'), day(3, '腿日')],
      now: base,
      minutesOfDay: 20 * 60 + 30, // 20:30
      trainedToday: false,
    );
    expect(items.length, 3);
    final first = DateTime.fromMillisecondsSinceEpoch(items.first.fireAtMs);
    expect(first.hour, 20);
    expect(first.minute, 30);
    expect(first.day, 26);
    expect(items[1].title, '拉日');
    expect(DateTime.fromMillisecondsSinceEpoch(items[2].fireAtMs).day, 29);
  });

  test('今天已练 → 跳过今天，明天起照排', () {
    final items = buildReminderSchedule(
      days: [day(0), day(1)],
      now: base,
      minutesOfDay: 20 * 60,
      trainedToday: true,
    );
    expect(items.length, 1);
    expect(DateTime.fromMillisecondsSinceEpoch(items.first.fireAtMs).day, 27);
  });

  test('今天的提醒时刻已过 → 不补当天', () {
    final late = DateTime(2026, 9, 26, 21, 0); // 21:00，已过 20:00
    final items = buildReminderSchedule(
      days: [day(0), day(1)],
      now: late,
      minutesOfDay: 20 * 60,
      trainedToday: false,
    );
    expect(items.length, 1);
    expect(DateTime.fromMillisecondsSinceEpoch(items.first.fireAtMs).day, 27);
  });

  test('提醒时刻在一分钟后 → 当天仍排（边界）', () {
    final items = buildReminderSchedule(
      days: [day(0)],
      now: DateTime(2026, 9, 26, 19, 58),
      minutesOfDay: 20 * 60, // 20:00，距今 2 分钟
      trainedToday: false,
    );
    expect(items.length, 1);
  });

  test('无训练日 → 空表', () {
    final items = buildReminderSchedule(
      days: const [],
      now: base,
      minutesOfDay: 20 * 60,
      trainedToday: false,
    );
    expect(items, isEmpty);
  });
}
