import 'package:flutter_test/flutter_test.dart';
import 'package:ai_diary_demo/ai_service.dart';
import 'package:ai_diary_demo/image_service.dart';

void main() {
  test('provider：默认 DeepSeek（纯文本）', () {
    final ai = AiService();
    expect(ai.provider, AiService.kDeepSeek);
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
    // DeepSeek provider
    final ds = ZhipuImageGen(ai: AiService());
    expect(ds.ready, isFalse);
    expect(await ds.generate('随便一句'), isNull);

    // 智谱 provider 但没 key
    final noKey = ZhipuImageGen(ai: AiService()..setProvider(AiService.kZhipu));
    expect(noKey.ready, isFalse);
    expect(await noKey.generate('随便一句'), isNull);
  });
}
