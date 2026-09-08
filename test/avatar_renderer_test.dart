import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_diary_demo/ai_service.dart';
import 'package:ai_diary_demo/avatar.dart';
import 'package:ai_diary_demo/avatar_samples.dart';
import 'package:ai_diary_demo/avatar_renderer.dart';
import 'package:ai_diary_demo/avatar_store.dart';
import 'package:ai_diary_demo/image_service.dart';
import 'package:ai_diary_demo/layered_memory.dart';
import 'package:ai_diary_demo/memory.dart';
import 'package:ai_diary_demo/profile.dart';

/// 不发网络的假 AI：罐头回复 + 记录每次调用消息。
class _FakeAvatarAi extends AiService {
  String reply = '';
  final List<List<Map<String, String>>> calls = [];
  @override
  bool get hasKey => true;

  @override
  Future<String> complete(List<Map<String, String>> messages) async {
    calls.add(messages);
    return reply;
  }
}

/// 空记忆的三层（语义/情景都空）。
LayeredMemory _emptyMemory() =>
    LayeredMemory(episodic: VectorMemory(), semantic: UserProfile());

/// 带一点积累的三层：画像里有一条目标 + 情景层有一条日记。
Future<LayeredMemory> _seededMemory() async {
  final semantic = UserProfile()
    ..merge(UserProfile.fromJson({
      'goals': ['减肥'],
      'values': [],
      'facts': [],
    }));
  final m = LayeredMemory(episodic: VectorMemory(), semantic: semantic);
  await m.remember('今天开始早睡', type: 'diary');
  return m;
}

String _replyOf(AvatarSpec spec) => '好的，为你显化：\n${jsonEncode(spec.toJson())}';

/// 假生图：可配置是否就绪 / 是否返回字节。
class _FakeImg implements ImageGen {
  final bool _ready;
  final List<int>? _bytes;
  _FakeImg({bool ready = true, List<int>? bytes})
      : _ready = ready,
        _bytes = bytes;
  @override
  bool get ready => _ready;
  @override
  Future<Uint8List?> generate(String prompt) async =>
      _bytes == null ? null : Uint8List.fromList(_bytes);
}

