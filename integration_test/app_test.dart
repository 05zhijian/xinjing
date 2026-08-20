import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ai_diary_demo/main.dart' as app;

/// 轮询等待某个控件出现（真实网络/AI 流式场景，pumpAndSettle 等不到）。
/// 超时时把当前屏幕全部文本打进失败信息，便于诊断。
Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 90),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) return;
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  fail('等待超时，未找到: $finder\n当前屏幕: ${screenTexts(tester)}');
}

/// 当前屏幕所有非空文本。
String screenTexts(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .where((s) => s.isNotEmpty)
    .join(' | ');

/// 直接设置聊天输入框文本。
/// 不用 enterText：Android 集成测试里第二次 enterText 可能因输入通道未重连而静默失败。
Future<void> typeChat(WidgetTester tester, String text) async {
  final tf = tester.widget<TextField>(find.byType(TextField));
  tf.controller?.text = text;
  await tester.pump();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('App 启动：标题、问候与 4 个 Tab', (tester) async {
    app.main();
    await tester.pumpAndSettle();

    expect(find.text('心镜 · AI 陪伴'), findsOneWidget);
    expect(find.textContaining('你好，我是你的 AI 陪伴师'), findsOneWidget);
    expect(find.text('聊天'), findsOneWidget);
    expect(find.text('功课'), findsOneWidget);
    expect(find.text('日记'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
  });

  testWidgets('对话→记忆入库→日记→整合：三层记忆全流程', (tester) async {
    app.main();
    await tester.pumpAndSettle();

    // 1. 第一条消息 → AI 回复完成 → 情景层写入（用户 + 助手 = 2 条）
    await typeChat(tester, '我想减肥');
    await tester.tap(find.byIcon(Icons.send));
    await pumpUntil(tester, find.textContaining('情景 2 条'));

    // 2. 第二条相关消息 → recall 检索 → 情景层累积到 4 条
    await typeChat(tester, '最近体重又涨了');
    await tester.tap(find.byIcon(Icons.send));
    await pumpUntil(tester, find.textContaining('情景 4 条'));

    // 3. 生成日记 → consolidate → 情景 +2（日记 + 洞察）、语义画像被抽取
    await tester.tap(find.byIcon(Icons.auto_awesome));
    await pumpUntil(tester, find.textContaining('✓ 日记已保存'));
    await pumpUntil(tester, find.textContaining('情景 6 条'));

    final counter =
        tester.widget<Text>(find.textContaining('画像')).data ?? '';
    expect(RegExp(r'画像 [1-9]').hasMatch(counter), isTrue,
        reason: 'consolidate 应把对话抽取为画像，实际: $counter');
    // 默认 testWidgets 超时只有 30s，不够真实 AI 流式回复 + consolidate 两次
    // 非流式调用；放宽到 5 分钟，避免慢网速/慢推理时被默认超时误杀。
  }, timeout: const Timeout(Duration(minutes: 5)));
}
