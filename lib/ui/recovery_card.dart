import 'package:flutter/material.dart';

import '../engine/engine.dart';
import '../presets/exercise_library.dart';
import 'muscle_body_view.dart';
import 'theme.dart';
import 'widgets/common.dart';

/// 肌群恢复度卡片（调研报告候选条目「肌群恢复度热力图」）。
///
/// 口径（见 lib/engine/recovery.dart 与 docs/recovery-heatmap.md）：
/// 近 7 天 done 会话的正式组容量按肌群分摊，按 48 小时时间常数指数衰减，
/// 恢复度 = 100×(1-累积疲劳)，无记录 = 100%。
///
/// **展示位置纪律：只出现在计划页与统计页，绝不进训练中页**——
/// 训练中屏幕只保留三要素（当前动作/本组目标/倒计时）。
class MuscleRecoveryCard extends StatefulWidget {
  const MuscleRecoveryCard({super.key});

  @override
  State<MuscleRecoveryCard> createState() => _MuscleRecoveryCardState();
}

class _MuscleRecoveryCardState extends State<MuscleRecoveryCard> {
  Future<Map<String, int>>? _future;
  bool _front = true;

  @override
  void initState() {
    super.initState();
    // initState 里不能同步读 InheritedWidget，延后一帧
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _future = _load());
    });
  }

  Future<Map<String, int>> _load() async {
    final c = app(context);
    final now = DateTime.now();
    final from = fmtDate(now.subtract(const Duration(days: kRecoveryLookbackDays)));
    final sessions = await c.db.sessionsBetween(from, fmtDate(now));
    final metaMap = {for (final m in kExerciseLibrary) m.name: m};
    // 内置词表 + DB 沉淀合并（与统计页热力图同口径）
    final known = metaMap.keys.toSet();
    for (final m in await c.db.allExerciseMeta()) {
      if (!known.contains(m.name)) metaMap[m.name] = m;
    }
    final input = <RecoverySession>[];
    for (final s in sessions) {
      final ses = await c.db.sessionExercises(s.id!);
      final map = await c.db.setsOfSession(s.id!);
      final byName = <String, List<SetEntry>>{};
      for (final se in ses) {
        final sets = map[se.id!] ?? const <SetEntry>[];
        if (sets.isEmpty) continue;
        byName.putIfAbsent(se.name, () => []).addAll(sets);
      }
      input.add(RecoverySession(
        endedAtMs: s.endedAt ?? s.startedAt,
        workingByName: byName,
      ));
    }
    return muscleRecovery(
      sessions: input,
      metaByName: metaMap,
      bodyWeightKg: c.settings.bodyWeightKg,
    );
  }

  Color _heat(int recovery) {
    // 100%（满血）→ 主题绿；0%（疲劳）→ 底色灰。恢复度与容量热力图同向：
    // 绿=练得多/刚练完与绿=容量高在视觉语言上一致，避免引入第三种语义色。
    final t = (recovery / 100).clamp(0.0, 1.0);
    return Color.lerp(AppTheme.cardHi, AppTheme.primary, 0.15 + 0.85 * t)!;
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: '肌群恢复度',
      child: FutureBuilder<Map<String, int>>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            );
          }
          final rec = snap.data!;
          final share = rec.map((k, v) => MapEntry(k, v / 100));
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '按近 7 天训练容量与 48 小时衰减估算（启发式参考，非生理测量）',
                style: const TextStyle(color: AppTheme.textDim, fontSize: 12),
              ),
              const SizedBox(height: 12),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('正面')),
                  ButtonSegment(value: false, label: Text('背面')),
                ],
                selected: {_front},
                onSelectionChanged: (sel) =>
                    setState(() => _front = sel.first),
                showSelectedIcon: false,
                style: ButtonStyle(
                  backgroundColor:
                      WidgetStateProperty.resolveWith((states) =>
                          states.contains(WidgetState.selected)
                              ? AppTheme.primary
                              : AppTheme.cardHi),
                  foregroundColor:
                      WidgetStateProperty.resolveWith((states) =>
                          states.contains(WidgetState.selected)
                              ? const Color(0xFF06220F)
                              : AppTheme.textDim),
                  side: const WidgetStatePropertyAll(
                      BorderSide(color: Colors.transparent)),
                  shape: const WidgetStatePropertyAll(RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.all(Radius.circular(10)))),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 300,
                child: MuscleBodyView(share: share, front: _front),
              ),
              const SizedBox(height: 12),
              ...kMuscleRegions.map((r) {
                final v = rec[r] ?? 100;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(
                          width: 44,
                          child:
                              Text(r, style: const TextStyle(fontSize: 14))),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: v / 100,
                            minHeight: 10,
                            backgroundColor: AppTheme.cardHi,
                            valueColor: AlwaysStoppedAnimation(_heat(v)),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 52,
                        child: Text('$v%',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              color: v <= 50
                                  ? AppTheme.warn
                                  : AppTheme.textDim,
                              fontSize: 13,
                            )),
                      ),
                    ],
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}
