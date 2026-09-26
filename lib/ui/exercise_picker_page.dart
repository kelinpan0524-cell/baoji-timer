import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/engine.dart';
import '../l10n/lang.dart';
import '../l10n/names.dart';
import '../presets/exercise_library.dart';
import 'theme.dart';
// app(context) 快捷读取容器（与动作库浏览页同一来源）
import 'widgets/common.dart';

/// 从动作库挑选动作加入训练日：搜索 + 肌群/场景筛选 + 多选批量添加。
/// 返回选中的动作列表（调用方按顺序插入当天）。
/// 词表口径与动作库浏览页一致：内置词表 + 用户沉淀（AI 拆解/手动添加）的
/// 词表外动作，同一动作在三个入口都能搜到。
class ExercisePickerPage extends StatefulWidget {
  const ExercisePickerPage({super.key, required this.existingNames});

  /// 当天已有的动作名（列表里标"已添加"并禁选，防重复）。
  final Set<String> existingNames;

  @override
  State<ExercisePickerPage> createState() => _ExercisePickerPageState();
}

class _ExercisePickerPageState extends State<ExercisePickerPage> {
  // 先用内置词表渲染首帧，首帧后再合入 DB 沉淀的动作。
  List<ExerciseMeta> _all = [...kExerciseLibrary];
  final _searchCtrl = TextEditingController();
  String _muscle = '全部';
  String _equipment = '全部';
  final Set<String> _selected = {};

  static const _muscles = ['全部', ...kMuscleRegions];
  static const _equipments = ['全部', '健身房', '居家'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  /// 合并 DB 沉淀的词表外动作（内置优先、按名去重），
  /// 与 exercise_library_page / 编辑表单联想同一口径。
  Future<void> _load() async {
    final fromDb = await app(context).db.allExerciseMeta();
    final known = {for (final m in kExerciseLibrary) m.name};
    if (!mounted) return;
    setState(() {
      _all = [
        ...kExerciseLibrary,
        ...fromDb.where((m) => !known.contains(m.name)),
      ];
    });
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
      appBar: AppBar(
          title: Text(tx('从动作库挑选（已选 ${_selected.length}）',
              en: 'Pick Exercise (${_selected.length} selected)'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, size: 20),
                hintText: tx('搜索动作名，如：卧推、划船…',
                    en: 'Search by exercise name…'),
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
                    label: Text(
                        // '全部' 是筛选值；肌群名是数据，显示层翻译
                        m == '全部' ? tx('全部', en: 'All') : mname(m),
                        style: const TextStyle(fontSize: 12)),
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
                    label: Text(
                        // 筛选值保持中文存储，仅在显示层翻译
                        e == '全部'
                            ? tx('全部', en: 'All')
                            : e == '健身房'
                                ? tx('健身房', en: 'Gym')
                                : tx('居家', en: 'Home'),
                        style: const TextStyle(fontSize: 12)),
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
              // 大字号下三个 chips + 计数挤同一行：Flexible 让计数缩省略号
              // 而不是把 Row 撑到溢出裁字。
              Flexible(
                child: Text(tx('共 ${list.length} 个', en: '${list.length} total'),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: const TextStyle(
                        color: AppTheme.textDim, fontSize: 12)),
              ),
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
                                Text(exname(m.name),
                                    style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: exists
                                            ? AppTheme.textDim
                                            : AppTheme.text)),
                                const SizedBox(height: 2),
                                Text(
                                  tx(
                                    '主练 ${mname(m.muscles.main)}'
                                    '${m.muscles.secondary.isEmpty ? '' : ' · 兼练 ${m.muscles.secondary.map(mname).join('/')}'}'
                                    ' · ${m.isCompound ? '复合' : '单关节'} · ${eqname(m.equipmentLabel)}',
                                    en: 'Main ${mname(m.muscles.main)}'
                                        '${m.muscles.secondary.isEmpty ? '' : ' · Secondary ${m.muscles.secondary.map(mname).join('/')}'}'
                                        ' · ${m.isCompound ? 'Compound' : 'Isolation'} · ${eqname(m.equipmentLabel)}',
                                  ),
                                  style: const TextStyle(
                                      color: AppTheme.textDim,
                                      fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          if (exists)
                            Text(tx('已添加', en: 'Added'),
                                style: const TextStyle(
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
                child: Text(
                    tx('添加 ${_selected.length} 个动作',
                        en: 'Add ${_selected.length} exercises')),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
