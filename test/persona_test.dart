import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xinjing/persona/companion_manual.dart';
import 'package:xinjing/persona/reply_checks.dart';

void main() {
  group('陪伴手册 · prompt 快照测试', () {
    test('关键条款必须在（改文案时别悄悄改坏）', () {
      const clauses = [
        '安全边界',
        '禁语',
        '问句最多两个',
        '命名情绪',
        '具体化 = 由你来说具体',
        '用户自贬时',
        '不使用 Markdown',
        '不出现"你应该"',
        '12356',
        '不超过 120 字',
      ];
      for (final c in clauses) {
        expect(companionSystemPrompt, contains(c), reason: '手册缺少条款：$c');
      }
    });

    test('长度在预算内（够细但不失控）', () {
      expect(companionSystemPrompt.length, greaterThan(600));
      expect(companionSystemPrompt.length, lessThan(3600));
    });

    test('App 真的在用这份手册（防止回退成硬编码的一句话）', () {
      final src = File('lib/chat_page.dart').readAsStringSync();
      expect(src, contains('companionSystemPrompt'));
    });
  });

  group('回复硬性检查（确定性，不依赖 LLM）', () {
    test('禁语命中', () {
      expect(checkReply('你应该早点睡').map((v) => v.code), contains('banned'));
      expect(checkReply('你是不是有焦虑症').map((v) => v.code), contains('banned'));
      expect(checkReply('你就是回避型人格').map((v) => v.code), contains('banned'));
    });

    test('Markdown 标记命中', () {
      expect(checkReply('**重点**：早点睡').map((v) => v.code), contains('markdown'));
      expect(checkReply('## 建议\n早点睡').map((v) => v.code), contains('markdown'));
    });

    test('问句数：两个以内通过（确认+深入），三个才违规', () {
      expect(checkReply('听起来很委屈，是吗？最扎你的是哪一下？'), isEmpty);
      expect(
        checkReply('你还好吗？要不要聊聊？现在方便吗？').map((v) => v.code),
        contains('multi_question'),
      );
    });

    test('危机情境缺少求助指引命中', () {
      expect(checkReply('我懂你。', requireSafety: true).map((v) => v.code),
          contains('no_safety'));
      expect(
        checkReply('听起来好难。请一定联系你信任的人，或拨打心理援助热线 12356。',
            requireSafety: true),
        isEmpty,
      );
    });

    test('过长命中', () {
      expect(checkReply('啊' * 250, maxChars: 200).map((v) => v.code),
          contains('too_long'));
    });

    test('复述用户自贬词 → 违规（数据驱动的 avoid_echo）', () {
      expect(
        checkReply('你是不是太敏感了？', avoidEcho: ['太敏感'])
            .map((v) => v.code),
        contains('echo_self_blame'),
      );
      // 拆开评价与事实的正例：不复述贬义词
      expect(
        checkReply('心慌手抖是真的，查不出毛病也不代表你的难受是假的。它一般什么时候来？',
            avoidEcho: ['太敏感', '矫情']),
        isEmpty,
      );
    });

    test('干净的回复通过', () {
      expect(checkReply('凌晨三点最难熬的那一下，是什么？'), isEmpty);
    });
  });
}
