// YCode — GPL-3.0-only.
import 'dart:convert';

import 'package:bao_link/bao_link.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/chat_page_harness.dart';

void main() {
  testWidgets('运行中编辑消息可直接重新发送，由电脑端停止当前这一轮', (tester) async {
    final state = ChineseChatPageState();
    addTearDown(state.dispose);
    state.history
      ..items.add({'t': 'user', 'text': '旧要求'})
      ..live = true;
    await tester.pumpWidget(chatHost(state));
    await tester.pump();
    await tester.tap(find.byTooltip('编辑并重新发送'));
    await tester.pumpAndSettle();
    expect(find.text('正在编辑 · 将中断并丢弃后续'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '新要求');
    await tester.pump();
    await tester.tap(find.byTooltip('重新发送'));
    await tester.pumpAndSettle();
    expect(find.textContaining('当前这一轮也会停止'), findsOneWidget);
    expect(state.calls.where((call) => call.$1 == LinkMethods.edit), isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, '丢弃并发送'));
    await tester.pump();
    final edit = state.calls.lastWhere((call) => call.$1 == LinkMethods.edit);
    expect(edit.$2['index'], 0);
    expect(edit.$2['text'], '新要求');
    expect(
      state.calls.any((call) => call.$1 == LinkMethods.stop),
      isFalse,
      reason: '电脑端的 edit 自己停止当前这一轮',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('运行中确认编辑后尾部增量不让编辑失效，发送键仍可用', (tester) async {
    final state = ChineseChatPageState();
    addTearDown(state.dispose);
    state.history
      ..items.add({'t': 'user', 'text': '旧要求'})
      ..items.add({'t': 'assistant', 'text': '回复'})
      ..live = true;
    await tester.pumpWidget(chatHost(state));
    await tester.pump();
    await tester.tap(find.byTooltip('编辑并重新发送'));
    await tester.pumpAndSettle();
    expect(find.textContaining('将中断并丢弃后续'), findsOneWidget);
    state.tail(
      LinkSessionUpdate(
        session: 'session',
        start: 1,
        count: 2,
        items: const [
          {'t': 'assistant', 'text': '回复继续'},
        ],
        live: true,
      ),
    );
    await tester.pump();
    state.tail(
      LinkSessionUpdate(
        session: 'session',
        start: 1,
        count: 2,
        items: const [
          {'t': 'assistant', 'text': '回复继续更多'},
        ],
        live: true,
      ),
    );
    await tester.pump();
    expect(find.text('编辑的消息已变化 · 请取消后重新选择'), findsNothing);
    expect(find.textContaining('正在编辑'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '新要求');
    await tester.pump();
    await tester.tap(find.byTooltip('重新发送'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '丢弃并发送'));
    await tester.pump();
    expect(state.calls.any((call) => call.$1 == LinkMethods.edit), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  group('编辑没有图片的消息后加图', () {
    const png =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=';

    LinkSessionUpdate sync(List<Object?> items) => LinkSessionUpdate(
      session: 'session',
      start: 0,
      count: items.length,
      items: items,
    );

    /// 进入编辑并粘贴一张图：和选图一样，只往输入框加图。
    Future<ChineseChatPageState> editAndAddImage(WidgetTester tester) async {
      final state = ChineseChatPageState();
      addTearDown(state.dispose);
      final data = const StandardMessageCodec().encodeMessage({
        'version': 1,
        'text': '',
        'images': [
          {'bytes': base64Decode(png), 'type': 'image/png', 'name': 'new.png'},
        ],
      })!;
      const channel = MethodChannel('local.baocode.mobile/platform');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'readChatClipboard'
            ? data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes)
            : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      state.history.apply(
        sync([
          {'t': 'user', 'text': '原来没有图片'},
          {'t': 'text', 'text': '回答'},
        ]),
        snapshot: true,
      );
      await tester.pumpWidget(chatHost(state));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('编辑并重新发送'));
      await tester.pumpAndSettle();
      // 气泡里的可选文本也含 EditableText，要取输入框里的那个。
      Actions.invoke(
        tester.element(
          find.descendant(
            of: find.byType(TextField).first,
            matching: find.byType(EditableText),
          ),
        ),
        const PasteTextIntent(SelectionChangedCause.keyboard),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('移除图片'), findsOneWidget);
      return state;
    }

    Future<void> resend(WidgetTester tester, ChineseChatPageState state) async {
      await tester.tap(find.byTooltip('重新发送'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '丢弃并发送'));
      await tester.pumpAndSettle();
      final edit = state.calls
          .singleWhere((call) => call.$1 == LinkMethods.edit)
          .$2;
      expect(edit['index'], 0);
      expect(edit['text'], '原来没有图片');
      expect((edit['images'] as List).single, containsPair('name', 'new.png'));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }

    testWidgets('不离开页面时可以发送，图片一起带上', (tester) async {
      final state = await editAndAddImage(tester);
      await resend(tester, state);
    });

    testWidgets('选图回来后对话重新同步但内容没变，仍可发送', (tester) async {
      final state = await editAndAddImage(tester);
      state.history.apply(
        sync([
          {'t': 'user', 'text': '原来没有图片'},
          {'t': 'text', 'text': '回答'},
        ]),
        snapshot: true,
      );
      state.notifyListeners();
      await tester.pump();
      expect(find.text('编辑的消息已变化 · 请取消后重新选择'), findsNothing);
      await resend(tester, state);
    });

    testWidgets('回合结束写回耗时和用量后仍可发送', (tester) async {
      final state = await editAndAddImage(tester);
      state.tail(
        LinkSessionUpdate(
          session: 'session',
          start: 0,
          count: 2,
          items: const [
            {'t': 'user', 'text': '原来没有图片', 'worked': 3000},
            {'t': 'text', 'text': '回答'},
          ],
        ),
      );
      await tester.pump();
      expect(find.text('编辑的消息已变化 · 请取消后重新选择'), findsNothing);
      await resend(tester, state);
    });

    testWidgets('同步后消息挪了位置，按新位置发送', (tester) async {
      final state = ChineseChatPageState();
      addTearDown(state.dispose);
      state.history.apply(
        sync([
          {'t': 'user', 'text': '更早', 'at': 100},
          {'t': 'user', 'text': '要改的', 'at': 200},
          {'t': 'text', 'text': '回答'},
        ]),
        snapshot: true,
      );
      await tester.pumpWidget(chatHost(state));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('编辑并重新发送').last);
      await tester.pumpAndSettle();
      state.history.apply(
        sync([
          {'t': 'user', 'text': '要改的', 'at': 200},
          {'t': 'text', 'text': '回答'},
        ]),
        snapshot: true,
      );
      state.notifyListeners();
      await tester.pump();
      await tester.tap(find.byTooltip('重新发送'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '丢弃并发送'));
      await tester.pumpAndSettle();
      final edit = state.calls
          .singleWhere((call) => call.$1 == LinkMethods.edit)
          .$2;
      expect(edit['index'], 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('同步进行中先不让发，完成后恢复', (tester) async {
      final state = await editAndAddImage(tester);
      state.history.loading = true;
      state.notifyListeners();
      await tester.pump();
      expect(find.text('正在编辑 · 正在同步对话'), findsOneWidget);
      await tester.tap(find.byTooltip('重新发送'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.widgetWithText(FilledButton, '丢弃并发送'), findsNothing);
      state.history.loading = false;
      state.notifyListeners();
      await tester.pump();
      await resend(tester, state);
    });

    testWidgets('同步后这条消息真的变了，仍禁用发送并提示', (tester) async {
      final state = await editAndAddImage(tester);
      state.history.apply(
        sync([
          {'t': 'user', 'text': '电脑上已被改过'},
          {'t': 'text', 'text': '回答'},
        ]),
        snapshot: true,
      );
      state.notifyListeners();
      await tester.pump();
      expect(find.text('编辑的消息已变化 · 请取消后重新选择'), findsOneWidget);
      await tester.tap(find.byTooltip('重新发送'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(state.calls.where((call) => call.$1 == LinkMethods.edit), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });

  testWidgets('编辑消息时提示条在输入框卡片里、胶囊之下，取消后恢复原草稿', (tester) async {
    final state = ChineseChatPageState()..savedDraft = '原草稿';
    addTearDown(state.dispose);
    state.history.items.add({'t': 'user', 'text': '要改的消息'});
    await tester.pumpWidget(chatHost(state));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('编辑并重新发送'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    final notice = find.byKey(const ValueKey('editing-notice'));
    expect(find.text('正在编辑 · 后续对话将被丢弃'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('composer-input-surface')),
        matching: notice,
      ),
      findsOneWidget,
    );
    expect(
      tester.getBottomLeft(notice).dy,
      lessThanOrEqualTo(tester.getTopLeft(find.byType(TextField).first).dy),
    );
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      '要改的消息',
    );
    await tester.tap(find.descendant(of: notice, matching: find.text('取消')));
    await tester.pump();
    expect(find.byKey(const ValueKey('editing-notice')), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      '原草稿',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('确认编辑期间历史变化时不使用新下标，保留原草稿', (tester) async {
    final state = ChatPageState()..savedDraft = '未发送草稿';
    addTearDown(state.dispose);
    state.history.items.add({'t': 'user', 'text': 'original'});
    await tester.pumpWidget(chatHost(state));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit and resend'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'edited');
    await tester.tap(find.byTooltip('Resend'));
    await tester.pumpAndSettle();
    state.history.items.insert(0, {'t': 'user', 'text': 'older'});
    state.update();
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Discard and send'));
    await tester.pumpAndSettle();
    expect(find.textContaining('The message changed'), findsWidgets);
    expect(state.calls.where((call) => call.$1 == LinkMethods.edit), isEmpty);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('editing-notice')),
        matching: find.text('Cancel'),
      ),
    );
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      '未发送草稿',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
