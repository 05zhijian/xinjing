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
    final d = date ?? DateTime.now();
    try {
      await _dir!.create(recursive: true);
      final file = File('${_dir!.path}/${_fileName(d)}');
      final existing = await file.exists() ? await file.readAsString() : '';
      final block = content.trim();
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
        entries.add(DiaryEntry(name, await e.readAsString()));
      }
      entries.sort((a, b) => b.date.compareTo(a.date));
      return entries;
    } catch (_) {
      return const [];
    }
  }
}
