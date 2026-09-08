import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'ai_service.dart';

/// 生图抽象：AvatarService 只依赖这个接口，厂商实现可换、测试用 Fake。
abstract class ImageGen {
  /// 当前服务商支持生图且已配 key。
  bool get ready;

  /// 生成一张图并返回 PNG 字节；失败 / 未就绪返回 null。
  Future<Uint8List?> generate(String prompt);
}

/// 智谱 CogView 实现（DevDoc §十二-5：与 GLM 文本共用一个 key）。
/// 真实接口探测结论（2026-09-09）：
///   POST /api/paas/v4/images/generations  {"model":"cogview-3-flash","prompt":"…"}
///   200 → {"data":[{"url":"<带签名下载地址>"}]}，再 GET url 取 PNG 字节。
class ZhipuImageGen implements ImageGen {
  final AiService ai;
  ZhipuImageGen({required this.ai});

  @override
  bool get ready => ai.supportsImages && ai.hasKey;

  @override
  Future<Uint8List?> generate(String prompt) async {
    final base = ai.imageBase;
    final model = ai.imageModel;
    if (!ready || base == null || model == null) return null;
    final client = http.Client();
    try {
      final resp = await client
          .post(
            Uri.parse(base),
            headers: {
              'Authorization': 'Bearer ${ai.apiKey}',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'model': model, 'prompt': prompt}),
          )
          .timeout(const Duration(seconds: 150));
      if (resp.statusCode != 200) return null;

      final j = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final dataList = j['data'];
      if (dataList is! List || dataList.isEmpty || dataList.first is! Map) {
        return null;
      }
      final url =
          ((dataList.first as Map).cast<String, dynamic>()['url']) as String?;
      if (url == null || url.isEmpty) return null;

      final img =
          await client.get(Uri.parse(url)).timeout(const Duration(seconds: 60));
      if (img.statusCode != 200) return null;
      return Uint8List.fromList(img.bodyBytes);
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }
}
