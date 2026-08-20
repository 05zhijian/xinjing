import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// DeepSeek AI 服务：流式对话（OpenAI 兼容 SSE）。
/// 复用「回忆册」的 SSE 流式解析思路（extractDeltaContent）。
class AiService {
  static const String _envKey = String.fromEnvironment('DEEPSEEK_API_KEY');
  static const String _base = 'https://api.deepseek.com/chat/completions';
  static const String _model = 'deepseek-v4-flash';

  /// 瞬态错误最大尝试次数（含首次）。
  static const int maxAttempts = 3;
  static const Duration _backoffBase = Duration(milliseconds: 1000);
  static const Duration _backoffCap = Duration(seconds: 8);

  String? _runtimeKey; // 界面填的 key，优先于编译注入

  /// 实际生效的 key：运行时填的优先，否则编译注入的。
  String get _apiKey => _runtimeKey ?? _envKey;

  bool get hasKey => _apiKey.isNotEmpty;

  /// 当前生效的 key（界面回显用）。
  String get apiKey => _apiKey;

  /// 运行时设置 key（界面填入）。
  void setApiKey(String key) => _runtimeKey = key.trim();

  /// 流式对话，逐段回调增量文本。
  /// 仅在「发送请求」阶段重试限流/5xx/网络错误；一旦开始流式输出就不再重试，
  /// 避免已回显的增量被重复。
  Future<void> chat(
    List<Map<String, String>> messages, {
    required void Function(String delta) onDelta,
    required void Function() onDone,
    required void Function(String error) onError,
  }) async {
    if (!hasKey) {
      onError('未配置 API Key：请用 --dart-define=DEEPSEEK_API_KEY=xxx 运行');
      return;
    }
    final client = http.Client();
    try {
      http.StreamedResponse? response;
      var delay = _backoffBase;
      for (var attempt = 1; attempt <= maxAttempts; attempt++) {
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
          response =
              await client.send(request).timeout(const Duration(seconds: 60));
          if (attempt < maxAttempts &&
              _isRetryableStatus(response.statusCode)) {
            delay = await _backoff(delay, response.headers['retry-after']);
            debugPrint('[ai] chat retry after ${delay.inMilliseconds}ms');
            continue;
          }
          break;
        } on Exception catch (e) {
          if (attempt < maxAttempts && _isRetryableError(e)) {
            delay = await _backoff(delay, null);
            debugPrint('[ai] chat retry on error: $e');
            continue;
          }
          onError('连接失败：$e');
          debugPrint('[ai] chat send error: $e');
          return;
        }
      }
      if (response == null || response.statusCode != 200) {
        onError('接口错误 ${response?.statusCode}');
        debugPrint('[ai] chat failed final: ${response?.statusCode}');
        return;
      }
      await for (final line in response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(const Duration(seconds: 45))) {
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
      debugPrint('[ai] chat stream error: $e');
    } finally {
      client.close();
    }
  }

  /// 非流式完整回复（画像抽取等一次性调用）。失败返回空串。
  Future<String> complete(List<Map<String, String>> messages) async {
    if (!hasKey) return '';
    final client = http.Client();
    try {
      final response = await _postWithRetry(
        client,
        Uri.parse(_base),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: {
          'model': _model,
          'messages': messages,
          'temperature': 0.3,
          // deepseek-v4-flash 是推理模型：输出 token 会被 reasoning_content
          // 大量消耗，不给足 max_tokens 会让真实 content 截断成残缺 JSON。
          'max_tokens': 2048,
        },
        timeout: const Duration(seconds: 90),
      );
      if (response.statusCode != 200) return '';
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = json['choices'] as List?;
      if (choices == null || choices.isEmpty) return '';
      final msg = (choices.first as Map<String, dynamic>)['message'];
      if (msg is Map<String, dynamic>) return msg['content'] as String? ?? '';
      return '';
    } catch (_) {
      return '';
    } finally {
      client.close();
    }
  }

  /// 非流式 POST，带限流/5xx/网络错误重试；耗尽重试次数后返回最后一次响应或抛错。
  Future<http.Response> _postWithRetry(
    http.Client client,
    Uri uri, {
    required Map<String, String> headers,
    required Map<String, dynamic> body,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    var delay = _backoffBase;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final response = await client
            .post(uri, headers: headers, body: jsonEncode(body))
            .timeout(timeout);
        if (attempt < maxAttempts && _isRetryableStatus(response.statusCode)) {
          delay = await _backoff(delay, response.headers['retry-after']);
          debugPrint('[ai] ${uri.path} retry ${response.statusCode} after ${delay.inMilliseconds}ms');
          continue;
        }
        if (response.statusCode != 200) {
          final body = response.body;
          debugPrint('[ai] ${uri.path} final status ${response.statusCode}: '
              '${body.length > 120 ? body.substring(0, 120) : body}');
        }
        return response;
      } on Exception catch (e) {
        if (attempt < maxAttempts && _isRetryableError(e)) {
          delay = await _backoff(delay, null);
          continue;
        }
        rethrow;
      }
    }
    throw http.ClientException('重试次数耗尽');
  }

  /// 退避等待：优先按 429 的 Retry-After，否则指数退避+抖动。返回下一次退避时长。
  Future<Duration> _backoff(Duration base, String? retryAfter) async {
    final ra = int.tryParse(retryAfter ?? '');
    final delay = (ra != null && ra >= 0)
        ? Duration(seconds: min(ra, _backoffCap.inSeconds))
        : base + Duration(milliseconds: Random().nextInt(300));
    await Future<void>.delayed(delay);
    final next = delay * 2;
    return next > _backoffCap ? _backoffCap : next;
  }

  /// 瞬态状态码：限流或服务端过载，值得重试。
  static bool _isRetryableStatus(int code) =>
      code == 429 || (code >= 500 && code <= 504);

  /// 网络层瞬态错误（超时、连接重置等），值得重试。
  static bool _isRetryableError(Object e) =>
      e is TimeoutException ||
      e is SocketException ||
      e is http.ClientException;

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
