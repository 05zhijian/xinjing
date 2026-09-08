import 'package:flutter/material.dart';
import 'diary_store.dart';

/// 日记归档页：日期列表 + 点开看全文。
class DiariesPage extends StatefulWidget {
  final DiaryStore store;
  const DiariesPage({super.key, required this.store});

  @override
  State<DiariesPage> createState() => DiariesPageState();
}

class DiariesPageState extends State<DiariesPage> {
  List<DiaryEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final entries = await widget.store.list();
    if (!mounted) return;
    setState(() => _entries = entries);
  }

  /// 供壳层 AppBar 右上角刷新触发。
  void refresh() => _refresh();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _entries.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  '还没有日记。去「聊天」页点右上角 ✨ 生成今日觉察日记。',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _entries.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final e = _entries[i];
                final preview =
                    e.content.replaceAll(RegExp(r'[#*\-\n]'), ' ').trim();
                return Card(
                  elevation: 0,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.shade200),
                  ),
                  child: ListTile(
                    title: Text(
                      e.date,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      preview.length > 60
                          ? '${preview.substring(0, 60)}…'
                          : preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    trailing: const Icon(Icons.chevron_right, size: 20),
                    onTap: () => _showDiary(e),
                  ),
                );
              },
            ),
    );
  }

  void _showDiary(DiaryEntry e) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(e.date),
        content: SingleChildScrollView(
          child: Text(e.content, style: const TextStyle(height: 1.6)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}
