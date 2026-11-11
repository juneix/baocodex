import 'package:bao_link/bao_link.dart';
import 'package:flutter/services.dart';

import 'chat_models.dart';

String messageBody(String text, List<ImageAttachment> images) {
  if (images.isEmpty) return text;
  final numbers = {
    for (final (index, image) in images.indexed) image.number ?? index + 1,
  };
  return text.replaceAllMapped(imageReferencePattern, (match) {
    return numbers.contains(int.tryParse(match[1]!)) ? '' : match[0]!;
  }).trim();
}

class ChatClipboardContent {
  const ChatClipboardContent({required this.text, required this.images});
  final String text;
  final List<ImageAttachment> images;
}

class ChatClipboard {
  static const _channel = MethodChannel('local.baocode.mobile/platform');
  static const _codec = StandardMessageCodec();
  static const _maxBytes = 32 * 1024 * 1024;

  static bool _validImage(Uint8List bytes, String type) =>
      bytes.isNotEmpty &&
      4 * ((bytes.length + 2) ~/ 3) < LinkLimits.image &&
      const [
        'image/png',
        'image/jpeg',
        'image/gif',
        'image/webp',
      ].contains(type);

  static Future<void> copyMessage(
    String text,
    List<ImageAttachment> images,
  ) async {
    final body = messageBody(text, images);
    if (images.isEmpty) {
      await Clipboard.setData(ClipboardData(text: body));
      return;
    }
    await _write(body, images);
  }

  static Future<void> copyImage(
    Uint8List bytes, {
    String? name,
    String? type,
  }) async {
    final mediaType = type ?? _imageType(bytes);
    final image = ImageAttachment(
      bytes: bytes,
      mediaType: mediaType,
      name: name,
    );
    await _write('', [image], image: {'bytes': bytes, 'type': mediaType});
  }

  static Future<void> _write(
    String text,
    List<ImageAttachment> images, {
    Map<String, Object?>? image,
  }) async {
    if (images.any((image) => !_validImage(image.bytes, image.mediaType))) {
      throw const FormatException('图片格式或大小无效');
    }
    final data = _codec.encodeMessage({
      'version': 1,
      'text': text,
      'images': [
        for (final image in images)
          {'bytes': image.bytes, 'type': image.mediaType, 'name': image.name},
      ],
    })!;
    if (data.lengthInBytes > _maxBytes) {
      throw const FormatException('图文内容超过剪贴板容量');
    }
    await _channel.invokeMethod<void>('writeChatClipboard', {
      'text': text,
      'payload': data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      ),
      'image': ?image,
    });
  }

  static Future<ChatClipboardContent?> read() async {
    final Uint8List? bytes;
    try {
      bytes = await _channel.invokeMethod<Uint8List>('readChatClipboard');
    } on MissingPluginException {
      return null;
    }
    if (bytes == null) return null;
    if (bytes.length > _maxBytes) throw const FormatException('剪贴板内容过大');
    final decoded = _codec.decodeMessage(ByteData.sublistView(bytes));
    if (decoded case {
      'version': 1,
      'text': final String text,
      'images': final List entries,
    }) {
      final images = <ImageAttachment>[];
      for (final entry in entries) {
        if (entry
            case {
              'bytes': final Uint8List data,
              'type': final String type,
              'name': final String? name,
            }
            when _validImage(data, type)) {
          images.add(ImageAttachment(bytes: data, mediaType: type, name: name));
        } else {
          throw const FormatException('剪贴板图片无效或超过大小限制');
        }
      }
      return ChatClipboardContent(text: text, images: images);
    }
    throw const FormatException('剪贴板图文格式无效');
  }

  static String _imageType(Uint8List bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff) {
      return 'image/jpeg';
    }
    if (bytes.length >= 6) {
      final header = String.fromCharCodes(bytes.take(6));
      if (header == 'GIF87a' || header == 'GIF89a') return 'image/gif';
    }
    if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.take(4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
      return 'image/webp';
    }
    throw const FormatException('不支持的图片格式');
  }
}
