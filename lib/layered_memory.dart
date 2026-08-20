import 'ai_service.dart';
import 'memory.dart';
import 'profile.dart';
import 'working_memory.dart';

/// 一次多级检索的结果：三层记忆合并后的上下文。
class MemoryRecall {
  final String semanticContext; // L3：画像文本，空串表示无画像
  final List<String> episodicHits; // L2：相关情景记忆原文
  final List<WorkingTurn> working; // L1：最近对话轮次

  const MemoryRecall({
    this.semanticContext = '',
    this.episodicHits = const [],
    this.working = const [],
  });
}

/// 一次记忆整合升华的结果。
class ConsolidationResult {
  final bool profileUpdated; // L3 语义层是否合并了新画像
  final String? insight; // 写入 L2 的洞察，null 表示抽取失败
  const ConsolidationResult({required this.profileUpdated, this.insight});
}

/// 三层记忆编排器。
/// L1 工作记忆（会话窗口）· L2 情景记忆（向量化原始记录）· L3 语义记忆（抽取画像）。
///
/// 写入：工作层在会话中实时记录（noteTurn）；情景层在对话结束后持久化（remember）；
///      整合（consolidate）把画像升华进语义层、洞察写回情景层。
/// 读取（recall）：语义层恒定注入 + 工作层最近轮次 + 情景层语义检索，三层合并控制上下文。
class LayeredMemory {
  final WorkingMemory working; // L1
  final VectorMemory episodic; // L2
  final UserProfile semantic; // L3

  LayeredMemory({
    required this.episodic,
    required this.semantic,
    WorkingMemory? working,
    int workingWindow = 20,
  }) : working = working ?? WorkingMemory(maxWindow: workingWindow);

  /// 语义层画像文本（恒定注入 system 用）。
  String get semanticContext => semantic.buildSystemContext();

  /// 各层当前条数（调试 / 未来 UI 用）。
  Map<String, int> stats() => {
        'working': working.length,
        'episodic': episodic.length,
        'semantic':
            semantic.goals.length + semantic.values.length + semantic.facts.length,
      };

  /// 工作层：会话中实时记录一轮（易失，不持久化）。
  void noteTurn(String role, String content) => working.addTurn(role, content);

  /// 情景层：对话/日记结束后持久化一条原始记录。
  Future<bool> remember(String text, {String type = 'chat'}) =>
      episodic.add(text, type: type);

  /// 多级检索：三层合并。情景层向量检索可能因无 Key 返回空，不抛异常。
  Future<MemoryRecall> recall(String query, {int workingLimit = 12}) async {
    final episodicHits =
        episodic.hasItems ? await episodic.search(query) : const <String>[];
    return MemoryRecall(
      semanticContext: semanticContext,
      episodicHits: episodicHits,
      working: working.recent(n: workingLimit),
    );
  }

  /// 记忆整合升华：从对话抽取画像→合并进语义层；压缩洞察→写回情景层。
  Future<ConsolidationResult> consolidate(
    AiService ai,
    List<Map<String, String>> messages,
  ) async {
    final profileUpdated = await semantic.extractFromConversation(ai, messages);
    final insight = await _extractInsight(ai, messages);
    if (insight != null) {
      await episodic.add(insight, type: 'insight');
    }
    return ConsolidationResult(profileUpdated: profileUpdated, insight: insight);
  }

  /// 把对话中最值得记住的一点压缩成一句 20 字内洞察。失败返回 null。
  Future<String?> _extractInsight(
    AiService ai,
    List<Map<String, String>> messages,
  ) async {
    final prompt = [
      {
        'role': 'system',
        'content': '你是用户成长陪伴师。把以下对话中最值得记住的一点，压缩成一句20字以内的洞察'
            '（一句人生启发或对用户自己的认识），只输出洞察本身，不要引号和多余文字。',
      },
      ...messages,
    ];
    final raw = (await ai.complete(prompt)).trim();
    return raw.isEmpty ? null : raw;
  }
}
