import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/settings.dart';
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
        SectionCard(
          title: '数据',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('手机本地存储是唯一数据源，建议每周导出备份。',
                  style: TextStyle(color: AppTheme.textDim, fontSize: 13)),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () async {
                  final csv = await c.export.buildCsv();
                  await c.export.shareText('训练记录 CSV', csv,
                      filename: 'training_export.csv');
                },
                child: const Text('导出 CSV（备份/表格）'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () async {
                  final json = await c.export.buildJson();
                  await c.export.shareText('训练记录 JSON', json,
                      filename: 'training_export.json');
                },
                child: const Text('导出 JSON（全量备份）'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () async {
                  final pack = await c.export.buildAiPack();
                  await c.export.shareText('AI 分析包', pack,
                      filename: 'ai_analysis_pack.md');
                },
                child: const Text('生成 AI 分析包（给 AI 做总结）'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.danger),
                onPressed: () async {
                  final ok = await confirmDialog(
                      context, '清空全部数据？', '所有训练记录、计划和身体数据将被删除且无法恢复。强烈建议先导出备份。',
                      okLabel: '全部删除');
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
          child: Text('薄肌训练计时器 v1.0 · 本地优先 · 无服务器',
              style: TextStyle(color: AppTheme.textDim, fontSize: 12)),
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
            icon: const Icon(Icons.remove_circle_outline)),
        Text('$value', style: const TextStyle(fontSize: 17)),
        IconButton(
            onPressed: () => onChanged((value + 15).clamp(30, 600)),
            icon: const Icon(Icons.add_circle_outline)),
      ],
    );
  }
}

/// 专注模式：分心 App 名单勾选（读取已装 App，点选切换）。
class _FocusCard extends StatefulWidget {
  const _FocusCard({required this.s});

  final Settings s;

  @override
  State<_FocusCard> createState() => _FocusCardState();
}

class _FocusCardState extends State<_FocusCard> {
  List<String>? _apps;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = app(context);
    final list = await c.focus.installedLauncherApps();
    // 过滤掉自己
    final filtered = list.where((p) => p != 'com.arono.baoji_timer').toList()..sort();
    if (mounted) setState(() => _apps = filtered);
  }

  /// 包名 → 友好名（常见 App 映射，未知显示尾段）。
  String _label(String pkg) {
    const known = {
      'com.smile.gifmaker': '抖音', 'com.ss.android.ugc.aweme': '抖音',
      'com.kuaishou.app': '快手', 'com.xingin.xhs': '小红书',
      'com.sina.weibo': '微博', 'tv.danmaku.bili': '哔哩哔哩',
      'com.tencent.weishi': '微视', 'com.tencent.mm': '微信',
      'com.eg.android.AlipayGphone': '支付宝', 'com.netease.cloudmusic': '网易云音乐',
    };
    if (known.containsKey(pkg)) return known[pkg]!;
    return pkg.split('.').last;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final selected = s.distractingAppsList.toSet();
    final apps = _apps;
    return SectionCard(
      title: '专注模式',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('训练中切到下面勾选的 App 后，回到本应用会提醒你。默认已含常见短视频/社交 App。',
              style: TextStyle(color: AppTheme.textDim, fontSize: 13)),
          const SizedBox(height: 10),
          if (apps == null)
            const Center(
                child: Padding(
              padding: EdgeInsets.all(8),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final pkg in apps.take(60))
                  FilterChip(
                    label: Text(_label(pkg), style: const TextStyle(fontSize: 13)),
                    selected: selected.contains(pkg),
                    onSelected: (on) {
                      final set = s.distractingAppsList.toSet();
                      on ? set.add(pkg) : set.remove(pkg);
                      s.distractingApps = set.join(',');
                      s.save();
                      setState(() {});
                    },
                    selectedColor: AppTheme.primary,
                    checkmarkColor: const Color(0xFF06220F),
                    backgroundColor: AppTheme.cardHi,
                    side: BorderSide.none,
                  ),
              ],
            ),
        ],
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
              style: TextStyle(color: AppTheme.textDim, fontSize: 13)),
          const SizedBox(height: 10),
          TextField(
              controller: _ctrlUrl,
              decoration: const InputDecoration(labelText: 'Base URL')),
          const SizedBox(height: 8),
          TextField(
              controller: _ctrlKey,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'API Key')),
          const SizedBox(height: 8),
          TextField(
              controller: _ctrlModel,
              decoration: const InputDecoration(labelText: '模型名')),
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
  late final _ctrlRefresh =
      TextEditingController(text: widget.s.larkRefreshToken);

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
              style: TextStyle(color: AppTheme.textDim, fontSize: 13)),
          const SizedBox(height: 10),
          TextField(
              controller: _ctrlId,
              decoration: const InputDecoration(labelText: 'App ID')),
          const SizedBox(height: 8),
          TextField(
              controller: _ctrlSecret,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'App Secret')),
          const SizedBox(height: 8),
          TextField(
              controller: _ctrlRefresh,
              obscureText: true,
              decoration:
                  const InputDecoration(labelText: 'Refresh Token（授权码）')),
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
                    messenger.showSnackBar(const SnackBar(
                        content: Text('测试中…'),
                        backgroundColor: AppTheme.cardHi,
                        behavior: SnackBarBehavior.floating));
                    try {
                      final cid = await c.lark.fetchPrimaryCalendar();
                      s.larkCalendarId = cid;
                      await s.save();
                      messenger.showSnackBar(const SnackBar(
                          content: Text('连接成功 ✓ 日历已绑定'),
                          backgroundColor: AppTheme.cardHi,
                          behavior: SnackBarBehavior.floating));
                    } catch (e) {
                      messenger.showSnackBar(SnackBar(
                          content: Text('连接失败：$e'),
                          backgroundColor: AppTheme.cardHi,
                          behavior: SnackBarBehavior.floating));
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

class _PermissionCard extends StatelessWidget {
  const _PermissionCard();

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
              await openAppSettings();
              return focus.isDndAccessGranted();
            },
          ),
          _permRow(
            title: '使用情况访问',
            desc: '训练中切到抖音等分心 App 后回来自动提醒。不给则没有分心提醒，其他功能不受影响。',
            check: () => focus.isUsageAccessGranted(),
            request: () async {
              await openAppSettings();
              return focus.isUsageAccessGranted();
            },
          ),
          _permRow(
            title: '精确闹钟',
            desc: '让休息结束的提醒准时响。不给则提醒可能晚几秒到几十秒。',
            check: () => focus.canExactAlarm(),
            request: () async {
              await focus.openExactAlarmSettings();
              return false;
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
                    Row(children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 6),
                      Text(granted ? '已授权' : '未授权',
                          style: TextStyle(
                              fontSize: 12,
                              color: granted
                                  ? AppTheme.primary
                                  : AppTheme.textDim)),
                    ]),
                    Text(desc,
                        style: const TextStyle(
                            color: AppTheme.textDim, fontSize: 12)),
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
