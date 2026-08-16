import 'package:flutter_test/flutter_test.dart';
import 'package:ai_diary_demo/memory.dart';

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
}
