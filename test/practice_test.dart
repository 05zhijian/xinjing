import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_diary_demo/practice.dart';

void main() {
  test('PracticeData toJson/fromJson 往返一致', () {
    final p = PracticeData();
    p.goals.add(PracticeGoal('早睡', done: true));
    p.goals.add(PracticeGoal('运动'));
    p.checkins['2026-08-16'] = true;
    final back = PracticeData.fromJson(
        jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>);
    expect(back.goals.length, 2);
    expect(back.goals[0].text, '早睡');
    expect(back.goals[0].done, isTrue);
    expect(back.goals[1].done, isFalse);
    expect(back.checkins['2026-08-16'], isTrue);
  });

  test('PracticeGoal 默认 done=false', () {
    expect(PracticeGoal('x').done, isFalse);
  });
}
