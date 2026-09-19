import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xinjing/avatar.dart';
import 'package:xinjing/avatar_samples.dart';
import 'package:xinjing/avatar_store.dart';

/// 基于 sampleSpecs[0]（白狐）造一个 scene 不同的 spec，用于验证「只 scene 变化」。
AvatarSpec _withScene(String setting) {
  final f = sampleSpecs[0];
  return AvatarSpec(
    being: f.being,
    scene: AvatarScene(
      setting: setting,
      season: '深冬',
      weather: '晴',
      moodPalette: '月白',
      props: const ['一只旧钢笔'],
      pose: '趴在窗台看日出',
    ),
    stateNote: '场景变化了',
  );
}

void main() {
  test('parse：容忍模型输出带前后缀文本', () {
    final raw =
        '好的，这是形象：\n${jsonEncode(sampleSpecs[0].toJson())}\n以上就是我设计的镜灵';
    final s = AvatarSpec.parse(raw);
    expect(s, isNotNull);
    expect(s!.being.species, '白狐');
  });

  test('parse：非 JSON 返回 null，不抛异常', () {
    expect(AvatarSpec.parse('抱歉，我无法完成这个请求。'), isNull);
  });

  test('fromJson：清洗列表、钳制超长字段', () {
    final long = '长' * 300;
    final s = AvatarSpec.fromJson({
      'being': {
        'species': '白狐',
        'essence': ['夜行', ' 夜行 ', '', '独立', '内敛', '创作', '专注'],
        'baseCoat': ['雪白'],
        'reason': long,
      },
      'scene': {'setting': '', 'pose': ''},
      'stateNote': long,
    });
    // 去空 + 去重不做、但空串滤掉，且单条上限/条数上限生效
    expect(s.being.essence, ['夜行', '夜行', '独立', '内敛', '创作']);
    expect(s.being.reason.length, kMaxReason);
    expect(s.stateNote.length, kMaxNote);
    expect(s.scene.isValid, isFalse);
  });

  test('isValid：species / setting / pose 任一缺失即非法', () {
    expect(sampleSpecs[0].isValid, isTrue);
    final noScene = AvatarSpec(
      being: sampleSpecs[0].being,
      scene: AvatarScene(setting: '', pose: ''),
    );
    expect(noScene.isValid, isFalse);
    final noBeing = AvatarSpec(
      being: AvatarBeing(species: ''),
      scene: sampleSpecs[0].scene,
    );
    expect(noBeing.isValid, isFalse);
  });

  test('scene.sameAs：逐字段比较，含道具顺序', () {
    final a = AvatarScene(setting: '书房', props: const ['纸', '笔'], pose: '趴着');
    final b = AvatarScene(setting: '书房', props: const ['纸', '笔'], pose: '趴着');
    final c = AvatarScene(setting: '书房', props: const ['笔', '纸'], pose: '趴着');
    expect(a.sameAs(b), isTrue);
    expect(a.sameAs(c), isFalse);
  });

  test('buildImagePrompt：只含具象画面，不含 reason / stateNote（隐私红线）', () {
    final s = sampleSpecs[0];
    final p = buildImagePrompt(s);
    expect(p, contains('白狐'));
    expect(p, contains(s.scene.setting));
    // reason 与 stateNote 是给用户看的解释，可能夹带具体事件，绝不进图 prompt
    expect(p, isNot(contains(s.being.reason.substring(0, 8))));
    expect(p, isNot(contains(s.stateNote.substring(0, 8))));
  });

  test('store：commit 去重；scene 变化才新增历史；可持久化往返', () async {
    final dir = await Directory.systemTemp.createTemp('avatar_test');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/avatar.json');

    final store = AvatarStore()..attach(file);
    final first = sampleSpecs[0];

    expect(await store.commit(first), isTrue); // 首次：变化
    expect(store.hasIdentity, isTrue);
    expect(store.history.length, 1);

    expect(await store.commit(first), isFalse); // 完全相同：不重复写
    expect(store.history.length, 1);

    final changed = _withScene('晨雾海边的灯塔');
    expect(await store.commit(changed), isTrue); // scene 变化：新增
    expect(store.history.length, 2);
    expect(store.history.first.spec.scene.setting, '晨雾海边的灯塔');

    // 重新 load：current 与历史都还在
    final store2 = AvatarStore()..attach(file);
    await store2.load();
    expect(store2.current!.scene.setting, '晨雾海边的灯塔');
    expect(store2.history.length, 2);

    // reset 身份：current 清空但历史保留
    store2.resetIdentity();
    await store2.save();
    final store3 = AvatarStore()..attach(file);
    await store3.load();
    expect(store3.current, isNull);
    expect(store3.history.length, 2);
  });

  test('store：文件损坏时静默兜底为空', () async {
    final dir = await Directory.systemTemp.createTemp('avatar_test');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/avatar.json')..writeAsStringSync('{{{bad json');
    final store = AvatarStore()..attach(file);
    await store.load();
    expect(store.current, isNull);
    expect(store.history, isEmpty);
  });

  test('store：反馈增删 / 上限 / 持久化往返', () async {
    final dir = await Directory.systemTemp.createTemp('avatar_test');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/avatar.json');

    final store = AvatarStore()..attach(file);
    store.addFeedback('别这么阴郁');
    store.addFeedback('我更喜欢豹一点');
    expect(store.feedback.first.text, '我更喜欢豹一点'); // 最新在前
    store.removeFeedbackAt(1);
    expect(store.feedback.length, 1);
    await store.save();

    // 超上限裁掉最旧
    for (var i = 0; i < 25; i++) {
      store.addFeedback('反馈$i');
    }
    expect(store.feedback.length, AvatarStore.maxFeedback);

    // 往返一致
    final store2 = AvatarStore()..attach(file);
    await store2.load();
    expect(store2.feedback.length, 1);
    expect(store2.feedback.first.text, '我更喜欢豹一点');
  });
}
