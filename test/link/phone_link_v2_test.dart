import 'dart:async';
import 'dart:convert';

import 'package:bao_link/bao_link.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:baocode_mobile/link/phone_link.dart';

void main() {
  test('旧身份生成新密钥但保留电脑记录，重新确认前不拨号', () async {
    final store = MemoryLinkStore();
    final oldIdentity = {'privateKey': encodeKey(randomBytes(32))};
    final oldDesktop = {
      'id': 'legacy-device-id',
      'name': '旧电脑',
      'publicKey': encodeKey(randomBytes(32)),
      'addresses': ['192.168.1.2:47100'],
    };
    await store.write('identity', jsonEncode(oldIdentity));
    await store.write('desktops', jsonEncode([oldDesktop]));
    final network = MemoryLinkNetwork();
    var nodes = 0;
    final phone = PhoneLink(
      store: store,
      nodeFactory: (identity, relays) async {
        nodes++;
        return network.node(identity.id);
      },
    );
    addTearDown(phone.dispose);
    await phone.initialize();
    await pumpEventQueue();
    expect(phone.desktops.single.id, 'legacy-device-id');
    expect(phone.desktops.single.needsPairing, isTrue);
    expect(phone.onlineIds, isEmpty);
    expect(nodes, 0);
    final identity = jsonDecode((await store.read('identity'))!) as Map;
    expect(identity['kind'], 'ed25519');
    expect(identity['privateKey'], isNot(oldIdentity['privateKey']));
    await phone.reconnect('legacy-device-id');
    expect(nodes, 0);
    final restored = PhoneLink(
      store: store,
      nodeFactory: (identity, relays) async => network.node(identity.id),
    );
    addTearDown(restored.dispose);
    await restored.initialize();
    expect(restored.desktops.single.needsPairing, isTrue);
    expect(await store.read('identity'), jsonEncode(identity));
  });

  test('迁移保存失败时不覆盖原身份或自动信任旧电脑', () async {
    final store = _FailingStore();
    final oldIdentity = jsonEncode({'privateKey': encodeKey(randomBytes(32))});
    await store.write('identity', oldIdentity);
    await store.write(
      'desktops',
      jsonEncode([
        {
          'id': 'legacy-device-id',
          'name': '旧电脑',
          'publicKey': encodeKey(randomBytes(32)),
          'addresses': ['192.168.1.2:47100'],
        },
      ]),
    );
    store.fail = true;
    final phone = PhoneLink(store: store);
    addTearDown(phone.dispose);
    await expectLater(phone.initialize(), throwsStateError);
    expect(await store.read('identity'), oldIdentity);
    expect(phone.onlineIds, isEmpty);
  });

  test('拒绝旧二维码且提示版本错误，不尝试连接', () async {
    var nodes = 0;
    final phone = PhoneLink(
      store: MemoryLinkStore(),
      nodeFactory: (identity, relays) async {
        nodes++;
        return MemoryLinkNetwork().node(identity.id);
      },
    );
    addTearDown(phone.dispose);
    final uri =
        'baocode://pair?d=${encodeKey(utf8.encode(jsonEncode({'v': 1})))}';
    await expectLater(phone.pair(uri), throwsA(isA<PairingVersionException>()));
    expect(nodes, 0);
  });

  test('连接已证明的公钥不匹配时拒绝配对', () async {
    final network = MemoryLinkNetwork();
    final expected = LinkIdentity.generate();
    final wrong = LinkIdentity.generate();
    final node = network.node(wrong.id);
    final phone = PhoneLink(
      store: MemoryLinkStore(),
      nodeFactory: (identity, relays) async =>
          _WrongRemoteNode(network.node(identity.id), node.id),
    );
    addTearDown(phone.dispose);
    final offer = PairingOffer(
      name: '电脑',
      key: expected.publicKey,
      token: randomBytes(16),
      expires: DateTime.now().add(const Duration(minutes: 1)),
    );
    await expectLater(
      phone.pair(offer.uri),
      throwsA(isA<LinkClosedException>()),
    );
    expect(phone.desktops, isEmpty);
    expect(node.connections.single.isClosed, isTrue);
  });
}

class _FailingStore extends MemoryLinkStore {
  bool fail = false;
  @override
  Future<void> write(String key, String value) {
    if (fail && key == 'desktops') throw StateError('保存失败');
    return super.write(key, value);
  }
}

class _WrongRemoteNode implements LinkNode {
  _WrongRemoteNode(this.delegate, this.wrongId);
  final LinkNode delegate;
  final String wrongId;
  @override
  String get id => delegate.id;
  @override
  Stream<LinkConnection> get incoming => delegate.incoming;
  @override
  Stream<LinkNodeInfo> get changes => delegate.changes;
  @override
  Future<LinkConnection> connect(
    LinkAddress address, {
    Duration timeout = const Duration(seconds: 15),
  }) => delegate.connect(LinkAddress(wrongId), timeout: timeout);
  @override
  Future<LinkNodeInfo> info() => delegate.info();
  @override
  void networkChanged() => delegate.networkChanged();
  @override
  Future<void> close() => delegate.close();
}
