import 'dart:convert';

import 'package:flutter/foundation.dart';

// 镜灵数据模型：AvatarSpec = 身份(Being，锁定) + 状态(Scene，演化) + 一句变化说明。
// 与本项目其他 JSON 持久化的风格一致（profile.dart）：fromJson 容忍脏值、
// 长度钳制，全部本地纯数据，不依赖网络。

/// 字段长度上限（钳制模型自由发挥，避免文案/ prompt 失控）。
const int kMaxSpecies = 12;
const int kMaxTag = 12;
const int kMaxPalette = 30;
const int kMaxSetting = 40;
const int kMaxSeason = 12;
const int kMaxWeather = 16;
const int kMaxPose = 60;
const int kMaxReason = 120;
const int kMaxNote = 60;

/// 截断到 [max] 个字符（中文按字符计）。
String _clamp(String? s, int max) {
  final t = (s ?? '').trim();
  return t.length <= max ? t : t.substring(0, max);
}

/// 清洗字符串列表：trim、去空、限条数、限单条长度。
List<String> _cleanList(List<dynamic>? raw, {int maxItems = 5, int maxLen = 24}) {
  final out = <String>[];
  for (final e in raw ?? const []) {
    if (out.length >= maxItems) break;
    final s = (e is String ? e : e?.toString() ?? '').trim();
    if (s.isEmpty) continue;
    out.add(s.length <= maxLen ? s : s.substring(0, maxLen));
  }
  return out;
}

/// 镜灵「身份」：物种 + 性格标签 + 底色 + 一句为什么。生成一次即锁定。
class AvatarBeing {
  String species;
  List<String> essence;
  List<String> baseCoat;
  String reason;

  AvatarBeing({
    required this.species,
    List<String>? essence,
    List<String>? baseCoat,
    this.reason = '',
  })  : essence = essence ?? [],
        baseCoat = baseCoat ?? [];

  bool get isValid => species.isNotEmpty;

  bool sameAs(AvatarBeing o) =>
      species == o.species &&
      listEquals(essence, o.essence) &&
      listEquals(baseCoat, o.baseCoat) &&
      reason == o.reason;

  Map<String, dynamic> toJson() => {
        'species': species,
        'essence': essence,
        'baseCoat': baseCoat,
        'reason': reason,
      };

  factory AvatarBeing.fromJson(Map<String, dynamic> j) => AvatarBeing(
        species: _clamp(j['species'], kMaxSpecies),
        essence: _cleanList(j['essence'], maxItems: 5, maxLen: kMaxTag),
        baseCoat: _cleanList(j['baseCoat'], maxItems: 4, maxLen: kMaxTag),
        reason: _clamp(j['reason'], kMaxReason),
      );
}

/// 镜灵「状态」：此刻的环境、光线、心情、发生的事。每次显化可漂移。
class AvatarScene {
  String setting;
  String season;
  String weather;
  String moodPalette;
  List<String> props;
  String pose;

  AvatarScene({
    this.setting = '',
    this.season = '',
    this.weather = '',
    this.moodPalette = '',
    List<String>? props,
    this.pose = '',
  }) : props = props ?? [];

  bool get isValid => setting.isNotEmpty && pose.isNotEmpty;

  bool sameAs(AvatarScene o) =>
      setting == o.setting &&
      season == o.season &&
      weather == o.weather &&
      moodPalette == o.moodPalette &&
      listEquals(props, o.props) &&
      pose == o.pose;

  Map<String, dynamic> toJson() => {
        'setting': setting,
        'season': season,
        'weather': weather,
        'moodPalette': moodPalette,
        'props': props,
        'pose': pose,
      };

  factory AvatarScene.fromJson(Map<String, dynamic> j) => AvatarScene(
        setting: _clamp(j['setting'], kMaxSetting),
        season: _clamp(j['season'], kMaxSeason),
        weather: _clamp(j['weather'], kMaxWeather),
        moodPalette: _clamp(j['moodPalette'], kMaxPalette),
        props: _cleanList(j['props'], maxItems: 6, maxLen: 24),
        pose: _clamp(j['pose'], kMaxPose),
      );
}

/// 一次完整的镜灵描述：身份固定、状态演化、一句给用户看的变化说明。
class AvatarSpec {
  final AvatarBeing being;
  final AvatarScene scene;
  final String stateNote;

  AvatarSpec({
    required this.being,
    required this.scene,
    this.stateNote = '',
  });

  bool get isValid => being.isValid && scene.isValid;

  bool sameAs(AvatarSpec o) =>
      being.sameAs(o.being) && scene.sameAs(o.scene) && stateNote == o.stateNote;

  Map<String, dynamic> toJson() => {
        'being': being.toJson(),
        'scene': scene.toJson(),
        'stateNote': stateNote,
      };

  factory AvatarSpec.fromJson(Map<String, dynamic> j) => AvatarSpec(
        being: AvatarBeing.fromJson(
            (j['being'] as Map<String, dynamic>?) ?? const {}),
        scene: AvatarScene.fromJson(
            (j['scene'] as Map<String, dynamic>?) ?? const {}),
        stateNote: _clamp(j['stateNote'], kMaxNote),
      );

  /// 从模型回复里取出第一个 JSON 对象（容忍带前后缀文本），失败返回 null。
  /// 镜像 profile.dart 的 parseJson 思路。
  static AvatarSpec? parse(String raw) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    try {
      return AvatarSpec.fromJson(
          jsonDecode(raw.substring(start, end + 1)) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}

/// 组装发给生图模型的画面描述。
/// 只取「具象描述」本身——绝不带原始记忆；also 排除 reason / stateNote，
/// 因为它们最容易夹带具体的个人事件，画面也不需要它们。
String buildImagePrompt(AvatarSpec spec, {String style = '细腻的插画风格'}) {
  final b = spec.being;
  final s = spec.scene;
  final coat = b.baseCoat.isEmpty ? '' : '，毛色 ${b.baseCoat.join('、')}';
  final where = <String>[s.season, s.weather].where((e) => e.isNotEmpty).join('，');
  final climate = where.isEmpty ? '' : '，时值$where';
  final palette = s.moodPalette.isEmpty ? '' : '，主色调 ${s.moodPalette}';
  final props =
      s.props.isEmpty ? '' : '，身边有 ${s.props.take(3).join('、')}';
  return '$style中的${b.species}$coat：${s.pose}；身处${s.setting}$climate$palette$props。'
      '画面安静、有故事感，不出现任何文字。';
}
