import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../core/app.dart';
import '../engine/engine.dart';
import '../services/ai_service.dart';
import '../services/plan_actions.dart';
import '../services/plan_repository.dart';
import 'plan_preview_sheet.dart';
import 'theme.dart';
import 'widgets/common.dart';

/// AI 教练：应用内对话 + 一键阶段复盘 + 对话式排计划（排计划模式）。
///
/// 设计纪律（2026-09-25 Arono 需求）：
/// - **不静默回落本地规则**——配置了 AI 就必须走 AI；请求失败明示原因并给
///   「重试」，绝不拿本地规则假装 AI 回答（计划拆解页的本地回落只在那里保留）；
/// - 未配置时给配置引导，不空报错；
/// - 训练数据包（近 8 周，ExportService.buildAiData）在首轮注入上下文，
///   多轮共用；人设与安全边界见 AiService.kCoachPersona；
/// - **排计划模式**：对话契约要求 AI 每次输出完整最新计划的 JSON（```json 围栏），
///   回复里成功提取到计划时气泡下出现「预览并保存为计划」——保存前仍走
///   plan_preview_sheet 逐动作人工确认（与计划页同一纪律，绝不直接落库）。
class AiCoachPage extends StatefulWidget {
  const AiCoachPage({super.key});

  @override
  State<AiCoachPage> createState() => _AiCoachPageState();
}

