import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_diary_demo/profile.dart';

void main() {
  test('merge：去重合并（大小写不敏感）', () {
    final p = UserProfile();
    p.merge(UserProfile.fromJson({
      'goals': ['早睡', '早睡', '运动'],
      'values': ['自由'],
      'facts': ['做移动端开发'],
    }));
    p.merge(UserProfile.fromJson({
      'goals': ['运动', '早起'],
      'values': [' 自由 '],
      'facts': [],
    }));
    expect(p.goals, ['早睡', '运动', '早起']);
    expect(p.values, ['自由']);
    expect(p.facts, ['做移动端开发']);
  });

  test('fromJson 空输入不抛异常', () {
    final p = UserProfile.fromJson({});
    expect(p.isEmpty, isTrue);
  });

  test('buildSystemContext：空画像返回空串', () {
    expect(UserProfile().buildSystemContext(), '');
  });

  test('buildSystemContext：非空画像包含各段', () {
    final p = UserProfile.fromJson({
      'goals': ['早睡'],
      'values': ['自由'],
      'facts': ['做移动端'],
    });
    final ctx = p.buildSystemContext();
    expect(ctx, contains('早睡'));
    expect(ctx, contains('自由'));
    expect(ctx, contains('做移动端'));
  });

  test('parseJson：容忍模型输出带前后缀文本', () {
    final raw = '好的，以下是抽取结果：\n{"goals":["早睡"],"values":[],"facts":[]}\n完';
    final p = UserProfile.parseJson(raw);
    expect(p, isNotNull);
    expect(p!.goals, ['早睡']);
  });

  test('toJson/fromJson 往返一致', () {
    final p = UserProfile.fromJson({'goals': ['a'], 'values': ['b'], 'facts': ['c']});
    final back =
        UserProfile.fromJson(jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>);
    expect(back.goals, ['a']);
    expect(back.values, ['b']);
    expect(back.facts, ['c']);
  });
}
