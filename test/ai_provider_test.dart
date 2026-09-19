import 'package:flutter_test/flutter_test.dart';
import 'package:xinjing/ai_service.dart';
import 'package:xinjing/image_service.dart';

void main() {
  test('provider：默认规则——显式 > 有智谱 key > 只有 DS key > 空环境(智谱)', () {
    // 空环境（分发的 APK）→ 智谱，开箱即完整体验
    expect(AiService.resolveProvider(), AiService.kZhipu);
    // 只有 DeepSeek key → 兼容老的一键运行
    expect(AiService.resolveProvider(hasDeepSeekKey: true),
        AiService.kDeepSeek);
    // 两个都有 → 智谱优先
    expect(
        AiService.resolveProvider(hasZhipuKey: true, hasDeepSeekKey: true),
        AiService.kZhipu);
    // 显式指定优先于一切
    expect(
        AiService.resolveProvider(
            explicit: AiService.kDeepSeek, hasZhipuKey: true),
        AiService.kDeepSeek);
    // 非法显式值被忽略，回落到 key 规则
    expect(AiService.resolveProvider(explicit: 'nope', hasZhipuKey: true),
        AiService.kZhipu);
  });

  test('provider：测试环境默认智谱（含生图）', () {
    final ai = AiService();
    expect(ai.provider, AiService.kZhipu);
    expect(ai.chatBase, contains('open.bigmodel.cn'));
    expect(ai.chatModel, 'glm-4-flash');
    expect(ai.supportsImages, isTrue);
  });

  test('provider：切到 DeepSeek → 纯文本、无生图', () {
    final ai = AiService()..setProvider(AiService.kDeepSeek);
    expect(ai.chatBase, contains('deepseek.com'));
    expect(ai.chatModel, 'deepseek-v4-flash');
    expect(ai.supportsImages, isFalse);
    expect(ai.imageBase, isNull);
  });

  test('provider：切到智谱 → GLM 文本 + CogView 生图（单 key 全通）', () {
    final ai = AiService()..setProvider(AiService.kZhipu);
    expect(ai.chatBase, contains('open.bigmodel.cn'));
    expect(ai.chatModel, 'glm-4-flash');
    expect(ai.supportsImages, isTrue);
    expect(ai.imageBase, contains('images/generations'));
    expect(ai.imageModel, 'cogview-3-flash');
  });

  test('provider：非法值被忽略、providers 枚举齐全', () {
    final ai = AiService()..setProvider(AiService.kZhipu);
    ai.setProvider('hack'); // 不生效
    expect(ai.provider, AiService.kZhipu);
    expect(AiService.providers, containsAll([AiService.kDeepSeek, AiService.kZhipu]));
  });

  test('ZhipuImageGen：未接智谱或无 key 时 ready=false，generate 空手返回（不发网络）', () async {
    // 非智谱服务商：不支持生图
    final ds = ZhipuImageGen(ai: AiService()..setProvider(AiService.kDeepSeek));
    expect(ds.ready, isFalse);
    expect(await ds.generate('随便一句'), isNull);

    // 智谱 provider 但没 key
    final noKey = ZhipuImageGen(ai: AiService()..setProvider(AiService.kZhipu));
    expect(noKey.ready, isFalse);
    expect(await noKey.generate('随便一句'), isNull);
  });
}
