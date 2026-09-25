import 'package:flutter/material.dart';

import '../core/app.dart';
import '../services/ai_service.dart';
import 'theme.dart';
import 'widgets/common.dart';

/// AI 教练：应用内对话 + 一键阶段复盘（直连用户自配的 OpenAI 兼容接口）。
///
/// 设计纪律（2026-09-25 Arono 需求）：
/// - **不静默回落本地规则**——配置了 AI 就必须走 AI；请求失败明示原因并给
///   「重试」，绝不拿本地规则假装 AI 回答（计划拆解页的本地回落只在那里保留）；
/// - 未配置时给配置引导，不空报错；
/// - 训练数据包（近 8 周，ExportService.buildAiData）在首轮注入上下文，
///   多轮共用；人设与安全边界见 AiService.kCoachPersona。
class AiCoachPage extends StatefulWidget {
  const AiCoachPage({super.key});

  @override
  State<AiCoachPage> createState() => _AiCoachPageState();
}

class _AiCoachPageState extends State<AiCoachPage> {
  final _turns = <AiMessage>[]; // 已完成的 user/assistant 对话轮
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
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
      final reply = await c.ai
          .chat(c.ai.buildCoachMessages(pack, history: _turns, userText: trimmed));
      if (!mounted) return;
      setState(() {
        _turns
          ..add(AiMessage('user', trimmed))
          ..add(AiMessage('assistant', reply));
        _pendingUser = null;
        _sending = false;
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
    setState(_turns.clear);
  }

  @override
  Widget build(BuildContext context) {
    final c = app(context);
    final configured = c.settings.aiConfigured;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: const Text('AI 教练'),
        actions: [
          IconButton(
            tooltip: '一键阶段复盘',
            onPressed: configured ? () => _send(AiService.kAnalysisInstruction) : null,
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

  /// 顶部状态行：模型名 + 数据包状态（对用户透明，方便排查"连的什么"）
  Widget _statusLine(AppContainer c, bool configured) {
    final model = c.settings.aiModel.isEmpty ? '未填模型名' : c.settings.aiModel;
    final dataState = _dataError != null
        ? '数据包加载失败'
        : _dataPack == null
            ? '数据包加载中…'
            : '已附近 8 周训练数据';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Row(
        children: [
          Icon(Icons.smart_toy_outlined,
              size: 14, color: configured ? AppTheme.primary : AppTheme.warn),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '模型 $model · $dataState',
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
      for (final m in _turns) _bubble(m),
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

  Widget _bubble(AiMessage m, {bool pending = false}) {
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
        child: SelectionArea(
          child: Text(
            m.content,
            style: TextStyle(
              fontSize: 15,
              height: 1.5,
              color: pending ? AppTheme.textDim : AppTheme.text,
            ),
          ),
        ),
      ),
    );
  }

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
