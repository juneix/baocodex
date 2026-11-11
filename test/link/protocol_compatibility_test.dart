import 'dart:convert';
import 'dart:typed_data';

import 'package:bao_iroh/bao_iroh.dart' show IrohException;
import 'package:bao_link/bao_link_io.dart';
import 'package:flutter_test/flutter_test.dart';

String offerUri(Map<String, Object?> extra) {
  final key = LinkIdentity.generate().publicKey;
  final json = <String, Object?>{
    'v': PairingOffer.version,
    'n': '桌面',
    'k': encodeKey(key),
    't': encodeKey(Uint8List.fromList(List.generate(16, (i) => i))),
    'x': 1800000000,
    'r': ['https://relay.example/'],
    'a': ['192.168.1.5:47100'],
    ...extra,
  };
  return '${PairingOffer.scheme}://pair?d=${encodeKey(utf8.encode(jsonEncode(json)))}';
}

Map<String, Object?> offerWire(String uri) {
  final data = Uri.parse(uri).queryParameters['d']!;
  return jsonDecode(utf8.decode(decodeKey(data))) as Map<String, Object?>;
}

void main() {
  group('项目置顶兼容', () {
    test('新桌面的项目置顶经 JSON 往返保留', () {
      final project = ProjectInfo.fromJson({
        'id': '/p',
        'name': '项目',
        'path': '/p',
        'pinned': true,
      });
      expect(ProjectInfo.fromJson(project.toJson()).pinned, isTrue);
    });

    test('旧桌面缺少置顶字段，不伪造能力', () {
      final project = ProjectInfo.fromJson({
        'id': '/p',
        'name': '项目',
        'path': '/p',
      });
      expect(project.pinned, isNull);
      expect(project.toJson().containsKey('pinned'), isFalse);
    });
  });

  group('PairingOffer.direct', () {
    test('二维码里的 direct 经解析再编码后仍为 true', () {
      final parsed = PairingOffer.parse(offerUri({'d': true}));
      expect(offerWire(parsed.uri)['d'], isTrue);
    });

    test('缺少 direct 的旧二维码再编码后不带该字段', () {
      final parsed = PairingOffer.parse(offerUri({}));
      expect(offerWire(parsed.uri).containsKey('d'), isFalse);
    });
  });

  group('DeviceInfo.direct', () {
    const base = <String, Object?>{
      'name': '桌面',
      'kind': 'mac',
      'system': 'macOS 26',
    };

    test('设备信息往返保留 direct 为 true', () {
      final info = DeviceInfo.fromJson({...base, 'direct': true});
      expect(info.toJson()['direct'], isTrue);
    });

    test('缺少 direct 的旧设备信息不输出该字段', () {
      final info = DeviceInfo.fromJson(base);
      expect(info.toJson().containsKey('direct'), isFalse);
    });

    test('direct 作为属性默认 false，copyWith 保留并可覆盖', () {
      final on = DeviceInfo.fromJson({...base, 'direct': true});
      expect(DeviceInfo.fromJson(base).direct, isFalse);
      expect(on.direct, isTrue);
      expect(on.copyWith(addrs: const ['10.0.0.2:47100']).direct, isTrue);
      expect(on.copyWith(direct: false).direct, isFalse);
    });
  });

  group('LinkBot.notices', () {
    const bot = <String, Object?>{'id': 'b', 'name': 'Bao'};

    test('含 notices 的机器人往返保留 id/chat/project/detail', () {
      final restored = LinkBot.fromJson(
        LinkBot.fromJson({
          ...bot,
          'notices': [
            {
              'id': 7,
              'kind': 'failed',
              'chat': 'c-1',
              'title': '修构建',
              'project': 'monad',
              'detail': 'exit 1',
            },
          ],
        }).toJson(),
      );
      final notice = restored.notices.single;
      expect(notice.id, 7);
      expect(notice.kind, 'failed');
      expect(notice.chat, 'c-1');
      expect(notice.title, '修构建');
      expect(notice.project, 'monad');
      expect(notice.detail, 'exit 1');
    });

    test('缺少 notices 时为空且不输出该字段，detail 缺省为 null', () {
      final plain = LinkBot.fromJson(bot);
      expect(plain.notices, isEmpty);
      expect(plain.toJson().containsKey('notices'), isFalse);
      final noDetail = LinkBot.fromJson({
        ...bot,
        'notices': [
          {'id': 1, 'kind': 'done', 'chat': 'c', 'title': 't', 'project': 'p'},
        ],
      });
      expect(noDetail.notices.single.detail, isNull);
    });
  });

  test('strictPort 绑定被占用端口时失败，默认仍回退到其他端口', () async {
    final first = await IrohLinkNode.bind(
      identity: LinkIdentity.generate(),
      relays: const [],
      port: 0,
    );
    addTearDown(first.close);
    final port = (await first.info()).port;
    expect(port, isNotNull);
    expect(port, greaterThan(0));

    IrohLinkNode? unexpected;
    Object? failure;
    try {
      unexpected = await IrohLinkNode.bind(
        identity: LinkIdentity.generate(),
        relays: const [],
        port: port!,
        strictPort: true,
      );
    } on Object catch (error) {
      failure = error;
    }
    if (unexpected != null) addTearDown(unexpected.close);
    expect(failure, isA<IrohException>(), reason: 'strictPort 应拒绝被占用端口');

    final fallback = await IrohLinkNode.bind(
      identity: LinkIdentity.generate(),
      relays: const [],
      port: port!,
    );
    addTearDown(fallback.close);
    final fallbackPort = (await fallback.info()).port;
    expect(fallbackPort, isNotNull);
    expect(fallbackPort, isNot(0));
    expect(fallbackPort, isNot(port));
  });
}
