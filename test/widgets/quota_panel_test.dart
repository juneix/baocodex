import 'dart:async';

import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/state/app_state.dart';
import 'package:baocode_mobile/link/link_store.dart';
import 'package:baocode_mobile/theme/app_theme.dart';
import 'package:baocode_mobile/ui/tasks/quota_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _State extends AppState {
  _State() : super(store: MemoryLinkStore());
  Object? failure;
  bool stale = false, multiple = false;
  final calls = <Map<String, Object?>>[];
  Completer<void>? gate;
  @override
  Future<Object?> request(
    String desktopId,
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    calls.add(params);
    await gate?.future;
    if (failure case final error?) throw error;
    return {
      'providers': [
        {
          'id': '账号源',
          'name': 'ChatGPT',
          'accounts': [
            {
              'id': '甲',
              'displayName': multiple ? 'user@example.com' : '用户甲',
              'current': true,
              'enabled': true,
              'plan': 'Plus',
              'at': DateTime.now()
                  .subtract(Duration(minutes: stale ? 10 : 0))
                  .millisecondsSinceEpoch,
              'windows': [
                {
                  'minutes': 300,
                  'leftPercent': 53,
                  'resetsAt': DateTime.now()
                      .add(const Duration(hours: 2, minutes: 8))
                      .millisecondsSinceEpoch,
                },
                {'minutes': 10080, 'leftPercent': 8},
              ],
            },
            if (multiple)
              {
                'id': '乙',
                'displayName': '备用',
                'enabled': true,
                'limitedUntil': DateTime.now()
                    .add(const Duration(hours: 1))
                    .millisecondsSinceEpoch,
                'windows': [],
              },
          ],
        },
      ],
    };
  }
}

