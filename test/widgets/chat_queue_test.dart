// YCode — GPL-3.0-only.
import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/state/conversation_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/chat_page_harness.dart';

void main() {
  testWidgets('运行中可编辑并将追加消息排队发送', (tester) async {
    final state = ChatPageState();
    state.history.live = true;
    addTearDown(state.dispose);
    await tester.pumpWidget(chatHost(state));
    await tester.pump();
    final composer = find.byType(TextField).first;
    expect(tester.widget<TextField>(composer).enabled, isNot(isFalse));
    await tester.enterText(composer, '追加内容');
    await tester.pump();
    expect(find.byTooltip('Send'), findsOneWidget);
    expect(find.byTooltip('Stop generation'), findsNothing);
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    // 运行中不上传：留在手机端的排队区，本轮结束后才发出。
    expect(state.calls.where((call) => call.$1 == LinkMethods.send), isEmpty);
    expect(state.localQueue.messages('desktop', 'session').single.text, '追加内容');
    expect(find.byKey(const ValueKey('queued-messages')), findsOneWidget);
    expect(find.byTooltip('Stop generation'), findsOneWidget);
    expect(state.history.live, isTrue, reason: '追加消息不能停止正在运行的任务');
    expect(state.calls.any((call) => call.$1 == LinkMethods.stop), isFalse);
  });

  testWidgets('运行中发送只在手机端排队，向上箭头才带 now 立即发送', (tester) async {
    final state = ChineseChatPageState();
    state.history.live = true;
    state.history.items.add({'t': 'user', 'text': '第一步'});
    addTearDown(state.dispose);
    await tester.pumpWidget(chatHost(state));
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, '下一步');
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pump();
    expect(state.calls.where((call) => call.$1 == LinkMethods.send), isEmpty);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      isEmpty,
    );
    final panel = find.byKey(const ValueKey('queued-messages'));
    expect(
      find.descendant(of: panel, matching: find.text('下一步')),
      findsOneWidget,
    );
    expect(
      tester.getBottomLeft(panel).dy,
      lessThanOrEqualTo(tester.getTopLeft(find.byType(TextField).first).dy),
    );
    await tester.tap(find.byTooltip('立即插入'));
    await tester.pump();
    final send = state.calls.lastWhere((call) => call.$1 == LinkMethods.send);
    expect(send.$2['text'], '下一步');
    expect(send.$2['now'], isTrue);
    expect(send.$2['id'], isA<String>());
    expect(state.calls.any((call) => call.$1 == LinkMethods.stop), isFalse);
    expect(panel, findsNothing);
    // 电脑还没接上（等手头的调用或后台任务）：对话里先占一条，标着排队中。
    expect(find.text('下一步'), findsOneWidget);
    expect(find.text('排队中'), findsOneWidget);
    // 电脑接上后对话里出现真的那条，占位的就不再画。
    state.tail(
      LinkSessionUpdate(
        session: 'session',
        start: state.history.items.length,
        items: const [
          {'t': 'user', 'text': '下一步'},
        ],
        count: state.history.items.length + 1,
        live: true,
      ),
    );
    state.localQueue.drain('desktop', 'session');
    await tester.pump();
    expect(find.text('下一步'), findsOneWidget);
    expect(find.text('排队中'), findsNothing);
    // 立即发送带 now，等待新一轮出现的宽限期结束前不再发其他消息。
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('排队消息列在输入框上方，可立即发送、移出或撤回编辑', (tester) async {
    final state = ChineseChatPageState();
    state.history.live = true;
    addTearDown(state.dispose);
    final queue = state.localQueue;
    List<String> queued() => [
      for (final message in queue.messages('desktop', 'session')) message.text,
    ];
    queue.add('desktop', 'session', text: '第一条排队');
    queue.add(
      'desktop',
      'session',
      text: '第二条排队',
      images: [
        for (final name in ['a.png', 'b.png'])
          DraftImage(name, 'image/png', Uint8List(0)),
      ],
    );
    queue.add('desktop', 'session', text: '第三条排队');
    await tester.pumpWidget(chatHost(state));
    await tester.pump();
    final panel = find.byKey(const ValueKey('queued-messages'));
    expect(find.text('3 条排队中 · 本轮结束后依次发送'), findsOneWidget);
    expect(find.text('[2 张图片] 第二条排队'), findsOneWidget);

    Finder action(String tooltip, int row) =>
        find.descendant(of: panel, matching: find.byTooltip(tooltip)).at(row);
    await tester.tap(action('移出队列', 1));
    await tester.pump();
    expect(queued(), ['第一条排队', '第三条排队']);
    final composer = find.byType(TextField).first;
    expect(tester.widget<TextField>(composer).controller!.text, isEmpty);

    await tester.tap(action('重新编辑', 0));
    await tester.pump();
    expect(queued(), ['第三条排队']);
    expect(tester.widget<TextField>(composer).controller!.text, '第一条排队');

    await tester.tap(action('立即插入', 0));
    await tester.pump();
    final send = state.calls.lastWhere((call) => call.$1 == LinkMethods.send);
    expect(send.$2['text'], '第三条排队');
    expect(send.$2['now'], isTrue);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('点击排队消息取回修改，再发送仍然排队而不立即插入', (tester) async {
    final state = ChineseChatPageState();
    addTearDown(state.dispose);
    state.history.live = true;
    state.localQueue.add('desktop', 'session', text: '原排队内容');
    await tester.pumpWidget(chatHost(state));
    await tester.pump();
    final panel = find.byKey(const ValueKey('queued-messages'));
    await tester.tap(find.descendant(of: panel, matching: find.text('原排队内容')));
    await tester.pump();
    final composer = find.byType(TextField).first;
    expect(tester.widget<TextField>(composer).controller!.text, '原排队内容');
    expect(state.localQueue.messages('desktop', 'session'), isEmpty);
    await tester.enterText(composer, '修改后的内容');
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pump();
    // 本轮仍在运行：取回后再发送是手机端排队，不上传，也不立即插入。
    expect(state.calls.where((call) => call.$1 == LinkMethods.send), isEmpty);
    expect(
      state.localQueue.messages('desktop', 'session').single.text,
      '修改后的内容',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('手机端排队：本轮结束后自动发出一条，下一条等它开始', (tester) async {
    final state = ChineseChatPageState();
    state.history.live = true;
    addTearDown(state.dispose);
    await tester.pumpWidget(chatHost(state));
    await tester.pump();
    for (final text in ['第一条', '第二条']) {
      await tester.enterText(find.byType(TextField).first, text);
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.pump();
    }
    List<(String, Map<String, Object?>)> sends() =>
        state.calls.where((call) => call.$1 == LinkMethods.send).toList();
    expect(sends(), isEmpty);
    expect(state.localQueue.messages('desktop', 'session'), hasLength(2));
    expect(find.text('2 条排队中 · 本轮结束后依次发送'), findsOneWidget);

    state.history.live = false;
    state.update();
    await tester.pump();
    expect(sends().map((call) => call.$2['text']), ['第一条']);
    expect(sends().single.$2['now'], isNull);
    expect(sends().single.$2['id'], isA<String>());
    expect(state.localQueue.messages('desktop', 'session').single.text, '第二条');
    // 第一条的回合尚未出现：不会连发第二条。
    state.update();
    await tester.pump();
    expect(sends(), hasLength(1));

    // 第一条开始并结束后，第二条才发出。
    state.history.live = true;
    state.update();
    await tester.pump();
    state.history.live = false;
    state.update();
    await tester.pump();
    expect(sends().map((call) => call.$2['text']), ['第一条', '第二条']);
    expect(find.byKey(const ValueKey('queued-messages')), findsNothing);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('离开聊天页再进入，手机端队列仍在；离线时提示保留，重连后只发一次', (tester) async {
    final state = ChineseChatPageState();
    state.history.live = true;
    addTearDown(state.dispose);
    await tester.pumpWidget(chatHost(state));
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, '离开前排队');
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    expect(state.localQueue.messages('desktop', 'session'), hasLength(1));

    state.online = false;
    await tester.pumpWidget(chatHost(state));
    await tester.pump();
    final panel = find.byKey(const ValueKey('queued-messages'));
    expect(
      find.descendant(of: panel, matching: find.text('离开前排队')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('offline-notice')), findsOneWidget);
    // 离线时本轮结束也不发送，队列保留。
    state.history.live = false;
    state.update();
    await tester.pump();
    expect(state.calls.where((call) => call.$1 == LinkMethods.send), isEmpty);
    expect(state.localQueue.messages('desktop', 'session'), hasLength(1));

    // 重新连上后继续发出，且只发一次。
    state.online = true;
    state.update();
    await tester.pump();
    final sends = state.calls.where((call) => call.$1 == LinkMethods.send);
    expect(sends.single.$2['text'], '离开前排队');
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('取回手机端排队消息：已有草稿不被覆盖，而是追加', (tester) async {
    final state = ChineseChatPageState();
    state.history.live = true;
    addTearDown(state.dispose);
    await tester.pumpWidget(chatHost(state));
    await tester.pump();
    final composer = find.byType(TextField).first;
    await tester.enterText(composer, '旧内容');
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pump();
    await tester.enterText(composer, '正在写的草稿');
    await tester.pump();
    await tester.tap(find.byTooltip('重新编辑'));
    await tester.pump();
    await tester.pump();
    expect(tester.widget<TextField>(composer).controller!.text, '正在写的草稿\n旧内容');
    expect(state.localQueue.messages('desktop', 'session'), isEmpty);
    expect(state.calls.where((call) => call.$1 == LinkMethods.send), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('排队消息发送失败：保留并提示，点重试后再发', (tester) async {
    final state = ChineseChatPageState();
    state.history.live = true;
    addTearDown(state.dispose);
    await tester.pumpWidget(chatHost(state));
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, '会失败');
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pump();
    state.failSend = true;
    state.history.live = false;
    state.update();
    await tester.pump();
    await tester.pump();
    expect(state.localQueue.messages('desktop', 'session'), hasLength(1));
    expect(find.byKey(const ValueKey('queue-failure-notice')), findsOneWidget);
    state.failSend = false;
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('queue-failure-notice')),
        matching: find.text('重试'),
      ),
    );
    await tester.pump();
    await tester.pump();
    final sends = state.calls
        .where((call) => call.$1 == LinkMethods.send)
        .toList();
    expect(sends, hasLength(2));
    expect(sends.first.$2['id'], sends.last.$2['id']);
    expect(state.localQueue.messages('desktop', 'session'), isEmpty);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
