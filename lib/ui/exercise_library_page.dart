import 'package:flutter/material.dart';

import '../engine/engine.dart';
import '../presets/exercise_library.dart';
import 'theme.dart';
import 'widgets/common.dart';

/// 动作库浏览页：按肌群分组的内置动作表，含器械场景（健身房/居家/皆可）
/// 与次级肌群。给编排计划时参考，也是"这个动作练哪"的速查表。
class ExerciseLibraryPage extends StatefulWidget {
  const ExerciseLibraryPage({super.key});

  @override
  State<ExerciseLibraryPage> createState() => _ExerciseLibraryPageState();
}

class _ExerciseLibraryPageState extends State<ExerciseLibraryPage> {
  bool _loading = true;
  List<ExerciseMeta> _metas = [];
  String _filter = '全部'; // 全部 / 肌群 / 场景

  static const _filters = ['全部', ...kMuscleRegions, '健身房', '居家'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final c = app(context);
    // 词表为准（内置库含全部动作），叠加用户沉淀的词表外动作
    final fromDb = await c.db.allExerciseMeta();
    final known = {for (final m in kExerciseLibrary) m.name};
    _metas = [
      ...kExerciseLibrary,
      ...fromDb.where((m) => !known.contains(m.name)),
    ];
    if (!mounted) return;
    setState(() => _loading = false);
  }

  List<ExerciseMeta> get _filtered {
    if (_filter == '全部') return _metas;
    if (_filter == '健身房') {
      return _metas.where((m) => m.equipment != 'home').toList();
    }
    if (_filter == '居家') {
      return _metas.where((m) => m.equipment != 'gym').toList();
    }
    return _metas.where((m) => m.muscles.main == _filter).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: const Text('动作库')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 筛选
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Row(
                    children: [
                      for (final f in _filters)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(f,
                                style: const TextStyle(fontSize: 12)),
                            selected: _filter == f,
                            onSelected: (_) => setState(() => _filter = f),
                            labelStyle: TextStyle(
                                fontSize: 12,
                                color: _filter == f
                                    ? const Color(0xFF06220F)
                                    : AppTheme.text),
                            selectedColor: AppTheme.primary,
                            backgroundColor: AppTheme.cardHi,
                            side: BorderSide.none,
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    itemCount: _filtered.length,
                    itemBuilder: (ctx, i) {
                      final m = _filtered[i];
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(m.name,
                                        style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 2),
                                    Text(
                                      '主练 ${m.muscles.main}'
                                      '${m.muscles.secondary.isEmpty ? '' : ' · 兼练 ${m.muscles.secondary.join('/')}'}'
                                      ' · ${m.isCompound ? '复合' : '单关节'}',
                                      style: const TextStyle(
                                          color: AppTheme.textDim,
                                          fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              _equipmentTag(m),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _equipmentTag(ExerciseMeta m) {
    final color = switch (m.equipment) {
      'gym' => AppTheme.accent,
      'home' => AppTheme.warn,
      _ => AppTheme.textDim,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(m.equipmentLabel,
          style: TextStyle(fontSize: 11, color: color)),
    );
  }
}