class _AiCoachPageState extends State<AiCoachPage> {
  final _turns = <AiMessage>[]; // 已完成的 user/assistant 对话轮
  final _planByIndex = <int, List<AiDaySpec>>{}; // 回复序号 → 提取出的计划
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _planMode = false; // 排计划模式：换契约 + 回复内提取计划
  String? _dataPack; // 训练数据包（首轮加载）
  String? _dataError;
  String? _pendingUser; // 发送中的用户输入（成功才进 _turns，失败可重试）
  String? _error; // 最近一次请求的可读失败原因
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    // initState 里不能同步读 InheritedWidget，延后一帧
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadData();
    });
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final c = app(context);
    setState(() {
      _dataError = null;
      _dataPack = null;
    });
    try {
      final pack = await c.export
          .buildAiData(weeks: 8, bodyWeightKg: c.settings.bodyWeightKg);
      if (mounted) setState(() => _dataPack = pack);
    } catch (e) {
      if (mounted) setState(() => _dataError = '训练数据读取失败：$e');
    }
  }

  Future<void> _send(String text) async {
    final trimmed = text.trim();
    if (_sending || trimmed.isEmpty) return;
    final c = app(context);
    final pack = _dataPack;
    if (!c.settings.aiConfigured || pack == null) {
      setState(() => _error = pack == null ? '训练数据还没准备好' : null);
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
      _pendingUser = trimmed;
    });
    _scrollToBottom();
    try {
      // 排计划模式用排计划契约（AI 每次输出完整最新计划 JSON），
      // 普通模式用教练人设——同一 chat 通道，不同 system 段。
      final messages = _planMode
          ? c.ai.buildPlanChatMessages(pack,
              history: _turns, userText: trimmed)
          : c.ai.buildCoachMessages(pack,
              history: _turns, userText: trimmed);
      final reply = await c.ai.chat(messages);
      if (!mounted) return;
      setState(() {
        // assistant 落在 user 之后：当前长度 +1 即新回复的下标
        final replyIdx = _turns.length + 1;
        _turns
          ..add(AiMessage('user', trimmed))
          ..add(AiMessage('assistant', reply));
        _pendingUser = null;
        _sending = false;
        // 回复里带完整计划 JSON（排计划模式的常态）→ 记录供气泡挂保存按钮；
        // 普通模式偶尔聊到排计划也能提取（契约不在，提取失败静默跳过）。
        final plan = c.ai.tryExtractPlan(reply);
        if (plan != null) _planByIndex[replyIdx] = plan;
      });
      _scrollToBottom();
    } on AiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message; // 中文可读原因，重试按钮见 _errorBar
          _sending = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'AI 请求失败，请重试（$e）';
          _sending = false;
        });
      }
    }
  }

  /// 气泡「预览并保存为计划」：仍走逐动作确认弹层，确认才落库
  /// （与计划页 AI 导入完全同一条链路：saveAiPlan + 撤旧日程 + 写新日程）。
  Future<void> _savePlanFromTurn(List<AiDaySpec> specs) async {
    final c = app(context);
    final picked = await showPlanPreviewSheet(context, specs,
        localMode: false);
    if (picked == null || !mounted) return;
    final (name, confirmed) = picked;
    final planName =
        name.isEmpty ? 'AI 生成 ${fmtDate(DateTime.now())}' : name;
    final plan =
        await saveAiPlanAndSync(c, name: planName, specs: confirmed);
    if (mounted) {
      toast(context, '已保存并设为使用中「${plan.name}」，点任意一天可微调');
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _clearChat() {
    if (_turns.isEmpty || _sending) return;
    setState(() {
      _turns.clear();
      _planByIndex.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = app(context);
    final configured = c.settings.aiConfigured;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: Text(_planMode ? 'AI 教练 · 排计划' : 'AI 教练'),
        actions: [
          // 排计划模式开关：开启后换排计划契约，AI 每轮输出完整最新计划
          IconButton(
            tooltip: _planMode ? '退出排计划模式' : '排计划模式（对话安排计划）',
            onPressed: _sending
                ? null
                : () => setState(() => _planMode = !_planMode),
            isSelected: _planMode,
            selectedIcon: const Icon(Icons.edit_calendar,
                color: AppTheme.primary),
            icon: const Icon(Icons.edit_calendar_outlined),
          ),
          if (!_planMode)
            IconButton(
              tooltip: '一键阶段复盘',
              onPressed: configured
                  ? () => _send(AiService.kAnalysisInstruction)
                  : null,
              icon: const Icon(Icons.bolt),
            ),
          IconButton(
            tooltip: '清空对话',
            onPressed: _turns.isEmpty || _sending ? null : _clearChat,
            icon: const Icon(Icons.restart_alt),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _statusLine(c, configured),
            Expanded(
              child: !configured
                  ? _guide(configured: false)
                  : _dataError != null
                      ? _dataErrorView()
                      : _chatList(),
            ),
            if (_error != null) _errorBar(),
            Divider(height: 1, color: AppTheme.cardHi),
            _inputRow(configured),
          ],
        ),
      ),
    );
  }

  /// 顶部状态行：模式 + 模型名 + 数据包状态（对用户透明，方便排查"连的什么"）
  Widget _statusLine(AppContainer c, bool configured) {
    final model = c.settings.aiModel.isEmpty ? '未填模型名' : c.settings.aiModel;
    final mode = _planMode ? '排计划模式' : '教练问答';
    final dataState = _dataError != null
        ? '数据包加载失败'
        : _dataPack == null
            ? '数据包加载中…'
            : '已附近 8 周训练数据';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Row(
        children: [
          Icon(
            _planMode ? Icons.edit_calendar_outlined : Icons.smart_toy_outlined,
            size: 14,
            color: configured ? AppTheme.primary : AppTheme.warn,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '$mode · 模型 $model · $dataState',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppTheme.textDim, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _guide({required bool configured}) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      children: [
        const Center(child: Icon(Icons.smart_toy_outlined, size: 56, color: AppTheme.textDim)),
        const SizedBox(height: 12),
        const Center(
          child: Text('和你的训练数据对话',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 8),
        const Center(
          child: Text(
            '基于手机里的真实训练记录回答：阶段复盘、找弱项、调计划、答疑。',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textDim, fontSize: 13),
          ),
        ),
        if (!configured) ...[
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.warn.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              '还没配置 AI 接口：\n'
              '1. 打开 设置 → AI 配置\n'
              '2. 填 Base URL、API Key、模型名（OpenAI 兼容格式）\n'
              '3. 点「测试连接」确认成功后回来即可对话',
              style: TextStyle(color: AppTheme.warn, fontSize: 13, height: 1.6),
            ),
          ),
        ] else ...[
          const SizedBox(height: 24),
          if (_planMode) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                '像聊天一样说需求，教练每轮给出完整计划；想改就说（换动作/改次数/加减训练日），'
                '满意后点回复里的「预览并保存为计划」。',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textDim, fontSize: 13),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _quickChip('帮我安排一份每周四练的计划'),
                _quickChip('居家只有哑铃，每周三练'),
                _quickChip('我想加强肩和背'),
                _quickChip('基于我最近的数据安排下阶段'),
              ],
            ),
          ] else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _quickChip('一键阶段复盘', AiService.kAnalysisInstruction),
                _quickChip('我最近练得怎么样？'),
                _quickChip('我的弱项在哪，怎么补？'),
                _quickChip('下周计划怎么调？'),
                _quickChip('我的组间休息合适吗？'),
              ],
            ),
        ],
      ],
    );
  }

  Widget _quickChip(String label, [String? text]) => ActionChip(
        backgroundColor: AppTheme.cardHi,
        side: BorderSide.none,
        label: Text(label,
            style: const TextStyle(fontSize: 13, color: AppTheme.text)),
        onPressed: () => _send(text ?? label),
      );

  Widget _dataErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 44, color: AppTheme.warn),
            const SizedBox(height: 12),
            Text(_dataError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.textDim, fontSize: 13)),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: _loadData, child: const Text('重试')),
          ],
        ),
      ),
    );
  }

  Widget _chatList() {
    final children = <Widget>[
      for (var i = 0; i < _turns.length; i++)
        _bubble(_turns[i], plan: _planByIndex[i]),
    ];
    if (_pendingUser != null) {
      children.add(_bubble(AiMessage('user', _pendingUser!), pending: true));
      if (_sending) children.add(_thinkingRow());
    }
    if (_turns.isEmpty && _pendingUser == null) {
      return _guide(configured: true);
    }
    return ListView(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      children: children,
    );
  }

  Widget _bubble(AiMessage m, {bool pending = false, List<AiDaySpec>? plan}) {
    final isUser = m.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? AppTheme.primary.withValues(alpha: 0.16)
              : AppTheme.cardHi,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isUser ? 14 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 14),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _bubbleContent(m, pending: pending, plan: plan),
            // 回复里提取到了完整计划 → 挂保存入口（仍走预览确认弹层）
            if (plan != null && !pending) ...[
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: _sending ? null : () => _savePlanFromTurn(plan),
                icon: const Icon(Icons.save_outlined, size: 18),
                label: const Text('预览并保存为计划'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 气泡正文：用户消息原样纯文本；AI 回复按 Markdown 排版
  /// （加粗/表格/列表/代码块，GFM 默认扩展集），可长按选择复制。
  /// 提取到计划时把 ```json 围栏从展示文本里摘掉——完整计划经
  /// 「预览并保存」查看更清楚，气泡只留说明文字。
  Widget _bubbleContent(
    AiMessage m, {
    required bool pending,
    List<AiDaySpec>? plan,
  }) {
    if (m.role != 'assistant') {
      return Text(
        m.content,
        style: TextStyle(
          fontSize: 15,
          height: 1.5,
          color: pending ? AppTheme.textDim : AppTheme.text,
        ),
      );
    }
    final data = plan == null
        ? m.content
        : m.content.replaceAll(
            RegExp(r'```(?:json)?\s*[\s\S]*?```'),
            '📋 **计划已生成**：点下方按钮预览并保存，也可以继续对话调整');
    return MarkdownBody(
      data: data,
      selectable: true,
      styleSheet: _mdStyle(context),
    );
  }

  /// 气泡内 Markdown 样式：对齐 App 深色主题（AI 输出的 Markdown
  /// 源码星号/竖线不再上屏，全部渲染成排版后的富文本）。
  MarkdownStyleSheet _mdStyle(BuildContext context) =>
      MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        p: const TextStyle(fontSize: 15, height: 1.5, color: AppTheme.text),
        h1: const TextStyle(
            fontSize: 17, height: 1.4, color: AppTheme.text, fontWeight: FontWeight.w700),
        h2: const TextStyle(
            fontSize: 16, height: 1.4, color: AppTheme.text, fontWeight: FontWeight.w700),
        h3: const TextStyle(
            fontSize: 15, height: 1.4, color: AppTheme.primary, fontWeight: FontWeight.w700),
        listBullet: const TextStyle(fontSize: 15, height: 1.5, color: AppTheme.textDim),
        blockquote: const TextStyle(color: AppTheme.textDim, fontSize: 14),
        blockquoteDecoration: BoxDecoration(
          border: const Border(left: BorderSide(color: AppTheme.cardHi, width: 3)),
          borderRadius: BorderRadius.circular(4),
        ),
        code: const TextStyle(
            fontFamily: 'monospace', fontSize: 13, color: AppTheme.accent),
        codeblockDecoration: BoxDecoration(
          color: AppTheme.bgDeep,
          borderRadius: BorderRadius.circular(8),
        ),
        tableHead: const TextStyle(
            fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.text),
        tableBody: const TextStyle(fontSize: 13, color: AppTheme.text),
        tableBorder: TableBorder.all(
            color: AppTheme.cardHi, width: 1, borderRadius: BorderRadius.circular(6)),
        tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      );

  Widget _thinkingRow() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Text('薄肌教练思考中…（通常 10-30 秒）',
                style: TextStyle(color: AppTheme.textDim, fontSize: 13)),
          ],
        ),
      );

  Widget _errorBar() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: AppTheme.warn.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 18, color: AppTheme.warn),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _error!,
              style: const TextStyle(color: AppTheme.warn, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: _pendingUser == null ? null : () => _send(_pendingUser!),
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _inputRow(bool configured) {
    return Padding(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom > 0 ? 8 : 12,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _inputCtrl,
              enabled: configured,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: configured ? (_) => _submit() : null,
              decoration: const InputDecoration(
                hintText: '问点训练上的事…',
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            tooltip: '发送',
            onPressed: configured && !_sending ? _submit : null,
            icon: _sending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send),
          ),
        ],
      ),
    );
  }

  void _submit() {
    final text = _inputCtrl.text;
    if (text.trim().isEmpty) return;
    _inputCtrl.clear();
    _send(text);
  }
}
