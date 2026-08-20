import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'ai_service.dart';

/// 用户画像（L2 语义记忆）：目标 / 在意 / 事实。
/// 持久化到 profile.json，每次对话注入 system，生成日记时由 AI 抽取合并。
class UserProfile {
  final List<String> goals = [];
  final List<String> values = [];
  final List<String> facts = [];
  File? _file;

  UserProfile(); // 显式默认构造（类里定义了工厂构造后需要）

  bool get isEmpty => goals.isEmpty && values.isEmpty && facts.isEmpty;

  void attach(File file) => _file = file;

  Map<String, dynamic> toJson() => {
        'goals': goals,
        'values': values,
        'facts': facts,
      };

  factory UserProfile.fromJson(Map<String, dynamic> j) {
    final p = UserProfile();
    p.goals.addAll((j['goals'] as List? ?? const []).cast<String>());
    p.values.addAll((j['values'] as List? ?? const []).cast<String>());
    p.facts.addAll((j['facts'] as List? ?? const []).cast<String>());
    return p;
  }

  /// 去重合并：重复（大小写不敏感）的条目不重复加入。
  void merge(UserProfile other) {
    void mergeInto(List<String> target, List<String> incoming) {
      for (final s in incoming) {
        final t = s.trim();
        if (t.isEmpty) continue;
        if (!target.any((e) => e.toLowerCase() == t.toLowerCase())) {
          target.add(t);
        }
      }
    }

    mergeInto(goals, other.goals);
    mergeInto(values, other.values);
    mergeInto(facts, other.facts);
  }

  /// 生成注入 system 的画像文本。空画像返回空串。
  String buildSystemContext() {
    final b = StringBuffer('【关于用户】');
    if (goals.isNotEmpty) b.write('\n- 目标：${goals.join('；')}');
    if (values.isNotEmpty) b.write('\n- 在意：${values.join('；')}');
    if (facts.isNotEmpty) b.write('\n- 已知：${facts.join('；')}');
    return b.length == 6 ? '' : b.toString();
  }

  Future<void> load() async {
    if (_file == null || !await _file!.exists()) return;
    try {
      final j = jsonDecode(await _file!.readAsString()) as Map<String, dynamic>;
      final p = UserProfile.fromJson(j);
      goals
        ..clear()
        ..addAll(p.goals);
      values
        ..clear()
        ..addAll(p.values);
      facts
        ..clear()
        ..addAll(p.facts);
    } catch (_) {}
  }

  Future<void> save() async {
    if (_file == null) return;
    try {
      await _file!.parent.create(recursive: true);
      await _file!.writeAsString(jsonEncode(toJson()));
    } catch (_) {}
  }

  /// 从对话历史抽取事实/目标/价值观并合并进画像。
  /// 抽取失败返回 false，不影响主流程。
  Future<bool> extractFromConversation(
    AiService ai,
    List<Map<String, String>> messages,
  ) async {
    final prompt = [
      {
        'role': 'system',
        'content': '你是用户成长陪伴师。根据对话内容抽取用户的真实情况，只输出 JSON：'
            '{"goals":[], "values":[], "facts":[]}。'
            'goals=用户想达成的目标；values=在意的价值观；facts=客观事实（职业、作息、习惯、近况）。'
            '每条不超过20字，只保留对话明确提到的，最多各3条。'
      },
      ...messages,
    ];
    final raw = await ai.complete(prompt);
    var extracted = parseJson(raw);
    if (extracted == null) {
      debugPrint('[profile] extract 首次解析失败，raw=${_clip(raw)}');
      // 推理模型有时把 JSON 包在解释/代码块里，追加严格指令重试一次。
      final retry = await ai.complete([
        ...prompt,
        {'role': 'user', 'content': '直接输出 JSON 对象本身，不要任何解释、代码块或多余文字。'},
      ]);
      extracted = parseJson(retry);
      if (extracted == null) {
        debugPrint('[profile] extract 重试仍失败，retry=${_clip(retry)}');
      }
    }
    if (extracted == null) return false;
    merge(extracted);
    await save();
    return true;
  }

  /// 截断超长字符串供日志打印。
  static String _clip(String s, {int max = 400}) =>
      s.length <= max ? s : '${s.substring(0, max)}…';

  /// 从回复里取出第一个 JSON 对象（容忍模型带前后缀文本）。
  static UserProfile? parseJson(String raw) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    try {
      final j =
          jsonDecode(raw.substring(start, end + 1)) as Map<String, dynamic>;
      return UserProfile.fromJson(j);
    } catch (_) {
      return null;
    }
  }
}
