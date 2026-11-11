import 'dart:async';
import 'dart:convert';

import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/link/phone_link.dart';
import 'package:baocode_mobile/state/app_state.dart';
import 'package:baocode_mobile/theme/app_theme.dart';
import 'package:baocode_mobile/ui/devices/devices_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _longRelay =
    'https://relay-with-a-very-long-host-name.region.example.test:8443';

Future<(AppState, String)> _page(
  WidgetTester tester, {
  bool? direct,
  List<String> relays = const [],
  bool published = false,
  bool textScaled = false,
}) async {
  tester.view.physicalSize = const Size(320, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final identity = LinkIdentity.generate();
  final id = deviceIdOf(identity.publicKey);
  final store = MemoryLinkStore();
  await store.write('identity', jsonEncode(LinkIdentity.generate().toJson()));
  await store.write(
    'desktops',
    jsonEncode([
      {
        'id': id,
        'name': '工作站',
        'publicKey': encodeKey(identity.publicKey),
        'addresses': ['192.168.1.20:47100'],
        'relays': relays,
        'direct': ?direct,
        if (published) 'relaysPublished': true,
        'kind': LinkIdentity.kind,
        'needsPairing': false,
      },
    ]),
  );
  final link = PhoneLink(
    store: store,
    nodeFactory: (identity, relays) => Completer<LinkNode>().future,
  );
  final state = AppState(store: store, link: link);
  state.settings.language = 'zh';
  await link.initialize();
  addTearDown(state.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: MobileTheme.build(Brightness.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScaled ? 1.6 : 1)),
        child: child!,
      ),
      home: DevicePage(state: state, desktopId: id),
    ),
  );
  await tester.pump();
  return (state, id);
}

/// Scrolls the page until [finder] is laid out: the sections below the fold
/// are only built once they come into view.
Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

class _FailingStore extends MemoryLinkStore {
  bool fail = false;

  @override
  Future<void> write(String key, String value) async {
    if (fail && key == 'desktops') throw StateError('合成存储失败');
    await super.write(key, value);
  }
}

