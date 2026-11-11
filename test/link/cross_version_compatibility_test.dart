import 'dart:async';

import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/link/phone_link.dart';
import 'package:baocode_mobile/state/app_state.dart';
import 'package:baocode_mobile/ui/tasks/quota_panel.dart';
import 'package:flutter_test/flutter_test.dart';

/// 只使用合成数据与内存网络的电脑端：按构造参数模拟旧 v2、纯官方和个人定制三种宿主。
class _Host {
  _Host(
    MemoryLinkNetwork network, {
    this.device,
    this.quotaError,
    this.quota,
    this.bots = const [],
  }) {
    node = network.node(identity.id);
    node.incoming.listen((connection) {
      unawaited(LinkPeer.accept(connection, onRequest: handle).then(peers.add));
    });
  }

  late final MemoryLinkNode node;
  final identity = LinkIdentity.generate();
  final peers = <LinkPeer>[];
  final calls = <String>[];
  final quotaParams = <Map<String, Object?>>[];
  final Map<String, Object?>? device;
  final String? quotaError;
  final Map<String, Object?>? quota;
  final List<LinkBot> bots;
  bool trusted = false;

  PairingOffer offer({bool direct = false}) => PairingOffer(
    name: 'Host',
    key: identity.publicKey,
    token: randomBytes(16),
    expires: DateTime.now().add(const Duration(minutes: 5)),
    addrs: const ['127.0.0.1:47100'],
    direct: direct,
  );

  Future<Object?> handle(String method, Map<String, Object?> params) async {
    calls.add(method);
    switch (method) {
      case LinkMethods.hello:
        if (!trusted && !params.containsKey('token')) {
          throw const LinkRemoteException('unpaired', 'Not trusted');
        }
        return {'device': ?device, if (!trusted) 'pairing': true};
      case LinkMethods.confirm:
        trusted = true;
        return {'device': ?device};
      case LinkMethods.state:
        final map = <String, Object?>{
          'projects': <Object?>[],
          'device': ?device,
        };
        if (bots.isNotEmpty) map['bots'] = [for (final b in bots) b.toJson()];
        return map;
      case LinkMethods.quota:
        quotaParams.add(Map.of(params));
        if (quotaError != null) {
          throw LinkRemoteException(quotaError!, 'No such request: $method');
        }
        return quota;
      case 'ping':
        return {'pong': params['n']};
      default:
        throw LinkRemoteException('unknown', 'No such request: $method');
    }
  }

  Future<void> close() async {
    for (final peer in peers) {
      await peer.close();
    }
    await node.close();
  }
}

