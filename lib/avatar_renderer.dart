import 'dart:convert';

import 'avatar.dart';
import 'avatar_samples.dart';
import 'avatar_store.dart';
import 'ai_service.dart';
import 'image_service.dart';
import 'layered_memory.dart';

/// 一次显化的结果类型。
enum AvatarOutcome { updated, unchanged, needData, error }

/// 显化结果：outcome + 面向用户的消息 + 成功后最新 spec。
class AvatarResult {
  final AvatarOutcome outcome;
  final String message;
  final AvatarSpec? spec;
  AvatarResult._(this.outcome, this.message, this.spec);

  factory AvatarResult.updated(AvatarSpec spec) =>
      AvatarResult._(AvatarOutcome.updated, '', spec);
  factory AvatarResult.unchanged() =>
      AvatarResult._(AvatarOutcome.unchanged, '镜灵最近没有新的变化，还是原来的样子。', null);
  factory AvatarResult.needData() => AvatarResult._(
      AvatarOutcome.needData, '镜灵还没有素材。先多聊几天、留几篇日记，再来显化你的样子。', null);
  factory AvatarResult.error(String message) =>
      AvatarResult._(AvatarOutcome.error, message, null);
}

/// 镜灵的映射层编排：把「画像 + 近期记忆」交给 LLM 换回 AvatarSpec。
///
/// 关键规则（DevDoc §5.3）：
/// - 身份 Being 一旦生成即锁定——再次显化时即使 LLM 改口，也以 store 里既有身份为准；
/// - 场景 Scene 每次可取最新，但只有真的变了才 commit（防重复落盘/未来重复花钱出图）；
/// - 给 LLM 的输入只含画像与记忆的提炼文本，输出只落一个 AvatarSpec（隐私红线在出图层）。
class AvatarService {
  final AiService ai;
  final LayeredMemory memory;
  final AvatarStore store;
  final ImageGen? imageGen; // M2 起接真实生图；无则纯占位画布

  AvatarService({
    required this.ai,
    required this.memory,
    required this.store,
    this.imageGen,
  });

  bool get hasKey => ai.hasKey;
  bool get hasIdentity => store.hasIdentity;
  bool get hasMemory =>
      !memory.semantic.isEmpty || memory.episodic.hasItems;
  AvatarSpec? get current => store.current;
  List<AvatarEntry> get history => store.history;
  List<AvatarFeedback> get feedback => store.feedback;

  /// 最新一版的真实出图路径（无则 null，UI 用占位画布）。
  String? get currentImagePath => store.currentImagePath;

  /// 记一条「人话纠偏」，下次显化/重置定身份时喂给映射层。
  Future<void> addFeedback(String text) async {
    store.addFeedback(text);
    await store.save();
  }

  Future<void> removeFeedback(int index) async {
    store.removeFeedbackAt(index);
    await store.save();
  }

  List<AvatarSpec> get samples => sampleSpecs;
  AvatarSpec sampleAt(int i) => sampleSpecs[i % sampleSpecs.length];

  /// 手动重置身份：清空当前 spec（历史保留），下次显化重新定身份。
  Future<void> resetIdentity() async {
    store.resetIdentity();
    await store.save();
  }

  /// 触发一次显化。无素材返回 needData；AI 不可用/返回不可解析返回 error。
  Future<AvatarResult> render() async {
    if (!hasKey) {
      return AvatarResult.error('未配置 AI Key：请先在「我的」页顶部的 AI Key 卡片设置。');
    }
    if (!hasMemory && !hasIdentity) return AvatarResult.needData();

    final existing = store.current?.being;
    final isFirst = existing == null;

    var msgs = _buildMessages(existing);
    var spec = AvatarSpec.parse(await ai.complete(msgs));
    if (spec == null || (isFirst ? !spec.isValid : !spec.scene.isValid)) {
      // 解析失败或字段缺失 → 追加严格指令重试一次（对齐 profile.extractFromConversation）。
      msgs = [
        ...msgs,
        {'role': 'user', 'content': '直接输出 JSON 对象本身，不要任何解释、代码块或多余文字。'},
      ];
      spec = AvatarSpec.parse(await ai.complete(msgs));
    }
    if (spec == null) {
      return AvatarResult.error('镜灵生成失败：AI 返回内容无法解析，可稍后重试。');
    }
    if (isFirst) {
      if (!spec.isValid) {
        return AvatarResult.error('镜灵生成失败：缺少身份或场景描述，可稍后重试。');
      }
    } else if (!spec.scene.isValid) {
      return AvatarResult.error('镜灵生成失败：缺少场景描述，可稍后重试。');
    }

    final finalSpec = AvatarSpec(
      being: existing ?? spec.being, // 身份锁定：有则用既有的，不随本次漂移
      scene: spec.scene,
      stateNote: spec.stateNote,
    );
    final changed = await store.commit(finalSpec);
    if (changed) await _materializeImage(finalSpec);
    return changed ? AvatarResult.updated(finalSpec) : AvatarResult.unchanged();
  }

