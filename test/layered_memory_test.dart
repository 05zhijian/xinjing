import 'package:flutter_test/flutter_test.dart';
import 'package:ai_diary_demo/ai_service.dart';
import 'package:ai_diary_demo/layered_memory.dart';
import 'package:ai_diary_demo/memory.dart';
import 'package:ai_diary_demo/profile.dart';

/// 不发网络的假 AI：complete 返回罐头回复。
/// 情景层向量已本地化（localEmbed），不再依赖 AiService.embed。
class FakeAi extends AiService {
  @override
  Future<String> complete(List<Map<String, String>> messages) async {
    final sys = messages.first['content'] ?? '';
    if (sys.contains('洞察')) return '记得自己真正的目标';
    return '{"goals":["减肥"],"values":["自由"],"facts":["做移动端"]}';
  }
}

/// 支持画像审查分支的假 AI：按 system 内容分流 extract / insight / review。
class _ReviewFakeAi extends AiService {
  @override
  Future<String> complete(List<Map<String, String>> messages) async {
    final sys = messages.first['content'] ?? '';
    if (sys.contains('expire')) {
      return '{"expire":["减肥"],"note":"你不再执着于减肥，转向考研方向。"}';
    }
    if (sys.contains('洞察')) return '记得自己真正的目标';
    return '{"goals":["考研"],"values":[],"facts":[]}';
  }
}

LayeredMemory buildLayered({UserProfile? semantic}) {
  return LayeredMemory(
    episodic: VectorMemory(),
    semantic: semantic ?? UserProfile(),
  );
}

void main() {
  test('remember：写入情景层（含日记类型）', () async {
    final m = buildLayered();
    final ok = await m.remember('今天很累', type: 'chat');
    expect(ok, isTrue);
    expect(m.episodic.length, 1);
    expect(m.episodic.items.single.type, 'chat');
    await m.remember('一篇日记', type: 'diary');
    expect(m.episodic.items.last.type, 'diary');
  });

  test('noteTurn：只写工作层，不污染情景层', () async {
    final m = buildLayered();
    m.noteTurn('user', '我想减肥');
    expect(m.working.length, 1);
    expect(m.episodic.length, 0);
  });

  test('recall：三层合并——画像 + 相关记忆 + 最近轮次', () async {
    final semantic = UserProfile.fromJson({'goals': ['早睡'], 'values': [], 'facts': []});
    final m = LayeredMemory(episodic: VectorMemory(), semantic: semantic);
    m.noteTurn('user', '我想减肥');
    m.noteTurn('assistant', '我们从每天运动开始');
    await m.remember('我想减肥', type: 'chat');
    await m.remember('我们从每天运动开始', type: 'chat');

    final r = await m.recall('我想减肥');
    expect(r.semanticContext, contains('早睡'));
    expect(r.episodicHits, contains('我想减肥')); // 同文本向量一致，必然命中
    expect(r.working.map((t) => t.content), ['我想减肥', '我们从每天运动开始']);
  });

  test('recall：workingLimit 限制最近轮次数', () async {
    final m = buildLayered();
    for (var i = 1; i <= 5; i++) {
      m.noteTurn('user', '第$i条');
    }
    final r = await m.recall('任意', workingLimit: 2);
    expect(r.working.length, 2);
    expect(r.working.last.content, '第5条');
  });

  test('recall：空记忆时各层兜底，不抛异常', () async {
    final m = buildLayered();
    final r = await m.recall('随便问问');
    expect(r.semanticContext, '');
    expect(r.episodicHits, isEmpty);
    expect(r.working, isEmpty);
  });

  test('consolidate：抽取画像合并进语义层 + 洞察写回情景层', () async {
    final m = buildLayered();
    final messages = [
      {'role': 'user', 'content': '我想减肥'},
      {'role': 'assistant', 'content': '我们从每天运动开始'},
    ];
    final result = await m.consolidate(FakeAi(), messages);
    expect(result.profileUpdated, isTrue);
    expect(result.insight, '记得自己真正的目标');
    expect(m.semantic.of('goals').map((e) => e.text), contains('减肥'));
    expect(m.semantic.of('values').map((e) => e.text), contains('自由'));
    expect(m.semantic.of('facts').map((e) => e.text), contains('做移动端'));
    expect(m.episodic.items.any((it) => it.type == 'insight'), isTrue);
  });

  test('consolidate：重复画像去重，不重复入库', () async {
    final m = buildLayered();
    final messages = [
      {'role': 'user', 'content': '我要减肥'},
      {'role': 'assistant', 'content': '加油'},
    ];
    await m.consolidate(FakeAi(), messages);
    await m.consolidate(FakeAi(), messages);
    final goal = m.semantic.of('goals').single;
    expect(goal.text, '减肥');
    expect(goal.strength, greaterThanOrEqualTo(2)); // 再印证只+强度，不重复建条目
    expect(m.episodic.items.where((it) => it.type == 'insight').length, 2);
  });

  test('stats：返回三层各自条数', () async {
    final semantic = UserProfile.fromJson({'goals': ['早睡'], 'values': ['自由'], 'facts': []});
    final m = LayeredMemory(episodic: VectorMemory(), semantic: semantic);
    m.noteTurn('user', 'hello');
    await m.remember('一条记忆', type: 'chat');
    expect(m.stats()['working'], 1);
    expect(m.stats()['episodic'], 1);
    expect(m.stats()['semantic'], 2);
  });

  test('consolidate：攒够阈值触发 review → 过时条目降级 + 记变化 + 计数归零', () async {
    final semantic = UserProfile()
      ..absorb({'goals': ['减肥'], 'values': [], 'facts': []});
    final m = LayeredMemory(
      episodic: VectorMemory(),
      semantic: semantic,
      diaryReviewEvery: 1, // 一篇就触发，方便测
    );
    await m.remember('我想考研了，放下对体重的执念', type: 'diary');
    final messages = [
      {'role': 'user', 'content': '我想考研'},
    ];

    final r = await m.consolidate(_ReviewFakeAi(), messages);
    expect(r.profileUpdated, isTrue);

    final activeGoals = m.semantic.of('goals').map((e) => e.text);
    expect(activeGoals, contains('考研'));
    expect(activeGoals, isNot(contains('减肥'))); // 被 review 降级
    expect(m.semantic.changeLog, isNotEmpty);
    expect(m.semantic.diarySinceReview, 0); // 计数已归零
    // 降级是「保留历史」，不是真删
    expect(m.semantic.inactiveCount, 1);
  });
}
