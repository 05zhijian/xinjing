import 'package:flutter/material.dart';
import 'avatar_page.dart';
import 'avatar_renderer.dart';
import 'profile.dart';

/// 我的页：镜灵入口 + AI 对你的了解（画像）查看与手动补充。
/// API Key 与服务商配置已上收到全局右上角 ⚙️（ai_settings_page.dart）。
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

  Future<void> _addItem(String section) async {
    final controller = TextEditingController();
    final label = switch (section) {
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
    if (text == null || text.isEmpty) return;
    setState(() {
      switch (section) {
        case 'goals':
          widget.profile.goals.add(text);
        case 'values':
          widget.profile.values.add(text);
        default:
          widget.profile.facts.add(text);
      }
    });
    await widget.profile.save();
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
            '来自日常对话的自动总结，你也可以手动补充。',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          _sectionCard('目标', p.goals, 'goals'),
          _sectionCard('在意 / 价值观', p.values, 'values'),
          _sectionCard('关于你的事实', p.facts, 'facts'),
        ],
      ),
    );
  }

  Widget _sectionCard(String title, List<String> items, String section) {
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
                  onPressed: () => _addItem(section),
                ),
              ],
            ),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8, left: 2),
                child: Text('暂无',
                    style:
                        TextStyle(fontSize: 13, color: Colors.grey.shade500)),
              )
            else
              ...items.map(
                (s) => Padding(
                  padding: const EdgeInsets.only(bottom: 6, left: 2),
                  child: Text('• $s',
                      style: const TextStyle(fontSize: 14, height: 1.4)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
