import 'package:flutter_test/flutter_test.dart';
import 'package:ai_diary_demo/image_exporter.dart';

void main() {
  test('saveBlockedReason：没图 / 路径空 → 说清是「还没有图」', () {
    expect(saveBlockedReason(imagePath: null, fileExists: false), contains('还没有图'));
    expect(saveBlockedReason(imagePath: '  ', fileExists: false), contains('还没有图'));
  });

  test('saveBlockedReason：路径在但文件没了 → 提示重新显化', () {
    expect(
      saveBlockedReason(imagePath: 'C:/x/a.png', fileExists: false),
      contains('重新显化'),
    );
  });

  test('saveBlockedReason：图存在 → 允许保存（返回 null）', () {
    expect(saveBlockedReason(imagePath: 'C:/x/a.png', fileExists: true), isNull);
  });
}
