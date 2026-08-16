import 'dart:math' as math;
import 'ai_service.dart';

class MemoryItem {
  final String text;
  final List<double> vector;
  MemoryItem(this.text, this.vector);
}

/// 向量记忆：文本向量化存储，按余弦相似度检索最相关的历史。
/// demo 量级小 → 线性扫描即可，不需要向量数据库。
class VectorMemory {
  final AiService _ai;
  final int topK;
  final double minSimilarity;
  final List<MemoryItem> _items = [];

  VectorMemory(this._ai, {this.topK = 5, this.minSimilarity = 0.2});

  bool get hasItems => _items.isNotEmpty;
  int get length => _items.length;

  /// 存一条（向量化失败返回 false，不抛异常）。
  Future<bool> add(String text) async {
    final t = text.trim();
    if (t.isEmpty) return false;
    final v = await _ai.embed(t);
    if (v == null || v.isEmpty) return false;
    _items.add(MemoryItem(t, v));
    return true;
  }

  /// 检索与 query 最相关的 topK 条原文（按余弦相似度降序）。
  Future<List<String>> search(String query) async {
    if (_items.isEmpty) return const [];
    final qv = await _ai.embed(query.trim());
    if (qv == null || qv.isEmpty) return const [];
    final scored = <(double, String)>[
      for (final it in _items) (cosineSimilarity(qv, it.vector), it.text),
    ]..sort((a, b) => b.$1.compareTo(a.$1));
    return scored
        .where((s) => s.$1 >= minSimilarity)
        .take(topK)
        .map((s) => s.$2)
        .toList();
  }
}

/// 余弦相似度。纯函数，可单元测试。
double cosineSimilarity(List<double> a, List<double> b) {
  if (a.length != b.length || a.isEmpty) return 0;
  double dot = 0, na = 0, nb = 0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  if (na == 0 || nb == 0) return 0;
  return dot / (math.sqrt(na) * math.sqrt(nb));
}
