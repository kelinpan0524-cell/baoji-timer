import 'package:flutter/material.dart';

import '../engine/engine.dart';
import '../services/plan_repository.dart';
import 'theme.dart';
import 'widgets/common.dart';

/// AI 计划预览确认弹层（计划页「AI 拆解导入」与 AI 教练「排计划模式」共用）。
///
/// 纪律（调研条目 12）：无论哪种来源（AI 拆解 / 描述生成 / 对话式排计划 /
/// 本地回落），都先进这里逐动作人工确认，点「保存为计划」才落库。
/// 返回 (计划名, 确认后的 specs)；放弃返回 null。
Future<(String, List<AiDaySpec>)?> showPlanPreviewSheet(
  BuildContext context,
  List<AiDaySpec> specs, {
  required bool localMode,
  String aiError = '',
}) {
  final nameCtrl = TextEditingController(
    text: localMode
        ? '本地计划 ${fmtDate(DateTime.now())}'
        : 'AI 生成 ${fmtDate(DateTime.now())}',
  );
  // 可编辑副本（AiDaySpec 不可变，按 (日, 序) 定位替换动作）
  final edited = [
    for (final d in specs) List<AiExerciseSpec>.of(d.exercises),
  ];
  return showModalBottomSheet<(String, List<AiDaySpec>)>(
    context: context,
    isScrollControlled: true,
    isDismissible: false, // 90 秒的成果不能被随手拖没
    enableDrag: false,
    backgroundColor: AppTheme.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.82,
        child: StatefulBuilder(
          builder: (ctx, setSheet) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          localMode ? '本地模式预览' : '计划预览',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '（${specs.length} 个训练日）',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.textDim,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      localMode
                          ? 'AI 不可用（${_truncateReason(aiError)}），已按内置规则生成。点动作可调整。'
                          : '点动作可换候选；标「待确认」的动作是 AI 名字没对上词表的，请务必确认。',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textDim,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: '计划名'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  children: [
                    for (var i = 0; i < specs.length; i++)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '周${'一二三四五六日'[specs[i].weekday - 1]} · ${specs[i].title}',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          for (var j = 0; j < edited[i].length; j++)
                            _previewExerciseRow(
                              edited[i][j],
                              onTap: () async {
                                final next = await _pickExerciseCandidate(
                                    ctx, edited[i][j]);
                                if (next != null) {
                                  setSheet(() => edited[i][j] = next);
                                }
                              },
                            ),
                          const SizedBox(height: 10),
                        ],
                      ),
                  ],
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final ok = await confirmDialog(
                              ctx,
                              '丢弃刚生成的计划？',
                              '放弃后需要重新生成一遍。',
                            );
                            if (ok && ctx.mounted) Navigator.pop(ctx);
                          },
                          child: const Text('放弃'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            final confirmed = [
                              for (var i = 0; i < specs.length; i++)
                                AiDaySpec(specs[i].weekday, specs[i].title,
                                    edited[i]),
                            ];
                            Navigator.pop(
                                ctx, (nameCtrl.text.trim(), confirmed));
                          },
                          child: const Text('保存为计划'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// AI 失败原因摘要：截断到 40 字，空值给兜底文案（预览页副标题用）。
String _truncateReason(String aiError) {
  final t = aiError.trim();
  if (t.isEmpty) return '未配置或网络不可用';
  return t.length <= 40 ? t : '${t.substring(0, 40)}…';
}

/// 预览页的一行动作：待确认的加警示色与徽标，全部可点进候选选择。
Widget _previewExerciseRow(AiExerciseSpec ex, {required VoidCallback onTap}) {
  final warn = ex.needsConfirm;
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '· ${ex.name}  ${ex.sets}×${ex.repsMin}-${ex.repsMax} · 休 ${ex.restSec ?? '-'}s',
              style: TextStyle(
                fontSize: 14,
                color: warn ? AppTheme.warn : AppTheme.text,
              ),
            ),
          ),
          if (warn)
            const Text(
              '待确认 ›',
              style: TextStyle(fontSize: 12, color: AppTheme.warn),
            )
          else
            const Text(
              '›',
              style: TextStyle(fontSize: 12, color: AppTheme.textDim),
            ),
        ],
      ),
    ),
  );
}

/// 候选选择：六级匹配的 top5 候选 + 保留原名（保存后走动作库沉淀兜底）。
/// 无候选（已确认动作）不弹窗。
Future<AiExerciseSpec?> _pickExerciseCandidate(
  BuildContext ctx,
  AiExerciseSpec ex,
) async {
  if (ex.candidates.isEmpty) return null;
  final original =
      ex.rawName.isNotEmpty ? ex.rawName : ex.name;
  return showModalBottomSheet<AiExerciseSpec>(
    context: ctx,
    backgroundColor: AppTheme.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetCtx) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        children: [
          Text(
            '「$original」匹配到以下动作，请确认',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          for (final cand in ex.candidates)
            ListTile(
              dense: true,
              title: Text(cand),
              leading: const Icon(Icons.fitness_center,
                  size: 18, color: AppTheme.primary),
              onTap: () => Navigator.pop(sheetCtx, ex.withName(cand)),
            ),
          const Divider(height: 1),
          ListTile(
            dense: true,
            title: Text('保留「$original」'),
            subtitle: const Text(
              '保存后沉淀进动作库，肌群按 AI 判定归类',
              style: TextStyle(fontSize: 12, color: AppTheme.textDim),
            ),
            leading:
                const Icon(Icons.edit_note, size: 18, color: AppTheme.textDim),
            onTap: () => Navigator.pop(sheetCtx, ex.withName(original)),
          ),
        ],
      ),
    ),
  );
}