void main() {
  testWidgets('设备页展示地址端口和连接测试，允许保存域名地址', (tester) async {
    final (state, id) = await _page(tester, direct: true);
    expect(find.text('连接端口（UDP）'), findsOneWidget);
    expect(find.text('47100'), findsOneWidget);
    expect(find.text('测试连接'), findsOneWidget);
    await reveal(tester, find.text('添加地址'));
    await tester.tap(find.text('添加地址'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Desk.Example.test:47100');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(state.link.desktops.single.addresses, ['desk.example.test:47100']);
    expect(state.link.desktops.single.direct, isTrue);
    expect(state.link.desktops.single.relays, isEmpty);
    expect(state.link.hasUnsavedAddress(id), isFalse);
  });

  testWidgets('direct 电脑显示“仅直连，不使用中继”，中继行不可编辑', (tester) async {
    await _page(tester, direct: true, relays: ['https://stale.example.test']);
    await reveal(tester, find.text('仅直连，不使用中继'));
    expect(find.text('仅直连，不使用中继'), findsOneWidget);
    expect(find.text('https://stale.example.test'), findsNothing);
    await tester.tap(find.text('电脑的中继'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('电脑公布的中继以只读“跟随电脑”展示，长地址不溢出', (tester) async {
    await _page(
      tester,
      relays: [_longRelay, 'https://relay-two.example.test'],
      published: true,
      textScaled: true,
    );
    await reveal(tester, find.text('跟随电脑'));
    expect(find.text('跟随电脑'), findsOneWidget);
    expect(find.textContaining(_longRelay), findsOneWidget);
    await tester.tap(find.text('电脑的中继'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('电脑明确公布空列表时显示“电脑未提供中继”，不冒称仅直连', (tester) async {
    await _page(tester, published: true);
    await reveal(tester, find.text('电脑未提供中继'));
    expect(find.text('电脑未提供中继'), findsOneWidget);
    expect(find.text('仅直连，不使用中继'), findsNothing);
    expect(find.text('自动使用内置中继'), findsNothing);
  });

  testWidgets('电脑尚未公布策略时说明使用内置列表', (tester) async {
    await _page(tester);
    await reveal(tester, find.text('尚未收到电脑的中继策略，暂用内置中继'));
    expect(find.text('尚未收到电脑的中继策略，暂用内置中继'), findsOneWidget);
  });

  testWidgets('旧版保存的中继在电脑公布前不叫“跟随电脑”', (tester) async {
    await _page(tester, relays: ['https://manual.example.test']);
    await reveal(tester, find.text('等待电脑公布'));
    expect(find.text('跟随电脑'), findsNothing);
    expect(find.text('等待电脑公布'), findsOneWidget);
    expect(find.textContaining('旧版保存的提示'), findsOneWidget);
    expect(find.textContaining('手动保存'), findsNothing);
    expect(find.textContaining('https://manual.example.test'), findsOneWidget);
  });

  testWidgets('策略保存失败后，设备页提示地址和中继策略都未保存', (tester) async {
    final hostIdentity = LinkIdentity.generate();
    final id = deviceIdOf(hostIdentity.publicKey);
    final peers = <LinkPeer>[];
    final store = _FailingStore();
    late final MemoryLinkNode hostNode;
    late final PhoneLink link;
    late final AppState state;
    // 内存网络依赖真实微任务，节点与监听必须在 runAsync 内创建。
    await tester.runAsync(() async {
      final network = MemoryLinkNetwork();
      hostNode = network.node(hostIdentity.id);
      hostNode.incoming.listen((connection) {
        unawaited(
          LinkPeer.accept(
            connection,
            onRequest: (method, params) async => {
              'device': {
                'name': '工作站',
                'relays': ['https://published.example.test'],
              },
              'projects': <Object?>[],
            },
          ).then(peers.add),
        );
      });
      await store.write(
        'identity',
        jsonEncode(LinkIdentity.generate().toJson()),
      );
      await store.write(
        'desktops',
        jsonEncode([
          {
            'id': id,
            'name': '工作站',
            'publicKey': encodeKey(hostIdentity.publicKey),
            'addresses': ['192.168.1.20:47100'],
            'relays': <String>[],
            'kind': LinkIdentity.kind,
            'needsPairing': false,
          },
        ]),
      );
      store.fail = true;
      link = PhoneLink(
        store: store,
        nodeFactory: (identity, relays) async =>
            network.node(identity.id, relays: relays),
      );
      state = AppState(store: store, link: link);
      state.settings.language = 'zh';
      await link.initialize();
      final end = DateTime.now().add(const Duration(seconds: 5));
      while (!link.hasUnsavedAddress(id)) {
        if (DateTime.now().isAfter(end)) fail('等待未保存标记超时');
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    addTearDown(() async {
      state.dispose();
      await tester.runAsync(() async {
        for (final peer in peers) {
          await peer.close();
        }
        await hostNode.close();
      });
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: MobileTheme.build(Brightness.light),
        home: DevicePage(state: state, desktopId: id),
      ),
    );
    await reveal(tester, find.textContaining('连接地址或中继策略未能保存'));
    expect(find.textContaining('连接地址或中继策略未能保存'), findsOneWidget);
    expect(find.text('跟随电脑'), findsOneWidget);
  });

  testWidgets('保留手动连接地址、重新连接和未保存提示', (tester) async {
    final (state, id) = await _page(tester);
    await reveal(tester, find.text('重新连接'));
    expect(find.text('重新连接'), findsOneWidget);
    await reveal(tester, find.text('192.168.1.20:47100'));
    expect(find.text('192.168.1.20:47100'), findsOneWidget);
    await tester.tap(find.text('添加地址'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(state.link.hasUnsavedAddress(id), isFalse);
    expect(tester.takeException(), isNull);
  });
}