  /// 出图并落盘。失败只丢图、不丢 spec——渲染结果不因生图失败而回滚。
  Future<void> _materializeImage(AvatarSpec spec) async {
    final gen = imageGen;
    if (gen == null || !gen.ready) return;
    try {
      final bytes = await gen.generate(buildImagePrompt(spec));
      if (bytes == null) return;
      final path = await store.saveImage(bytes);
      if (path != null) {
        if (store.history.isNotEmpty) store.history.first.imagePath = path;
        await store.save();
      }
    } catch (_) {}
  }

  /// 组装给映射层 LLM 的 messages（system=规则+物种池，user=已有身份+画像+近期记忆）。
  List<Map<String, String>> _buildMessages(AvatarBeing? existing) {
    final user = StringBuffer();
    if (existing != null) {
      user.writeln('【已有身份】——species/essence/baseCoat/reason 必须逐字保留，只更新 scene 与 stateNote：');
      user.writeln(jsonEncode(existing.toJson()));
    } else {
      user.writeln('【身份】首次生成。请从候选物种池中为 TA 选定一个物种，并给出像样的理由。');
    }

    final profile = memory.semantic.buildSystemContext();
    user.writeln();
    user.writeln(profile.isEmpty ? '【关于用户】暂无积累。' : profile);

    final recents = memory.episodic.items
        .where((it) => it.type == 'diary' || it.type == 'insight')
        .toList()
      ..sort((a, b) => b.time.compareTo(a.time));
    final recentLines =
        recents.take(5).map((it) => '· ${it.text}').join('\n');
    user.writeln();
    user.writeln('【近期记忆】');
    user.writeln(recentLines.isEmpty ? '（暂无）' : recentLines);

    // 人话纠偏：用户对镜灵形象表达过的不满意/偏好，优先参考。
    final feedbackLines =
        store.feedback.take(5).map((f) => '· ${f.text}').join('\n');
    if (feedbackLines.isNotEmpty) {
      user.writeln();
      user.writeln('【你对镜灵形象的反馈】（优先参考；若与锁定身份矛盾，只按它调整 scene，别改 species）');
      user.writeln(feedbackLines);
    }

    return [
      {
        'role': 'system',
        'content': '你是「心镜」的形象设计师。用户的内在自我会投影为一只具象的「镜灵」（多为动物，'
            '也可含少量精灵/器物）。根据【关于用户】与【近期记忆】设计 TA 此刻应有的样子，'
            '只输出一个 JSON 对象，不要任何解释或代码块，结构如下：\n'
            '{"being":{"species":"","essence":["3-5个标签"],"baseCoat":["毛色/底色"],'
            '"reason":"一句为什么是它，60字内"},"scene":{"setting":"场景",'
            '"season":"季节","weather":"天气","moodPalette":"主色调",'
            '"props":["最多3个相关道具"],"pose":"姿态，具体、有画面"},"stateNote":"这一版比上一版变了什么，40字内，给用户看"}\n'
            '要求：species 只能从候选池里选：${speciesPool.join('、')}；'
            'scene 必须贴近期记忆里的具体事件或情绪，禁止空泛的"安静""开心"；'
            'reason 真诚不浮夸；若给了【已有身份】，being 必须逐字照抄。',
      },
      {'role': 'user', 'content': user.toString().trim()},
    ];
  }
}
