import 'package:flutter_test/flutter_test.dart';
import 'package:xinjing/persona/ab_stats.dart';

void main() {
  test('变体表：manual 是线上手册，baseline 是历史一行 prompt', () {
    expect(manualVariants.keys, containsAll(['manual', 'baseline']));
    expect(manualVariants['manual']!.length, greaterThan(600));
    expect(manualVariants['baseline']!.length, lessThan(200));
  });

  test('配对统计：按用例配对，抵消整体漂移', () {
    // B 那一列整体比 A 高 2 分（模拟"时段更好"），但 A 在成对比较里仍占优：
    // A: 5,4,3  B: 4,3,2  → 每对都差 +1
    final s = pairedStats(
      {'c1': 5, 'c2': 4, 'c3': 3},
      {'c1': 4, 'c2': 3, 'c3': 2},
    );
    expect(s.n, 3);
    expect(s.meanDelta, closeTo(1.0, 1e-9));
    expect(s.improved, 3);
    expect(s.worsened, 0);
    expect(s.tied, 0);
  });

  test('配对统计：只在共同用例上配对，缺失的不计入', () {
    final s = pairedStats({'c1': 4, 'c2': 5}, {'c2': 3, 'c9': 1});
    expect(s.n, 1);
    expect(s.meanDelta, closeTo(2.0, 1e-9));
    expect(s.improved, 1);
  });

  test('配对统计：空输入不炸', () {
    final s = pairedStats({}, {});
    expect(s.n, 0);
    expect(s.meanDelta, 0);
  });

  test('配对统计：持平会被算进 tied', () {
    final s = pairedStats({'c1': 4, 'c2': 3}, {'c1': 4, 'c2': 5});
    expect(s.tied, 1);
    expect(s.worsened, 1);
  });
}
