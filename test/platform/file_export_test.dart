import 'dart:convert';

import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/platform/file_export.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('local.baocode.mobile/platform');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('下载按原始字节解码，空文件和 8 MiB 边界都可保存', () {
    expect(decodeFileDownload({'data': 'AAH/'}), [0, 1, 255]);
    expect(decodeFileDownload({'data': ''}), isEmpty);
    final bytes = Uint8List(LinkLimits.download);
    expect(
      decodeFileDownload({'data': base64Encode(bytes)}).length,
      8 * 1024 * 1024,
    );
  });

  test('超限与损坏响应不能触发原生保存', () {
    expect(
      () => decodeFileDownload({'tooLarge': true, 'size': 9000000}),
      throwsA(isA<DownloadTooLargeException>()),
    );
    expect(
      () => decodeFileDownload({'data': 'SYNTHETIC_PRIVATE_FILE!'}),
      throwsA(
        isA<FormatException>().having(
          (error) => error.toString(),
          '错误不回显文件内容',
          isNot(contains('SYNTHETIC_PRIVATE_FILE')),
        ),
      ),
    );
    expect(() => decodeFileDownload({'data': 123}), throwsFormatException);
    expect(
      () => decodeFileDownload({
        'data': base64Encode(Uint8List(LinkLimits.download + 1)),
      }),
      throwsA(isA<DownloadTooLargeException>()),
    );
  });

  test('原生保存使用文件名和字节，取消返回 false，不伪造成功', () async {
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          received = call;
          return false;
        });
    expect(await saveFile('notes.txt', Uint8List.fromList([65, 66])), isFalse);
    expect(received!.method, 'saveFile');
    expect(received!.arguments, {
      'name': 'notes.txt',
      'bytes': [65, 66],
    });
    expect(() => saveFile('../secret', Uint8List(0)), throwsFormatException);
  });

  test('平台保存失败继续报告失败', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          throw PlatformException(code: 'save_failed', message: '合成保存失败');
        });
    await expectLater(
      saveFile('a.txt', Uint8List(0)),
      throwsA(isA<PlatformException>()),
    );
  });
}
