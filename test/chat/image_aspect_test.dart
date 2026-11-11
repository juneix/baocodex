import 'dart:typed_data';

import 'package:baocode_mobile/chat/widgets/image_aspect.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _png(int width, int height) {
  final data = ByteData(24);
  data.setUint8(0, 0x89);
  data.setUint8(1, 0x50);
  data.setUint32(16, width);
  data.setUint32(20, height);
  return data.buffer.asUint8List();
}

Uint8List _jpeg(int width, int height, {int? orientation}) {
  final bytes = <int>[0xFF, 0xD8];
  if (orientation != null) {
    bytes.addAll([0xFF, 0xE1, 0x00, 0x22]);
    bytes.addAll([0x45, 0x78, 0x69, 0x66, 0, 0]);
    bytes.addAll([0x49, 0x49, 0x2A, 0, 8, 0, 0, 0]);
    bytes.addAll([1, 0]);
    bytes.addAll([0x12, 0x01, 3, 0, 1, 0, 0, 0, orientation, 0, 0, 0]);
    bytes.addAll([0, 0, 0, 0]);
  }
  bytes.addAll([0xFF, 0xC0, 0x00, 0x11, 8]);
  bytes.addAll([height >> 8, height & 255, width >> 8, width & 255]);
  bytes.addAll(List.filled(12, 0));
  return Uint8List.fromList(bytes);
}

void main() {
  test('PNG 与 JPEG 从文件头读出比例', () {
    expect(imageAspect(_png(1272, 2772)), closeTo(2.18, .01));
    expect(imageAspect(_jpeg(400, 300)), .75);
  });

  test('EXIF 转了向的照片按显示的方向算', () {
    expect(imageAspect(_jpeg(400, 300, orientation: 6)), closeTo(1.33, .01));
    expect(imageAspect(_jpeg(400, 300, orientation: 1)), .75);
  });

  test('认不出的和残缺的文件给 null，不抛异常', () {
    expect(imageAspect(Uint8List(0)), isNull);
    expect(imageAspect(Uint8List.fromList([1, 2, 3, 4])), isNull);
    expect(imageAspect(_png(0, 10)), isNull);
    expect(imageAspect(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE1])), isNull);
  });
}
