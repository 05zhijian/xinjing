/// 手册版本表 + A/B 配对统计（纯 Dart，可单测）。
///
/// 为什么需要它：实测发现同一个手册跨时段测出来的分数会漂（服务商侧负载/版本差异），
/// 「改前跑一次、改后跑一次」得不出结论。正确做法是**同会话交错**：
/// 同一个用例在两个变体下相邻时间各跑一次，用**配对差**抵消时段漂移。
library;

import 'companion_manual.dart';

/// 手册化之前的那一句话 system（保留下来做 A/B 基线）。
/// 注意：它现在只用于对照实验，App 里跑的是 [companionSystemPrompt]。
const String baselineOneLinerPrompt =
    '你是"心镜"的AI成长陪伴师，融合心理学、教练技术与金刚智慧，引导用户觉察、设定目标、完成每日功课。'
    '语气温暖、简洁、有引导性，避免说教。';

/// 可对照的手册版本。key 供 `dart run tool/eval.dart --ab manual,baseline` 使用。
const Map<String, String> manualVariants = {
  'manual': companionSystemPrompt, // 现在线上用的结构化手册
  'baseline': baselineOneLinerPrompt, // 手册化之前的一行 prompt
};

/// 一个维度上的配对比较结果（A 相对 B）。
class PairedStats {
  final int n; // 成对样本数
  final double meanA;
  final double meanB;
  final double meanDelta; // A - B 的均值；正数 = A 更好
  final int improved; // A > B 的用例数
  final int worsened; // A < B 的用例数
  final int tied;

  const PairedStats({
    required this.n,
    required this.meanA,
    required this.meanB,
    required this.meanDelta,
    required this.improved,
    required this.worsened,
    required this.tied,
  });

  String get summary =>
      'n=$n · A ${meanA.toStringAsFixed(2)} vs B ${meanB.toStringAsFixed(2)} · '
      '配对差 ${meanDelta >= 0 ? '+' : ''}${meanDelta.toStringAsFixed(2)} '
      '（A 更好 $improved / B 更好 $worsened / 持平 $tied）';
}

/// 按用例 id 配对计算 A/B 差异；任一侧缺失的用例不计入。
PairedStats pairedStats(Map<String, double> a, Map<String, double> b) {
  final keys = a.keys.where(b.containsKey).toList();
  if (keys.isEmpty) {
    return const PairedStats(
        n: 0, meanA: 0, meanB: 0, meanDelta: 0, improved: 0, worsened: 0, tied: 0);
  }
  var sumA = 0.0, sumB = 0.0, sumDelta = 0.0;
  var improved = 0, worsened = 0, tied = 0;
  for (final k in keys) {
    final va = a[k]!, vb = b[k]!;
    sumA += va;
    sumB += vb;
    final d = va - vb;
    sumDelta += d;
    if (d > 0.001) {
      improved++;
    } else if (d < -0.001) {
      worsened++;
    } else {
      tied++;
    }
  }
  final n = keys.length;
  return PairedStats(
    n: n,
    meanA: sumA / n,
    meanB: sumB / n,
    meanDelta: sumDelta / n,
    improved: improved,
    worsened: worsened,
    tied: tied,
  );
}