void main() {
  final controllers = <QuotaController>[];
  tearDown(() {
    for (final controller in controllers) {
      controller.dispose();
    }
    controllers.clear();
  });
  Widget host(_State state) {
    final controller = QuotaController(state, '电脑', '会话');
    controllers.add(controller);
    controller.load();
    return MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => Column(
            children: [
              QuotaPanel(
                controller: controller,
                provider: '账号源',
                title: 'ChatGPT',
              ),
              QuotaPanel(controller: controller, provider: 'acme', title: 'acme'),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('多账号摘要带短名及可用数量，颜色按最少额度阈值', (tester) async {
    final state = _State()..multiple = true;
    state.settings.language = 'zh';
    addTearDown(state.dispose);
    await tester.pumpWidget(host(state));
    await tester.pumpAndSettle();
    expect(find.textContaining('user · 5 小时剩 53%'), findsOneWidget);
    expect(find.textContaining('可用 1/2'), findsOneWidget);
    final context = tester.element(find.text('ChatGPT'));
    expect(
      quotaColor(context, [
        {'leftPercent': 10},
      ], summary: true),
      Theme.of(context).colorScheme.error,
    );
    expect(
      quotaColor(context, [
        {'leftPercent': 30},
      ], summary: true),
      MobileTheme.statusColorsOf(context).warning,
    );
    expect(
      quotaColor(context, [
        {'leftPercent': 31},
      ], summary: true),
      Theme.of(context).colorScheme.onSurfaceVariant,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    for (final controller in controllers) {
      controller.dispose();
    }
    controllers.clear();
  });
  testWidgets('账号额度展开显示且刷新带强制参数', (tester) async {
    final state = _State()..settings.language = 'zh';
    addTearDown(state.dispose);
    await tester.pumpWidget(host(state));
    await tester.pumpAndSettle();
    expect(state.calls.single.containsKey('refresh'), isFalse);
    expect(state.calls.single.containsKey('provider'), isFalse);
    expect(find.textContaining('5 小时剩 53%'), findsOneWidget);
    expect(find.widgetWithText(InkWell, 'acme'), findsNothing);
    await tester.tap(find.text('ChatGPT'));
    await tester.pumpAndSettle();
    expect(find.text('用户甲'), findsOneWidget);
    await tester.pump(const Duration(minutes: 1));
    expect(tester.takeException(), isNull);
    expect(find.text('当前对话'), findsOneWidget);
    expect(find.text('剩余 53%'), findsOneWidget);
    expect(find.text('每周'), findsOneWidget);
    expect(find.textContaining('上次更新'), findsOneWidget);
    await tester.tap(find.byTooltip('刷新额度'));
    await tester.pumpAndSettle();
    expect(state.calls.last['refresh'], isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    for (final controller in controllers) {
      controller.dispose();
    }
    controllers.clear();
  });
  testWidgets('旧额度只自动强刷一次，失败保留快照并显示文案，展开状态保留', (tester) async {
    final state = _State()..stale = true;
    state.settings.language = 'zh';
    addTearDown(state.dispose);
    await tester.pumpWidget(host(state));
    await tester.pumpAndSettle();
    expect(state.calls.length, 2);
    expect(state.calls.last['refresh'], isTrue);
    await tester.tap(find.textContaining('5 小时剩'));
    await tester.pumpAndSettle();
    expect(find.text('当前对话'), findsOneWidget);
    state.failure = StateError('离线');
    await tester.tap(find.byTooltip('刷新额度'));
    await tester.pumpAndSettle();
    expect(find.textContaining('刷新失败，显示的是'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(host(state));
    await tester.pumpAndSettle();
    expect(controllers.last.isOpen('账号源'), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    for (final controller in controllers) {
      controller.dispose();
    }
    controllers.clear();
  });
  testWidgets('箭头收起朝右、展开朝下', (tester) async {
    final state = _State()..settings.language = 'zh';
    addTearDown(state.dispose);
    await tester.pumpWidget(host(state));
    await tester.pumpAndSettle();
    double turns() => tester
        .widget<AnimatedRotation>(find.byKey(const ValueKey('quota-chevron')))
        .turns;
    expect(turns(), 0);
    await tester.tap(find.text('ChatGPT'));
    await tester.pumpAndSettle();
    expect(turns(), 0.25);
    await tester.pumpWidget(const SizedBox.shrink());
    for (final controller in controllers) {
      controller.dispose();
    }
    controllers.clear();
  });
  testWidgets('有缓存时新控制器立即显示摘要，后台刷新期间保持旧数据', (tester) async {
    final state = _State()..settings.language = 'zh';
    addTearDown(state.dispose);
    await tester.pumpWidget(host(state));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    final gate = Completer<void>();
    state.gate = gate;
    await tester.pumpWidget(host(state));
    await tester.pump();
    // The request is still pending, yet the summary is already there.
    expect(find.textContaining('5 小时剩 53%'), findsOneWidget);
    expect(controllers.last.busy, isTrue);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('5 小时剩 53%'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    for (final controller in controllers) {
      controller.dispose();
    }
    controllers.clear();
  });
  testWidgets('官方桌面无额度扩展时明确提示且不重复请求', (tester) async {
    final state = _State()
      ..failure = const LinkRemoteException('unknown', 'No such request: quota')
      ..settings.language = 'zh';
    addTearDown(state.dispose);
    await tester.pumpWidget(host(state));
    await tester.pumpAndSettle();
    expect(find.text('此电脑不支持额度查询'), findsNWidgets(2));
    expect(controllers.last.unsupported, isTrue);
    expect(controllers.last.failed, isFalse);
    await controllers.last.load(refresh: true);
    expect(state.calls, hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    for (final controller in controllers) {
      controller.dispose();
    }
    controllers.clear();
  });

  for (final error in [
    const LinkRemoteException('unknown', '不支持'),
    const LinkRemoteException('unsupported', '不支持'),
    const LinkRemoteException('notFound', '暂无数据'),
    TimeoutException('超时'),
    StateError('离线'),
  ]) {
    testWidgets('额度请求失败静默隐藏并缓存：$error', (tester) async {
      final state = _State()..failure = error;
      state.settings.language = 'zh';
      addTearDown(state.dispose);
      await tester.pumpWidget(host(state));
      await tester.pumpAndSettle();
      expect(find.text('ChatGPT'), findsOneWidget);
      expect(find.byTooltip('刷新额度'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(host(state));
      await tester.pumpAndSettle();
      expect(state.calls, hasLength(2));
      await tester.pumpWidget(const SizedBox.shrink());
      for (final controller in controllers) {
        controller.dispose();
      }
      controllers.clear();
    });
  }
}
