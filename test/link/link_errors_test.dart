import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/link/link_errors.dart';
import 'package:baocode_mobile/link/phone_link.dart'
    show PairingStorageException;
import 'package:flutter_test/flutter_test.dart';

void main() {
  String english(String _, String en) => en;

  test('连接检查显示授权失败原因，不暴露上游异常或令牌', () {
    final message = connectionCheckErrorMessage(
      const LinkRemoteException(
        LinkErrors.unpaired,
        'synthetic-token-do-not-show',
      ),
      english,
    );
    expect(message, contains('Pair again'));
    expect(message, isNot(contains('synthetic-token')));
    expect(
      connectionCheckErrorMessage(
        StateError('synthetic-private-error'),
        english,
      ),
      isNot(contains('synthetic-private-error')),
    );
  });

  test('malformed pairing errors do not expose the token-bearing source', () {
    const secret = 'baocode://pair?d=ONE_TIME_TOKEN';
    final message = pairingErrorMessage(
      const FormatException('Invalid', secret),
      english,
    );
    expect(message, contains('invalid or expired'));
    expect(message, isNot(contains(secret)));
    expect(message, isNot(contains('ONE_TIME_TOKEN')));
  });

  test('信任回滚失败明确提示可能残留授权，不伪装成连接错误', () {
    final message = pairingErrorMessage(
      const PairingStorageException(),
      english,
    );
    expect(message, contains('Trust may remain'));
    expect(message, contains('Revoke this phone on the desktop'));
  });

  test('旧协议二维码提示更新电脑，新协议二维码提示更新手机', () {
    expect(
      pairingErrorMessage(const PairingVersionException(1), english),
      contains('Update BaoCode on the computer'),
    );
    expect(
      pairingErrorMessage(const PairingVersionException(3), english),
      contains('Update BaoCode on this phone'),
    );
  });

  test('remote error text cannot smuggle a pairing secret into the UI', () {
    final message = pairingErrorMessage(
      const LinkRemoteException(
        LinkErrors.busy,
        'secret-token-in-untrusted-message',
      ),
      english,
    );
    expect(message, contains('another phone'));
    expect(message, isNot(contains('secret-token')));
  });
}
