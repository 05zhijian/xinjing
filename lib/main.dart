import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'ai_service.dart';
import 'chat_page.dart';
import 'diaries_page.dart';
import 'diary_store.dart';
import 'layered_memory.dart';
import 'memory.dart';
import 'practice.dart';
import 'practice_page.dart';
import 'profile.dart';
import 'settings_page.dart';

void main() => runApp(const AiDiaryApp());

class AiDiaryApp extends StatefulWidget {
  const AiDiaryApp({super.key});

  @override
  State<AiDiaryApp> createState() => _AiDiaryAppState();
}

class _AiDiaryAppState extends State<AiDiaryApp> {
  final AiService _ai = AiService();
  late final VectorMemory _episodic = VectorMemory();
  late final UserProfile _profile = UserProfile();
  late final LayeredMemory _memory =
      LayeredMemory(episodic: _episodic, semantic: _profile);
  late final DiaryStore _diaryStore = DiaryStore();
  late final PracticeData _practice = PracticeData();
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _initStorage();
  }

  /// 数据目录：documents/xianhuadewo/（桌面与移动端通用）。
  Future<void> _initStorage() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final dataDir = Directory('${dir.path}/xianhuadewo');
      await dataDir.create(recursive: true);
      _episodic.attach(File('${dataDir.path}/memories.json'));
      _profile.attach(File('${dataDir.path}/profile.json'));
      _diaryStore.attach(Directory('${dataDir.path}/diaries'));
      _practice.attach(File('${dataDir.path}/practice.json'));
      await Future.wait([
        _episodic.load(),
        _profile.load(),
        _practice.load(),
      ]);
      if (mounted) setState(() {});
    } catch (_) {
      // 存储初始化失败不阻塞 UI，各 store 内部已静默兜底
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '心镜',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF5C8A6E),
        scaffoldBackgroundColor: const Color(0xFFFAF9F4),
      ),
      home: Scaffold(
        body: IndexedStack(
          index: _tab,
          children: [
            ChatPage(
              ai: _ai,
              memory: _memory,
              diaryStore: _diaryStore,
            ),
            PracticePage(data: _practice),
            DiariesPage(store: _diaryStore),
            SettingsPage(ai: _ai, profile: _profile),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline),
              selectedIcon: Icon(Icons.chat_bubble),
              label: '聊天',
            ),
            NavigationDestination(
              icon: Icon(Icons.checklist_rtl),
              label: '功课',
            ),
            NavigationDestination(
              icon: Icon(Icons.menu_book_outlined),
              selectedIcon: Icon(Icons.menu_book),
              label: '日记',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: '我的',
            ),
          ],
        ),
      ),
    );
  }
}
