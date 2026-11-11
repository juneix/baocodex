import 'dart:async';
import 'dart:convert';

import 'package:bao_link/bao_link_io.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:baocode_mobile/link/phone_link.dart';
import 'package:baocode_mobile/state/app_state.dart';

import '../../tool/fixture_desktop.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUpAll(() {
    for (final name in [
      'local.baocode.mobile/platform',
      'local.baocode.mobile/discovery',
    ]) {
      messenger.setMockMethodCallHandler(
        MethodChannel(name),
        (_) async => null,
      );
    }
  });
  tearDownAll(() {
    for (final name in [
      'local.baocode.mobile/platform',
      'local.baocode.mobile/discovery',
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(name), null);
    }
  });
  late AppState state;
  late fixture.FixtureDesktop server;
  late PhoneLink phone;
  late String desktop;

  setUp(() async {
    final network = MemoryLinkNetwork();
    final identity = LinkIdentity.generate();
    server = await fixture.FixtureDesktop.start(
      identity: identity,
      node: network.node(identity.id),
    );
    final offer = server.offer;
    final store = MemoryLinkStore();
    phone = PhoneLink(
      store: store,
      nodeFactory: (identity, relays) async => network.node(identity.id),
    );
    state = AppState(store: store, link: phone);
    await state.initialize();
    final attempt = await phone.pair(offer.uri);
    await phone.confirmPairing(attempt);
    desktop = attempt.desktopId;
    await phone.call(desktop, LinkMethods.open, {'session': 'fixture-session'});
  });

  tearDown(() async {
    state.dispose();
    await server.close();
  });

  test(
    'pagination keeps wire indexes when a live reply arrives through AppState',
    () async {
      await state.openSession(desktop, 'fixture-long');
      final buffer = state.buffer(desktop, 'fixture-long');
      expect(buffer.items, hasLength(60));
      await state.loadEarlier(desktop, 'fixture-long');
      expect(buffer.items, hasLength(110));
      expect((buffer.items.first as Map)['text'], '分页测试消息 11');

      final received = Completer<void>();
      void changed() {
        if (buffer.items.isNotEmpty &&
            (buffer.items.last as Map)['text'] ==
                '已收到本地测试消息：paged-live。没有调用模型或执行代码。' &&
            !received.isCompleted) {
          received.complete();
        }
      }

      state.addListener(changed);
      addTearDown(() => state.removeListener(changed));
      await state.sendMessage(
        desktop,
        session: 'fixture-long',
        text: 'paged-live',
      );
      await received.future.timeout(const Duration(seconds: 2));
      expect(buffer.items, hasLength(112));
      expect((buffer.items.first as Map)['text'], '分页测试消息 11');
      await state.loadEarlier(desktop, 'fixture-long');
      expect(buffer.items, hasLength(122));
      expect((buffer.items.first as Map)['text'], '分页测试消息 1');
      await state.closeSession(desktop, 'fixture-long');
    },
  );

  test('retained sessions resume live updates after reconnect without a new open from UI', () async {
    await state.openSession(desktop, 'fixture-long');
    final buffer = state.buffer(desktop, 'fixture-long');
    await phone.reconnect(desktop);
    final received = Completer<void>();
    void changed() {
      if (buffer.items.isNotEmpty &&
          (buffer.items.last as Map)['text'] ==
              '已收到本地测试消息：reconnected-live。没有调用模型或执行代码。' &&
          !received.isCompleted) {
        received.complete();
      }
    }

    state.addListener(changed);
    addTearDown(() => state.removeListener(changed));
    await state.sendMessage(
      desktop,
      session: 'fixture-long',
      text: 'reconnected-live',
    );
    await received.future.timeout(const Duration(seconds: 2));
    expect(state.isOnline(desktop), isTrue);
    expect(buffer.error, isNull);
    await state.closeSession(desktop, 'fixture-long');
  });

  test('缺失流式基线时自动重新打开已订阅会话', () async {
    await state.openSession(desktop, 'fixture-session');
    await pumpEventQueue();
    final before = server.calls
        .where((method) => method == LinkMethods.open)
        .length;
    server.peers.single.emit(LinkEvents.session, {
      'session': 'fixture-session',
      'partial': true,
      'start': 99999,
      'count': 99999,
      'items': [],
    });
    await pumpEventQueue(times: 50);
    expect(
      server.calls.where((method) => method == LinkMethods.open).length,
      before + 1,
    );
    expect(state.buffer(desktop, 'fixture-session').error, isNull);
    expect(state.buffer(desktop, 'fixture-session').items, isNotEmpty);
    await state.closeSession(desktop, 'fixture-session');
  });

  test(
    'custom bot can be created, messaged, edited, cleared, and deleted',
    () async {
      final created = await state.request(desktop, LinkMethods.saveBot, {
        'name': 'Functional test bot',
        'identity': 'Synthetic bot only',
        'abilities': ['agents'],
      }) as Map;
      final bot = (created['bot'] as Map)['id'] as String;
      expect(state.bots.any((ref) => ref.bot.id == bot), isTrue);
      final sent = await state.sendMessage(desktop, bot: bot, text: 'bot-live');
      expect(sent, bot);
      final snapshot = await state.request(desktop, LinkMethods.open, {
        'session': bot,
      }) as Map;
      expect((snapshot['items'] as List).last, {
        't': 'text',
        'text': '已收到本地测试消息：bot-live。没有调用模型或执行代码。',
      });
      await state.request(desktop, LinkMethods.saveBot, {
        'bot': bot,
        'name': 'Renamed test bot',
      });
      expect(
        state.bots.firstWhere((ref) => ref.bot.id == bot).bot.name,
        'Renamed test bot',
      );
      await state.request(desktop, LinkMethods.setBotMemory, {
        'bot': bot,
        'text': 'memory marker',
      });
      await state.request(desktop, LinkMethods.setBotSelf, {
        'bot': bot,
        'text': 'self marker',
      });
      expect(
        await state.request(desktop, LinkMethods.botMemory, {'bot': bot}),
        {'text': 'memory marker', 'self': 'self marker'},
      );
      await state.request(desktop, LinkMethods.clearBotChat, {'bot': bot});
      final cleared = await state.request(desktop, LinkMethods.open, {
        'session': bot,
      }) as Map;
      expect(cleared['items'], isEmpty);
      await expectLater(
        state.request(desktop, LinkMethods.deleteBot, {'bot': 'fixture-bot'}),
        throwsA(isA<LinkRemoteException>()),
      );
      await state.request(desktop, LinkMethods.deleteBot, {'bot': bot});
      expect(state.bots.any((ref) => ref.bot.id == bot), isFalse);
    },
  );

  test('encrypted edit preserves the window prefix, payload and rejects invalid indexes', () async {
    await state.openSession(desktop, 'fixture-long');
    final buffer = state.buffer(desktop, 'fixture-long');
    expect(buffer.items, hasLength(60));
    await state.loadEarlier(desktop, 'fixture-long');
    expect(buffer.items, hasLength(110));
    expect((buffer.items.first as Map)['text'], '分页测试消息 11');

    await phone.call(desktop, LinkMethods.send, {
      'session': 'fixture-long',
      'text': 'history boundary',
    });
    await state.refreshSession(desktop, 'fixture-long');
    final actualWireIndex = buffer.items.indexWhere(
      (item) => item is Map && item['text'] == 'history boundary',
    );
    expect(actualWireIndex, greaterThanOrEqualTo(0));
    final sent = <Map<String, Object?>>[];
    for (var i = 0; i < 6; i++) {
      await state.sendMessage(
        desktop,
        session: 'fixture-long',
        text: 'edit target $i',
        images: [
          {'name': 'sample.png', 'mediaType': 'image/png', 'data': 'AA=='},
        ],
        mentions: const ['lib/main.dart'],
      );
      final item = buffer.items.firstWhere(
        (item) => item is Map && item['text'] == 'edit target $i',
      ) as Map;
      sent.add(Map<String, Object?>.from(item));
    }
    expect(buffer.items.length, greaterThan(actualWireIndex + 1));
    expect(sent.first['images'], isNotEmpty);

    await phone.call(desktop, LinkMethods.edit, {
      'session': 'fixture-long',
      'index': actualWireIndex + 2,
      'text': 'edited target',
      'images': sent.first['images'],
      'mentions': ['lib/main.dart'],
    });
    await state.refreshSession(desktop, 'fixture-long');
    final editedIndex = buffer.items.indexWhere(
      (item) => item is Map && item['text'] == 'edited target',
    );
    expect(editedIndex, greaterThanOrEqualTo(0));
    expect((buffer.items[editedIndex] as Map)['images'], sent.first['images']);
    expect((buffer.items[editedIndex] as Map)['mentions'], ['lib/main.dart']);
    expect(buffer.items.length, 114);
    final full = await phone.call(desktop, LinkMethods.open, {
      'session': 'fixture-long',
      'window': 1000,
    }) as Map;
    final allItems = full['items'] as List;
    expect(allItems, hasLength(124));
    expect((allItems[120] as Map)['text'], 'history boundary');
    expect((allItems[122] as Map)['text'], 'edited target');

    await expectLater(
      phone.call(desktop, LinkMethods.edit, {
        'session': 'fixture-long',
        'index': 99999,
        'text': 'unknown index',
      }),
      throwsA(isA<LinkRemoteException>()),
    );
    await state.closeSession(desktop, 'fixture-long');
  });

  test(
    'background completion invokes native notification without message content',
    () async {
      final notification = Completer<Map<Object?, Object?>>();
      messenger.setMockMethodCallHandler(
        const MethodChannel('local.baocode.mobile/platform'),
        (call) async {
          if (call.method == 'notify' && !notification.isCompleted) {
            notification.complete(
              Map<Object?, Object?>.from(call.arguments as Map),
            );
          }
          return null;
        },
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          const MethodChannel('local.baocode.mobile/platform'),
          (_) async => null,
        ),
      );
      state.foreground = false;
      await state.sendMessage(
        desktop,
        session: 'fixture-session',
        text: 'notify probe',
      );
      final posted = await notification.future.timeout(
        const Duration(seconds: 3),
      );
      // 通知写对话标题和电脑名，不写发出的内容。
      expect(posted['title'], '聊天与文件预览');
      expect(posted['body'], '${state.desktopName(desktop)} · Turn completed');
      expect(jsonEncode(posted), isNot(contains('notify probe')));
      expect(posted['id'], isA<int>());
    },
  );
}
