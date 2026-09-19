import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:xinjing/memory.dart';

void main() {
  test('cosineSimilarity：相同向量 = 1', () {
    expect(cosineSimilarity([1.0, 0.0], [1.0, 0.0]), closeTo(1.0, 1e-9));
  });

  test('cosineSimilarity：正交向量 = 0', () {
    expect(cosineSimilarity([1.0, 0.0], [0.0, 1.0]), closeTo(0.0, 1e-9));
  });

  test('cosineSimilarity：相反向量 = -1', () {
    expect(cosineSimilarity([1.0, 0.0], [-1.0, 0.0]), closeTo(-1.0, 1e-9));
  });

  test('cosineSimilarity：同向不同模长只与夹角有关', () {
    final a = [3.0, 4.0];
    final b = [6.0, 8.0]; // 与 a 同向
    expect(cosineSimilarity(a, b), closeTo(1.0, 1e-9));
  });

  test('cosineSimilarity：维度不一致返回 0', () {
    expect(cosineSimilarity([1.0], [1.0, 0.0]), 0);
  });

  test('MemoryItem JSON 往返一致', () {
    final it = MemoryItem('你好', [1.0, 2.0], time: 1000, type: 'diary');
    final back =
        MemoryItem.fromJson(jsonDecode(jsonEncode(it.toJson())) as Map<String, dynamic>);
    expect(back.text, '你好');
    expect(back.vector, [1.0, 2.0]);
    expect(back.time, 1000);
    expect(back.type, 'diary');
  });

  test('MemoryItem 默认 time/type', () {
    final it = MemoryItem('x', [0.5]);
    expect(it.type, 'chat');
    expect(it.time, greaterThan(0));
  });

  test('timeDecay：现在 = 1，半衰期后 = 0.5', () {
    final now = DateTime.now().millisecondsSinceEpoch;
    expect(VectorMemory.timeDecay(now), closeTo(1.0, 1e-9));
    final weekAgo = now - const Duration(days: 7).inMilliseconds;
    expect(VectorMemory.timeDecay(weekAgo), closeTo(0.5, 1e-9));
  });

  test('localEmbed：确定性、维度固定、空文本零向量', () {
    final v1 = localEmbed('我想减肥');
    final v2 = localEmbed('我想减肥');
    expect(v1, v2);
    expect(v1.length, 256);
    expect(localEmbed(''), everyElement(0.0));
    expect(v1.any((x) => x > 0), isTrue);
  });

  test('localEmbed：相似文本余弦高、无关文本余弦低', () {
    final related = cosineSimilarity(localEmbed('我想减肥'), localEmbed('最近想减肥'));
    final unrelated =
        cosineSimilarity(localEmbed('我想减肥'), localEmbed('宇宙飞船发射成功'));
    expect(related, greaterThan(unrelated));
    expect(unrelated, lessThan(0.3));
  });
}
