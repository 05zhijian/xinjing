import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ai_service.dart';
import 'diary_store.dart';
import 'layered_memory.dart';

class ChatMessage {
  String role; // 'user' | 'assistant'
  String content;
  ChatMessage(this.role, this.content);
}

class ChatPage extends StatefulWidget {
  final AiService ai;
  final LayeredMemory memory;
  final DiaryStore diaryStore;
  const ChatPage({
    super.key,
    required this.ai,
    required this.memory,
    required this.diaryStore,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  late final AiService _ai = widget.ai;
  late final LayeredMemory _memory = widget.memory;
  final List<ChatMessage> _messages = [
    ChatMessage('assistant', '你好，我是你的 AI 陪伴师。今天想聊聊什么？可以是当下的觉察、一个小目标，或者任何心事。'),
  ];
  bool _thinking = false;

  @override
  void initState() {
    super.initState();
    _loadSavedKey();
  }

  /// 启动时从本地恢复保存的 key。
  Future<void> _loadSavedKey() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final k = prefs.getString('api_key');
      if (k != null && k.isNotEmpty) _ai.setApiKey(k);
    } catch (_) {}
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// 组装给模型的 messages。
  /// 三层记忆各自注入：L3 语义画像进 system 首段，L2 相关记忆进 system【相关记忆】，
  /// L1 工作记忆作为对话历史。[useAll] = true 时拼全部历史（生成日记用，不注入相关记忆）。
  List<Map<String, String>> _buildHistory({
    required List<Map<String, String>> dialogue,
    String semanticContext = '',
    List<String> memoryHits = const [],
    bool useAll = false,
  }) {
    final msgs = <Map<String, String>>[];
    final system = '你是"心镜"的AI成长陪伴师，融合心理学、教练技术与金刚智慧，引导用户觉察、设定目标、完成每日功课。语气温暖、简洁、有引导性，避免说教。';
    msgs.add({
      'role': 'system',
      'content': semanticContext.isEmpty ? system : '$system\n$semanticContext',
    });
    if (!useAll && memoryHits.isNotEmpty) {
      for (final r in memoryHits) {
        msgs.add({'role': 'system', 'content': '【相关记忆】$r'});
      }
    }
    msgs.addAll(dialogue);
    return msgs;
  }

  void _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _thinking) return;
    setState(() {
      _messages.add(ChatMessage('user', text));
      _messages.add(ChatMessage('assistant', ''));
      _thinking = true;
    });
    _input.clear();
    _scrollToBottom();
    final index = _messages.length - 1;

    // L1 工作记忆实时记录当前问题；L2 情景层此时尚未入库，检索不会命中它自身。
    _memory.noteTurn('user', text);
    final recall = await _memory.recall(text);
    if (!mounted) return;

    final dialogue = [
      for (final t in recall.working)
        {'role': t.role, 'content': t.content},
    ];
    await _ai.chat(
      _buildHistory(
        dialogue: dialogue,
        semanticContext: recall.semanticContext,
        memoryHits: recall.episodicHits,
      ),
      onDelta: (d) => setState(() => _messages[index].content += d),
      onDone: () async {
        if (!mounted) return;
        setState(() {
          _thinking = false;
        });
        _scrollToBottom();
        // 对话结束后：工作层记 assistant 轮次，情景层持久化原始问答。
        _memory.noteTurn('assistant', _messages[index].content);
        await _memory.remember(text, type: 'chat');
        await _memory.remember(_messages[index].content, type: 'chat');
        if (mounted) setState(() {});
      },
      onError: (e) {
        if (!mounted) return;
        debugPrint('[chat] send onError: $e');
        setState(() {
          _messages[index].content = '⚠️ $e';
          _thinking = false;
        });
      },
    );
  }

  /// 弹窗让用户填/改 AI Key，保存到本地。
  Future<void> _setKeyDialog() async {
    final controller = TextEditingController(text: _ai.apiKey);
    final key = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('设置 AI Key'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '粘贴你的 DeepSeek API Key',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (key != null && key.isNotEmpty) {
      _ai.setApiKey(key);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('api_key', key);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_ai.hasKey ? '✓ Key 已保存' : 'Key 为空，未生效')),
        );
      }
    }
  }

  /// 把今天的对话生成结构化觉察日记（用全部历史，不检索）。
  void _generateDiary() async {
    if (_thinking) return;
    setState(() {
      _messages.add(ChatMessage('assistant', ''));
      _thinking = true;
    });
    _scrollToBottom();
    final index = _messages.length - 1;
    // 全量回顾本次会话（工作记忆的完整上下文），生成结构化日记。
    final dialogue = [
      for (final m in _messages)
        if (m.content.isNotEmpty) {'role': m.role, 'content': m.content},
    ];
    final history = _buildHistory(
      dialogue: dialogue,
      semanticContext: _memory.semanticContext,
      useAll: true,
    );
    history[0] = {
      'role': 'system',
      'content': '根据用户和你的对话内容，生成一份结构化觉察日记，包含【今日觉察】【今日收获】【明日功课】。语言真诚、口语化、不空洞，150字以内，只输出日记正文。',
    };
    await _ai.chat(
      history,
      onDelta: (d) => setState(() => _messages[index].content += d),
      onDone: () async {
        if (!mounted) return;
        setState(() => _thinking = false);
        _scrollToBottom();
        final content = _messages[index].content.trim();
        await widget.diaryStore.save(content);
        await _memory.remember(content, type: 'diary');
        // 记忆整合升华：抽取画像进语义层 + 洞察写回情景层。
        await _memory.consolidate(_ai, history);
        if (mounted) {
          setState(() {});
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✓ 日记已保存到「日记」页')),
          );
        }
      },
      onError: (e) {
        if (!mounted) return;
        setState(() {
          _messages[index].content = '⚠️ $e';
          _thinking = false;
        });
      },
    );
  }

  void _scrollToBottom() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('心镜 · AI 陪伴'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: '设置 AI Key',
            icon: const Icon(Icons.key),
            onPressed: _setKeyDialog,
          ),
          IconButton(
            tooltip: '生成今日觉察日记',
            icon: const Icon(Icons.auto_awesome),
            onPressed: _thinking ? null : _generateDiary,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (_, i) => _bubble(_messages[i]),
            ),
          ),
          if (!_ai.hasKey)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                '⚠️ 未配置 API Key：flutter run --dart-define=DEEPSEEK_API_KEY=你的key',
                style: TextStyle(color: Colors.orange, fontSize: 12),
              ),
            ),
          if (_memory.stats()['episodic']! > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '🧠 情景 ${_memory.stats()['episodic']} 条 · '
                  '画像 ${_memory.stats()['semantic']} 条',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                ),
              ),
            ),
          _inputBar(),
        ],
      ),
    );
  }

  Widget _bubble(ChatMessage m) {
    final isUser = m.role == 'user';
    final thinking = m.content.isEmpty;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFF5C8A6E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: thinking
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(
                m.content,
                style: TextStyle(
                  color: isUser ? Colors.white : const Color(0xFF333333),
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
      ),
    );
  }

  Widget _inputBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                enabled: !_thinking,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: '聊聊你的觉察、目标或心事…',
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: '发送',
              onPressed: _thinking ? null : _send,
              icon: const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}
