import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_diary_demo/diary_store.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('diary_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('save/list：归档可按日期列出', () async {
    final store = DiaryStore()..attach(tempDir);
    await store.save('第一篇觉察', date: DateTime(2026, 8, 15));
    await store.save('第二篇觉察', date: DateTime(2026, 8, 16));

    final entries = await store.list();
    expect(entries.length, 2);
    expect(entries.first.date, '2026-08-16'); // 倒序
    expect(entries.first.content, contains('第二篇觉察'));
  });

  test('save：同一天追加多篇', () async {
    final store = DiaryStore()..attach(tempDir);
    await store.save('第一篇', date: DateTime(2026, 8, 16));
    await store.save('第二篇', date: DateTime(2026, 8, 16));

    final entries = await store.list();
    expect(entries.length, 1);
    expect(entries.first.content, contains('第一篇'));
    expect(entries.first.content, contains('第二篇'));
  });

  test('list：空目录返回空列表', () async {
    final store = DiaryStore()..attach(tempDir);
    expect(await store.list(), isEmpty);
  });

  test('save：空内容/纯空白不落盘（避免 1 字节空日记）', () async {
    final store = DiaryStore()..attach(tempDir);
    await store.save('');
    await store.save('   \n  ', date: DateTime(2026, 8, 17));
    expect(await tempDir.list().toList(), isEmpty);
    expect(await store.list(), isEmpty);
  });

  test('list：忽略历史遗留的空日记文件', () async {
    final store = DiaryStore()..attach(tempDir);
    // 模拟早期版本写下的空白文件
    await File('${tempDir.path}/2026-08-01.md').writeAsString('\n');
    await store.save('正常的一篇', date: DateTime(2026, 8, 20));

    final entries = await store.list();
    expect(entries.length, 1);
    expect(entries.single.date, '2026-08-20');
  });
}
