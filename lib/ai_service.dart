import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// 智谱 AI 服务：流式对话。
/// 复用「回忆册」的 SSE 流式解析思路（extractDeltaContent）。
class AiService {
  static const String _envKey = String.fromEnvironment('ZHIPU_API_KEY');
  static const String _base =
      'https://open.bigmodel.cn/api/paas/v4/chat/completions';
  static const String _model = 'glm-4-flash';
  String? _runtimeKey; // 界面填的 key，优先于编译注入

  /// 实际生效的 key：运行时填的优先，否则编译注入的。
  String get _apiKey => _runtimeKey ?? _envKey;

  bool get hasKey => _apiKey.isNotEmpty;

  /// 当前生效的 key（界面回显用）。
  String get apiKey => _apiKey;

  /// 运行时设置 key（界面填入）。
  void setApiKey(String key) => _runtimeKey = key.trim();

  /// 流式对话，逐段回调增量文本。
  Future<void> chat(
    List<Map<String, String>> messages, {
    required void Function(String delta) onDelta,
    required void Function() onDone,
    required void Function(String error) onError,
  }) async {
    if (!hasKey) {
      onError('未配置 API Key：请用 --dart-define=ZHIPU_API_KEY=xxx 运行');
      return;
    }
    final client = http.Client();
    try {
      final request = http.Request('POST', Uri.parse(_base))
        ..headers['Authorization'] = 'Bearer $_apiKey'
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode({
          'model': _model,
          'messages': messages,
          'stream': true,
          'temperature': 0.7,
        });
      final response =
          await client.send(request).timeout(const Duration(seconds: 60));
      if (response.statusCode != 200) {
        onError('接口错误 ${response.statusCode}');
        return;
      }
      await for (final line in response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        final delta = extractDeltaContent(line);
        if (delta != null && delta.isNotEmpty) {
          onDelta(delta);
        }
        if (line.trim().startsWith('data:') && line.contains('[DONE]')) {
          break;
        }
      }
      onDone();
    } catch (e) {
      onError('连接失败：$e');
    } finally {
      client.close();
    }
  }

  /// 文本转向量（智谱 embedding-2）。
  Future<List<double>?> embed(String text) async {
    if (!hasKey) return null;
    final client = http.Client();
    try {
      final response = await client
          .post(
            Uri.parse('https://open.bigmodel.cn/api/paas/v4/embeddings'),
            headers: {
              'Authorization': 'Bearer $_apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'model': 'embedding-2', 'input': [text]}),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) return null;
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final data = (json['data'] as List).first as Map<String, dynamic>;
      return (data['embedding'] as List)
          .map((e) => (e as num).toDouble())
          .toList();
    } catch (_) {
      return null;
    }
  }

  /// 从一条 SSE 行解析增量文本。非法行返回 null（设计上不抛异常）。
  static String? extractDeltaContent(String line) {
    if (!line.startsWith('data:')) return null;
    final data = line.substring(5).trim();
    if (data == '[DONE]') return null;
    try {
      final json = jsonDecode(data) as Map<String, dynamic>;
      final choices = json['choices'] as List?;
      if (choices == null || choices.isEmpty) return null;
      final delta = (choices.first as Map<String, dynamic>)['delta'];
      if (delta is Map<String, dynamic>) return delta['content'] as String?;
      return null;
    } catch (_) {
      return null;
    }
  }
}
