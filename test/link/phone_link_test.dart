import 'dart:async';
import 'dart:convert';

import 'package:bao_link/bao_link.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:baocode_mobile/link/phone_link.dart';
import 'package:baocode_mobile/models/user_facing_error.dart';

class _Desktop {
  _Desktop([MemoryLinkNetwork? network])
    : network = network ?? MemoryLinkNetwork() {
    node = this.network.node(identity.id);
    node.incoming.listen((connection) {
      connections++;
      unawaited(LinkPeer.accept(connection, onRequest: handle).then(peers.add));
    });
  }

  final MemoryLinkNetwork network;
  late final MemoryLinkNode node;
  final identity = LinkIdentity.generate();
  final peers = <LinkPeer>[];
  final calls = <String>[];
  Map<String, Object?>? hello;
  bool approvalRequired = false;
  bool trusted = false;
  bool failWrites = false;
  bool hangNextState = false;
  Completer<void>? approval;
  int connections = 0;
  String address = '127.0.0.1:47200';

  PairingOffer get offer => PairingOffer(
    name: 'Workstation',
    key: identity.publicKey,
    token: randomBytes(16),
    expires: DateTime.now().add(const Duration(minutes: 5)),
    addrs: const ['127.0.0.1:47100'],
  );

  Future<LinkNode> nodeFactory(
    LinkIdentity identity,
    List<String> relays,
  ) async => network.node(identity.id);

  Future<Object?> handle(String method, Map<String, Object?> params) async {
    calls.add(method);
    switch (method) {
      case LinkMethods.hello:
        hello = params;
        if (!trusted &&
            !params.containsKey('token') &&
            params['request'] != true) {
          throw const LinkRemoteException('unpaired', 'Not trusted');
        }
        return {
          'device': {
            'name': 'Actual desktop',
            'relays': ['https://relay.example.test'],
            'addrs': [address],
          },
          if (!trusted) 'pairing': true,
          if (approvalRequired) 'approval': true,
        };
      case LinkMethods.confirm:
        if (approvalRequired) {
          await (approval ??= Completer<void>()).future;
        }
        trusted = true;
        return {
          'device': {'name': 'Actual desktop'},
        };
      case LinkMethods.state:
        if (hangNextState) {
          hangNextState = false;
          await Completer<void>().future;
        }
        return {'projects': <Object?>[], 'source': identity.id};
      case LinkMethods.open:
        return {
          'session': params['session'],
          'start': 0,
          'count': 1,
          'items': [
            {'t': 'text', 'text': '初始'},
          ],
          'live': true,
        };
      case LinkMethods.unpair:
        trusted = false;
        return null;
      default:
        if (failWrites) {
          throw const LinkRemoteException('failed', 'Write failed');
        }
        return {'received': params};
    }
  }

  Future<void> close() async {
    for (final peer in peers) {
      await peer.close();
    }
    await node.close();
  }
}

class _Storage extends MemoryLinkStore {
  bool fail = false;
  bool failAfterGate = false;
  int writes = 0;
  Completer<void>? gate;
  final started = Completer<void>();

  @override
  Future<void> write(String key, String value) async {
    if (key == 'desktops') {
      writes++;
      final pending = gate;
      if (pending != null) {
        gate = null;
        started.complete();
        await pending.future;
        await super.write(key, value);
        fail = failAfterGate;
        return;
      }
      if (fail) throw StateError('合成存储失败');
    }
    await super.write(key, value);
  }
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 30));

