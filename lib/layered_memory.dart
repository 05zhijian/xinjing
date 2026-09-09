import 'dart:convert';

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
///      整合（consolidate）把画像升华进语义层、洞察写回情景层；
///      画像会「成长」：每篇日记修订一次，攒够 [diaryReviewEvery] 篇触发 review，
///      让过时条目降级（见 profile.dart 与 DevDoc「画像进化」）。
/// 读取（recall）：语义层恒定注入 + 工作层最近轮次 + 情景层语义检索，三层合并控制上下文。
class LayeredMemory {
  final WorkingMemory working; // L1
  final VectorMemory episodic; // L2
  final UserProfile semantic; // L3
  final int diaryReviewEvery; // 触发画像审查所需的新日记数

  LayeredMemory({
    required this.episodic,
    required this.semantic,
    WorkingMemory? working,
    int workingWindow = 20,
    this.diaryReviewEvery = kProfileDiaryReviewEvery,
  }) : working = working ?? WorkingMemory(maxWindow: workingWindow);

  /// 语义层画像文本（恒定注入 system 用）。
  String get semanticContext => semantic.buildSystemContext();

  /// 各层当前条数（调试 / 未来 UI 用）。
  Map<String, int> stats() => {
        'working': working.length,
        'episodic': episodic.length,
        'semantic': semantic.activeCount,
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

  /// 记忆整合升华：抽取画像→修订合并进语义层；洞察写回情景层；
  /// 每篇日记计数，攒够阈值触发画像审查 review。
  Future<ConsolidationResult> consolidate(
    AiService ai,
    List<Map<String, String>> messages,
  ) async {
    final profileUpdated = await semantic.extractFromConversation(
        (msgs) => ai.complete(msgs), messages);
    final insight = await _extractInsight(ai, messages);
    if (insight != null) {
      await episodic.add(insight, type: 'insight');
    }
    semantic.addDiary();
    if (semantic.diarySinceReview >= diaryReviewEvery) {
      await _review(ai);
    }
    return ConsolidationResult(
        profileUpdated: profileUpdated, insight: insight);
  }

  /// 画像审查：让模型对照近期日记/洞察，找出已过时/被推翻的条目并降级，
  /// 同时留下一句人话变化记录（changeLog）。
  Future<void> _review(AiService ai) async {
    final profileLines = <String>[];
    for (final d in UserProfile.dims) {
      for (final it in semantic.of(d)) {
        profileLines.add('· ${it.text}');
      }
    }
    final recents = episodic.items
        .where((it) => it.type == 'diary' || it.type == 'insight')
        .toList()
      ..sort((a, b) => b.time.compareTo(a.time));
    final recentText =
        recents.take(10).map((it) => '· ${it.text}').join('\n');

    final system = '你是用户画像的审查师。用户在使用一款 AI 陪伴日记，画像由每篇日记自动抽取累积。'
        '请对照用户的近期记忆，找出其中已经过时、被推翻或不再成立的条目。'
        '只输出一个 JSON，不要解释或代码块：'
        '{"expire":["与下方画像完全一致的原文", ...], "note":"一句话概括用户这段时间的变化（≤40字，给用户看；没变化就空字符串）"}。'
        '规则：expire 里的每条必须能逐字对应下方某条画像原文；证据不足时宁可不 expire；'
        '不要臆造用户没表达过的事，也不要改动没证据的条目。';

    final messages = [
      {'role': 'system', 'content': system},
      {
        'role': 'user',
        'content': '【当前画像】\n${profileLines.isEmpty ? '（空）' : profileLines.join('\n')}\n\n'
            '【近期记忆】\n${recentText.isEmpty ? '（暂无）' : recentText}',
      },
    ];

    final raw = await ai.complete(messages);
    var review = _parseReview(raw);
    review ??= _parseReview(await ai.complete([
      ...messages,
      {'role': 'user', 'content': '直接输出 JSON 对象本身，不要任何解释、代码块或多余文字。'},
    ]));
    if (review == null) return;

    var expired = 0;
    for (final text in review['expire'] as List? ?? const []) {
      expired += semantic.deactivate(text as String);
    }
    semantic.resetDiaryCount();
    final note = (review['note'] as String? ?? '').trim();
    if (note.isNotEmpty) {
      semantic.logChange(note);
    } else if (expired > 0) {
      semantic.logChange('我把 $expired 条已过时的信息放下了。');
    }
    await semantic.save();
  }

  /// 从模型回复里取 review JSON（容忍前后缀）。
  static Map<String, dynamic>? _parseReview(String raw) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    try {
      return jsonDecode(raw.substring(start, end + 1)) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
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
