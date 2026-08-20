/// 工作记忆（L1）中的一轮对话。
class WorkingTurn {
  final String role; // 'user' | 'assistant'
  final String content;
  WorkingTurn(this.role, this.content);
}

/// 工作记忆（L1）：会话内最近消息的环形缓冲。
/// 易失、不持久化，超 [maxWindow] 自动淘汰最旧，控制注入 prompt 的上下文长度。
class WorkingMemory {
  final int maxWindow;
  final List<WorkingTurn> _items = [];

  WorkingMemory({this.maxWindow = 20});

  int get length => _items.length;
  bool get isEmpty => _items.isEmpty;

  /// 追加一轮，溢出时淘汰最旧。
  void addTurn(String role, String content) {
    final t = content.trim();
    if (t.isEmpty) return;
    _items.add(WorkingTurn(role, t));
    if (_items.length > maxWindow) {
      _items.removeRange(0, _items.length - maxWindow);
    }
  }

  /// 返回最近 [n] 轮（默认全部，最多 maxWindow），按时间先后排序。
  List<WorkingTurn> recent({int? n}) {
    final count = (n == null || n > _items.length) ? _items.length : n;
    return List.unmodifiable(_items.sublist(_items.length - count));
  }

  void clear() => _items.clear();
}
