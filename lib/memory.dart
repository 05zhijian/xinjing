import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

class MemoryItem {
  final String text;
  final List<double> vector;
  final int time; // epoch ms
  final String type; // 'chat' | 'insight' | 'diary' | ...
  MemoryItem(this.text, this.vector, {int? time, this.type = 'chat'})
      : time = time ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toJson() => {
        'text': text,
        'vector': vector,
        'time': time,
        'type': type,
      };

  factory MemoryItem.fromJson(Map<String, dynamic> j) => MemoryItem(
        j['text'] as String? ?? '',
        (j['vector'] as List? ?? const [])
            .map((e) => (e as num).toDouble())
            .toList(),
        time: j['time'] as int?,
        type: j['type'] as String? ?? 'chat',
      );
}

/// 向量记忆：本地嵌入后按余弦相似度 × 时间衰减检索。
/// 持久化到 JSON 文件（demo 量级线性扫描即可）。
class VectorMemory {
  final int topK;
  final double minSimilarity;
  final List<MemoryItem> _items = [];
  File? _file;

  VectorMemory({this.topK = 5, this.minSimilarity = 0.2});

  bool get hasItems => _items.isNotEmpty;
  int get length => _items.length;
  List<MemoryItem> get items => List.unmodifiable(_items);

  /// 绑定持久化文件，启动时调用一次。
  void attach(File file) => _file = file;

  Future<void> load() async {
    if (_file == null || !await _file!.exists()) return;
    try {
      final list = jsonDecode(await _file!.readAsString()) as List;
      _items.clear();
      for (final e in list) {
        _items.add(MemoryItem.fromJson(e as Map<String, dynamic>));
      }
    } catch (_) {
      // 文件损坏时静默清空，不阻塞启动
    }
  }

  Future<void> save() async {
    if (_file == null) return;
    try {
      await _file!.parent.create(recursive: true);
      await _file!
          .writeAsString(jsonEncode([for (final it in _items) it.toJson()]));
    } catch (_) {}
  }

  /// 存一条（本地嵌入不依赖网络，恒可用）。
  Future<bool> add(String text, {String type = 'chat'}) async {
    final t = text.trim();
    if (t.isEmpty) return false;
    final v = localEmbed(t);
    _items.add(MemoryItem(t, v, type: type));
    await save();
    return true;
  }

  /// 检索与 query 最相关的 topK 条原文（相似度 × 时间衰减降序）。
  Future<List<String>> search(String query, {String? type}) async {
    if (_items.isEmpty) return const [];
    final qv = localEmbed(query.trim());
    final scored = <(double, String)>[
      for (final it in _items)
        if (type == null || it.type == type)
          (cosineSimilarity(qv, it.vector) * timeDecay(it.time), it.text),
    ]..sort((a, b) => b.$1.compareTo(a.$1));
    return scored
        .where((s) => s.$1 >= minSimilarity)
        .take(topK)
        .map((s) => s.$2)
        .toList();
  }

  /// 时间衰减：半衰期 [halfLifeDays] 天，越久远权重越低。
  static double timeDecay(int timeMs, {double halfLifeDays = 7}) {
    final days = (DateTime.now().millisecondsSinceEpoch - timeMs) / 86400000.0;
    if (days <= 0) return 1.0;
    return math.pow(0.5, days / halfLifeDays).toDouble();
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

/// 本地特征嵌入：字符 n-gram 哈希到固定维度向量。
/// 确定性（同一文本 → 同一向量）、无外部 API、无网络，供情景层余弦检索。
/// 这是刻意的不依赖 LLM 的实现：demo 量级下自包含、可测试、不限流。
List<double> localEmbed(String text, {int dim = 256, int maxNgram = 3}) {
  final vec = List<double>.filled(dim, 0);
  final t = text.toLowerCase();
  if (t.isEmpty) return vec;
  for (var n = 1; n <= maxNgram; n++) {
    for (var i = 0; i + n <= t.length; i++) {
      final h = _stableHash(t.substring(i, i + n));
      vec[h % dim] += 1.0;
    }
  }
  return vec;
}

/// 跨平台稳定的字符串哈希（不依赖 Dart 的 hashCode 实现细节）。
int _stableHash(String s) {
  var h = 0;
  for (final c in s.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return h;
}
