import 'dart:typed_data';

/// 图片的高宽比，从文件头读出来，不用等解码，排版不会在解码后跳动。
/// 认不出的格式给 null。
double? imageAspect(Uint8List bytes) {
  final size = _pngSize(bytes) ?? _gifSize(bytes) ?? _jpegSize(bytes);
  if (size == null || size.$1 <= 0 || size.$2 <= 0) return null;
  return size.$2 / size.$1;
}

(int, int)? _pngSize(Uint8List b) {
  if (b.length < 24 || b[0] != 0x89 || b[1] != 0x50) return null;
  final data = ByteData.sublistView(b);
  return (data.getUint32(16), data.getUint32(20));
}

(int, int)? _gifSize(Uint8List b) {
  if (b.length < 10 || b[0] != 0x47 || b[1] != 0x49 || b[2] != 0x46) {
    return null;
  }
  final data = ByteData.sublistView(b);
  return (data.getUint16(6, Endian.little), data.getUint16(8, Endian.little));
}

(int, int)? _jpegSize(Uint8List b) {
  if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return null;
  final data = ByteData.sublistView(b);
  var turned = false;
  var at = 2;
  while (at + 9 < b.length) {
    if (b[at] != 0xFF) return null;
    final marker = b[at + 1];
    final length = data.getUint16(at + 2);
    if (marker == 0xE1) turned = _exifTurned(data, at + 4, length - 2);
    final isFrame =
        marker >= 0xC0 &&
        marker <= 0xCF &&
        marker != 0xC4 &&
        marker != 0xC8 &&
        marker != 0xCC;
    if (isFrame) {
      final height = data.getUint16(at + 5);
      final width = data.getUint16(at + 7);
      return turned ? (height, width) : (width, height);
    }
    at += 2 + length;
  }
  return null;
}

/// 相机照片常把方向写在 EXIF 里，显示时才转过来：5 到 8 是宽高互换的。
bool _exifTurned(ByteData data, int start, int length) {
  const exifHeader = 6;
  if (length < exifHeader + 8 || start + length > data.lengthInBytes) {
    return false;
  }
  if (data.getUint32(start) != 0x45786966) return false;
  final tiff = start + exifHeader;
  final order = data.getUint16(tiff) == 0x4949 ? Endian.little : Endian.big;
  final entries = tiff + data.getUint32(tiff + 4, order);
  if (entries + 2 > start + length) return false;
  final count = data.getUint16(entries, order);
  for (var i = 0; i < count; i++) {
    final entry = entries + 2 + i * 12;
    if (entry + 12 > start + length) return false;
    if (data.getUint16(entry, order) == 0x0112) {
      return data.getUint16(entry + 8, order) >= 5;
    }
  }
  return false;
}
