import 'dart:convert';
import 'dart:io';

import 'avatar.dart';

/// 一次显化结果的存档条目（最新在前）。
class AvatarEntry {
  final int ts; // epoch ms
  final AvatarSpec spec;
  String? imagePath; // 预留：M2 真实出图后指向 PNG，M1 恒为 null

  AvatarEntry({required this.ts, required this.spec, this.imagePath});

  Map<String, dynamic> toJson() => {
        'ts': ts,
        'spec': spec.toJson(),
        if (imagePath != null) 'imagePath': imagePath,
      };

  factory AvatarEntry.fromJson(Map<String, dynamic> j) => AvatarEntry(
        ts: j['ts'] as int? ?? DateTime.now().millisecondsSinceEpoch,
        spec: AvatarSpec.fromJson(
            (j['spec'] as Map<String, dynamic>?) ?? const {}),
        imagePath: j['imagePath'] as String?,
      );
}

/// 一条「人话纠偏」：用户对镜灵形象的反馈，下一次显化（含重置定身份）参考。
class AvatarFeedback {
  final int ts;
  final String text;
  const AvatarFeedback({required this.ts, required this.text});

  Map<String, dynamic> toJson() => {'ts': ts, 'text': text};

  factory AvatarFeedback.fromJson(Map<String, dynamic> j) => AvatarFeedback(
        ts: j['ts'] as int? ?? DateTime.now().millisecondsSinceEpoch,
        text: (j['text'] as String? ?? '').trim(),
      );
}

/// 镜灵持久化：avatar.json = 当前 spec + 显化历史 + 用户纠偏反馈。
/// 风格对齐 profile.dart 的 attach/load/save：文件损坏时静默兜底为「空」。
class AvatarStore {
  AvatarSpec? current;
  final List<AvatarEntry> history = []; // 最新在前
  final List<AvatarFeedback> feedback = []; // 最新在前，上限 20
  File? _file;
  Directory? _imageDir;

  AvatarStore();

  bool get hasIdentity => current?.being.isValid ?? false;

  AvatarSpec? get latest => current;

  /// 最新一版的图（等于 history 首条，commit 时与 current 同步）。
  String? get currentImagePath =>
      history.isNotEmpty ? history.first.imagePath : null;

  void attach(File file) => _file = file;

  /// 绑定生图存档目录（avatar/imgs/）。M2 起真图落盘用。
  void attachImageDir(Directory dir) => _imageDir = dir;

  Future<void> load() async {
    if (_file == null || !await _file!.exists()) return;
    try {
      final j = jsonDecode(await _file!.readAsString()) as Map<String, dynamic>;
      final cur = j['current'];
      current = cur == null
          ? null
          : AvatarSpec.fromJson(cur as Map<String, dynamic>);
      history.clear();
      for (final e in (j['history'] as List? ?? const [])) {
        history.add(AvatarEntry.fromJson(e as Map<String, dynamic>));
      }
      feedback.clear();
      for (final f in (j['feedback'] as List? ?? const [])) {
        feedback.add(AvatarFeedback.fromJson(f as Map<String, dynamic>));
      }
      // 一致性兜底：current 与历史最新条解耦时以 current 为准，不强修历史。
    } catch (_) {}
  }

  Future<void> save() async {
    if (_file == null) return;
    try {
      await _file!.parent.create(recursive: true);
      await _file!.writeAsString(jsonEncode(toJson()));
    } catch (_) {}
  }

  Map<String, dynamic> toJson() => {
        if (current != null) 'current': current!.toJson(),
        'history': [for (final e in history) e.toJson()],
        if (feedback.isNotEmpty)
          'feedback': [for (final f in feedback) f.toJson()],
      };

  /// 提交一次显化结果。仅当「身份或场景真的变了」才推进并落盘，返回是否变化。
  /// 相同则不重复写历史（防无谓刷新/未来重复花钱出图）。
  Future<bool> commit(AvatarSpec spec) async {
    if (current != null && spec.scene.sameAs(current!.scene)) {
      // 场景没变：若身份也相同则是重复显化，直接忽略。
      if (spec.being.sameAs(current!.being)) return false;
    }
    history.insert(
      0,
      AvatarEntry(ts: DateTime.now().millisecondsSinceEpoch, spec: spec),
    );
    current = spec;
    await save();
    return true;
  }

  /// 重置身份：清空当前 spec（保留历史作旧史），下次显化重新定身份。
  void resetIdentity() {
    current = null;
  }

  /// 把生图字节存成 {imageDir}/{ts}.png，返回绝对路径；失败返回 null。
  Future<String?> saveImage(List<int> bytes) async {
    if (_imageDir == null) return null;
    try {
      await _imageDir!.create(recursive: true);
      final f =
          File('${_imageDir!.path}/${DateTime.now().millisecondsSinceEpoch}.png');
      await f.writeAsBytes(bytes);
      return f.path;
    } catch (_) {
      return null;
    }
  }

  static const int maxFeedback = 20;

  /// 记一条纠偏反馈（最新在前，超过上限裁掉最旧）。
  void addFeedback(String text) {
    final t = text.trim();
    if (t.isEmpty) return;
    feedback.insert(0, AvatarFeedback(ts: DateTime.now().millisecondsSinceEpoch, text: t));
    if (feedback.length > maxFeedback) {
      feedback.removeRange(maxFeedback, feedback.length);
    }
  }

  void removeFeedbackAt(int i) {
    if (i >= 0 && i < feedback.length) feedback.removeAt(i);
  }
}
