import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/app.dart';
import '../services/focus_service.dart';
import '../services/settings.dart';
import '../services/update_service.dart';
import 'theme.dart';
import 'widgets/common.dart';

/// 设置页：训练偏好 / AI / 飞书 / 数据导出 / 权限。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = app(context);
    final s = c.settings;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _FocusCard(s: s),
        const SizedBox(height: 12),
        SectionCard(
          title: '训练偏好',
          child: Column(
            children: [
              _numRow('复合动作休息（秒）', s.restCompoundSec, (v) {
                s.restCompoundSec = v;
                s.save();
              }),
              _numRow('辅助动作休息（秒）', s.restAssistanceSec, (v) {
                s.restAssistanceSec = v;
                s.save();
              }),
              // 体重（自重容量折算用，点名条目二）：引体/俯卧撑类动作
              // 按 系数×体重 计入容量趋势；设 0 关闭折算。
              _weightRow('体重（自重容量折算用）', s.bodyWeightKg, (v) {
                s.bodyWeightKg = v;
                s.save();
              }),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('完成组时震动'),
                value: s.vibrationOn,
                activeThumbColor: AppTheme.primary,
                onChanged: (v) {
                  s.vibrationOn = v;
                  s.save();
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('休息提示音'),
                subtitle: const Text(
                  '组间休息的开始/半程/最后3秒提示音',
                  style: TextStyle(color: AppTheme.textDim, fontSize: 12),
                ),
                value: s.restCueEnabled,
                activeThumbColor: AppTheme.primary,
                onChanged: (v) {
                  s.restCueEnabled = v;
                  s.save();
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('锁屏时保持显示'),
                subtitle: const Text(
                  '锁屏后训练计时仍显示在锁屏上，下次开始训练生效',
                  style: TextStyle(color: AppTheme.textDim, fontSize: 12),
                ),
                value: s.lockScreenKeepOn,
                activeThumbColor: AppTheme.primary,
                onChanged: (v) {
                  s.lockScreenKeepOn = v;
                  s.save();
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('空闲提醒'),
                subtitle: const Text(
                  '训练中放下手机太久，发通知拉你回来',
                  style: TextStyle(color: AppTheme.textDim, fontSize: 12),
                ),
                value: s.idleNudgeEnabled,
                activeThumbColor: AppTheme.primary,
                onChanged: (v) {
                  s.idleNudgeEnabled = v;
                  s.save();
                },
              ),
              if (s.idleNudgeEnabled)
                _nudgeRow('放下手机多久后提醒', s.idleNudgeMinutes, (v) {
                  s.idleNudgeMinutes = v;
                  s.save();
                }),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _AiCard(s: s),
        const SizedBox(height: 12),
        _LarkCard(s: s),
        const SizedBox(height: 12),
        _PermissionCard(),
        const SizedBox(height: 12),
        _UpdateCard(s: s),
        const SizedBox(height: 12),
        SectionCard(
          title: '数据',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '手机本地存储是唯一数据源，建议每周导出存档。存档含训练记录、计划、身体数据与动作标注；换手机或误清数据时可用 JSON 存档一键恢复。',
                style: TextStyle(color: AppTheme.textDim, fontSize: 13),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () async {
                  final csv = await c.export.buildCsv();
                  await c.export.shareText(
                    '训练记录 CSV',
                    csv,
                    filename: 'training_export.csv',
                  );
                },
                child: const Text('导出 CSV（备份/表格）'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () async {
                  final json = await c.export.buildJson();
                  await c.export.shareText(
                    '训练记录 JSON',
                    json,
                    filename: 'training_export.json',
                  );
                },
                child: const Text('导出 JSON（存档）'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => _restoreFromJson(context, c),
                child: const Text('从 JSON 存档恢复'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () async {
                  final pack = await c.export
                      .buildAiPack(bodyWeightKg: c.settings.bodyWeightKg);
                  await c.export.shareText(
                    'AI 分析包',
                    pack,
                    filename: 'ai_analysis_pack.md',
                  );
                },
                child: const Text('生成 AI 分析包（给 AI 做总结）'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.danger,
                ),
                onPressed: () async {
                  final ok = await confirmDialog(
                    context,
                    '清空全部数据？',
                    '所有训练记录、计划和身体数据将被删除且无法恢复。强烈建议先导出备份。',
                    okLabel: '全部删除',
                  );
                  if (ok) {
                    if (c.session.hasActive) await c.session.quit();
                    await c.db.wipeAll();
                    await c.planRepo.reload();
                    if (context.mounted) toast(context, '已清空');
                  }
                },
                child: const Text('清空全部数据'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Center(
          child: Text(
            '薄肌训练计时器 v1.0 · 本地优先 · 无服务器',
            style: TextStyle(color: AppTheme.textDim, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _numRow(String label, int value, ValueChanged<int> onChanged) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        IconButton(
          onPressed: () => onChanged((value - 15).clamp(30, 600)),
          icon: const Icon(Icons.remove_circle_outline),
        ),
        Text('$value', style: const TextStyle(fontSize: 17)),
        IconButton(
          onPressed: () => onChanged((value + 15).clamp(30, 600)),
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }

  Widget _weightRow(String label, double value, ValueChanged<double> onChanged) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        IconButton(
          onPressed: () => onChanged((value - 1).clamp(0, 200)),
          icon: const Icon(Icons.remove_circle_outline),
        ),
        Text(value <= 0 ? '关' : '${_fmtWeight(value)} kg',
            style: const TextStyle(fontSize: 17)),
        IconButton(
          onPressed: () => onChanged((value + 1).clamp(0, 200)),
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }

  String _fmtWeight(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  /// 空闲提醒阈值：离散档位 5/10/15/30/60 分钟（步进沿档位移动）。
  Widget _nudgeRow(String label, int value, ValueChanged<int> onChanged) {
    const choices = [5, 10, 15, 30, 60];
    var i = choices.indexOf(value);
    if (i < 0) i = 1; // 脏值回落到默认档 10
    return Row(
      children: [
        Expanded(child: Text(label)),
        IconButton(
          onPressed: i > 0 ? () => onChanged(choices[i - 1]) : null,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        Text('${choices[i]} 分钟', style: const TextStyle(fontSize: 17)),
        IconButton(
          onPressed: i < choices.length - 1
              ? () => onChanged(choices[i + 1])
              : null,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }

  /// 从 JSON 存档恢复：先清空再导入（恢复 = 回到备份时点）。
  /// 备份内容走剪贴板（分享出去的 .json 文件打开后全选复制即可）。
  Future<void> _restoreFromJson(BuildContext context, AppContainer c) async {
    final ok = await confirmDialog(
      context,
      '从 JSON 存档恢复？',
      '手机上的现有数据会先清空，再导入备份内容。\n\n'
          '步骤：先打开之前导出的 JSON 存档文件，全选复制全部内容到剪贴板，再回来点「恢复」。此操作无法撤销。',
      okLabel: '恢复',
    );
    if (!ok || !context.mounted) return;
    final clip = await Clipboard.getData('text/plain');
    final text = (clip?.text ?? '').trim();
    if (!context.mounted) return;
    if (text.isEmpty) {
      toast(context, '剪贴板是空的：请先复制 JSON 存档的全部内容');
      return;
    }
    dynamic data;
    try {
      data = jsonDecode(text);
    } catch (_) {
      toast(context, '恢复失败：剪贴板内容不是有效的 JSON');
      return;
    }
    if (data is! Map<String, dynamic>) {
      toast(context, '恢复失败：内容不是本应用导出的备份格式');
      return;
    }
    try {
      // 恢复前先结束进行中的训练（恢复会清空会话表）
      if (c.session.hasActive) await c.session.quit();
      final n = await c.export.restoreFromJson(data);
      await c.planRepo.reload();
      if (context.mounted) toast(context, '已恢复 $n 次训练记录 ✓');
    } on FormatException catch (e) {
      if (context.mounted) toast(context, '恢复失败：${e.message}');
    } catch (_) {
      if (context.mounted) toast(context, '恢复失败：存档可能不完整，数据未改动');
    }
  }
}

/// 专注模式：分心 App 名单（带应用图标与名称的列表，支持搜索勾选）。
class _FocusCard extends StatefulWidget {
  const _FocusCard({required this.s});

  final Settings s;

  @override
  State<_FocusCard> createState() => _FocusCardState();
}

class _FocusCardState extends State<_FocusCard> {
  List<AppEntry>? _apps;
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    // initState 里不能同步读 InheritedWidget（_load 首句 app(context)），
    // 延后一帧
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final c = app(context);
    final list = await c.focus.installedAppsWithIcons();
    // 过滤掉自己
    final filtered = list
        .where((a) => a.packageName != 'com.arono.baoji_timer')
        .toList();
    if (mounted) setState(() => _apps = filtered);
  }

  void _toggle(String pkg, bool on) {
    final s = widget.s;
    final set = s.distractingAppsList.toSet();
    on ? set.add(pkg) : set.remove(pkg);
    s.distractingApps = set.join(',');
    s.save();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final selected = s.distractingAppsList.toSet();
    final apps = _apps;
    final q = _query.trim();
    final filtered = (apps ?? const <AppEntry>[])
        .where(
          (a) =>
              q.isEmpty ||
              a.label.toLowerCase().contains(q.toLowerCase()) ||
              a.packageName.toLowerCase().contains(q.toLowerCase()),
        )
        .toList();
    return SectionCard(
      title: '专注模式',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '勾选训练中不想刷的 App，切过去再回来会提醒你。',
            style: TextStyle(color: AppTheme.textDim, fontSize: 13),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search, size: 20),
              hintText: '搜索应用名…',
              isDense: true,
            ),
          ),
          const SizedBox(height: 6),
          if (apps == null)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(8),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (filtered.isEmpty)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text(
                '没有匹配的应用',
                style: TextStyle(color: AppTheme.textDim, fontSize: 13),
              ),
            )
          else
          // 列表带图标：默认只铺前 12 行防卡片过长，搜索时展开全部匹配
          ...[
            const SizedBox(height: 2),
            for (final a in filtered.take(q.isEmpty ? 12 : filtered.length))
              _appRow(a, selected.contains(a.packageName)),
            if (q.isEmpty && filtered.length > 12)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 4),
                child: Text(
                  '还有 ${filtered.length - 12} 个，输入名称搜索',
                  style: const TextStyle(color: AppTheme.textDim, fontSize: 12),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _appRow(AppEntry a, bool selected) {
    final icon = a.icon;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _toggle(a.packageName, !selected),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
        child: Row(
          children: [
            SizedBox(
              width: 38,
              height: 38,
              child: icon != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: Image.memory(
                        icon,
                        width: 38,
                        height: 38,
                        fit: BoxFit.cover,
                      ),
                    )
                  : const Icon(
                      Icons.android_outlined,
                      size: 30,
                      color: AppTheme.textDim,
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    a.packageName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textDim,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Checkbox(
              value: selected,
              activeColor: AppTheme.primary,
              onChanged: (on) => _toggle(a.packageName, on == true),
            ),
          ],
        ),
      ),
    );
  }
}

class _AiCard extends StatefulWidget {
  const _AiCard({required this.s});

  final Settings s;

  @override
  State<_AiCard> createState() => _AiCardState();
}

class _AiCardState extends State<_AiCard> {
  late final _ctrlUrl = TextEditingController(text: widget.s.aiBaseUrl);
  late final _ctrlKey = TextEditingController(text: widget.s.aiApiKey);
  late final _ctrlModel = TextEditingController(text: widget.s.aiModel);

  @override
  void dispose() {
    _ctrlUrl.dispose();
    _ctrlKey.dispose();
    _ctrlModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return SectionCard(
      title: 'AI 配置（计划拆解）',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '兼容 OpenAI 接口格式。例：Base URL 填 https://api.moonshot.cn/v1，模型填 kimi-k2。Key 只保存在手机本地。',
            style: TextStyle(color: AppTheme.textDim, fontSize: 13),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _ctrlUrl,
            decoration: const InputDecoration(labelText: 'Base URL'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _ctrlKey,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'API Key'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _ctrlModel,
            decoration: const InputDecoration(labelText: '模型名'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () {
              s.aiBaseUrl = _ctrlUrl.text.trim();
              s.aiApiKey = _ctrlKey.text.trim();
              s.aiModel = _ctrlModel.text.trim();
              s.save();
              toast(context, 'AI 配置已保存');
            },
            child: const Text('保存 AI 配置'),
          ),
        ],
      ),
    );
  }
}

class _LarkCard extends StatefulWidget {
  const _LarkCard({required this.s});

  final Settings s;

  @override
  State<_LarkCard> createState() => _LarkCardState();
}

class _LarkCardState extends State<_LarkCard> {
  late final _ctrlId = TextEditingController(text: widget.s.larkAppId);
  late final _ctrlSecret = TextEditingController(text: widget.s.larkAppSecret);
  late final _ctrlRefresh = TextEditingController(
    text: widget.s.larkRefreshToken,
  );

  @override
  void dispose() {
    _ctrlId.dispose();
    _ctrlSecret.dispose();
    _ctrlRefresh.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = app(context);
    final s = widget.s;
    return SectionCard(
      title: '飞书日历联动',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('启用（训练日写入飞书日历）'),
            value: s.larkEnabled,
            activeThumbColor: AppTheme.primary,
            onChanged: (v) {
              s.larkEnabled = v;
              s.save();
            },
          ),
          const Text(
            '首次配置：在飞书开放平台创建自建应用（开日历权限），用电脑 lark-cli 授权拿到 refresh_token，粘贴到这里。详见 README。',
            style: TextStyle(color: AppTheme.textDim, fontSize: 13),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _ctrlId,
            decoration: const InputDecoration(labelText: 'App ID'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _ctrlSecret,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'App Secret'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _ctrlRefresh,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Refresh Token（授权码）'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    s.larkAppId = _ctrlId.text.trim();
                    s.larkAppSecret = _ctrlSecret.text.trim();
                    s.larkRefreshToken = _ctrlRefresh.text.trim();
                    s.save();
                    toast(context, '飞书配置已保存');
                  },
                  child: const Text('保存'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    s.larkAppId = _ctrlId.text.trim();
                    s.larkAppSecret = _ctrlSecret.text.trim();
                    s.larkRefreshToken = _ctrlRefresh.text.trim();
                    await s.save();
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('测试中…'),
                        backgroundColor: AppTheme.cardHi,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                    try {
                      final cid = await c.lark.fetchPrimaryCalendar();
                      s.larkCalendarId = cid;
                      await s.save();
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('连接成功 ✓ 日历已绑定'),
                          backgroundColor: AppTheme.cardHi,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    } catch (e) {
                      final msg = e.toString();
                      final friendly =
                          msg.contains('TimeoutException') ||
                              msg.contains('ClientException')
                          ? '网络不可用或超时，请检查网络'
                          : (msg.length > 80
                                ? '${msg.substring(0, 80)}…'
                                : msg);
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text('连接失败：$friendly'),
                          backgroundColor: AppTheme.cardHi,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                  child: const Text('测试连接'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PermissionCard extends StatefulWidget {
  const _PermissionCard();

  @override
  State<_PermissionCard> createState() => _PermissionCardState();
}

class _PermissionCardState extends State<_PermissionCard>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 勿扰/使用情况等特殊权限必须离 App 去系统设置授权，
    // 返回 resumed 时重建各行 FutureBuilder，状态即时刷新
    if (state == AppLifecycleState.resumed) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = app(context);
    final focus = c.focus;
    return SectionCard(
      title: '权限（逐项说明，可跳过）',
      child: Column(
        children: [
          _permRow(
            title: '通知',
            desc: '锁屏/切后台时显示组间休息倒计时和结束提醒。不给则训练时需留在 App 内看计时。',
            check: () async => await Permission.notification.isGranted,
            request: () async {
              await Permission.notification.request();
              return Permission.notification.isGranted;
            },
          ),
          _permRow(
            title: '勿扰模式访问',
            desc: '训练开始自动开勿扰（屏蔽消息），结束自动恢复。不给则需手动开勿扰。',
            check: () => focus.isDndAccessGranted(),
            request: () async {
              await focus.openDndAccessSettings();
              return focus.isDndAccessGranted();
            },
          ),
          _permRow(
            title: '使用情况访问',
            desc: '训练中切到抖音等分心 App 后回来自动提醒。不给则没有分心提醒，其他功能不受影响。',
            check: () => focus.isUsageAccessGranted(),
            request: () async {
              await focus.openUsageAccessSettings();
              return focus.isUsageAccessGranted();
            },
          ),
          _permRow(
            title: '精确闹钟',
            desc: '让休息结束的提醒准时响。不给则提醒可能晚几秒到几十秒。',
            check: () => focus.canExactAlarm(),
            request: () async {
              await focus.openExactAlarmSettings();
              return focus.canExactAlarm();
            },
          ),
          _permRow(
            title: '电池优化白名单',
            desc: '防止系统在后台杀掉计时。不给则锁屏久了计时仍准确（墙钟），但提醒可能延迟。',
            check: () => focus.isIgnoringBatteryOptimizations(),
            request: () async {
              await focus.requestIgnoreBattery();
              return focus.isIgnoringBatteryOptimizations();
            },
          ),
        ],
      ),
    );
  }

  Widget _permRow({
    required String title,
    required String desc,
    required Future<bool> Function() check,
    required Future<bool> Function() request,
  }) {
    return FutureBuilder<bool>(
      future: check(),
      builder: (context, snap) {
        final granted = snap.data == true;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                granted ? Icons.check_circle : Icons.info_outline,
                color: granted ? AppTheme.primary : AppTheme.warn,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          granted ? '已授权' : '未授权',
                          style: TextStyle(
                            fontSize: 12,
                            color: granted
                                ? AppTheme.primary
                                : AppTheme.textDim,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      desc,
                      style: const TextStyle(
                        color: AppTheme.textDim,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (!granted)
                TextButton(
                  onPressed: () async {
                    await request();
                  },
                  child: const Text('去开启'),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// 应用更新：GitHub Releases 自更新（公开仓库免令牌；私有部署可配只读令牌）。
class _UpdateCard extends StatefulWidget {
  const _UpdateCard({required this.s});

  final Settings s;

  @override
  State<_UpdateCard> createState() => _UpdateCardState();
}

class _UpdateCardState extends State<_UpdateCard> with WidgetsBindingObserver {
  late final _ctrlToken = TextEditingController(text: widget.s.ghUpdateToken);
  bool _checking = false;
  bool _upToDate = false;
  bool _needInstallPerm = false;
  String? _error;
  int? _received;
  int? _total;
  String? _apkPath;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ctrlToken.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从"允许安装未知应用"系统页返回时自动继续安装
    if (state == AppLifecycleState.resumed &&
        _needInstallPerm &&
        _apkPath != null) {
      _tryInstall();
    }
  }

  Future<void> _check() async {
    final s = widget.s;
    // 检查前先把输入框里的令牌存下（与 AI 卡片一致的本地保存策略）
    s.ghUpdateToken = _ctrlToken.text.trim();
    await s.save();
    setState(() {
      _checking = true;
      _error = null;
      _upToDate = false;
    });
    try {
      final release = await UpdateService(s).checkLatest();
      s.set(() => s.pendingUpdate = release);
      if (mounted) {
        setState(() => _upToDate = release == null);
      }
    } on UpdateException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Exception catch (e) {
      if (mounted) setState(() => _error = '检查失败：$e');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _downloadAndInstall() async {
    final s = widget.s;
    final release = s.pendingUpdate;
    if (release == null) return;
    setState(() {
      _error = null;
      _received = 0;
      _total = release.apkSize;
    });
    try {
      final path = await UpdateService(s).downloadApk(
        release,
        onProgress: (r, t) {
          if (mounted) {
            setState(() {
              _received = r;
              _total = t;
            });
          }
        },
      );
      if (!mounted) return;
      setState(() => _apkPath = path);
      await _tryInstall();
    } on UpdateException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Exception catch (e) {
      if (mounted) setState(() => _error = '下载失败：$e');
    }
  }

  Future<void> _tryInstall() async {
    final path = _apkPath;
    if (path == null) return;
    final svc = UpdateService(widget.s);
    try {
      if (await svc.canRequestInstall()) {
        await svc.installApk(path);
      } else if (mounted) {
        setState(() => _needInstallPerm = true);
      }
    } on Exception catch (e) {
      if (mounted) setState(() => _error = '无法启动安装：$e');
    }
  }

  String _briefNotes(String notes) {
    final lines = notes.split('\n').take(8).join('\n');
    return lines.length > 240 ? '${lines.substring(0, 240)}…' : lines;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return SectionCard(
      title: '应用更新',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snap) => Text(
              snap.hasData
                  ? '当前版本 v${snap.data!.version}（构建 ${snap.data!.buildNumber}）'
                  : '当前版本 …',
              style: const TextStyle(color: AppTheme.textDim, fontSize: 13),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '更新包发布在 GitHub Releases：开源公开仓库免令牌，直接检查更新即可。'
            '仅当你把仓库 fork 成私有仓库自用时，才需要粘贴只读令牌'
            '（Fine-grained tokens，只勾选该仓库，权限 Contents: Read-only）。令牌只存手机本地。',
            style: TextStyle(color: AppTheme.textDim, fontSize: 13),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _ctrlToken,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'GitHub 只读令牌（公开仓库可留空）',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _checking ? null : _check,
                  child: Text(_checking ? '正在检查…' : '检查更新'),
                ),
              ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: const TextStyle(color: AppTheme.danger, fontSize: 13),
              ),
            ),
          if (_upToDate && s.pendingUpdate == null)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                '已是最新版本 ✓',
                style: TextStyle(color: AppTheme.primary, fontSize: 13),
              ),
            ),
          ListenableBuilder(
            listenable: s,
            builder: (context, _) {
              final release = s.pendingUpdate;
              if (release == null) return const SizedBox.shrink();
              final received = _received;
              final total = _total;
              final downloading = received != null;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 24),
                  Text(
                    '发现新版 ${release.title.isEmpty ? '构建 ${release.buildNumber}' : release.title}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  if (release.notes.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        _briefNotes(release.notes),
                        style: const TextStyle(
                          color: AppTheme.textDim,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  if (downloading) ...[
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: (total != null && total > 0)
                          ? received / total
                          : null,
                      backgroundColor: AppTheme.cardHi,
                      color: AppTheme.primary,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '下载中 ${(received / 1048576).toStringAsFixed(1)}MB'
                      '${(total != null && total > 0) ? ' / ${(total / 1048576).toStringAsFixed(1)}MB' : ''}',
                      style: const TextStyle(
                        color: AppTheme.textDim,
                        fontSize: 12,
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 10),
                    FilledButton(
                      onPressed: _downloadAndInstall,
                      child: const Text('下载并安装'),
                    ),
                  ],
                  if (_needInstallPerm && _apkPath != null) ...[
                    const SizedBox(height: 8),
                    const Text(
                      '系统要求先允许本应用"安装未知应用"（只需授权一次）',
                      style: TextStyle(color: AppTheme.warn, fontSize: 12),
                    ),
                    TextButton(
                      onPressed: () =>
                          UpdateService(s).openInstallPermissionSettings(),
                      child: const Text('去系统授权'),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
