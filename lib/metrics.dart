import 'dart:convert';
import 'dart:io';

/// 一次 AI 调用的埋点（追加写到 metrics.jsonl，一行一条）。
class MetricEvent {
  final String kind; // 'chat'（流式对话）| 'complete'（画像/镜灵等非流式）
  final String provider;
  final String model;
  final int ms;
  final bool ok;
  final int? status; // HTTP 状态码
  final int? tokens; // 服务商返回的 usage.total_tokens（有则记）
  final int ts;

  MetricEvent({
    required this.kind,
    required this.provider,
    required this.model,
    required this.ms,
    required this.ok,
    this.status,
    this.tokens,
    int? ts,
  }) : ts = ts ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toJson() => {
        'ts': ts,
        'kind': kind,
        'provider': provider,
        'model': model,
        'ms': ms,
        'ok': ok,
        if (status != null) 'status': status,
        if (tokens != null) 'tokens': tokens,
      };

  factory MetricEvent.fromJson(Map<String, dynamic> j) => MetricEvent(
        kind: j['kind'] as String? ?? 'unknown',
        provider: j['provider'] as String? ?? '',
        model: j['model'] as String? ?? '',
        ms: (j['ms'] as num?)?.toInt() ?? 0,
        ok: j['ok'] as bool? ?? false,
        status: (j['status'] as num?)?.toInt(),
        tokens: (j['tokens'] as num?)?.toInt(),
        ts: (j['ts'] as num?)?.toInt(),
      );
}

/// 汇总（给 ⚙️ 页面和评测报告用）。
class MetricsSummary {
  final int calls;
  final int ok;
  final int tokens;
  final int p90Ms;
  final double avgMs;
  final Map<String, int> byKind;

  const MetricsSummary({
    required this.calls,
    required this.ok,
    required this.tokens,
    required this.p90Ms,
    required this.avgMs,
    required this.byKind,
  });

  int get failed => calls - ok;
  double get okRate => calls == 0 ? 0 : ok / calls;

  /// 一行摘要，可直接展示。
  String get line => calls == 0
      ? '暂无调用记录'
      : '调用 $calls 次 · 成功 ${(okRate * 100).toStringAsFixed(0)}% · '
          '平均 ${avgMs.toStringAsFixed(1)}ms · P90 ${p90Ms}ms'
          '${tokens > 0 ? ' · tokens $tokens' : ''}';
}

/// metrics.jsonl 的读写。追加写 + 超限裁剪（保留最近 500 条），失败静默不阻塞业务。
class MetricsStore {
  File? _file;
  static const int maxBytes = 512 * 1024;
  static const int keepLines = 500;

  void attach(File file) => _file = file;

  bool get isAttached => _file != null;

  Future<void> add(MetricEvent e) async {
    final f = _file;
    if (f == null) return;
    try {
      await f.parent.create(recursive: true);
      await f.writeAsString('${jsonEncode(e.toJson())}\n', mode: FileMode.append);
      if (await f.length() > maxBytes) await _trim(f);
    } catch (_) {}
  }

  Future<void> _trim(File f) async {
    try {
      final lines = (await f.readAsString())
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .toList();
      final kept = lines.length <= keepLines
          ? lines
          : lines.sublist(lines.length - keepLines);
      await f.writeAsString('${kept.join('\n')}\n');
    } catch (_) {}
  }

  /// 最近的 [limit] 条（时间正序）。坏行跳过。
  Future<List<MetricEvent>> recent({int limit = 200}) async {
    final f = _file;
    if (f == null || !await f.exists()) return const [];
    try {
      final lines = (await f.readAsString())
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .toList();
      final tail = lines.length <= limit ? lines : lines.sublist(lines.length - limit);
      final out = <MetricEvent>[];
      for (final l in tail) {
        try {
          out.add(MetricEvent.fromJson(jsonDecode(l) as Map<String, dynamic>));
        } catch (_) {}
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<MetricsSummary> summary({int limit = 200}) async {
    final events = await recent(limit: limit);
    if (events.isEmpty) {
      return const MetricsSummary(
          calls: 0, ok: 0, tokens: 0, p90Ms: 0, avgMs: 0, byKind: {});
    }
    final ms = events.map((e) => e.ms).toList()..sort();
    final okCount = events.where((e) => e.ok).length;
    final tokens = events.fold<int>(0, (a, e) => a + (e.tokens ?? 0));
    final byKind = <String, int>{};
    for (final e in events) {
      byKind[e.kind] = (byKind[e.kind] ?? 0) + 1;
    }
    return MetricsSummary(
      calls: events.length,
      ok: okCount,
      tokens: tokens,
      p90Ms: ms[(0.9 * (ms.length - 1)).round()],
      avgMs: ms.reduce((a, b) => a + b) / ms.length,
      byKind: byKind,
    );
  }
}
