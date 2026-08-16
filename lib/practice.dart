import 'dart:convert';
import 'dart:io';

class PracticeGoal {
  final String text;
  bool done;
  PracticeGoal(this.text, {this.done = false});

  Map<String, dynamic> toJson() => {'text': text, 'done': done};

  factory PracticeGoal.fromJson(Map<String, dynamic> j) =>
      PracticeGoal(j['text'] as String? ?? '', done: j['done'] as bool? ?? false);
}

/// 修行闭环数据：目标列表 + 每日功课打卡。
/// 持久化到 practice.json。
class PracticeData {
  final List<PracticeGoal> goals = [];
  final Map<String, bool> checkins = {}; // date(YYYY-MM-DD) -> done
  File? _file;

  PracticeData(); // 显式默认构造（类里定义了工厂构造后需要）

  void attach(File file) => _file = file;

  Map<String, dynamic> toJson() => {
        'goals': [for (final g in goals) g.toJson()],
        'checkins': checkins,
      };

  factory PracticeData.fromJson(Map<String, dynamic> j) {
    final p = PracticeData();
    for (final e in (j['goals'] as List? ?? const [])) {
      p.goals.add(PracticeGoal.fromJson(e as Map<String, dynamic>));
    }
    (j['checkins'] as Map? ?? const {}).forEach((k, v) {
      p.checkins[k as String] = v as bool;
    });
    return p;
  }

  static String today() {
    final d = DateTime.now();
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  bool get hasTodayCheckin => checkins.containsKey(today());
  bool get todayDone => checkins[today()] ?? false;

  Future<void> load() async {
    if (_file == null || !await _file!.exists()) return;
    try {
      final j = jsonDecode(await _file!.readAsString()) as Map<String, dynamic>;
      final p = PracticeData.fromJson(j);
      goals
        ..clear()
        ..addAll(p.goals);
      checkins
        ..clear()
        ..addAll(p.checkins);
    } catch (_) {}
  }

  Future<void> save() async {
    if (_file == null) return;
    try {
      await _file!.parent.create(recursive: true);
      await _file!.writeAsString(jsonEncode(toJson()));
    } catch (_) {}
  }
}
