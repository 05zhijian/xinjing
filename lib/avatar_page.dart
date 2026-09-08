import 'dart:io';

import 'package:flutter/material.dart';

import 'avatar.dart';
import 'avatar_renderer.dart';
import 'avatar_store.dart';

/// 镜灵画面：有真实出图（[imagePath] 指向 PNG）就显示图片，否则用主题色
/// 渐变 + 图标占位。物种决定渐变配色（确定性），夜/雨/雪加月亮以示气氛。
class AvatarArt extends StatelessWidget {
  final AvatarSpec? spec;
  final String? imagePath;
  final double size;
  const AvatarArt({
    super.key,
    required this.spec,
    this.imagePath,
    this.size = 64,
  });

  static const List<List<Color>> _pairs = [
    [Color(0xFF9CBFA8), Color(0xFFE7EEE7)], // sage
    [Color(0xFF8FB0CA), Color(0xFFE2EAF1)], // 冷蓝
    [Color(0xFFD5BD9A), Color(0xFFF3EADB)], // 暖杏
    [Color(0xFFB9ABD3), Color(0xFFEFEAF6)], // 淡紫
  ];

  @override
  Widget build(BuildContext context) {
    final species = spec?.being.species ?? '';
    var seed = 0;
    for (final c in species.codeUnits) {
      seed = (seed * 31 + c) & 0x7fffffff;
    }
    final palette = _pairs[seed % _pairs.length];
    final mood = '${spec?.scene.weather}${spec?.scene.moodPalette}';
    final night =
        mood.contains('夜') || mood.contains('雨') || mood.contains('雪') || mood.contains('墨');

    final path = imagePath;
    final file = (path == null || path.isEmpty) ? null : File(path);
    if (file != null && file.existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.18),
        child: SizedBox(
          width: size,
          height: size,
          child: Image.file(
            file,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                _placeholder(species, size, palette, night),
          ),
        ),
      );
    }
    return _placeholder(species, size, palette, night);
  }

  Widget _placeholder(
      String species, double size, List<Color> palette, bool night) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.18),
      child: SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: palette,
            ),
          ),
          child: Stack(
            children: [
              Center(
                child: Icon(
                  species.isEmpty ? Icons.auto_awesome : Icons.pets,
                  size: size * 0.46,
                  color: Colors.white.withValues(alpha: 0.75),
                ),
              ),
              if (night)
                Positioned(
                  top: size * 0.10,
                  right: size * 0.12,
                  child: Container(
                    width: size * 0.16,
                    height: size * 0.16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 「我的」页顶部的镜灵英雄卡（DevDoc §八）。
class AvatarCard extends StatelessWidget {
  final AvatarService service;
  final VoidCallback onTap;
  const AvatarCard({super.key, required this.service, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final spec = service.current;
    final subtitle = !service.hasKey
        ? '⚠️ 先在上方设置 AI Key，才能显化'
        : (spec == null
            ? '生成一只此刻的你的具象化身'
            : (spec.stateNote.isNotEmpty
                ? spec.stateNote
                : spec.being.essence.join(' · ')));
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              AvatarArt(
                  spec: spec, imagePath: service.currentImagePath, size: 52),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      spec == null ? '镜灵 · 尚未显化' : '镜灵 · ${spec.being.species}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12, height: 1.4, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}

/// 全屏化身页：当前镜灵 + 显化 + 重置身份 + 示例预览 + 演化史。
class AvatarPage extends StatefulWidget {
  final AvatarService service;
  const AvatarPage({super.key, required this.service});

  @override
  State<AvatarPage> createState() => _AvatarPageState();
}

class _AvatarPageState extends State<AvatarPage> {
  bool _busy = false;
  int _sampleIndex = 0;

  AvatarService get service => widget.service;

  Future<void> _render() async {
    if (_busy) return;
    if (!service.hasKey) {
      _toast('请先在「我的」页设置 AI Key');
      return;
    }
    if (!service.hasMemory && !service.hasIdentity) {
      _toast(AvatarResult.needData().message);
      return;
    }
    setState(() => _busy = true);
    final wasFirst = !service.hasIdentity;
    final r = await service.render();
    if (!mounted) return;
    setState(() => _busy = false);
    switch (r.outcome) {
      case AvatarOutcome.updated:
        final s = r.spec!;
        _toast(wasFirst ? '✨ 你的镜灵显化了：一只${s.being.species}' : '镜灵已更新');
      case AvatarOutcome.unchanged:
        _toast(r.message);
      case AvatarOutcome.needData:
        _toast(r.message);
      case AvatarOutcome.error:
        _toast(r.message);
    }
  }

  Future<void> _resetIdentity() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重置镜灵身份？'),
        content: const Text('会忘掉当前物种，下次显化重新生成一个新的。历史存档会保留。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: const Text('重置')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    await service.resetIdentity();
    if (!mounted) return;
    setState(() => _busy = false);
    _toast('已重置身份，下次显化会重新生成。');
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    final spec = service.current;
    return Scaffold(
      appBar: AppBar(title: const Text('镜灵'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (spec == null) _buildIntro(),
          if (spec != null) _buildCurrent(spec),
          const SizedBox(height: 8),
          _buildActions(spec != null),
          if (spec == null && !service.hasMemory) const _NoDataHint(),
          if (spec == null) _buildSamples(),
          if (service.history.isNotEmpty) _buildHistory(),
        ],
      ),
    );
  }

  Widget _buildIntro() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        '镜灵是你此刻内在自我的具象化身：物种代表你是谁，环境与气氛跟随你最近的经历而变化。',
        style: TextStyle(fontSize: 13, height: 1.6, color: Colors.grey.shade700),
      ),
    );
  }

  Widget _buildCurrent(AvatarSpec spec) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 280,
          child: Center(
            child: AvatarArt(
                spec: spec,
                imagePath: service.currentImagePath,
                size: 260),
          ),
        ),
        const SizedBox(height: 12),
        Text('一只${spec.being.species}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final e in spec.being.essence)
              Chip(
                label: Text(e, style: const TextStyle(fontSize: 12)),
                visualDensity: VisualDensity.compact,
                backgroundColor: const Color(0xFFF2F6F0),
                side: BorderSide.none,
              ),
          ],
        ),
        if (spec.being.reason.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(spec.being.reason,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13, height: 1.6, color: Colors.grey.shade700)),
        ],
        const SizedBox(height: 10),
        if (_sceneLine(spec).isNotEmpty)
          _dimLine('场景 · ${_sceneLine(spec)}'),
        if (spec.scene.props.isNotEmpty)
          _dimLine('身旁 · ${spec.scene.props.join('、')}'),
        const SizedBox(height: 6),
        if (spec.stateNote.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF2F6F0),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(spec.stateNote,
                style: const TextStyle(fontSize: 13, height: 1.5)),
          ),
      ],
    );
  }

  String _sceneLine(AvatarSpec s) => [
        s.scene.setting,
        s.scene.season,
        s.scene.weather,
        s.scene.moodPalette,
      ].where((e) => e.isNotEmpty).join(' · ');

  Widget _dimLine(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(text,
            style: TextStyle(fontSize: 13, height: 1.5, color: Colors.grey.shade600)),
      );

  Widget _buildActions(bool hasIdentity) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: _busy ? null : _render,
            icon: _busy
                ? const SizedBox(
                    width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_awesome, size: 18),
            label: Text(hasIdentity ? '再显化一次' : '显化镜灵'),
          ),
        ),
        if (hasIdentity) ...[
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: _busy ? null : _resetIdentity,
            child: const Text('重置身份'),
          ),
        ],
      ],
    );
  }

  Widget _buildSamples() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text('先看看「镜灵」长什么样',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
        const SizedBox(height: 2),
        Text('示例形象 · 不代表你',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 0; i < service.samples.length; i++)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _sampleIndex = i),
                  child: Column(
                    children: [
                      Opacity(
                        opacity: i == _sampleIndex ? 1 : 0.55,
                        child: AvatarArt(spec: service.sampleAt(i), size: 64),
                      ),
                      const SizedBox(height: 4),
                      Text(service.sampleAt(i).being.species,
                          style: const TextStyle(fontSize: 11)),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        _buildCurrent(service.sampleAt(_sampleIndex)),
        const SizedBox(height: 6),
        Center(
          child: Text('用你的记忆「显化」后，会替换成你自己的镜灵',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        ),
      ],
    );
  }

  Widget _buildHistory() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Text('演化史',
            style:
                TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
        const SizedBox(height: 8),
        for (final e in service.history.take(20)) _entryTile(e),
      ],
    );
  }

  Widget _entryTile(AvatarEntry e) {
    final date = _fmt(e.ts);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 6),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ListTile(
        dense: true,
        onTap: () => _showEntry(e),
        leading: AvatarArt(spec: e.spec, imagePath: e.imagePath, size: 40),
        title: Text('${e.spec.being.species} · $date',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        subtitle: e.spec.stateNote.isEmpty
            ? null
            : Text(e.spec.stateNote,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        trailing: const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
      ),
    );
  }

  String _fmt(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    return '${d.year}/${d.month}/${d.day} ${d.hour}:${d.minute.toString().padLeft(2, '0')}';
  }

  /// 点开一条演化史：大图 + 当次的完整画面说明。
  void _showEntry(AvatarEntry e) {
    final s = e.spec;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AvatarArt(spec: s, imagePath: e.imagePath, size: 260),
              const SizedBox(height: 14),
              Text('${s.being.species} · ${_fmt(e.ts)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final t in s.being.essence)
                    Chip(
                      label: Text(t, style: const TextStyle(fontSize: 12)),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: const Color(0xFFF2F6F0),
                      side: BorderSide.none,
                    ),
                ],
              ),
              if (s.being.reason.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(s.being.reason,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13, height: 1.6, color: Colors.grey.shade700)),
              ],
              const SizedBox(height: 10),
              if (_sceneLine(s).isNotEmpty) _dimLine('场景 · ${_sceneLine(s)}'),
              if (s.scene.props.isNotEmpty)
                _dimLine('身旁 · ${s.scene.props.join('、')}'),
              const SizedBox(height: 6),
              if (s.stateNote.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F6F0),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(s.stateNote,
                      style: const TextStyle(fontSize: 13, height: 1.5)),
                ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('关闭'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoDataHint extends StatelessWidget {
  const _NoDataHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F1E3),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Text(
        '镜灵要靠了解你才能显化：先去「聊天」页多聊几天、生成几篇日记，再回来点「显化镜灵」。',
        style: TextStyle(fontSize: 12, height: 1.5),
      ),
    );
  }
}
