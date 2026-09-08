import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ai_service.dart';

/// 全局右上角 ⚙️ 打开的 AI 设置页：服务商选择 + API Key（一处配置，全功能共用）。
class AiSettingsPage extends StatefulWidget {
  final AiService ai;
  const AiSettingsPage({super.key, required this.ai});

  @override
  State<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends State<AiSettingsPage> {
  late final TextEditingController _key =
      TextEditingController(text: widget.ai.apiKey);

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  bool get _zhipu => widget.ai.provider == AiService.kZhipu;

  Future<void> _setProvider(String p) async {
    if (p == widget.ai.provider) return;
    widget.ai.setProvider(p);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ai_provider', p);
    if (mounted) setState(() {});
  }

  Future<void> _saveKey() async {
    final k = _key.text.trim();
    if (k.isEmpty) {
      _toast('Key 为空，未保存');
      return;
    }
    widget.ai.setApiKey(k);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_key', k);
    await prefs.setString('ai_provider', widget.ai.provider);
    _toast('✓ Key 已保存');
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI 设置'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _card(
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('服务商',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  DropdownButton<String>(
                    value: widget.ai.provider,
                    isDense: true,
                    underline: const SizedBox.shrink(),
                    style: const TextStyle(color: Color(0xFF5C8A6E)),
                    items: const [
                      DropdownMenuItem(
                          value: AiService.kDeepSeek, child: Text('DeepSeek')),
                      DropdownMenuItem(
                          value: AiService.kZhipu, child: Text('智谱')),
                    ],
                    onChanged: (v) {
                      if (v != null) _setProvider(v);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _zhipu
                    ? '智谱：一个 key 全通——GLM 文本/日记 + CogView 生图（镜灵出真图）'
                    : 'DeepSeek：纯文本/日记；无生图，镜灵用占位画布',
                style: TextStyle(fontSize: 12, height: 1.4, color: Colors.grey.shade600),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _card(
            children: [
              const Text('API Key',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                controller: _key,
                decoration: InputDecoration(
                  hintText: '粘贴所选服务商的 API Key',
                  isDense: true,
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _saveKey,
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text('保存'),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.ai.hasKey
                    ? '当前已配置：…${widget.ai.apiKey.substring(widget.ai.apiKey.length > 6 ? widget.ai.apiKey.length - 6 : 0)}'
                    : '未配置：镜灵不可显化、对话不可用',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _card(
            children: [
              Text('说明',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
              const SizedBox(height: 6),
              Text(
                '· Key 与服务商只保存在本机，重启自动记住。\n'
                '· 发给生图/对话平台的只是提炼后的文本，原始记忆留在本地。\n'
                '· 智谱一个 key 即可解锁全部功能（含镜灵真图）。',
                style: TextStyle(
                    fontSize: 12, height: 1.7, color: Colors.grey.shade600),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _card({required List<Widget> children}) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }
}
