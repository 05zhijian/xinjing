import 'dart:convert';
import 'dart:io';

/// 画像审查阈值：每新增 [kProfileDiaryReviewEvery] 篇日记触发一次 review。
const int kProfileDiaryReviewEvery = 7;

/// 一条画像条目：文本 + 维度 + 元数据。
/// 「懂你」的成长 = 每被对话/日记反复印证就刷新 strength/lastSeen；
/// review 把过时的降级（active=false，保留历史）——只降级，不真删。
class ProfileItem {
  final String dim; // 'goals' | 'values' | 'facts'
  String text;
  int strength; // 被支持的次数
  int lastSeen; // epoch ms，最近一次被对话印证
  bool active;

  ProfileItem({
    required this.dim,
    required this.text,
    this.strength = 1,
    int? lastSeen,
    this.active = true,
  }) : lastSeen = lastSeen ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toJson() => {
        'dim': dim,
        'text': text,
        'strength': strength,
        'lastSeen': lastSeen,
        'active': active,
      };

  factory ProfileItem.fromJson(Map<String, dynamic> j) => ProfileItem(
        dim: j['dim'] as String? ?? 'goals',
        text: (j['text'] as String? ?? '').trim(),
        strength: (j['strength'] as num?)?.toInt() ?? 1,
        lastSeen: (j['lastSeen'] as num?)?.toInt(),
        active: j['active'] as bool? ?? true,
      );
}

/// 一次画像审查留下的人话记录（时间轴 =「它怎么修正自己」的证据）。
class ProfileChange {
  final int ts;
  final String note;
  const ProfileChange({required this.ts, required this.note});

  Map<String, dynamic> toJson() => {'ts': ts, 'note': note};

  factory ProfileChange.fromJson(Map<String, dynamic> j) => ProfileChange(
        ts: j['ts'] as int? ?? DateTime.now().millisecondsSinceEpoch,
        note: (j['note'] as String? ?? '').trim(),
      );
}

/// L3 语义画像（用户模型）：条目化存储，支持修订/降级/时间轴。
/// 兼容旧版 profile.json（goals/values/facts 纯数组）——读旧数据自动转条目。
class UserProfile {
  static const List<String> dims = ['goals', 'values', 'facts'];

  final List<ProfileItem> items = [];
  int diarySinceReview = 0; // 距上次 review 的新日记数
  final List<ProfileChange> changeLog = []; // 最新在前
  File? _file;

  UserProfile();

  bool get isEmpty => !items.any((e) => e.active);
  int get activeCount => items.where((e) => e.active).length;
  int get inactiveCount => items.length - activeCount;

  /// 某维度的条目（默认只看活跃）。
  List<ProfileItem> of(String dim, {bool onlyActive = true}) =>
      items.where((e) => e.dim == dim && (!onlyActive || e.active)).toList();

  /// 各维度活跃条数（UI/调试用）。
  Map<String, int> activeCounts() => {
        for (final d in dims) d: of(d).length,
      };

  void attach(File file) => _file = file;

  /// 修订型写入：同维同文（忽略大小写）命中 → 刷新并 +1；否则新开一条。
  /// 这是「每篇日记都在强化/新增、从不当耳边风」的机制。
  void upsert(String dim, String text) {
    final t = text.trim();
    if (t.isEmpty || !dims.contains(dim)) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final i = items.indexWhere(
        (e) => e.dim == dim && e.text.toLowerCase() == t.toLowerCase());
    if (i >= 0) {
      final it = items[i];
      it.text = t;
      it.active = true;
      it.strength += 1;
      it.lastSeen = now;
    } else {
      items.add(ProfileItem(dim: dim, text: t, strength: 1, lastSeen: now));
    }
  }

  /// 吸收一组抽取结果（goals/values/facts）。
  void absorb(Map<String, List<String>> groups) {
    for (final d in dims) {
      for (final t in groups[d] ?? const <String>[]) {
        upsert(d, t);
      }
    }
  }

  /// 审查/人工标错：把该原文对应的活跃条目降级（保留历史）。返回降级条数。
  int deactivate(String text) {
    final t = text.trim();
    var n = 0;
    for (final it in items) {
      if (it.active && it.text.toLowerCase() == t.toLowerCase()) {
        it.active = false;
        n++;
      }
    }
    return n;
  }

  void addDiary() => diarySinceReview++;
  void resetDiaryCount() => diarySinceReview = 0;

