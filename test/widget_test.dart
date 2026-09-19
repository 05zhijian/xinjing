import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xinjing/main.dart';

void main() {
  testWidgets('Demo renders chat page', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const AiDiaryApp());
    await tester.pump();
    expect(find.textContaining('AI 陪伴'), findsWidgets);
  });

  testWidgets('右上角 ⚙️ 打开 AI 设置（服务商 + Key 一处配置）',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const AiDiaryApp());
    await tester.pump();

    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('AI 设置'), findsOneWidget);
    expect(find.textContaining('服务商'), findsWidgets);
  });
}