void main() {
  final network = MemoryLinkNetwork();
  final binds = <List<String>>[];
  final hosts = <_Host>[];
  final states = <AppState>[];
  final controllers = <QuotaController>[];

  Future<LinkNode> bind(LinkIdentity identity, List<String> relays) async {
    binds.add(List.of(relays));
    return network.node(identity.id, relays: relays);
  }

  _Host newHost({
    Map<String, Object?>? device,
    String? quotaError,
    Map<String, Object?>? quota,
    List<LinkBot> bots = const [],
  }) {
    final host = _Host(
      network,
      device: device,
      quotaError: quotaError,
      quota: quota,
      bots: bots,
    );
    hosts.add(host);
    return host;
  }

  Future<AppState> pairedState(_Host host, {bool direct = false}) async {
    final state = AppState(
      store: MemoryLinkStore(),
      link: PhoneLink(store: MemoryLinkStore(), nodeFactory: bind),
    );
    states.add(state);
    final attempt = await state.link.pair(host.offer(direct: direct).uri);
    await state.link.confirmPairing(attempt);
    final id = state.link.desktops.single.id;
    final end = DateTime.now().add(const Duration(seconds: 5));
    while (state.snapshots[id] == null) {
      if (DateTime.now().isAfter(end)) fail('等待首个状态快照超时');
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    return state;
  }

  QuotaController quotaOf(AppState state) {
    final controller = QuotaController(
      state,
      state.link.desktops.single.id,
      'session-1',
    );
    controllers.add(controller);
    return controller;
  }

  setUp(binds.clear);
  tearDown(() async {
    for (final controller in controllers) {
      controller.dispose();
    }
    controllers.clear();
    for (final state in states) {
      state.dispose();
    }
    states.clear();
    for (final host in hosts) {
      await host.close();
    }
    hosts.clear();
  });

  group('跨版本组合（合成宿主，不接真实电脑或共享中继）', () {
    test(
      '旧 v2：hello/state 无 direct、relays、notices，额度 unknown，配对和基础聊天请求仍可用',
      () async {
        final host = newHost(device: {'name': 'Old'}, quotaError: 'unknown');
        final state = await pairedState(host);
        final id = state.link.desktops.single.id;

        final saved = state.link.desktops.single;
        expect(saved.direct, isFalse);
        expect(saved.relaysPublished, isFalse);
        expect(state.bots, isEmpty);
        expect(await state.request(id, 'ping', {'n': 1}), {'pong': 1});

        final quota = quotaOf(state);
        await quota.load();
        expect(quota.unsupported, isTrue);
        expect(quota.failed, isFalse);
        expect(await state.request(id, 'ping', {'n': 2}), {'pong': 2});
        expect(state.isOnline(id), isTrue);
      },
    );

    for (final code in ['unknown', 'unsupported']) {
      test('纯官方桌面额度返回 $code：额度显示不支持，基础请求不受影响', () async {
        final host = newHost(
          device: {'name': 'Official', 'relays': <String>[]},
          quotaError: code,
        );
        final state = await pairedState(host);
        final id = state.link.desktops.single.id;
        final quota = quotaOf(state);
        await quota.load();
        expect(quota.unsupported, isTrue);
        expect(quota.accounts('chatgpt'), isEmpty);
        expect(host.quotaParams, hasLength(1));
        await quota.load();
        expect(host.quotaParams, hasLength(1), reason: '已判定不支持后不重复请求');
        expect(await state.request(id, 'ping', {'n': 3}), {'pong': 3});
      });
    }

    test('个人定制桌面额度可用，刷新参数按原契约传递', () async {
      final host = newHost(
        device: {'name': 'Custom', 'relays': <String>[]},
        quota: {
          'providers': [
            {
              'id': 'chatgpt',
              'name': 'ChatGPT',
              'accounts': [
                {
                  'id': 'a',
                  'displayName': '合成账号',
                  'current': true,
                  'enabled': true,
                  'at': DateTime.now().millisecondsSinceEpoch,
                  'windows': [
                    {'minutes': 300, 'leftPercent': 53},
                  ],
                },
              ],
            },
          ],
        },
      );
      final state = await pairedState(host);
      final quota = quotaOf(state);
      await quota.load();
      expect(quota.unsupported, isFalse);
      expect(quota.failed, isFalse);
      expect(quota.accounts('chatgpt').single['displayName'], '合成账号');
      expect(host.quotaParams.single['session'], 'session-1');
      expect(host.quotaParams.single.containsKey('refresh'), isFalse);
      await quota.load(refresh: true);
      expect(host.quotaParams.last['refresh'], isTrue);
    });

    test('direct + notices：不绑定中继即可配对并聊天，通知随状态进入 Bot', () async {
      final host = newHost(
        device: {'name': 'Direct', 'relays': <String>[], 'direct': true},
        quotaError: 'unknown',
        bots: [
          LinkBot(
            id: 'watcher',
            name: '看门狗',
            notices: [
              LinkBotNotice(
                id: 7,
                kind: 'done',
                chat: 'chat-1',
                title: '合成任务',
                project: '合成项目',
              ),
            ],
          ),
        ],
      );
      final state = await pairedState(host, direct: true);
      final id = state.link.desktops.single.id;
      expect(binds, [<String>[]]);
      expect(state.link.desktops.single.direct, isTrue);
      expect(state.link.desktops.single.dialRelays, isEmpty);
      expect(state.bots.single.bot.notices.single.id, 7);
      expect(state.bots.single.bot.notices.single.project, '合成项目');
      expect(await state.request(id, 'ping', {'n': 4}), {'pong': 4});
      final quota = quotaOf(state);
      await quota.load();
      expect(quota.unsupported, isTrue);
      expect(binds, hasLength(1));
    });
  });
}