void main() {
  test('render：无记忆且无身份 → needData，不打搅 AI', () async {
    final ai = _FakeAvatarAi();
    final svc = AvatarService(
        ai: ai, memory: _emptyMemory(), store: AvatarStore());
    final r = await svc.render();
    expect(r.outcome, AvatarOutcome.needData);
    expect(ai.calls, isEmpty);
  });

  test('render：首次生成 → 锁定身份 + 把画像与近期记忆喂给模型', () async {
    final ai = _FakeAvatarAi();
    ai.reply = _replyOf(sampleSpecs[0]); // 白狐
    final store = AvatarStore();
    final svc = AvatarService(
        ai: ai, memory: await _seededMemory(), store: store);

    final r = await svc.render();
    expect(r.outcome, AvatarOutcome.updated);
    expect(r.spec!.being.species, '白狐');
    expect(store.hasIdentity, isTrue);
    expect(store.current!.being.species, '白狐');
    expect(store.history.length, 1);

    final messages = ai.calls.last;
    final system = messages.firstWhere((m) => m['role'] == 'system')['content']!;
    final user = messages.firstWhere((m) => m['role'] == 'user')['content']!;
    expect(system, contains('候选池')); // 物种约束在场
    expect(user, contains('减肥')); // 画像被传入
    expect(user, contains('早睡')); // 近期日记被传入
  });

  test('render：相同结果重复显化 → unchanged，不新增历史', () async {
    final ai = _FakeAvatarAi();
    final store = AvatarStore();
    final svc = AvatarService(
        ai: ai, memory: await _seededMemory(), store: store);

    ai.reply = _replyOf(sampleSpecs[0]);
    expect((await svc.render()).outcome, AvatarOutcome.updated);
    expect(store.history.length, 1);

    expect((await svc.render()).outcome, AvatarOutcome.unchanged);
    expect(store.history.length, 1);
  });

  test('render：身份锁定——模型想换物种也以既有身份为准，场景照常演化', () async {
    final ai = _FakeAvatarAi();
    final store = AvatarStore();
    final svc = AvatarService(
        ai: ai, memory: await _seededMemory(), store: store);

    // 第一次：白狐
    ai.reply = _replyOf(sampleSpecs[0]);
    expect((await svc.render()).outcome, AvatarOutcome.updated);
    expect(store.current!.being.species, '白狐');

    // 第二次：模型想改口成猎豹 + 换了场景
    final attempt = AvatarSpec(
      being: AvatarBeing(
          species: '猎豹',
          essence: const ['勇猛'],
          baseCoat: const ['金色'],
          reason: '（模型错误改口）'),
      scene: AvatarScene(
        setting: '清晨的海边灯塔',
        season: '夏',
        weather: '日出',
        moodPalette: '橘粉',
        props: const ['一本翻开的书'],
        pose: '站在塔顶看海',
      ),
      stateNote: '想去海边散心',
    );
    ai.reply = _replyOf(attempt);
    expect((await svc.render()).outcome, AvatarOutcome.updated);

    // 身份仍是白狐（锁定），场景用了新内容
    expect(store.current!.being.species, '白狐');
    expect(store.current!.scene.setting, '清晨的海边灯塔');
    expect(store.history.length, 2);
    expect(store.history.first.spec.being.species, '白狐');
  });

  test('render：AI 返回垃圾 → 重试一次后 error，store 不变', () async {
    final ai = _FakeAvatarAi();
    ai.reply = '抱歉，我暂时无法完成。';
    final store = AvatarStore();
    final svc = AvatarService(
        ai: ai, memory: await _seededMemory(), store: store);

    final r = await svc.render();
    expect(r.outcome, AvatarOutcome.error);
    expect(r.message, isNotEmpty);
    expect(store.hasIdentity, isFalse);
    expect(ai.calls.length, 2); // 首次 + 严格指令重试
  });

  test('render：未配 Key → error，不打搅模型', () async {
    // 真 AiService（无 key，hasKey=false）
    final svc = AvatarService(
        ai: AiService(), memory: await _seededMemory(), store: AvatarStore());
    final r = await svc.render();
    expect(r.outcome, AvatarOutcome.error);
    expect(r.message, contains('Key'));
  });

  test('render：生图就绪 → PNG 落盘并挂到最新历史条目', () async {
    final dir = await Directory.systemTemp.createTemp('avatar_img');
    addTearDown(() => dir.delete(recursive: true));

    final ai = _FakeAvatarAi();
    ai.reply = _replyOf(sampleSpecs[0]);
    final store = AvatarStore()
      ..attachImageDir(Directory('${dir.path}/imgs'));
    final svc = AvatarService(
        ai: ai,
        memory: await _seededMemory(),
        store: store,
        imageGen: _FakeImg(bytes: const [1, 2, 3]));

    final r = await svc.render();
    expect(r.outcome, AvatarOutcome.updated);
    final path = store.currentImagePath;
    expect(path, isNotNull);
    expect(File(path!).existsSync(), isTrue);
    expect(store.history.first.imagePath, path);
  });

  test('render：生图失败 → 只丢图不丢 spec，镜灵照常更新', () async {
    final ai = _FakeAvatarAi();
    ai.reply = _replyOf(sampleSpecs[0]);
    final store = AvatarStore();
    final svc = AvatarService(
        ai: ai,
        memory: await _seededMemory(),
        store: store,
        imageGen: _FakeImg(bytes: null)); // 生成返回 null = 失败

    final r = await svc.render();
    expect(r.outcome, AvatarOutcome.updated);
    expect(r.spec!.being.species, '白狐'); // spec 保住
    expect(store.currentImagePath, isNull); // 只丢图
    expect(store.history.length, 1);
  });
}
