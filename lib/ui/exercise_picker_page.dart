import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/engine.dart';
import '../presets/exercise_library.dart';
import 'theme.dart';

/// 从动作库挑选动作加入训练日：搜索 + 肌群/场景筛选 + 多选批量添加。
/// 返回选中的动作列表（调用方按顺序插入当天）。
class ExercisePickerPage extends StatefulWidget {
  const ExercisePickerPage({super.key, required this.existingNames});

  /// 当天已有的动作名（列表里标"已添加"并禁选，防重复）。
  final Set<String> existingNames;

  @override
  State<ExercisePickerPage> createState() => _ExercisePickerPageState();
}

class _ExercisePickerPageState extends State<ExercisePickerPage> {
  late List<ExerciseMeta> _all;
  final _searchCtrl = TextEditingController();
  String _muscle = '全部';
  String _equipment = '全部';
  final Set<String> _selected = {};

  static const _muscles = ['全部', ...kMuscleRegions];
  static const _equipments = ['全部', '健身房', '居家'];

  @override
  void initState() {
    super.initState();
    _all = [...kExerciseLibrary];
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<ExerciseMeta> get _filtered {
    final q = _searchCtrl.text.trim();
    return _all.where((m) {
      if (q.isNotEmpty && !m.name.contains(q)) return false;
      if (_muscle != '全部' && m.muscles.main != _muscle) return false;
      if (_equipment == '健身房' && m.equipment == 'home') return false;
      if (_equipment == '居家' && m.equipment == 'gym') return false;
      return true;
    }).toList()
      // 已添加的排最后
      ..sort((a, b) {
        final ax = widget.existingNames.contains(a.name) ? 1 : 0;
        final bx = widget.existingNames.contains(b.name) ? 1 : 0;
        return ax.compareTo(bx);
      });
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: Text('从动作库挑选（已选 ${_selected.length}）')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search, size: 20),
                hintText: '搜索动作名，如：卧推、划船…',
                isDense: true,
              ),
            ),
          ),
          // 肌群筛选
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              for (final m in _muscles)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(m, style: const TextStyle(fontSize: 12)),
                    selected: _muscle == m,
                    onSelected: (_) => setState(() => _muscle = m),
                    selectedColor: AppTheme.primary,
                    backgroundColor: AppTheme.cardHi,
                    side: BorderSide.none,
                    labelStyle: TextStyle(
                        fontSize: 12,
                        color: _muscle == m
                            ? const Color(0xFF06220F)
                            : AppTheme.text),
                  ),
                ),
            ]),
          ),
          // 场景筛选
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Row(children: [
              for (final e in _equipments)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(e, style: const TextStyle(fontSize: 12)),
                    selected: _equipment == e,
                    onSelected: (_) => setState(() => _equipment = e),
                    selectedColor: AppTheme.accent,
                    backgroundColor: AppTheme.cardHi,
                    side: BorderSide.none,
                    labelStyle: TextStyle(
                        fontSize: 12,
                        color: _equipment == e
                            ? const Color(0xFF06220F)
                            : AppTheme.text),
                  ),
                ),
              const Spacer(),
              Text('共 ${list.length} 个',
                  style: const TextStyle(
                      color: AppTheme.textDim, fontSize: 12)),
            ]),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              itemCount: list.length,
              itemBuilder: (ctx, i) {
                final m = list[i];
                final exists = widget.existingNames.contains(m.name);
                final sel = _selected.contains(m.name);
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: exists
                        ? null
                        : () {
                            HapticFeedback.selectionClick();
                            setState(() => sel
                                ? _selected.remove(m.name)
                                : _selected.add(m.name));
                          },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      child: Row(
                        children: [
                          Icon(
                            exists
                                ? Icons.check
                                : (sel
                                    ? Icons.check_circle
                                    : Icons.circle_outlined),
                            size: 22,
                            color: exists
                                ? AppTheme.textDim
                                : (sel
                                    ? AppTheme.primary
                                    : AppTheme.textDim),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(m.name,
                                    style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: exists
                                            ? AppTheme.textDim
                                            : AppTheme.text)),
                                const SizedBox(height: 2),
                                Text(
                                  '主练 ${m.muscles.main}'
                                  '${m.muscles.secondary.isEmpty ? '' : ' · 兼练 ${m.muscles.secondary.join('/')}'}'
                                  ' · ${m.isCompound ? '复合' : '单关节'} · ${m.equipmentLabel}',
                                  style: const TextStyle(
                                      color: AppTheme.textDim,
                                      fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          if (exists)
                            const Text('已添加',
                                style: TextStyle(
                                    color: AppTheme.textDim,
                                    fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // 底部确认
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
              child: FilledButton(
                onPressed: _selected.isEmpty
                    ? null
                    : () => Navigator.pop(
                        context,
                        _all
                            .where((m) => _selected.contains(m.name))
                            .toList()),
                child: Text('添加 ${_selected.length} 个动作'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
