import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_diary_demo/main.dart';

void main() {
  testWidgets('Demo renders chat page', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const AiDiaryApp());
    await tester.pump();
    expect(find.textContaining('AI 陪伴'), findsWidgets);
  });
}
