import 'package:flutter_test/flutter_test.dart';
import 'package:xinjing/persona/crisis_guard.dart';

void main() {
  group('危机识别（宽进严出：宁可误报，不可漏报）', () {
    test('自伤/自杀信号命中', () {
      expect(needsCrisisGuard('最近真的撑不住了，有时候会想如果我不在了会不会更好'), isTrue);
      expect(needsCrisisGuard('我不想活了'), isTrue);
      expect(needsCrisisGuard('有时候真想一了百了，不如死掉算了'), isTrue);
    });

    test('正在遭受暴力的信号命中', () {
      expect(needsCrisisGuard('他昨天又动手了，我没跟任何人说'), isTrue);
      expect(needsCrisisGuard('他前天打我了'), isTrue);
      expect(needsCrisisGuard('我被家暴了，不敢告诉别人'), isTrue);
    });

    test('伤害他人的信号命中', () {
      expect(needsCrisisGuard('我真想杀了他'), isTrue);
    });

    test('常见表达不误报', () {
      expect(needsCrisisGuard('今天累死了，倒头就睡'), isFalse);
      expect(needsCrisisGuard('我想死磕这个项目，一定要做完'), isFalse); // 死磕
      expect(needsCrisisGuard('方案被打回了，有点沮丧'), isFalse); // 被打回
      expect(needsCrisisGuard('今天跟朋友打了会儿球'), isFalse);
    });
  });

  group('确定性安全兜底', () {
    test('漏了求助指引 → 补上资源', () {
      final guarded = ensureSafetyGuidance('听起来很难，你愿意说说吗？', required: true);
      expect(guarded, contains('12356'));
      expect(guarded, contains('110'));
      expect(guarded, contains('你愿意说说吗')); // 保留模型那句关怀
    });

    test('「有条件地提一句」不算够 → 仍要补上无条件版本', () {
      const conditional = '如果你方便，可以考虑拨打心理援助热线 12356。';
      expect(hasSufficientSafetyGuidance(conditional), isFalse);
      final guarded = ensureSafetyGuidance(conditional, required: true);
      expect(guarded, contains('请一定'));
      expect(guarded.length, greaterThan(conditional.length));
    });

    test('缺「明确」措辞也不算够（可以联系 ≠ 请一定联系）', () {
      expect(hasSufficientSafetyGuidance('你可以联系信任的人，或拨打 12356。'), isFalse);
    });

    test('已经够（有资源 + 明确 + 无条件）→ 原样返回，不重复堆叠', () {
      const good = '我会陪着你。请一定联系你信任的人，也请一定拨打心理援助热线 12356。';
      expect(hasSufficientSafetyGuidance(good), isTrue);
      expect(ensureSafetyGuidance(good, required: true), good);
    });

    test('非危机情境 → 完全不动', () {
      const normal = '听起来很委屈，最扎你的是哪一下？';
      expect(ensureSafetyGuidance(normal, required: false), normal);
    });

    test('模型完全失败（空回复）→ 直接给兜底文案', () {
      expect(ensureSafetyGuidance('', required: true), crisisSafetyReply);
    });
  });
}