void main() {
  test('desktop records validate their pinned identity and round trip', () {
    final identity = LinkIdentity.generate();
    final desktop = KeptDesktop(
      id: deviceIdOf(identity.publicKey),
      name: 'Desk',
      publicKey: encodeKey(identity.publicKey),
      addresses: const ['host:47100'],
    );
    expect(KeptDesktop.fromJson(desktop.toJson()).toJson(), desktop.toJson());
    expect(desktop.copyWith(name: 'New').id, desktop.id);
    expect(
      () => KeptDesktop.fromJson({...desktop.toJson(), 'id': 'impostor'}),
      throwsFormatException,
    );
  });

  test(
    'identity is generated once and persisted across initialization',
    () async {
      final store = MemoryLinkStore();
      final phone = PhoneLink(store: store);
      await Future.wait([phone.initialize(), phone.initialize()]);
      final identity = await store.read('identity');
      expect(identity, isNotNull);
      phone.dispose();
      final next = PhoneLink(store: store);
      await next.initialize();
      expect(await store.read('identity'), identity);
      next.dispose();
    },
  );

  test(
    'QR pairing uses encrypted hello and only persists after confirmation',
    () async {
      final desktop = _Desktop();
      final store = MemoryLinkStore();
      final phone = PhoneLink(store: store, nodeFactory: desktop.nodeFactory);
      addTearDown(() async {
        phone.dispose();
        await desktop.close();
      });
      final offer = desktop.offer;
      final attempt = await phone.pair(offer.uri);
      expect(phone.desktops, isEmpty);
      expect(await store.read('desktops'), isNull);
      expect(attempt.name, 'Actual desktop');
      expect(desktop.hello!['token'], encodeKey(offer.token));
      // 电脑端「已配对的手机」直接显示这两个值。
      expect(desktop.hello!['name'], 'BaoCodeX');
      expect(desktop.hello!['system'], isNotEmpty);
      final phoneIdentity = LinkIdentity.fromJson(
        Map<String, Object?>.from(
          jsonDecode((await store.read('identity'))!) as Map,
        ),
      )!;
      expect(
        attempt.safetyCode,
        safetyCode(desktop.identity.publicKey, phoneIdentity.publicKey),
      );
      await phone.confirmPairing(attempt);
      expect(phone.onlineIds, {attempt.desktopId});
      expect(phone.states[attempt.desktopId]!['projects'], isEmpty);
      expect(jsonDecode((await store.read('desktops'))!), hasLength(1));
    },
  );

  test('重置密钥：通知在线电脑解除配对，换新指纹，所有电脑需重新配对', () async {
    final desktop = _Desktop();
    final store = MemoryLinkStore();
    final phone = PhoneLink(store: store, nodeFactory: desktop.nodeFactory);
    addTearDown(() async {
      phone.dispose();
      await desktop.close();
    });
    final attempt = await phone.pair(desktop.offer.uri);
    await phone.confirmPairing(attempt);
    final before = phone.fingerprint;
    final storedBefore = await store.read('identity');
    expect(before, isNotNull);
    expect(phone.onlineIds, {attempt.desktopId});

    await phone.resetIdentity();

    expect(desktop.calls, contains(LinkMethods.unpair));
    expect(phone.fingerprint, isNot(before));
    expect(await store.read('identity'), isNot(storedBefore));
    expect(phone.onlineIds, isEmpty);
    expect(phone.statusOf(attempt.desktopId), DesktopLinkStatus.needsPairing);
    final saved = jsonDecode((await store.read('desktops'))!) as List;
    expect(saved.single['kind'], 'legacy');
  });

  test(
    'saved desktops reconnect with the same identity and no QR token',
    () async {
      final desktop = _Desktop();
      final store = MemoryLinkStore();
      final first = PhoneLink(store: store, nodeFactory: desktop.nodeFactory);
      final attempt = await first.pair(desktop.offer.uri);
      await first.confirmPairing(attempt);
      final identity = await store.read('identity');
      first.dispose();
      final next = PhoneLink(store: store, nodeFactory: desktop.nodeFactory);
      addTearDown(() async {
        next.dispose();
        await desktop.close();
      });
      await next.initialize();
      await _settle();
      expect(next.onlineIds, {attempt.desktopId});
      expect(next.pathOf(attempt.desktopId).kind, LinkPathKind.lan);
      expect(next.pathOf('unknown'), LinkPath.none);
      expect(desktop.hello, isNot(contains('token')));
      expect(await store.read('identity'), identity);
    },
  );

  for (final changed in [false, true]) {
    test('已信任桌面重连不依赖地址持久化成功：地址变化=$changed', () async {
      final desktop = _Desktop();
      final store = _Storage();
      final phone = PhoneLink(store: store, nodeFactory: desktop.nodeFactory);
      addTearDown(() async {
        phone.dispose();
        await desktop.close();
      });
      final attempt = await phone.pair(desktop.offer.uri);
      await phone.confirmPairing(attempt);
      final before = await store.read('desktops');
      final writes = store.writes;
      store.fail = true;
      if (changed) desktop.address = '127.0.0.1:47300';
      await phone.reconnect(attempt.desktopId);
      expect(phone.onlineIds, {attempt.desktopId});
      expect(await store.read('desktops'), before);
      expect(store.writes, writes + (changed ? 1 : 0));
      expect(phone.desktops.single.addresses, contains(desktop.address));
      expect(phone.hasUnsavedAddress(attempt.desktopId), changed);
      store.fail = false;
      await phone.reconnect(attempt.desktopId);
      expect(phone.hasUnsavedAddress(attempt.desktopId), isFalse);
      if (changed) {
        expect((await store.read('desktops'))!, contains('127.0.0.1:47300'));
      }
    });
  }

  test('回到前台时连接已死但还没发现：探测超时后立刻重连，不等空闲超时', () async {
    final desktop = _Desktop();
    final phone = PhoneLink(
      store: MemoryLinkStore(),
      nodeFactory: desktop.nodeFactory,
    );
    addTearDown(() async {
      phone.dispose();
      await desktop.close();
    });
    final attempt = await phone.pair(desktop.offer.uri);
    await phone.confirmPairing(attempt);
    await _settle();
    final before = desktop.connections;
    desktop.hangNextState = true;
    await phone.verifyConnections(timeout: const Duration(milliseconds: 40));
    await _settle();
    expect(desktop.connections, before + 1);
    expect(phone.statusOf(attempt.desktopId), DesktopLinkStatus.online);
  });

  test('回到前台时连接正常：不重连，也不闪“连接中”', () async {
    final desktop = _Desktop();
    final phone = PhoneLink(
      store: MemoryLinkStore(),
      nodeFactory: desktop.nodeFactory,
    );
    addTearDown(() async {
      phone.dispose();
      await desktop.close();
    });
    final attempt = await phone.pair(desktop.offer.uri);
    await phone.confirmPairing(attempt);
    await _settle();
    final before = desktop.connections;
    final seen = <DesktopLinkStatus>[];
    phone.addListener(() => seen.add(phone.statusOf(attempt.desktopId)));
    await phone.verifyConnections();
    await _settle();
    expect(desktop.connections, before);
    expect(seen, isNot(contains(DesktopLinkStatus.connecting)));
  });

  test('连接状态：断开后先是连接中，多次失败才算未连接，手动重试回到连接中', () async {
    final desktop = _Desktop();
    final phone = PhoneLink(
      store: MemoryLinkStore(),
      nodeFactory: desktop.nodeFactory,
    );
    addTearDown(() async {
      phone.dispose();
      await desktop.close();
    });
    final attempt = await phone.pair(desktop.offer.uri);
    await phone.confirmPairing(attempt);
    await _settle();
    final id = attempt.desktopId;
    expect(phone.statusOf(id), DesktopLinkStatus.online);

    await desktop.close();
    await _settle();
    expect(phone.onlineIds, isEmpty);
    expect(
      phone.statusOf(id),
      DesktopLinkStatus.connecting,
      reason: '刚断开，正在自动重试',
    );

    // 连续失败后不再假装“连接中”。
    for (var i = 0; i < 3; i++) {
      await phone.reconnect(id);
    }
    expect(phone.statusOf(id), DesktopLinkStatus.offline);

    final seen = <DesktopLinkStatus>[];
    phone.addListener(() => seen.add(phone.statusOf(id)));
    await phone.reconnect(id);
    expect(seen.first, DesktopLinkStatus.connecting, reason: '手动重试');
    expect(phone.statusOf(id), DesktopLinkStatus.offline);

    // 后台自动重试失败多次后不再来回闪。
    seen.clear();
    await phone.reconnect(id, background: true);
    expect(seen, isNot(contains(DesktopLinkStatus.connecting)));
  });

  test('慢写期间取消配对成功时已持久化撤销记录', () async {
    final desktop = _Desktop();
    final gate = Completer<void>();
    final store = _Storage()..gate = gate;
    final phone = PhoneLink(store: store, nodeFactory: desktop.nodeFactory);
    addTearDown(() async {
      phone.dispose();
      await desktop.close();
    });
    final attempt = await phone.pair(desktop.offer.uri);
    final confirmation = expectLater(
      phone.confirmPairing(attempt),
      throwsStateError,
    );
    await store.started.future;
    final cancellation = phone.cancelPairing(attempt);
    gate.complete();
    await cancellation;
    await confirmation;
    expect(jsonDecode((await store.read('desktops'))!), isEmpty);
    expect(phone.desktops, isEmpty);
    expect(phone.onlineIds, isEmpty);
  });

  test('取消配对等待慢写结束，回滚失败时不能报告取消成功', () async {
    final desktop = _Desktop();
    final gate = Completer<void>();
    final store = _Storage()
      ..gate = gate
      ..failAfterGate = true;
    final phone = PhoneLink(store: store, nodeFactory: desktop.nodeFactory);
    addTearDown(() async {
      phone.dispose();
      await desktop.close();
    });
    final attempt = await phone.pair(desktop.offer.uri);
    final confirmed = phone.confirmPairing(attempt);
    final confirmation = expectLater(
      confirmed,
      throwsA(isA<PairingStorageException>()),
    );
    await store.started.future;
    final cancelled = phone.cancelPairing(attempt);
    var returned = false;
    cancelled.then<void>((_) {
      returned = true;
    }, onError: (Object _) {});
    await pumpEventQueue();
    final returnedBeforeSave = returned;
    gate.complete();
    await confirmation;
    await expectLater(cancelled, throwsA(isA<PairingStorageException>()));
    expect(returnedBeforeSave, isFalse);
    expect(phone.onlineIds, isEmpty);
  });

  test('按公钥配对后保存 hello 中的新地址与中继', () async {
    final desktop = _Desktop();
    final phone = PhoneLink(
      store: MemoryLinkStore(),
      nodeFactory: desktop.nodeFactory,
    );
    addTearDown(() async {
      phone.dispose();
      await desktop.close();
    });
    final attempt = await phone.pair(desktop.offer.uri);
    await phone.confirmPairing(attempt);
    expect(
      phone.desktops.single.relays,
      contains('https://relay.example.test'),
    );
    expect(phone.desktops.single.addresses, contains('127.0.0.1:47200'));
    expect(phone.desktops.single.needsPairing, isFalse);
  });

  test('流式精简补丁经镜像还原，缺失基线时请求重新同步', () async {
    final desktop = _Desktop();
    final phone = PhoneLink(
      store: MemoryLinkStore(),
      nodeFactory: desktop.nodeFactory,
    );
    addTearDown(() async {
      phone.dispose();
      await desktop.close();
    });
    final attempt = await phone.pair(desktop.offer.uri);
    await phone.confirmPairing(attempt);
    await phone.call(attempt.desktopId, LinkMethods.open, {'session': 's'});
    await pumpEventQueue();
    final update = phone.events.firstWhere((e) => e.name == LinkEvents.session);
    desktop.peers.last.emit(LinkEvents.session, {
      'session': 's',
      'partial': true,
      'start': 1,
      'count': 1,
      'items': [],
      'append': {
        'index': 0,
        'path': ['text'],
        'text': '追加',
      },
    });
    final received = (await update).params as Map;
    expect(received['live'], isTrue);
    expect(received['items'], [
      {'t': 'text', 'text': '初始追加'},
    ]);
    final resync = phone.events.firstWhere((e) => e.name == LinkEvents.resync);
    desktop.peers.last.emit(LinkEvents.session, {
      'session': 'missing',
      'partial': true,
      'start': 1,
      'count': 1,
      'items': [],
    });
    expect((await resync).params, {'session': 'missing'});
  });

  test('expired QR codes never reach the connector', () async {
    final desktop = _Desktop();
    final phone = PhoneLink(
      store: MemoryLinkStore(),
      nodeFactory: desktop.nodeFactory,
    );
    addTearDown(phone.dispose);
    final offer = PairingOffer(
      name: 'Expired',
      key: desktop.identity.publicKey,
      token: randomBytes(16),
      expires: DateTime.now().subtract(const Duration(seconds: 1)),
    );
    await expectLater(phone.pair(offer.uri), throwsFormatException);
    expect(desktop.connections, 0);
  });

  test(
    'desktop approval blocks confirmation and cancellation never trusts it',
    () async {
      final desktop = _Desktop()..approvalRequired = true;
      final store = MemoryLinkStore();
      final phone = PhoneLink(store: store, nodeFactory: desktop.nodeFactory);
      addTearDown(() async {
        phone.dispose();
        await desktop.close();
      });
      final attempt = await phone.pair(desktop.offer.uri);
      final confirmed = phone.confirmPairing(attempt);
      final assertion = expectLater(
        confirmed,
        throwsA(isA<LinkClosedException>()),
      );
      await _settle();
      expect(phone.desktops, isEmpty);
      await phone.cancelPairing(attempt);
      await assertion;
      desktop.approval?.complete();
      expect(await store.read('desktops'), isNull);
    },
  );

  test('multiple desktops keep raw states and adapt event.data without replaying calls', () async {
    final network = MemoryLinkNetwork();
    final a = _Desktop(network);
    final b = _Desktop(network);
    final phone = PhoneLink(
      store: MemoryLinkStore(),
      nodeFactory: a.nodeFactory,
    );
    addTearDown(() async {
      phone.dispose();
      await a.close();
      await b.close();
    });
    final first = await phone.pair(a.offer.uri);
    await phone.confirmPairing(first);
    final second = await phone.pair(b.offer.uri);
    await phone.confirmPairing(second);
    expect(phone.states.keys.toSet(), {first.desktopId, second.desktopId});
    await pumpEventQueue();
    final event = phone.events.first;
    a.peers.last.emit('session', {
      'session': 's',
      'start': 0,
      'count': 0,
      'items': [],
    });
    final received = await event;
    expect(received.desktopId, first.desktopId);
    expect(received.name, 'session');
    expect(received.params, {
      'session': 's',
      'start': 0,
      'count': 0,
      'items': [],
    });
    a.failWrites = true;
    await expectLater(
      phone.call(first.desktopId, 'send', {'text': 'once'}),
      throwsA(isA<LinkRemoteException>()),
    );
    expect(a.calls.where((m) => m == 'send'), hasLength(1));
    await phone.forget(first.desktopId);
    expect(phone.onlineIds, {second.desktopId});
    expect(a.calls, contains(LinkMethods.unpair));
  });

  testWidgets('connection failures back off and forgetting cancels timers', (
    tester,
  ) async {
    final desktop = _Desktop();
    final kept = KeptDesktop(
      id: deviceIdOf(desktop.identity.publicKey),
      name: 'Offline',
      publicKey: encodeKey(desktop.identity.publicKey),
      addresses: const ['host:47100'],
    );
    final store = MemoryLinkStore();
    await store.write('identity', jsonEncode(LinkIdentity.generate().toJson()));
    await store.write('desktops', jsonEncode([kept.toJson()]));
    var attempts = 0;
    final phone = PhoneLink(
      store: store,
      nodeFactory: (identity, relays) async {
        attempts++;
        throw StateError('offline');
      },
    );
    await phone.initialize();
    await tester.pump();
    expect(attempts, 1);
    await tester.pump(const Duration(seconds: 2));
    expect(attempts, 2);
    await tester.pump(const Duration(seconds: 3));
    expect(attempts, 2);
    await tester.pump(const Duration(seconds: 1));
    expect(attempts, 3);
    await phone.forget(kept.id);
    expect(jsonDecode((await store.read('desktops'))!), isEmpty);
    await tester.pump(const Duration(seconds: 30));
    expect(attempts, 3);
    phone.dispose();
  });

  test('desktop approval must complete before the desktop is saved', () async {
    final desktop = _Desktop()..approvalRequired = true;
    final store = MemoryLinkStore();
    final phone = PhoneLink(store: store, nodeFactory: desktop.nodeFactory);
    addTearDown(() async {
      phone.dispose();
      await desktop.close();
    });
    final attempt = await phone.pair(desktop.offer.uri);
    final confirmed = phone.confirmPairing(attempt);
    await _settle();
    expect(await store.read('desktops'), isNull);
    desktop.approval!.complete();
    await confirmed;
    expect(phone.onlineIds, {attempt.desktopId});
  });

  test('dispose closes a node arriving from an in-flight factory', () async {
    final desktop = _Desktop();
    final gate = Completer<LinkNode>();
    final phone = PhoneLink(
      store: MemoryLinkStore(),
      nodeFactory: (identity, relays) => gate.future,
    );
    await phone.initialize();
    final pending = phone.pair(desktop.offer.uri);
    final assertion = expectLater(pending, throwsStateError);
    await _settle();
    phone.dispose();
    final node = desktop.network.node(LinkIdentity.generate().id);
    gate.complete(node);
    await assertion;
    await expectLater(
      node.connect(desktop.offer.address),
      throwsA(isA<LinkClosedException>()),
    );
  });

  test('附近发现用 v2 公钥配对，网络变化通知已有端点', () async {
    final desktop = _Desktop();
    late MemoryLinkNode node;
    final phone = PhoneLink(
      store: MemoryLinkStore(),
      nodeFactory: (identity, relays) async =>
          node = desktop.network.node(identity.id),
    );
    addTearDown(() async {
      phone.dispose();
      await desktop.close();
    });
    final attempt = await phone.pairNearby(
      LinkAdvert(
        name: '附近电脑',
        key: desktop.identity.publicKey,
        port: 47100,
        pairing: true,
        addresses: ['127.0.0.1'],
      ),
    );
    expect(desktop.hello!['request'], isTrue);
    expect(desktop.hello!.containsKey('token'), isFalse);
    await phone.confirmPairing(attempt);
    phone.networkChanged();
    expect(node.networkChanges, 1);
    await phone.updateAddresses(attempt.desktopId, [
      ' [::1]:47100 ',
      '127.0.0.1:47100',
    ]);
    expect(phone.desktops.single.addresses, ['[::1]:47100', '127.0.0.1:47100']);
    await expectLater(
      phone.updateAddresses(attempt.desktopId, ['wss://example.com']),
      throwsA(isA<UserFacingError>()),
    );
  });

  test('在手机上改名只记在本机，重连时电脑公布的名字不会盖回来', () async {
    final desktop = _Desktop();
    final store = _Storage();
    final phone = PhoneLink(store: store, nodeFactory: desktop.nodeFactory);
    addTearDown(() async {
      phone.dispose();
      await desktop.close();
    });
    final attempt = await phone.pair(desktop.offer.uri);
    await phone.confirmPairing(attempt);
    await _settle();
    final original = phone.desktops.single.name;
    expect(original, isNotEmpty);

    await phone.renameDesktop(attempt.desktopId, '  书房的台式机  ');
    expect(phone.desktops.single.name, '书房的台式机');
    expect(phone.desktops.single.renamed, isTrue);
    // 存下来，重启后还是这个名字。
    expect(await store.read('desktops'), contains('书房的台式机'));

    // 改回空名说不通，保持原样。
    await expectLater(
      phone.renameDesktop(attempt.desktopId, '   '),
      throwsArgumentError,
    );
    expect(phone.desktops.single.name, '书房的台式机');
  });

  test('域名地址保存失败回滚，不在内存伪造已保存', () async {
    final desktop = _Desktop();
    final store = _Storage();
    final phone = PhoneLink(store: store, nodeFactory: desktop.nodeFactory);
    addTearDown(() async {
      phone.dispose();
      await desktop.close();
    });
    final attempt = await phone.pair(desktop.offer.uri);
    await phone.confirmPairing(attempt);
    await _settle();
    final before = phone.desktops.single.addresses.toList();
    store.fail = true;
    await expectLater(
      phone.updateAddresses(attempt.desktopId, ['desk.example.test:47100']),
      throwsStateError,
    );
    expect(phone.desktops.single.addresses, before);
  });

  test('已在线连接检查复用认证连接，只读取状态，不重发 hello', () async {
    final desktop = _Desktop();
    final phone = PhoneLink(
      store: MemoryLinkStore(),
      nodeFactory: desktop.nodeFactory,
    );
    addTearDown(() async {
      phone.dispose();
      await desktop.close();
    });
    final attempt = await phone.pair(desktop.offer.uri);
    await phone.confirmPairing(attempt);
    await _settle();
    final connections = desktop.connections;
    desktop.calls.clear();
    await phone.checkConnection(attempt.desktopId);
    expect(desktop.connections, connections);
    expect(desktop.calls, [LinkMethods.state]);
  });

  test('电脑撤销授权后连接检查报告失败，不伪造在线成功', () async {
    final desktop = _Desktop();
    final phone = PhoneLink(
      store: MemoryLinkStore(),
      nodeFactory: desktop.nodeFactory,
    );
    addTearDown(() async {
      phone.dispose();
      await desktop.close();
    });
    final attempt = await phone.pair(desktop.offer.uri);
    await phone.confirmPairing(attempt);
    desktop.trusted = false;
    for (final peer in desktop.peers.toList()) {
      await peer.close();
    }
    await _settle();
    await expectLater(
      phone.checkConnection(attempt.desktopId),
      throwsA(isA<LinkRemoteException>()),
    );
    expect(phone.onlineIds, isEmpty);
  });

  test('disposed instances reject pairing without notifying', () async {
    final desktop = _Desktop();
    final phone = PhoneLink(
      store: MemoryLinkStore(),
      nodeFactory: desktop.nodeFactory,
    );
    var notifications = 0;
    phone.addListener(() => notifications++);
    await phone.initialize();
    final before = notifications;
    phone.dispose();
    await expectLater(phone.pair(desktop.offer.uri), throwsStateError);
    expect(notifications, before);
    await desktop.close();
  });
}
