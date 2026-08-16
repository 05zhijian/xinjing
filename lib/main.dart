import 'package:flutter/material.dart';
import 'chat_page.dart';

void main() => runApp(const AiDiaryApp());

class AiDiaryApp extends StatelessWidget {
  const AiDiaryApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '显化的我 Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF5C8A6E),
        scaffoldBackgroundColor: const Color(0xFFFAF9F4),
      ),
      home: const ChatPage(),
    );
  }
}
