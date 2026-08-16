import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'ai_service.dart';

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

/// 向量记忆：文本向量化存储，按余弦相似度 × 时间衰减检索。
/// 持久化到 JSON 文件（demo 量级线性扫描即可）。
class VectorMemory {
  final AiService _ai;
  final int topK;
  final double minSimilarity;
  final List<MemoryItem> _items = [];
  File? _file;

  VectorMemory(this._ai, {this.topK = 5, this.minSimilarity = 0.2});

  bool get hasItems => _items.isNotEmpty;
  int get length => _items.length;

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

  /// 存一条（向量化失败返回 false，不抛异常）。
  Future<bool> add(String text, {String type = 'chat'}) async {
    final t = text.trim();
    if (t.isEmpty) return false;
    final v = await _ai.embed(t);
    if (v == null || v.isEmpty) return false;
    _items.add(MemoryItem(t, v, type: type));
    await save();
    return true;
  }

  /// 检索与 query 最相关的 topK 条原文（相似度 × 时间衰减降序）。
  Future<List<String>> search(String query, {String? type}) async {
    if (_items.isEmpty) return const [];
    final qv = await _ai.embed(query.trim());
    if (qv == null || qv.isEmpty) return const [];
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