  void logChange(String note) {
    final t = note.trim();
    if (t.isEmpty) return;
    changeLog.insert(
        0, ProfileChange(ts: DateTime.now().millisecondsSinceEpoch, note: t));
    if (changeLog.length > 30) changeLog.removeRange(30, changeLog.length);
  }

  /// 注入 system 的画像文本：只含活跃条目，同维度内「最近印证」优先。
  String buildSystemContext() {
    final b = StringBuffer('【关于用户】');
    for (final d in dims) {
      final act = of(d)
        ..sort((a, z) {
          final bySeen = z.lastSeen.compareTo(a.lastSeen);
          return bySeen != 0 ? bySeen : z.strength.compareTo(a.strength);
        });
      if (act.isEmpty) continue;
      b.write('\n- ${_label(d)}：${act.map((e) => e.text).join('；')}');
    }
    return b.length == 6 ? '' : b.toString();
  }

  static String _label(String dim) => switch (dim) {
        'goals' => '目标',
        'values' => '在意',
        _ => '已知',
      };

  Map<String, dynamic> toJson() => {
        'items': [for (final it in items) it.toJson()],
        'diarySinceReview': diarySinceReview,
        if (changeLog.isNotEmpty)
          'changeLog': [for (final c in changeLog) c.toJson()],
      };

  factory UserProfile.fromJson(Map<String, dynamic> j) {
    final p = UserProfile();
    p.diarySinceReview = (j['diarySinceReview'] as num?)?.toInt() ?? 0;
    final rawItems = j['items'];
    if (rawItems is List && rawItems.isNotEmpty) {
      for (final e in rawItems) {
        p.items.add(ProfileItem.fromJson(e as Map<String, dynamic>));
      }
    } else {
      // 旧格式兼容：纯数组 goals/values/facts → 转条目（视为活跃、strength=1）
      for (final d in dims) {
        for (final s in (j[d] as List? ?? const [])) {
          final t = (s as String).trim();
          if (t.isNotEmpty) p.items.add(ProfileItem(dim: d, text: t));
        }
      }
    }
    for (final c in (j['changeLog'] as List? ?? const [])) {
      p.changeLog.add(ProfileChange.fromJson(c as Map<String, dynamic>));
    }
    return p;
  }

  Future<void> load() async {
    if (_file == null || !await _file!.exists()) return;
    try {
      final p = UserProfile.fromJson(
          jsonDecode(await _file!.readAsString()) as Map<String, dynamic>);
      items
        ..clear()
        ..addAll(p.items);
      diarySinceReview = p.diarySinceReview;
      changeLog
        ..clear()
        ..addAll(p.changeLog);
    } catch (_) {}
  }

  Future<void> save() async {
    if (_file == null) return;
    try {
      await _file!.parent.create(recursive: true);
      await _file!.writeAsString(jsonEncode(toJson()));
    } catch (_) {}
  }

  /// 从对话抽取目标/在意/事实并吸收进画像（修订型）。
  /// 成功返回 true。沿用旧版行为：失败用更严格的 prompt 重试一次。
  Future<bool> extractFromConversation(
    Future<String> Function(List<Map<String, String>>) complete,
    List<Map<String, String>> messages,
  ) async {
    final prompt = [
      {
        'role': 'system',
        'content': '你是用户成长陪伴师。根据对话内容抽取用户的真实情况，只输出 JSON：'
            '{"goals":[], "values":[], "facts":[]}。'
            'goals=用户想达成的目标；values=在意的价值观；facts=客观事实（职业、作息、习惯、近况）。'
            '每条不超过20字，只保留对话明确提到的，最多各3条。'
      },
      ...messages,
    ];
    var groups = parseGroups(await complete(prompt));
    if (groups == null) {
      final retry = await complete([
        ...prompt,
        {'role': 'user', 'content': '直接输出 JSON 对象本身，不要任何解释、代码块或多余文字。'},
      ]);
      groups = parseGroups(retry);
    }
    if (groups == null) return false;
    absorb(groups);
    await save();
    return true;
  }

  /// 从模型回复里取 groups（容忍前后缀）。失败返回 null。
  static Map<String, List<String>>? parseGroups(String raw) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    try {
      final j = jsonDecode(raw.substring(start, end + 1)) as Map<String, dynamic>;
      return {
        for (final d in dims)
          d: (j[d] as List? ?? const [])
              .whereType<String>()
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList(),
      };
    } catch (_) {
      return null;
    }
  }
}
