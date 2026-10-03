import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ai_service.dart';
import 'diary_store.dart';
import 'layered_memory.dart';
import 'persona/companion_manual.dart';
import 'persona/crisis_guard.dart';

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
  State<ChatPage> createState() => ChatPageState();
}

class ChatPageState extends State<ChatPage> {
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

  /// 启动时恢复本地配置：只有显式选过服务商，才恢复它配套的 key；
  /// 否则保持编译期配置（--dart-define 的 AI_PROVIDER / ZHIPU_API_KEY），
  /// 避免旧 DeepSeek key 污染智谱会话。
  Future<void> _loadSavedKey() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final p = prefs.getString('ai_provider');
      if (p == null) return;
      _ai.setProvider(p);
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
  /// [forceSafety] = true 时追加危机强制条款（不把安全交给模型自觉）。
  List<Map<String, String>> _buildHistory({
    required List<Map<String, String>> dialogue,
    String semanticContext = '',
    List<String> memoryHits = const [],
    bool useAll = false,
    bool forceSafety = false,
  }) {
    final msgs = <Map<String, String>>[];
    // 人格与行为规范统一在 lib/persona/companion_manual.dart：
    // 评测工具（dart run tool/eval.dart）评的就是这一份，改完跑 test/persona_test.dart
    final system = companionSystemPrompt + (forceSafety ? crisisDirective : '');
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
    // 危机信号识别：命中则强制注入安全条款，并在回复落地前做确定性兜底
    final requireSafety = needsCrisisGuard(text);
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
        forceSafety: requireSafety,
      ),
      onDelta: (d) => setState(() => _messages[index].content += d),
      onDone: () async {
        if (!mounted) return;
        setState(() {
          _thinking = false;
        });
        _scrollToBottom();
        // 危机兜底：模型若漏了求助指引，用确定性文案补上（安全不依赖模型自觉）
        final guarded = ensureSafetyGuidance(
          _messages[index].content,
          required: requireSafety,
        );
        if (guarded != _messages[index].content.trim()) {
          setState(() => _messages[index].content = guarded);
        }
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
        if (content.isEmpty) {
          // 兜底：没内容就不落盘、不进记忆（AiService 已把「零输出」当失败处理）
          setState(() => _messages[index].content = '⚠️ 这次没生成出内容，请重试');
          return;
        }
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

  /// 供壳层 AppBar 右上角 ✨ 触发（真实动作仍在页内维护 _thinking 状态）。
  void generateDiary() => _generateDiary();

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
                '⚠️ 未配置 AI Key：点右上角 ⚙️ 选服务商并粘贴你的 key',
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
