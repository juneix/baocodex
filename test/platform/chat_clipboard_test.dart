import 'dart:convert';

import 'package:baocode_mobile/chat/chat_clipboard.dart';
import 'package:baocode_mobile/chat/chat_models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('local.baocode.mobile/platform');
  const codec = StandardMessageCodec();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=',
  );
  final image = ImageAttachment(bytes: png, mediaType: 'image/png', number: 11);

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test('只隐藏本条附件的编号，不吞掉无对应图片的文字引用', () {
    expect(messageBody('看图 [Image #11]', [image]), '看图');
    expect(messageBody('[Image #11]', [image]), '');
    expect(messageBody('找 [Image #99]', [image]), '找 [Image #99]');
    expect(
      messageBody('[Image #9999999999999999999999999999]', [image]),
      '[Image #9999999999999999999999999999]',
    );
    expect(messageBody('文字 [Image #11]', []), '文字 [Image #11]');
    expect(messageBody('  保留格式\n', []), '  保留格式\n');
  });

  test('纯文字复制使用系统正文，不创建图文副本', () async {
    String? copied;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => fail('纯文字不应写图文剪贴板'),
    );
    await ChatClipboard.copyMessage('原样正文', []);
    expect(copied, '原样正文');
  });

  test('图文副本恢复多图原始字节、格式和名称，不沿用旧会话编号', () async {
    final data = codec.encodeMessage({
      'version': 1,
      'text': '两张图',
      'images': [
        {'bytes': png, 'type': 'image/png', 'name': 'first.png'},
        {'bytes': png, 'type': 'image/png', 'name': null},
      ],
    })!;
    messenger.setMockMethodCallHandler(
      channel,
      (_) async =>
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    final content = (await ChatClipboard.read())!;
    expect(content.text, '两张图');
    expect(content.images, hasLength(2));
    expect(content.images.first.bytes, png);
    expect(content.images.first.mediaType, 'image/png');
    expect(content.images.first.name, 'first.png');
    expect(content.images.last.name, isNull);
    expect(content.images.every((image) => image.number == null), isTrue);
  });

  test('剪贴板已换成普通文字时，不复用上次图片', () async {
    final data = codec.encodeMessage({
      'version': 1,
      'text': '正文',
      'images': [
        {'bytes': png, 'type': 'image/png', 'name': null},
      ],
    })!;
    var current = true;
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => current
          ? data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes)
          : null,
    );
    expect((await ChatClipboard.read())!.images, hasLength(1));
    current = false;
    expect(await ChatClipboard.read(), isNull);
  });

  test('不支持或空图片在复制前明确拒绝，不伪造已复制', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => fail('无效图片不能写入系统剪贴板'),
    );
    for (final image in [
      ImageAttachment(bytes: Uint8List(0), mediaType: 'image/png'),
      ImageAttachment(bytes: png, mediaType: 'image/heic'),
    ]) {
      await expectLater(
        ChatClipboard.copyMessage('说明', [image]),
        throwsFormatException,
      );
    }
  });

  test('副本丢失报错，不静默丢弃附件', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'clipboard_unavailable'),
    );
    await expectLater(ChatClipboard.read(), throwsA(isA<PlatformException>()));
  });

  for (final bad in [
    {'version': 2, 'text': '正文', 'images': []},
    {
      'version': 1,
      'text': '正文',
      'images': [
        {'type': 'image/png', 'bytes': 'not bytes', 'name': null},
      ],
    },
    {
      'version': 1,
      'text': '正文',
      'images': [
        {'type': 'text/html', 'bytes': png, 'name': null},
      ],
    },
    {
      'version': 1,
      'text': '正文',
      'images': [
        {'type': 'image/png', 'bytes': Uint8List(0), 'name': null},
      ],
    },
  ]) {
    test('无效副本拒绝整条粘贴：$bad', () async {
      final data = codec.encodeMessage(bad)!;
      messenger.setMockMethodCallHandler(
        channel,
        (_) async =>
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      await expectLater(ChatClipboard.read(), throwsFormatException);
    });
  }
}
