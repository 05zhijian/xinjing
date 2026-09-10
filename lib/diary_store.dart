import 'dart:io';

class DiaryEntry {
  final String date; // YYYY-MM-DD
  final String content;
  DiaryEntry(this.date, this.content);
}

/// 反思日记（L3）归档：每条存 diaries/YYYY-MM-DD.md。
/// 同一天多篇用 --- 分隔追加。
class DiaryStore {
  Directory? _dir;

  void attach(Directory dir) => _dir = dir;

  String _fileName(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}.md';

  static String formatDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<void> save(String content, {DateTime? date}) async {
    if (_dir == null) return;
    final block = content.trim();
    if (block.isEmpty) return; // 空内容不落盘：避免出现「1 字节的空日记」
    final d = date ?? DateTime.now();
    try {
      await _dir!.create(recursive: true);
      final file = File('${_dir!.path}/${_fileName(d)}');
      final existing = await file.exists() ? await file.readAsString() : '';
      final merged = existing.isEmpty ? block : '$existing\n\n---\n\n$block';
      await file.writeAsString('$merged\n');
    } catch (_) {}
  }

  Future<List<DiaryEntry>> list() async {
    if (_dir == null || !await _dir!.exists()) return const [];
    try {
      final children = await _dir!.list().toList();
      final entries = <DiaryEntry>[];
      for (final e in children) {
        if (e is! File || !e.path.endsWith('.md')) continue;
        final name = e.uri.pathSegments.last.replaceAll('.md', '');
        final content = await e.readAsString();
        // 历史遗留的空日记（早期版本可能写入空白内容）不再展示
        if (content.replaceAll(RegExp(r'[-\s]'), '').isEmpty) continue;
        entries.add(DiaryEntry(name, content));
      }
      entries.sort((a, b) => b.date.compareTo(a.date));
      return entries;
    } catch (_) {
      return const [];
    }
  }
}
