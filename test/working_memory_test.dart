import 'package:flutter_test/flutter_test.dart';
import 'package:xinjing/working_memory.dart';

void main() {
  test('addTurn：按时间先后追加，顺序保持', () {
    final w = WorkingMemory(maxWindow: 5);
    w.addTurn('user', 'a');
    w.addTurn('assistant', 'b');
    expect(w.length, 2);
    expect(w.recent().map((t) => t.content), ['a', 'b']);
  });

  test('addTurn：溢出时淘汰最旧', () {
    final w = WorkingMemory(maxWindow: 3);
    w.addTurn('user', '1');
    w.addTurn('user', '2');
    w.addTurn('user', '3');
    w.addTurn('user', '4');
    expect(w.length, 3);
    expect(w.recent().map((t) => t.content), ['2', '3', '4']);
  });

  test('addTurn：空内容不入库', () {
    final w = WorkingMemory();
    w.addTurn('user', '  ');
    w.addTurn('user', '');
    expect(w.isEmpty, isTrue);
  });

  test('recent(n)：只取最近 n 条', () {
    final w = WorkingMemory();
    for (var i = 1; i <= 5; i++) {
      w.addTurn('user', '$i');
    }
    expect(w.recent(n: 2).map((t) => t.content), ['4', '5']);
    expect(w.recent(n: 10).length, 5);
  });

  test('recent()：默认返回全部且不可变', () {
    final w = WorkingMemory(maxWindow: 3);
    w.addTurn('user', 'x');
    final recent = w.recent();
    expect(recent.length, 1);
    expect(() => recent.add(WorkingTurn('user', 'y')), throwsUnsupportedError);
  });

  test('clear：清空所有轮次', () {
    final w = WorkingMemory();
    w.addTurn('user', 'a');
    w.clear();
    expect(w.isEmpty, isTrue);
  });

  test('WorkingTurn 保留角色', () {
    final w = WorkingMemory();
    w.addTurn('user', '你好');
    w.addTurn('assistant', '嗨');
    final turns = w.recent();
    expect(turns[0].role, 'user');
    expect(turns[1].role, 'assistant');
  });
}
