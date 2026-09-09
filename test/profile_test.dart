import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_diary_demo/profile.dart';

void main() {
  test('旧格式兼容：纯数组 goals/values/facts → 转活跃条目', () {
    final p = UserProfile.fromJson({
      'goals': ['早睡', '运动'],
      'values': ['自由'],
      'facts': ['做移动端'],
    });
    expect(p.of('goals').map((e) => e.text), ['早睡', '运动']);
    expect(p.of('values').map((e) => e.text), ['自由']);
    expect(p.activeCount, 4);
  });

  test('upsert：同维同文（忽略大小写）刷新强度，不重复建条目', () {
    final p = UserProfile();
    p.upsert('goals', '早睡');
    p.upsert('goals', ' 早睡 ');
    p.upsert('goals', '运动');
    expect(p.of('goals').length, 2);
    final zaoShui = p.of('goals').firstWhere((e) => e.text == '早睡');
    expect(zaoShui.strength, 2);
  });

  test('deactivate：降级保留历史，注入只含活跃', () {
    final p = UserProfile()
      ..absorb({'goals': ['减肥'], 'values': [], 'facts': []});
    p.upsert('goals', '考研');
    expect(p.deactivate('减肥'), 1);
    expect(p.of('goals').map((e) => e.text), ['考研']);
    expect(p.inactiveCount, 1);
    expect(p.buildSystemContext(), contains('考研'));
    expect(p.buildSystemContext(), isNot(contains('减肥')));
  });

  test('buildSystemContext：空画像返回空串；非空含各段', () {
    expect(UserProfile().buildSystemContext(), '');
    final p = UserProfile()
      ..absorb({'goals': ['早睡'], 'values': ['自由'], 'facts': ['做移动端']});
    final ctx = p.buildSystemContext();
    expect(ctx, contains('早睡'));
    expect(ctx, contains('自由'));
    expect(ctx, contains('做移动端'));
  });

  test('parseGroups：容忍模型输出带前后缀；垃圾返回 null', () {
    final g = UserProfile.parseGroups('好的：\n{"goals":["早睡"],"values":[],"facts":["做移动端"]}\n完');
    expect(g, isNotNull);
    expect(g!['goals'], ['早睡']);
    expect(UserProfile.parseGroups('抱歉，无法完成。'), isNull);
  });

  test('extractFromConversation：回调抽取成功吸收；失败重试一次', () async {
    final p = UserProfile();
    var calls = 0;
    Future<String> complete(List<Map<String, String>> messages) async {
      calls++;
      if (calls == 1) return '不是 JSON';
      return '{"goals":["早睡"],"values":[],"facts":[]}';
    }

    final ok = await p.extractFromConversation(complete, [
      {'role': 'user', 'content': '我想早睡'},
    ]);
    expect(ok, isTrue);
    expect(calls, 2);
    expect(p.of('goals').map((e) => e.text), ['早睡']);

    // 彻底失败返回 false，不抛异常
    final p2 = UserProfile();
    Future<String> fail(List<Map<String, String>> _) async => '不是 JSON';
    expect(await p2.extractFromConversation(fail, []), isFalse);
  });

  test('changeLog：logChange 写入并在前、超上限裁剪', () {
    final p = UserProfile();
    p.logChange('你不再执着于减肥');
    p.logChange('开始准备考研');
    expect(p.changeLog.first.note, '开始准备考研');
    p.logChange('  ');
    expect(p.changeLog.length, 2);
  });

  test('toJson/fromJson 往返：保留条目元数据、计数与 changeLog', () {
    final p = UserProfile()
      ..absorb({'goals': ['减肥'], 'values': [], 'facts': []});
    p.upsert('goals', '减肥'); // strength→2
    p.upsert('goals', '考研');
    p.deactivate('减肥');
    p.addDiary();
    p.logChange('放下了减肥');

    final back = UserProfile.fromJson(
        jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>);
    expect(back.activeCount, 1);
    expect(back.inactiveCount, 1);
    expect(back.of('goals').single.text, '考研');
    expect(back.diarySinceReview, 1);
    expect(back.changeLog.single.note, '放下了减肥');
    // 降级条目的 strength 也保留了
    expect(back.items.where((e) => !e.active).single.strength, 2);
  });

  test('文件损坏时静默兜底为空', () async {
    final dir = await Directory.systemTemp.createTemp('profile_test');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/profile.json')..writeAsStringSync('{{{');
    final p = UserProfile()..attach(file);
    await p.load();
    expect(p.activeCount, 0);
  });
}
