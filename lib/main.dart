import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'ai_service.dart';
import 'ai_settings_page.dart';
import 'avatar_renderer.dart';
import 'avatar_store.dart';
import 'chat_page.dart';
import 'diaries_page.dart';
import 'diary_store.dart';
import 'image_service.dart';
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
  final AvatarStore _avatarStore = AvatarStore();
  late final ImageGen _imageGen = ZhipuImageGen(ai: _ai);
  late final AvatarService _avatar = AvatarService(
      ai: _ai,
      memory: _memory,
      store: _avatarStore,
      imageGen: _imageGen);
  final GlobalKey<ChatPageState> _chatKey = GlobalKey<ChatPageState>();
  final GlobalKey<DiariesPageState> _diariesKey =
      GlobalKey<DiariesPageState>();
  int _tab = 0;

  static const List<String> _titles = ['心镜 · AI 陪伴', '今日功课', '觉察日记', '我的'];

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
      _avatarStore.attach(File('${dataDir.path}/avatar.json'));
      _avatarStore.attachImageDir(Directory('${dataDir.path}/avatar'));
      await Future.wait([
        _episodic.load(),
        _profile.load(),
        _practice.load(),
        _avatarStore.load(),
      ]);
      if (mounted) setState(() {});
    } catch (_) {
      // 存储初始化失败不阻塞 UI，各 store 内部已静默兜底
    }
  }

  void _openAiSettings(BuildContext shellCtx) {
    // 用 MaterialApp 内部的 context（在 Navigator 之下），不能用手上的 State context。
    Navigator.of(shellCtx).push(
      MaterialPageRoute(builder: (_) => AiSettingsPage(ai: _ai)),
    );
  }

  /// 壳层共享 AppBar 的右侧动作：聊天=✨生成日记，日记=刷新，各 Tab 都有 ⚙️。
  List<Widget> _actions(BuildContext shellCtx) {
    return <Widget>[
      if (_tab == 0)
        IconButton(
          tooltip: '生成今日觉察日记',
          icon: const Icon(Icons.auto_awesome),
          onPressed: () => _chatKey.currentState?.generateDiary(),
        ),
      if (_tab == 2)
        IconButton(
          tooltip: '刷新',
          icon: const Icon(Icons.refresh),
          onPressed: () => _diariesKey.currentState?.refresh(),
        ),
      IconButton(
        tooltip: 'AI 设置',
        icon: const Icon(Icons.settings_outlined),
        onPressed: () => _openAiSettings(shellCtx),
      ),
    ];
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
      home: Builder(
        builder: (shellCtx) => Scaffold(
        appBar: AppBar(
          title: Text(_titles[_tab]),
          centerTitle: true,
          actions: _actions(shellCtx),
        ),
        body: IndexedStack(
          index: _tab,
          children: [
            ChatPage(
              key: _chatKey,
              ai: _ai,
              memory: _memory,
              diaryStore: _diaryStore,
            ),
            PracticePage(data: _practice),
            DiariesPage(
              key: _diariesKey,
              store: _diaryStore,
            ),
            SettingsPage(profile: _profile, avatar: _avatar),
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
      ),
    );
  }
}
