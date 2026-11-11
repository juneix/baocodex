import 'dart:async';
import 'dart:convert';

import 'package:bao_link/bao_link.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:baocode_mobile/link/phone_link.dart';

const _r1 = 'https://r1.example.test';
const _r2 = 'https://r2.example.test';
const _r3 = 'https://r3.example.test';
const _stale = 'https://stale.example.test';

/// 记录每次绑定的中继、拨号地址与关闭状态的内存节点。
class _SpyNode implements LinkNode {
  _SpyNode(this.inner, this.relays);

  final MemoryLinkNode inner;
  final List<String> relays;
  final dialed = <LinkAddress>[];
  bool closed = false;
  Completer<void>? closeGate;
  final closeStarted = Completer<void>();

  @override
  String get id => inner.id;
  @override
  Stream<LinkConnection> get incoming => inner.incoming;
  @override
  Stream<LinkNodeInfo> get changes => inner.changes;
  @override
  Future<LinkNodeInfo> info() => inner.info();
  @override
  void networkChanged() => inner.networkChanged();

  @override
  Future<LinkConnection> connect(
    LinkAddress address, {
    Duration timeout = const Duration(seconds: 15),
  }) {
    dialed.add(address);
    return inner.connect(address, timeout: timeout);
  }

  @override
  Future<void> close() async {
    closed = true;
    if (!closeStarted.isCompleted) closeStarted.complete();
    final gate = closeGate;
    if (gate != null) await gate.future;
    await inner.close();
  }
}

class _Binder {
  final network = MemoryLinkNetwork();
  final binds = <List<String>>[];
  final nodes = <_SpyNode>[];
  final _gates = <int, Completer<void>>{};
  final _started = <int, Completer<void>>{};
  final _closeGates = <int, Completer<void>>{};

  Completer<void> holdClose(int index) =>
      _closeGates[index] = Completer<void>();

  Completer<void> hold(int index) => _gates[index] = Completer<void>();
  Future<void> started(int index) =>
      (_started[index] ??= Completer<void>()).future;

  Future<LinkNode> call(LinkIdentity identity, List<String> relays) async {
    final index = binds.length;
    binds.add(List.of(relays));
    (_started[index] ??= Completer<void>()).complete();
    final gate = _gates[index];
    if (gate != null) await gate.future;
    final node = _SpyNode(network.node(identity.id, relays: relays), relays);
    node.closeGate = _closeGates[index];
    nodes.add(node);
    return node;
  }

  _SpyNode get last => nodes.last;
  Iterable<LinkAddress> get dialed => [for (final n in nodes) ...n.dialed];
  LinkAddress dialedTo(String id) => dialed.lastWhere((a) => a.id == id);
}

class _Host {
  _Host(MemoryLinkNetwork network, {this.trusted = true}) {
    node = network.node(identity.id);
    node.incoming.listen((connection) {
      unawaited(LinkPeer.accept(connection, onRequest: handle).then(peers.add));
    });
  }

  late final MemoryLinkNode node;
  final identity = LinkIdentity.generate();
  final peers = <LinkPeer>[];
  final calls = <String>[];
  bool trusted;
  Map<String, Object?>? device = {
    'name': 'Host',
    'addrs': ['127.0.0.1:47100'],
  };
  Map<String, Object?>? Function()? hello;
  Completer<void>? holdSend;

  String get id => deviceIdOf(identity.publicKey);

  PairingOffer offer({List<String> relays = const [], bool direct = false}) =>
      PairingOffer(
        name: 'Host',
        key: identity.publicKey,
        token: randomBytes(16),
        expires: DateTime.now().add(const Duration(minutes: 5)),
        relays: relays,
        addrs: const ['127.0.0.1:47100'],
        direct: direct,
      );

  Map<String, Object?> saved({
    bool? direct,
    List<String> relays = const [],
    bool published = false,
  }) => {
    'id': id,
    'name': 'Saved',
    'publicKey': encodeKey(identity.publicKey),
    'addresses': ['127.0.0.1:47100'],
    'relays': relays,
    'kind': LinkIdentity.kind,
    'needsPairing': false,
    'direct': ?direct,
    if (published) 'relaysPublished': true,
  };

