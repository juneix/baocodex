import 'dart:async';

import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/link/desktop_address.dart';
import 'package:baocode_mobile/link/link_store.dart';
import 'package:baocode_mobile/models/user_facing_error.dart';
import 'package:baocode_mobile/platform/file_export.dart';
import 'package:baocode_mobile/state/app_state.dart';
import 'package:baocode_mobile/ui/user_message.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _State extends AppState {
  _State({this.zh = true}) : super(store: MemoryLinkStore());
  final bool zh;
  @override
  String tr(String chinese, String english) => zh ? chinese : english;
}

void main() {
  late _State state;
  setUp(() => state = _State());
  tearDown(() => state.dispose());

  test('手机端已经说好的一句话原样显示，不再包一层', () {
    expect(
      userMessage(state, const UserFacingError('每张图片必须小于 8 MB')),
      '每张图片必须小于 8 MB',
    );
  });

  test('电脑的拒绝按代码说成人话，不露出异常类名', () {
    expect(
      userMessage(state, const LinkRemoteException(LinkErrors.notFound, 'x')),
      '电脑上找不到这项内容。',
    );
    expect(
      userMessage(
        state,
        const LinkRemoteException(LinkErrors.unsupported, 'x'),
      ),
      '电脑端版本过旧，暂不支持这个操作。',
    );
  });

  test('超时、格式、平台和未知错误都有中文说法', () {
    for (final error in <Object?>[
      TimeoutException('x'),
      const FormatException('x'),
      PlatformException(code: 'x'),
      StateError('private detail'),
      null,
    ]) {
      final message = userMessage(state, error);
      expect(message, isNotEmpty);
      expect(message, isNot(contains('Exception')));
      expect(message, isNot(contains('private detail')));
    }
  });

  test('已知的本机失败各说各的', () {
    expect(
      userMessage(state, const DownloadTooLargeException()),
      contains('8 MiB'),
    );
    expect(
      userMessage(state, const AddressResolutionException()),
      contains('域名'),
    );
  });

  test('英文界面也说英文，不中英混排', () {
    final english = _State(zh: false);
    addTearDown(english.dispose);
    for (final error in <Object?>[
      const LinkRemoteException(LinkErrors.notFound, 'x'),
      TimeoutException('x'),
      const FormatException('x'),
      StateError('private detail'),
    ]) {
      expect(userMessage(english, error), isNot(matches(RegExp(r'[一-鿿]'))));
    }
  });
}
