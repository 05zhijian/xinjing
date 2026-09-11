import 'dart:io';

import 'package:gal/gal.dart';

/// 保存到相册的结果。
enum SaveOutcome { saved, noImage, denied, failed }

/// 保存前的可判定原因（纯函数，便于单测）；返回 null 表示可以尝试保存。
/// 镜灵图在未接生图（如 DeepSeek 纯文本档）或显化失败时并不存在，
/// 这种情况要说清原因，而不是给用户一个「保存失败」。
String? saveBlockedReason({String? imagePath, required bool fileExists}) {
  if (imagePath == null || imagePath.trim().isEmpty) {
    return '这一版还没有图（DeepSeek 不提供生图，或还没显化成功）';
  }
  if (!fileExists) return '图片文件已不在，重新显化一次即可';
  return null;
}

/// 把镜灵 PNG 存进系统相册（Android 走 MediaStore，落在「心镜」相册目录）。
class ImageExporter {
  static Future<SaveOutcome> toGallery(String path) async {
    try {
      await Gal.putImage(path, album: '心镜');
      return SaveOutcome.saved;
    } on GalException catch (e) {
      return e.type == GalExceptionType.accessDenied
          ? SaveOutcome.denied
          : SaveOutcome.failed;
    } catch (_) {
      return SaveOutcome.failed;
    }
  }

  /// 先做可判定检查，再保存；返回一句可直接展示给用户的话。
  static Future<String> saveToGalleryWithMessage(String? imagePath) async {
    final path = imagePath;
    final blocked = saveBlockedReason(
      imagePath: path,
      fileExists: path != null && File(path).existsSync(),
    );
    if (blocked != null) return blocked;
    switch (await toGallery(path!)) {
      case SaveOutcome.saved:
        return '✓ 已保存到相册（心镜）';
      case SaveOutcome.denied:
        return '没有相册权限：去系统设置里允许后重试';
      case SaveOutcome.failed:
        return '保存失败，请重试';
      case SaveOutcome.noImage:
        return '这一版还没有图';
    }
  }
}
