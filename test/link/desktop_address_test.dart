import 'dart:async';
import 'dart:io';

import 'package:baocode_mobile/link/desktop_address.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode_mobile/models/user_facing_error.dart';

void main() {
  test('域名、IPv4、IPv6 保留端口，格式无歧义', () {
    expect(
      DesktopAddress.parse(' Desk.Example.test:47100 ').normalized,
      'desk.example.test:47100',
    );
    expect(DesktopAddress.parse('[::1]:47100').normalized, '[::1]:47100');
    expect(DesktopAddress.parse('127.0.0.1:65535').port, 65535);
    for (final invalid in [
      'example.test',
      'example.test:0',
      'example.test:65536',
      'user:secret@example.test:47100',
      'example.test:47100/path',
      'https://example.test:47100',
      'example.test:47100?key=secret',
      'example.test:47100#part',
      '999.999.1.1:47100',
      'bad_host:47100',
    ]) {
      expect(
        () => DesktopAddress.parse(invalid),
        throwsA(isA<UserFacingError>()),
        reason: invalid,
      );
    }
  });

  test('拨号时解析域名，不覆盖保存的域名，IP 地址不请求 DNS', () async {
    final lookedUp = <String>[];
    const addresses = ['desk.example.test:47100', '[::1]:47101'];
    final resolved = await resolveDesktopAddresses(
      addresses,
      lookup: (host) async {
        lookedUp.add(host);
        return [InternetAddress('127.0.0.1'), InternetAddress('::1')];
      },
    );
    expect(resolved, ['127.0.0.1:47100', '[::1]:47100', '[::1]:47101']);
    expect(lookedUp, ['desk.example.test']);
    expect(addresses.first, 'desk.example.test:47100');
  });

  test('单域名失败不丢失其他地址，全部 DNS 失败明确报告', () async {
    Future<List<InternetAddress>> fail(String _) async =>
        throw const SocketException('合成 DNS 错误');
    expect(
      await resolveDesktopAddresses([
        'bad.example.test:47100',
        '127.0.0.1:47100',
      ], lookup: fail),
      ['127.0.0.1:47100'],
    );
    await expectLater(
      resolveDesktopAddresses(['bad.example.test:47100'], lookup: fail),
      throwsA(isA<AddressResolutionException>()),
    );
  });

  test('DNS 等待有界，允许明确配置了中继的电脑继续拨号', () async {
    await expectLater(
      resolveDesktopAddresses(
        ['slow.example.test:47100'],
        timeout: const Duration(milliseconds: 1),
        lookup: (_) => Completer<List<InternetAddress>>().future,
      ),
      throwsA(isA<AddressResolutionException>()),
    );
    expect(
      await resolveDesktopAddresses(
        ['bad.example.test:47100'],
        lookup: (_) async => [],
        allowEmpty: true,
      ),
      isEmpty,
    );
  });
}
