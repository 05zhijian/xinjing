import 'package:flutter/material.dart';
import 'avatar_page.dart';
import 'avatar_renderer.dart';
import 'profile.dart';

/// 我的页：镜灵入口 + AI 对你的了解（画像）查看/纠错/手动补充。
/// 每条画像可删除（标为过期，不真删），带「被印证次数」；
/// 顶部顺带展示「画像审查」留下的人话变化记录。
/// API Key 与服务商配置上收到全局右上角 ⚙️（ai_settings_page.dart）。
class SettingsPage extends StatefulWidget {
  final UserProfile profile;
  final AvatarService avatar;
  const SettingsPage({
    super.key,
    required this.profile,
    required this.avatar,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  /// 进入全屏化身页；返回后刷新顶部卡片。
  Future<void> _openAvatar() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AvatarPage(service: widget.avatar)),
    );
    if (mounted) setState(() {});
  }

  Future<void> _addItem(String dim) async {
    final controller = TextEditingController();
    final label = switch (dim) {
      'goals' => '目标',
      'values' => '在意 / 价值观',
      _ => '事实',
    };
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('补充$label'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: '输入$label', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (text == null || text.isEmpty) return;
    setState(() => widget.profile.upsert(dim, text));
    await widget.profile.save();
  }

  /// 把一条画像标为「已不适用」（降级保留历史，不再注入）。
  Future<void> _deactivate(ProfileItem item) async {
    setState(() => widget.profile.deactivate(item.text));
    await widget.profile.save();
  }

  String _fmt(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    return '${d.month}月${d.day}日';
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AvatarCard(service: widget.avatar, onTap: _openAvatar),
          const SizedBox(height: 16),
          Text('AI 对你的了解',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            '对话/日记自动积累；被反复印证会变牢靠，说错的你随时能「放下」。',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          _sectionCard('目标', 'goals'),
          _sectionCard('在意 / 价值观', 'values'),
          _sectionCard('关于你的事实', 'facts'),
          if (p.changeLog.isNotEmpty) ...[
            const SizedBox(height: 8),
            _changeLogCard(),
          ],
        ],
      ),
    );
  }

  Widget _sectionCard(String title, String dim) {
    final list = widget.profile.of(dim);
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                IconButton(
                  tooltip: '补充',
                  icon: const Icon(Icons.add, size: 20),
                  onPressed: () => _addItem(dim),
                ),
              ],
            ),
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8, left: 2),
                child: Text('暂无',
                    style:
                        TextStyle(fontSize: 13, color: Colors.grey.shade500)),
              )
            else
              ...list.map(
                (it) => Padding(
                  padding: const EdgeInsets.only(bottom: 6, left: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text('• ${it.text}',
                            style: const TextStyle(fontSize: 14, height: 1.4)),
                      ),
                      if (it.strength > 1)
                        Padding(
                          padding: const EdgeInsets.only(top: 2, right: 6),
                          child: Text('×${it.strength}',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: const Color(0xFF5C8A6E))),
                        ),
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () async {
                          await _deactivate(it);
                          if (mounted) {
                            ScaffoldMessenger.of(context)
                              ..hideCurrentSnackBar()
                              ..showSnackBar(const SnackBar(
                                  content: Text('已放下这条，不再作为对你的了解'),
                                  behavior: SnackBarBehavior.floating));
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Text('放下',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade500)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _changeLogCard() {
    final log = widget.profile.changeLog.take(6).toList();
    return Card(
      elevation: 0,
      color: const Color(0xFFF2F6F0),
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.psychology_outlined, size: 18, color: Color(0xFF5C8A6E)),
                SizedBox(width: 6),
                Text('它对自己的修正',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 8),
            for (final c in log)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('${_fmt(c.ts)} · ${c.note}',
                    style: const TextStyle(fontSize: 13, height: 1.5)),
              ),
          ],
        ),
      ),
    );
  }
}