  Future<Object?> handle(String method, Map<String, Object?> params) async {
    calls.add(method);
    switch (method) {
      case LinkMethods.hello:
        if (!trusted &&
            !params.containsKey('token') &&
            params['request'] != true) {
          throw const LinkRemoteException('unpaired', 'Not trusted');
        }
        return {'device': ?device, if (!trusted) 'pairing': true};
      case LinkMethods.confirm:
        trusted = true;
        return {'device': ?device};
      case LinkMethods.state:
        return {'projects': <Object?>[], 'device': ?device};
      case LinkMethods.send:
        await holdSend?.future;
        return {'ok': true};
      default:
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

class _Store extends MemoryLinkStore {
  bool failDesktops = false;
  Completer<void>? failAfter;
  final writing = <Completer<void>>[];

  @override
  Future<void> write(String key, String value) async {
    if (failDesktops && key == 'desktops') throw StateError('合成存储失败');
    final gate = failAfter;
    if (gate != null && key == 'desktops') {
      failAfter = null;
      writing.add(gate);
      await gate.future;
      throw StateError('合成延迟存储失败');
    }
    await super.write(key, value);
  }
}

Future<MemoryLinkStore> _seed(
  List<Map<String, Object?>> desktops, [
  MemoryLinkStore? store,
]) async {
  store ??= MemoryLinkStore();
  await store.write('identity', jsonEncode(LinkIdentity.generate().toJson()));
  await store.write('desktops', jsonEncode(desktops));
  return store;
}

Future<void> _until(bool Function() ready, [String reason = '条件']) async {
  final end = DateTime.now().add(const Duration(seconds: 5));
  while (!ready()) {
    if (DateTime.now().isAfter(end)) fail('等待超时：$reason');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Future<void> _quiet() => Future<void>.delayed(const Duration(milliseconds: 80));

void main() {
  late _Binder binder;
  final phones = <PhoneLink>[];
  final hosts = <_Host>[];

  setUp(() => binder = _Binder());
  tearDown(() async {
    for (final phone in phones) {
      phone.dispose();
    }
    phones.clear();
    for (final host in hosts) {
      await host.close();
    }
    hosts.clear();
  });

  _Host newHost({bool trusted = true}) {
    final host = _Host(binder.network, trusted: trusted);
    hosts.add(host);
    return host;
  }

  PhoneLink newPhone([MemoryLinkStore? store]) {
    final phone = PhoneLink(
      store: store ?? MemoryLinkStore(),
      nodeFactory: binder.call,
    );
    phones.add(phone);
    return phone;
  }

  group('KeptDesktop 持久化 direct', () {
    test('direct 与是否已由电脑公布中继可往返保存，旧记录按 false 读取', () {
      final host = newHost();
      final direct = KeptDesktop.fromJson(
        host.saved(direct: true, relays: [_stale]),
      );
      expect(direct.toJson()['direct'], isTrue);
      expect(KeptDesktop.fromJson(direct.toJson()).toJson(), direct.toJson());
      final legacy = KeptDesktop.fromJson(host.saved());
      expect(legacy.toJson()['direct'], isFalse);
      final published = KeptDesktop.fromJson(host.saved(published: true));
      expect(published.toJson()['relaysPublished'], isTrue);
    });
  });

  group('手机端点绑定的中继', () {
    test('direct 二维码在节点绑定前就不使用任何中继，拨号目标也不带中继', () async {
      final host = newHost(trusted: false)
        ..device = {
          'name': 'Host',
          'relays': <String>[],
          'addrs': ['127.0.0.1:47100'],
          'direct': true,
        };
      final phone = newPhone();
      final attempt = await phone.pair(
        host.offer(relays: [_stale], direct: true).uri,
      );
      expect(binder.binds, [<String>[]]);
      expect(binder.dialedTo(host.id).relays, isEmpty);
      await phone.confirmPairing(attempt);
      expect(phone.desktops.single.toJson()['direct'], isTrue);
      expect(phone.desktops.single.relays, isEmpty);
      expect(binder.binds, hasLength(1));
      expect(phone.onlineIds, {host.id});
    });

    test('所有已信任设备 direct 时启动节点不绑定中继', () async {
      final a = newHost()..device = _direct;
      final b = newHost()..device = _direct;
      final store = await _seed([
        a.saved(direct: true, relays: [_stale]),
        b.saved(direct: true, relays: [_r1]),
      ]);
      final phone = newPhone(store);
      await phone.initialize();
      await _until(() => phone.onlineIds.length == 2, '两台 direct 电脑上线');
      expect(binder.binds, [<String>[]]);
      expect(binder.dialedTo(a.id).relays, isEmpty);
      expect(binder.dialedTo(b.id).relays, isEmpty);
    });

    test('混合设备只绑定非 direct 设备的中继并集，direct 拨号目标不带中继', () async {
      final a = newHost()
        ..device = {
          'name': 'A',
          'relays': [_r1, _r2],
        };
      final c = newHost()
        ..device = {
          'name': 'C',
          'relays': [_r2, _r3],
        };
      final b = newHost()..device = _direct;
      final store = await _seed([
        a.saved(relays: [_r1, _r2], published: true),
        c.saved(relays: [_r2, _r3], published: true),
        b.saved(direct: true, relays: [_stale]),
      ]);
      final phone = newPhone(store);
      await phone.initialize();
      await _until(() => phone.onlineIds.length == 3, '三台电脑上线');
      expect(binder.binds, hasLength(1));
      expect(binder.binds.single.toSet(), {_r1, _r2, _r3});
      expect(binder.dialedTo(b.id).relays, isEmpty);
      expect(binder.dialedTo(a.id).relays, [_r1, _r2]);
    });

    test('direct 变回非 direct：官方 hello 省略 false 但给出 relays 时可切回', () async {
      final host = newHost()
        ..device = {
          'name': 'Host',
          'relays': [_r1],
        };
      final store = await _seed([
        host.saved(direct: true, relays: [_stale]),
      ]);
      final phone = newPhone(store);
      await phone.initialize();
      await _until(
        () => binder.binds.length == 2 && phone.onlineIds.isNotEmpty,
        '改回中继后重建并上线',
      );
      expect(binder.binds, [
        <String>[],
        [_r1],
      ]);
      expect(binder.nodes.first.closed, isTrue);
      final desktop = phone.desktops.single;
      expect(desktop.toJson()['direct'], isFalse);
      expect(desktop.relays, [_r1]);
      final persisted = jsonDecode((await store.read('desktops'))!) as List;
      expect((persisted.single as Map)['direct'], isFalse);
    });

    test('明确空 relays 不补默认中继，并在重启后依旧保持', () async {
      final host = newHost()..device = {'name': 'Host', 'relays': <String>[]};
      final store = await _seed([host.saved()]);
      final phone = newPhone(store);
      await phone.initialize();
      await _until(
        () => binder.binds.length == 2 && phone.onlineIds.isNotEmpty,
        '收到空列表后去掉默认中继',
      );
      expect(binder.binds, [defaultLinkRelays, <String>[]]);
      expect(phone.desktops.single.relays, isEmpty);
      expect(binder.dialedTo(host.id).relays, isEmpty);
      phone.dispose();

      final restarted = newPhone(store);
      await restarted.initialize();
      await _until(() => restarted.onlineIds.isNotEmpty, '重启后上线');
      expect(binder.binds.last, isEmpty);
      expect(binder.binds, hasLength(3));
    });

    test('旧端 hello 不带任何策略字段仍可聊天，且不触发重建', () async {
      final host = newHost()..device = {'name': 'Old'};
      final store = await _seed([host.saved()]);
      final phone = newPhone(store);
      await phone.initialize();
      await _until(() => phone.onlineIds.isNotEmpty, '旧端上线');
      expect(binder.binds, [defaultLinkRelays]);
      expect(phone.desktops.single.toJson()['direct'], isFalse);
      final reply = await phone.call(host.id, 'ping', {'x': 1}) as Map;
      expect(reply['received'], {'x': 1});
      await _quiet();
      expect(binder.binds, hasLength(1));
    });

    test('hello 完全没有 device 对象的更旧端也能上线', () async {
      final host = newHost()..device = null;
      final phone = newPhone(await _seed([host.saved()]));
      await phone.initialize();
      await _until(() => phone.onlineIds.isNotEmpty, '无 device 的旧端上线');
      expect(binder.binds, [defaultLinkRelays]);
    });

    test('手动保存的中继只在电脑未公布策略前作为提示，公布后被替换不合并', () async {
      final host = newHost()..device = {'name': 'Host'};
      final store = await _seed([
        host.saved(relays: [_stale]),
      ]);
      final phone = newPhone(store);
      await phone.initialize();
      await _until(() => phone.onlineIds.isNotEmpty, '使用手动提示上线');
      expect(binder.binds, [
        [_stale],
      ]);
      expect(binder.dialedTo(host.id).relays, [_stale]);

      host.device = {
        'name': 'Host',
        'relays': [_r2],
      };
      await phone.reconnect(host.id);
      await _until(
        () => binder.binds.length == 2 && phone.onlineIds.isNotEmpty,
        '公布后替换',
      );
      expect(phone.desktops.single.relays, [_r2]);
      expect(binder.binds.last, [_r2]);
      expect(binder.nodes.first.closed, isTrue);
    });

    test('hello 中已撤销的中继不会被并回', () async {
      final host = newHost()
        ..device = {
          'name': 'Host',
          'relays': [_r2],
        };
      final store = await _seed([
        host.saved(relays: [_r1, _r2], published: true),
      ]);
      final phone = newPhone(store);
      await phone.initialize();
      await _until(
        () => binder.binds.length == 2 && phone.onlineIds.isNotEmpty,
        '撤销后重建',
      );
      expect(phone.desktops.single.relays, [_r2]);
      expect(binder.binds.last, [_r2]);
    });

    test('state 快照里电脑策略变化时同样协调端点', () async {
      final host = newHost()
        ..device = {
          'name': 'Host',
          'relays': [_r1],
        };
      final store = await _seed([
        host.saved(relays: [_r1], published: true),
      ]);
      final phone = newPhone(store);
      await phone.initialize();
      await _until(() => phone.onlineIds.isNotEmpty, '上线');
      expect(binder.binds, [
        [_r1],
      ]);
      host.device = _direct;
      host.peers.single.emit(LinkEvents.state, {
        'projects': <Object?>[],
        'device': _direct,
      });
      await _until(
        () => binder.binds.length == 2 && phone.onlineIds.isNotEmpty,
        'state 触发的重建',
      );
      expect(binder.binds.last, isEmpty);
      expect(phone.desktops.single.toJson()['direct'], isTrue);
    });
  });

  group('临时配对策略与回滚', () {
    test('取消配对后恢复先前的端点策略并关闭为候选创建的节点', () async {
      final a = newHost()
        ..device = {
          'name': 'A',
          'relays': [_r1],
        };
      final b = newHost(trusted: false)
        ..device = {
          'name': 'B',
          'relays': [_r2],
        };
      final store = await _seed([
        a.saved(relays: [_r1], published: true),
      ]);
      final phone = newPhone(store);
      await phone.initialize();
      await _until(() => phone.onlineIds.contains(a.id), 'A 上线');
      final attempt = await phone.pair(b.offer(relays: [_r2]).uri);
      expect(binder.binds.last.toSet(), {_r1, _r2});
      await phone.cancelPairing(attempt);
      await _until(
        () =>
            binder.binds.last.toSet().length == 1 &&
            phone.onlineIds.contains(a.id),
        '取消后恢复到 A 的策略',
      );
      expect(binder.binds.last, [_r1]);
      expect(binder.last.closed, isFalse);
      expect(phone.desktops.map((d) => d.id), [a.id]);
    });

    test('保存失败时恢复先前策略且不留下新电脑', () async {
      final a = newHost()
        ..device = {
          'name': 'A',
          'relays': [_r1],
        };
      final b = newHost(trusted: false)
        ..device = {
          'name': 'B',
          'relays': [_r2],
        };
      final store = _Store();
      await _seed([
        a.saved(relays: [_r1], published: true),
      ], store);
      final phone = newPhone(store);
      await phone.initialize();
      await _until(() => phone.onlineIds.contains(a.id), 'A 上线');
      final attempt = await phone.pair(b.offer(relays: [_r2]).uri);
      store.failDesktops = true;
      await expectLater(phone.confirmPairing(attempt), throwsStateError);
      store.failDesktops = false;
      await _until(
        () => binder.binds.last.length == 1 && phone.onlineIds.contains(a.id),
        '保存失败后恢复',
      );
      expect(binder.binds.last, [_r1]);
      expect(phone.desktops.map((d) => d.id), [a.id]);
    });

    test('没有任何已信任电脑时取消 direct 配对会释放端点，之后按默认策略重新绑定', () async {
      final host = newHost(trusted: false)..device = _direct;
      final phone = newPhone();
      final attempt = await phone.pair(host.offer(direct: true).uri);
      expect(binder.binds, [<String>[]]);
      await phone.cancelPairing(attempt);
      await _until(() => binder.nodes.first.closed, '临时节点被释放');
      final other = newHost(trusted: false);
      await phone.pair(other.offer().uri);
      expect(binder.binds, [<String>[], defaultLinkRelays]);
    });
  });

  group('附近配对的临时拨号策略', () {
    LinkAdvert advert(_Host host) => LinkAdvert(
      name: 'Nearby',
      key: host.identity.publicKey,
      port: 47100,
      pairing: true,
      addresses: const ['127.0.0.1'],
    );

    test('没有已有电脑时，附近 direct 电脑的首次绑定与拨号地址都不带中继，hello 后策略准确', () async {
      final host = newHost(trusted: false)..device = _direct;
      final phone = newPhone();
      final attempt = await phone.pairNearby(advert(host));
      expect(binder.binds, [<String>[]]);
      expect(binder.dialedTo(host.id).relays, isEmpty);
      await phone.confirmPairing(attempt);
      expect(binder.binds, hasLength(1));
      final desktop = phone.desktops.single;
      expect(desktop.toJson()['direct'], isTrue);
      expect(desktop.relays, isEmpty);
      expect(desktop.toJson()['relaysPublished'], isFalse);
      expect(phone.onlineIds, {host.id});
    });

    test('附近非 direct 电脑 hello 公布中继后，确认时才改用其中继', () async {
      final host = newHost(trusted: false)
        ..device = {
          'name': 'Host',
          'relays': [_r1],
        };
      final phone = newPhone();
      final attempt = await phone.pairNearby(advert(host));
      expect(binder.binds, [<String>[]]);
      expect(binder.dialedTo(host.id).relays, isEmpty);
      await phone.confirmPairing(attempt);
      await _until(
        () => binder.binds.length == 2 && phone.onlineIds.isNotEmpty,
        '确认后按公布策略重建',
      );
      expect(binder.binds.last, [_r1]);
      expect(binder.nodes.first.closed, isTrue);
      expect(phone.desktops.single.relays, [_r1]);
    });

    test('全部已保存电脑 direct 时，未知附近候选不会让共享节点连默认中继', () async {
      final a = newHost()..device = _direct;
      final nearby = newHost(trusted: false)
        ..device = {
          'name': 'N',
          'relays': [_r1],
        };
      final store = await _seed([a.saved(direct: true)]);
      final phone = newPhone(store);
      await phone.initialize();
      await _until(() => phone.onlineIds.contains(a.id), 'direct 电脑上线');
      final attempt = await phone.pairNearby(advert(nearby));
      expect(binder.binds, [<String>[]]);
      expect(binder.nodes.single.closed, isFalse);
      expect(binder.dialedTo(nearby.id).relays, isEmpty);
      await phone.cancelPairing(attempt);
      await _quiet();
      expect(binder.binds, hasLength(1));
      expect(phone.onlineIds, {a.id});
    });

    test('已有非 direct 电脑时共享端点保持其中继，附近目标仍无中继拨号，取消后配置不变', () async {
      final a = newHost()
        ..device = {
          'name': 'A',
          'relays': [_r1],
        };
      final nearby = newHost(trusted: false)..device = {'name': 'N'};
      final store = await _seed([
        a.saved(relays: [_r1], published: true),
      ]);
      final phone = newPhone(store);
      await phone.initialize();
      await _until(() => phone.onlineIds.contains(a.id), 'A 上线');
      final attempt = await phone.pairNearby(advert(nearby));
      expect(binder.binds, [
        [_r1],
      ]);
      expect(binder.dialedTo(nearby.id).relays, isEmpty);
      await phone.cancelPairing(attempt);
      await _quiet();
      expect(binder.binds, hasLength(1));
      expect(binder.nodes.single.closed, isFalse);
      expect(phone.onlineIds, {a.id});
    });

    test('已保存 direct 的电脑再次附近配对不丢失其策略', () async {
      final a = newHost(trusted: false)..device = {'name': 'A'};
      final store = await _seed([
        a.saved(direct: true, relays: [_stale]),
      ]);
      final phone = newPhone(store);
      await phone.initialize();
      await _until(() => binder.nodes.isNotEmpty, '初始节点');
      final attempt = await phone.pairNearby(advert(a));
      expect(binder.binds, [<String>[]]);
      expect(binder.dialedTo(a.id).relays, isEmpty);
      await phone.confirmPairing(attempt);
      await _quiet();
      final desktop = phone.desktops.single;
      expect(desktop.toJson()['direct'], isTrue);
      expect(desktop.relays, [_stale]);
      expect(desktop.dialRelays, isEmpty);
      expect(binder.dialed.every((address) => address.relays.isEmpty), isTrue);
    });

    test('旧 v2 附近电脑不公布任何策略时仍可确认并聊天，确认后回退内置中继', () async {
      final host = newHost(trusted: false)..device = {'name': 'Old'};
      final phone = newPhone();
      final attempt = await phone.pairNearby(advert(host));
      expect(binder.binds, [<String>[]]);
      await phone.confirmPairing(attempt);
      await _until(
        () => binder.binds.length == 2 && phone.onlineIds.isNotEmpty,
        '回退兼容中继并上线',
      );
      expect(binder.binds.last, defaultLinkRelays);
      final desktop = phone.desktops.single;
      expect(desktop.toJson()['direct'], isFalse);
      expect(desktop.toJson()['relaysPublished'], isFalse);
      final reply = await phone.call(host.id, 'ping', {'x': 1}) as Map;
      expect(reply['received'], {'x': 1});
    });

    test('需要重新配对且没有任何策略的已存记录：hello 前只走局域网，确认后可重启重连', () async {
      final host = newHost(trusted: false)..device = {'name': 'Old'};
      final record = host.saved()..['needsPairing'] = true;
      final store = await _seed([record]);
      final phone = newPhone(store);
      await phone.initialize();
      await _quiet();
      expect(binder.binds, isEmpty);
      final attempt = await phone.pairNearby(advert(host));
      expect(binder.binds, [<String>[]]);
      expect(binder.dialedTo(host.id).relays, isEmpty);
      final before = phone.desktops.single;
      expect(before.needsPairing, isTrue);
      expect(before.relays, isEmpty);
      await phone.confirmPairing(attempt);
      final saved =
          (jsonDecode((await store.read('desktops'))!) as List).single as Map;
      expect(saved['needsPairing'], isFalse);
      expect(saved['direct'], isFalse);
      expect(saved['relays'], isEmpty);
      expect(saved['relaysPublished'], isFalse);
      await _until(
        () => binder.binds.length == 2 && phone.onlineIds.isNotEmpty,
        '旧端无策略，确认后回退兼容中继并上线',
      );
      expect(binder.binds.last, defaultLinkRelays);

      final restarted = newPhone(store);
      await restarted.initialize();
      await _until(() => restarted.onlineIds.contains(host.id), '重启后重连');
      expect(restarted.desktops.single.needsPairing, isFalse);
    });

    Future<List<dynamic>> savedRecords(MemoryLinkStore store) async =>
        jsonDecode((await store.read('desktops'))!) as List;

    test('需要重新配对且残留中继：hello 前绑定与拨号都不带中继，确认后持久化 hello 公布的策略', () async {
      final host = newHost(trusted: false)
        ..device = {
          'name': 'Host',
          'relays': [_r2],
        };
      final record = host.saved(relays: [_r1], published: true)
        ..['needsPairing'] = true;
      final store = await _seed([record]);
      final phone = newPhone(store);
      await phone.initialize();
      await _quiet();
      expect(binder.binds, isEmpty);
      final attempt = await phone.pairNearby(advert(host));
      expect(binder.binds, [<String>[]]);
      expect(binder.dialedTo(host.id).relays, isEmpty);
      expect(phone.desktops.single.relays, [_r1], reason: '拨号临时值不改动已存记录');
      await phone.confirmPairing(attempt);
      final saved = (await savedRecords(store)).single as Map;
      expect(saved['needsPairing'], isFalse);
      expect(saved['direct'], isFalse);
      expect(saved['relays'], [_r2]);
      expect(saved['relaysPublished'], isTrue);
      await _until(
        () => binder.binds.length == 2 && phone.onlineIds.isNotEmpty,
        '确认后按 hello 公布的策略重建',
      );
      expect(binder.binds.last, [_r2]);
    });

    test('需要重新配对且残留 direct 与中继：hello 前不带中继，hello 公布中继后以公布为准', () async {
      final host = newHost(trusted: false)
        ..device = {
          'name': 'Host',
          'relays': [_r2],
        };
      final record = host.saved(direct: true, relays: [_stale])
        ..['needsPairing'] = true;
      final store = await _seed([record]);
      final phone = newPhone(store);
      await phone.initialize();
      await _quiet();
      final attempt = await phone.pairNearby(advert(host));
      expect(binder.binds, [<String>[]]);
      expect(binder.dialedTo(host.id).relays, isEmpty);
      await phone.confirmPairing(attempt);
      final saved = (await savedRecords(store)).single as Map;
      expect(saved['needsPairing'], isFalse);
      expect(saved['direct'], isFalse);
      expect(saved['relays'], [_r2]);
      await _until(
        () => binder.binds.length == 2 && phone.onlineIds.isNotEmpty,
        '确认后按公布策略重建',
      );
      expect(binder.binds.last, [_r2]);
    });

    test('需要重新配对且残留中继，hello 缺字段（旧 v2）：hello 前不带中继，确认后沿用既有策略', () async {
      final host = newHost(trusted: false)..device = {'name': 'Old'};
      final record = host.saved(relays: [_r1])..['needsPairing'] = true;
      final store = await _seed([record]);
      final phone = newPhone(store);
      await phone.initialize();
      await _quiet();
      final attempt = await phone.pairNearby(advert(host));
      expect(binder.binds, [<String>[]]);
      expect(binder.dialedTo(host.id).relays, isEmpty);
      await phone.confirmPairing(attempt);
      final saved = (await savedRecords(store)).single as Map;
      expect(saved['needsPairing'], isFalse);
      expect(saved['direct'], isFalse);
      expect(saved['relays'], [_r1], reason: '旧端不公布策略，沿用记录里的既有策略');
      expect(saved['relaysPublished'], isFalse);
      await _until(
        () => binder.binds.length == 2 && phone.onlineIds.isNotEmpty,
        '确认后按既有策略重建',
      );
      expect(binder.binds.last, [_r1]);
    });

    test('没有任何电脑时取消附近配对会释放临时端点', () async {
      final host = newHost(trusted: false)..device = _direct;
      final phone = newPhone();
      final attempt = await phone.pairNearby(advert(host));
      await phone.cancelPairing(attempt);
      await _until(() => binder.nodes.first.closed, '临时节点被释放');
    });
  });

  group('生命周期', () {
    test('慢绑定被新配置取代时关闭迟到节点，只保留最新配置', () async {
      final a = newHost()
        ..device = {
          'name': 'A',
          'relays': [_r1],
        };
      final b = newHost(trusted: false)
        ..device = {
          'name': 'B',
          'relays': [_r2],
        };
      final gate = binder.hold(0);
      final store = await _seed([
        a.saved(relays: [_r1], published: true),
      ]);
      final phone = newPhone(store);
      await phone.initialize();
      await binder.started(0);
      final pairing = phone.pair(b.offer(relays: [_r2]).uri);
      await _quiet();
      gate.complete();
      final attempt = await pairing;
      expect(binder.nodes.first.relays, [_r1]);
      expect(binder.nodes.first.closed, isTrue);
      expect(binder.binds.last.toSet(), {_r1, _r2});
      expect(binder.last.closed, isFalse);
      await phone.cancelPairing(attempt);
    });

    test('慢绑定期间取消配对，迟到节点被关闭且不再触发新绑定', () async {
      final a = newHost();
      final gate = binder.hold(0);
      final store = await _seed([
        a.saved(relays: [_r1], published: true),
      ]);
      final phone = newPhone(store);
      await phone.initialize();
      await binder.started(0);
      final forgotten = phone.forget(a.id);
      await _quiet();
      gate.complete();
      await forgotten;
      await _until(() => binder.nodes.isNotEmpty && binder.nodes.first.closed);
      await _quiet();
      expect(binder.binds, hasLength(1));
      expect(phone.onlineIds, isEmpty);
    });

    test('dispose 时关闭迟到节点，且不再写回状态或通知', () async {
      final a = newHost();
      final gate = binder.hold(0);
      final store = await _seed([
        a.saved(relays: [_r1], published: true),
      ]);
      final phone = newPhone(store);
      await phone.initialize();
      await binder.started(0);
      var notifications = 0;
      phone.addListener(() => notifications++);
      phone.dispose();
      gate.complete();
      await _until(() => binder.nodes.isNotEmpty && binder.nodes.first.closed);
      await _quiet();
      expect(notifications, 0);
      expect(binder.binds, hasLength(1));
      expect(phone.onlineIds, isEmpty);
    });

    test('旧端点关闭期间 dispose，不再调用工厂绑定新端点', () async {
      final a = newHost()
        ..device = {
          'name': 'A',
          'relays': [_r1],
        };
      final b = newHost(trusted: false)
        ..device = {
          'name': 'B',
          'relays': [_r2],
        };
      final closing = binder.holdClose(0);
      final store = await _seed([
        a.saved(relays: [_r1], published: true),
      ]);
      final phone = newPhone(store);
      await phone.initialize();
      await _until(() => phone.onlineIds.contains(a.id), 'A 上线');
      expect(binder.binds, hasLength(1));
      final pairing = phone.pair(b.offer(relays: [_r2]).uri);
      final failure = expectLater(pairing, throwsA(isA<StateError>()));
      await binder.nodes.first.closeStarted.future;
      phone.dispose();
      closing.complete();
      await failure;
      await _quiet();
      expect(binder.binds, hasLength(1));
      expect(binder.nodes, hasLength(1));
    });

    test('并发重连在配置不变时复用同一个节点', () async {
      final a = newHost()
        ..device = {
          'name': 'A',
          'relays': [_r1],
        };
      final store = await _seed([
        a.saved(relays: [_r1], published: true),
      ]);
      final phone = newPhone(store);
      await phone.initialize();
      await Future.wait([
        phone.reconnect(a.id),
        phone.reconnect(a.id),
        phone.reconnect(a.id),
      ]);
      await _until(() => phone.onlineIds.isNotEmpty, '上线');
      await _quiet();
      expect(binder.binds, hasLength(1));
      expect(binder.nodes.single.closed, isFalse);
    });

    test('策略切换重建期间不重放进行中的 send', () async {
      final host = newHost()..device = _direct;
      host.holdSend = Completer<void>();
      final store = await _seed([host.saved(direct: true)]);
      final phone = newPhone(store);
      await phone.initialize();
      await _until(() => phone.onlineIds.isNotEmpty, '上线');
      final pending = phone.call(host.id, LinkMethods.send, {'text': 'once'});
      final failure = expectLater(pending, throwsA(isA<LinkClosedException>()));
      await _until(() => host.calls.contains(LinkMethods.send), '写请求已到达');
      host.device = {
        'name': 'Host',
        'relays': [_r1],
      };
      await phone.reconnect(host.id);
      await failure;
      await _until(
        () => binder.binds.length == 2 && phone.onlineIds.isNotEmpty,
        '重建后上线',
      );
      host.holdSend!.complete();
      await _quiet();
      expect(host.calls.where((m) => m == LinkMethods.send), hasLength(1));
    });
  });

  group('电脑策略保存失败的内存标记', () {
    Future<(_Host, _Store, PhoneLink)> online() async {
      final host = newHost()..device = {'name': 'A'};
      final store = _Store();
      await _seed([host.saved()], store);
      final phone = newPhone(store);
      await phone.initialize();
      await _until(() => phone.onlineIds.contains(host.id), '上线');
      return (host, store, phone);
    }

    // 公布的中继与内置回退相同：策略记录变化，但共享端点不需要重建。
    void pushDirect(_Host host) => host.peers.single.emit(LinkEvents.state, {
      'projects': <Object?>[],
      'device': {'name': 'A', 'relays': defaultLinkRelays},
    });

    test('延迟保存失败且电脑仍是当前配置时，才标记未保存并通知', () async {
      final (host, store, phone) = await online();
      var notifications = 0;
      phone.addListener(() => notifications++);
      final gate = store.failAfter = Completer<void>();
      pushDirect(host);
      await _until(() => store.writing.isNotEmpty, '策略保存已开始');
      final before = notifications;
      expect(phone.hasUnsavedAddress(host.id), isFalse);
      gate.complete();
      await _until(() => phone.hasUnsavedAddress(host.id), '失败后出现标记');
      expect(notifications, greaterThan(before));
    });

    test('保存失败回调迟到时，已忘记的电脑不会残留标记也不再通知', () async {
      final (host, store, phone) = await online();
      final gate = store.failAfter = Completer<void>();
      pushDirect(host);
      await _until(() => store.writing.isNotEmpty, '策略保存已开始');
      final forgetting = phone.forget(host.id);
      var notifications = 0;
      phone.addListener(() => notifications++);
      gate.complete();
      await forgetting;
      await _quiet();
      expect(phone.desktops, isEmpty);
      expect(phone.hasUnsavedAddress(host.id), isFalse);
      expect(notifications, 0);
    });

    test('保存失败回调迟到时，已 dispose 的 PhoneLink 不再通知', () async {
      final (host, store, phone) = await online();
      final gate = store.failAfter = Completer<void>();
      pushDirect(host);
      await _until(() => store.writing.isNotEmpty, '策略保存已开始');
      phone.dispose();
      gate.complete();
      await _quiet();
      expect(phone.hasUnsavedAddress(host.id), isFalse);
    });
  });

  group('权威策略分支表', () {
    final cases =
        <
          (
            String,
            Map<String, Object?>,
            Map<String, Object?>,
            bool,
            List<String>,
            bool,
          )
        >[
          (
            'direct=true 忽略同时出现的 relays',
            {
              'direct': true,
              'relays': [_r1],
            },
            {
              'relays': [_stale],
            },
            true,
            <String>[],
            false,
          ),
          (
            'direct=true 且 relays 缺失',
            {'direct': true},
            {
              'relays': [_stale],
            },
            true,
            <String>[],
            false,
          ),
          (
            'direct 缺失 + 非空 relays => 非 direct，使用该列表',
            {
              'relays': [_r1],
            },
            {'direct': true},
            false,
            [_r1],
            true,
          ),
          (
            'direct=false + 非空 relays',
            {
              'direct': false,
              'relays': [_r1],
            },
            {'direct': true},
            false,
            [_r1],
            true,
          ),
          (
            'direct 缺失 + 空 relays => 非 direct 且明确无中继',
            {'relays': <String>[]},
            {
              'relays': [_stale],
            },
            false,
            <String>[],
            true,
          ),
          (
            'direct=false + relays 缺失 => 沿用已保存的中继提示',
            {'direct': false},
            {
              'relays': [_r3],
            },
            false,
            [_r3],
            false,
          ),
          (
            'direct=false + relays 缺失，原为 direct => 无提示，回退默认',
            {'direct': false},
            {'direct': true},
            false,
            <String>[],
            false,
          ),
          (
            '两者都缺失 => 保留既有 direct',
            {'name': 'Host'},
            {'direct': true},
            true,
            <String>[],
            false,
          ),
          (
            '两者都缺失 => 保留既有中继提示',
            {'name': 'Host'},
            {
              'relays': [_r3],
            },
            false,
            [_r3],
            false,
          ),
        ];
    for (final (name, device, saved, direct, relays, published) in cases) {
      test(name, () async {
        final host = newHost()..device = {'name': 'Host', ...device};
        final store = await _seed([
          host.saved(
            direct: saved['direct'] as bool?,
            relays: [...?(saved['relays'] as List?)?.cast<String>()],
          ),
        ]);
        final phone = newPhone(store);
        await phone.initialize();
        await _until(() => phone.onlineIds.isNotEmpty, '上线');
        await _quiet();
        final desktop = phone.desktops.single;
        expect(desktop.toJson()['direct'], direct);
        expect(desktop.relays, relays);
        expect(
          (desktop.toJson()['relaysPublished'] as bool?) ?? false,
          published,
        );
      });
    }
  });
}

const _direct = <String, Object?>{
  'name': 'Direct',
  'relays': <String>[],
  'addrs': ['127.0.0.1:47100'],
  'direct': true,
};
