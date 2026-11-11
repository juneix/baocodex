// YCode — GPL-3.0-only.
import 'dart:async';
import 'dart:convert';

import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/state/conversation_input.dart';
import 'package:baocode_mobile/chat/widgets/image_deck.dart';
import 'package:baocode_mobile/chat/widgets/message_pictures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/chat_page_harness.dart';

void main() {
  for (final bot in [null, 'bot']) {
    testWidgets(
      '${bot == null ? '对话待发图片在输入框内' : 'Bot 待发图片在输入框上方'}，可放大、返回、移除并保留发送内容',
      (tester) async {
        final state = ChineseChatPageState();
        addTearDown(state.dispose);
        final bytes = base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=',
        );
        await state.saveInputDraft(
          'desktop',
          bot == null ? 'session' : 'bot:bot',
          InputDraft(
            text: '图片说明',
            images: [
              DraftImage('first.png', 'image/png', bytes),
              DraftImage('second.png', 'image/png', bytes),
            ],
          ),
        );
        await tester.pumpWidget(chatHost(state, bot: bot));
        await tester.pumpAndSettle();
        final surface = find.byKey(const ValueKey('composer-input-surface'));
        final thumbnail = find.byWidgetPredicate(
          (widget) => widget is Image && widget.semanticLabel == 'first.png',
        );
        if (bot == null) {
          expect(
            tester.getRect(surface).contains(tester.getTopLeft(thumbnail)),
            isTrue,
          );
          expect(
            tester.getRect(surface).contains(tester.getBottomRight(thumbnail)),
            isTrue,
          );
        } else {
          // 输入框不被图片撑高，光标还在一行里；“+”和发送都在。
          expect(
            tester.getBottomLeft(thumbnail).dy,
            lessThanOrEqualTo(tester.getTopLeft(surface).dy),
          );
          expect(tester.getSize(surface).height, lessThan(50));
          expect(find.byTooltip('添加附件'), findsOneWidget);
          expect(find.byTooltip('表情'), findsOneWidget);
          expect(find.byTooltip('发送'), findsOneWidget);
        }
        expect(find.byTooltip('移除图片'), findsNWidgets(2));
        await tester.tap(thumbnail);
        await tester.pumpAndSettle();
        expect(find.byType(InteractiveViewer), findsOneWidget);
        expect(find.text('first.png'), findsOneWidget);
        final viewer = find.descendant(
          of: find.byType(InteractiveViewer),
          matching: find.byType(Image),
        );
        expect(
          (tester.widget<Image>(viewer).image as MemoryImage).bytes,
          bytes,
        );
        expect(
          state.calls.where((call) => call.$1 == LinkMethods.send),
          isEmpty,
        );
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(InteractiveViewer), findsNothing);
        expect(
          tester
              .widget<TextField>(find.byType(TextField).first)
              .controller!
              .text,
          '图片说明',
        );
        await tester.tap(find.byTooltip('移除图片').last);
        await tester.pump();
        expect(find.byTooltip('移除图片'), findsOneWidget);
        await tester.tap(find.byTooltip('发送'));
        await tester.pump();
        final sent = state.calls
            .lastWhere((call) => call.$1 == LinkMethods.send)
            .$2;
        expect(sent['text'], '图片说明');
        expect(sent['images'], [
          {
            'name': 'first.png',
            'type': 'image/png',
            'data': base64Encode(bytes),
          },
        ]);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final text in ['图片说明 [Image #11]', '[Image #11]']) {
    for (final bot in [null, 'bot']) {
      testWidgets('复制图文到另一个${bot == null ? '对话' : 'Bot'}恢复附件，不显示内部编号：$text', (
        tester,
      ) async {
        final state = ChatPageState();
        addTearDown(state.dispose);
        const png =
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=';
        final message = {
          't': 'user',
          'text': text,
          'images': [
            {'name': 'original.png', 'type': 'image/png', 'data': png, 'n': 11},
          ],
        };
        Uint8List? copied;
        String? plain;
        const channel = MethodChannel('local.baocode.mobile/platform');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            if (call.method == 'writeChatClipboard') {
              final args = call.arguments as Map;
              plain = args['text'] as String;
              copied = args['payload'] as Uint8List;
            }
            if (call.method == 'readChatClipboard') return copied;
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        await tester.pumpWidget(messageHost(state, message));
        await tester.pumpAndSettle();
        expect(find.textContaining('[Image #11]'), findsNothing);
        await tester.tap(find.byTooltip('Copy'));
        await tester.pump();
        expect(plain, text.startsWith('图片说明') ? '图片说明' : '');
        expect(copied, isNotNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(
          chatHost(state, session: 'another-session', bot: bot),
        );
        await tester.pumpAndSettle();
        final field = find.byType(TextField).first;
        await tester.tap(field);
        await tester.pump();
        Actions.invoke(
          tester.element(find.byType(EditableText).first),
          const PasteTextIntent(SelectionChangedCause.keyboard),
        );
        await tester.pumpAndSettle();
        expect(find.byTooltip('Remove image'), findsOneWidget);
        expect(tester.widget<TextField>(field).controller!.text, plain);
        await tester.tap(find.byTooltip('Send'));
        await tester.pump();
        final sent = state.calls
            .lastWhere((call) => call.$1 == LinkMethods.send)
            .$2;
        expect(sent['text'], plain);
        expect(sent['images'], [
          {'name': 'original.png', 'type': 'image/png', 'data': png},
        ]);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets('长按粘贴菜单恢复多图，替换选中文字并保留已有附件', (tester) async {
    final state = ChatPageState();
    addTearDown(state.dispose);
    const png =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=';
    final bytes = base64Decode(png);
    await state.saveInputDraft(
      'desktop',
      'session',
      InputDraft(
        text: '原来的正文',
        images: [DraftImage('draft.png', 'image/png', bytes)],
      ),
    );
    final payload = const StandardMessageCodec().encodeMessage({
      'version': 1,
      'text': '粘贴的正文',
      'images': [
        {'bytes': bytes, 'type': 'image/png', 'name': 'one.png'},
        {'bytes': bytes, 'type': 'image/png', 'name': 'two.png'},
      ],
    })!;
    const channel = MethodChannel('local.baocode.mobile/platform');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'readChatClipboard'
          ? payload.buffer.asUint8List(
              payload.offsetInBytes,
              payload.lengthInBytes,
            )
          : null,
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => switch (call.method) {
        'Clipboard.hasStrings' => {'value': true},
        'Clipboard.getData' => {'text': '不应优先粘贴这个纯文本副本'},
        _ => null,
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });
    await tester.pumpWidget(chatHost(state));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField).first);
    final editable = tester.state<EditableTextState>(
      find.byType(EditableText).first,
    );
    editable.widget.controller.selection = const TextSelection(
      baseOffset: 0,
      extentOffset: 5,
    );
    editable.showToolbar();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paste'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      '粘贴的正文',
    );
    expect(find.byTooltip('Remove image'), findsNWidgets(3));
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    final sent = state.calls
        .lastWhere((call) => call.$1 == LinkMethods.send)
        .$2;
    expect((sent['images'] as List).map((image) => (image as Map)['name']), [
      'draft.png',
      'one.png',
      'two.png',
    ]);
    expect(
      (sent['images'] as List).every((image) => (image as Map)['data'] == png),
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('发送等待期间仍能粘贴下一条图文草稿，发送完成不清掉它', (tester) async {
    final state = ChatPageState()..sending = Completer<void>();
    addTearDown(state.dispose);
    const png =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=';
    final data = const StandardMessageCodec().encodeMessage({
      'version': 1,
      'text': '下一条',
      'images': [
        {'bytes': base64Decode(png), 'type': 'image/png', 'name': 'next.png'},
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
    await tester.pumpWidget(chatHost(state));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '正在发送');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    expect(
      state.calls.where((call) => call.$1 == LinkMethods.send),
      hasLength(1),
    );
    final controller = tester
        .widget<TextField>(find.byType(TextField).first)
        .controller!;
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );
    Actions.invoke(
      tester.element(find.byType(EditableText).first),
      const PasteTextIntent(SelectionChangedCause.keyboard),
    );
    await tester.pump();
    await tester.pump();
    expect(controller.text, '下一条');
    expect(find.byTooltip('Remove image'), findsOneWidget);
    state.sending!.complete();
    await tester.pumpAndSettle();
    expect(controller.text, '下一条');
    expect(find.byTooltip('Remove image'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('图文副本不可用时保留当前草稿并提示重新复制', (tester) async {
    final state = ChatPageState();
    addTearDown(state.dispose);
    const channel = MethodChannel('local.baocode.mobile/platform');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'clipboard_unavailable'),
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.pumpWidget(chatHost(state));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '原有草稿');
    Actions.invoke(
      tester.element(find.byType(EditableText).first),
      const PasteTextIntent(SelectionChangedCause.keyboard),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      '原有草稿',
    );
    expect(
      find.text('Could not paste the message. Copy it again and retry.'),
      findsOneWidget,
    );
    expect(state.calls.where((call) => call.$1 == LinkMethods.send), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('复制失败明确提示，不显示已复制', (tester) async {
    final state = ChatPageState();
    addTearDown(state.dispose);
    const channel = MethodChannel('local.baocode.mobile/platform');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'clipboard_failed'),
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.pumpWidget(
      messageHost(state, {
        't': 'user',
        'text': '[Image #1]',
        'images': [
          {'type': 'image/png', 'data': 'AQID', 'n': 1},
        ],
      }),
    );
    await tester.tap(find.byTooltip('Copy'));
    await tester.pump();
    expect(find.text('Copy failed. Please try again.'), findsOneWidget);
    expect(find.text('Copied'), findsNothing);
  });

  testWidgets('编辑带编号图片时隐藏编号，重发仍保留原图', (tester) async {
    final state = ChatPageState();
    addTearDown(state.dispose);
    const png =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=';
    state.history.items.add({
      't': 'user',
      'text': '图片说明 [Image #11]',
      'images': [
        {'name': 'original.png', 'type': 'image/png', 'data': png, 'n': 11},
      ],
    });
    await tester.pumpWidget(chatHost(state));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit and resend'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      '图片说明',
    );
    expect(find.byTooltip('Remove image'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '改过的说明');
    await tester.tap(find.byTooltip('Resend'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Discard and send'));
    await tester.pump();
    final edited = state.calls
        .lastWhere((call) => call.$1 == LinkMethods.edit)
        .$2;
    expect(edited['text'], '改过的说明');
    expect(edited['images'], [
      {'name': 'original.png', 'type': 'image/png', 'data': png},
    ]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('历史消息多图点第二张打开画廊，可左右翻看且不跨消息', (tester) async {
    final state = ChatPageState();
    addTearDown(state.dispose);
    const png =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=';
    Map<String, Object?> user(String tag, int count) => {
      't': 'user',
      'text': tag,
      'images': [
        for (var i = 0; i < count; i++)
          {'name': '$tag-$i.png', 'type': 'image/png', 'data': png},
      ],
    };
    state.history.items
      ..add(user('甲', 3))
      ..add(user('乙', 2));
    await tester.pumpWidget(chatHost(state));
    await tester.pump();
    // 先解码，图片才有真实尺寸可点。
    await tester.runAsync(() async {
      for (final image in tester.widgetList<Image>(find.byType(Image))) {
        await precacheImage(
          image.image,
          tester.element(find.byType(Image).first),
        );
      }
    });
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('image-deck-expand')).first);
    await tester.pump();
    final first = find.byWidgetPredicate(
      (w) => w is Image && w.semanticLabel == '甲-1.png',
    );
    await tester.tap(first);
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
    await tester.fling(find.byType(PageView).last, const Offset(-400, 0), 1500);
    await tester.pumpAndSettle();
    expect(find.text('3 / 3'), findsOneWidget);
    await tester.fling(find.byType(PageView).last, const Offset(-400, 0), 1500);
    await tester.pumpAndSettle();
    expect(find.text('3 / 3'), findsOneWidget, reason: '不翻进另一条消息');
    await tester.pageBack();
    await tester.pumpAndSettle();
    final other = find.byWidgetPredicate(
      (w) => w is Image && w.semanticLabel == '乙-0.png',
    );
    await tester.tap(other);
    await tester.pumpAndSettle();
    expect(find.text('1 / 2'), findsOneWidget);
  });

  testWidgets('普通对话多图叠成一摞可展开折叠，单张不叠', (tester) async {
    final state = ChatPageState();
    addTearDown(state.dispose);
    const png =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=';
    Map<String, Object?> user(String tag, int count) => {
      't': 'user',
      'text': tag,
      'images': [
        for (var i = 0; i < count; i++)
          {'name': '$tag-$i.png', 'type': 'image/png', 'data': png},
      ],
    };
    state.history.items.add(user('单张', 1));
    await tester.pumpWidget(chatHost(state));
    await tester.pump();
    expect(find.byType(ImageDeck), findsNothing);
    expect(find.byType(MemoryPicture), findsOneWidget);

    state.history.items.add(user('三张', 3));
    state.update();
    await tester.pump();
    expect(find.byType(ImageDeck), findsOneWidget);
    expect(find.byKey(const ValueKey('image-deck-collapse')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('image-deck-expand')));
    await tester.pump();
    expect(find.byKey(const ValueKey('image-deck-collapse')), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is Image && w.semanticLabel == '三张-2.png',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('image-deck-collapse')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byKey(const ValueKey('image-deck-expand')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('从消息的编辑入口进入编辑态后，编辑附件可左右翻看', (tester) async {
    final state = ChatPageState();
    addTearDown(state.dispose);
    const png =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=';
    state.history.items.add({
      't': 'user',
      'text': '带三张图',
      'images': [
        for (var i = 0; i < 3; i++)
          {'name': 'att-$i.png', 'type': 'image/png', 'data': png},
      ],
    });
    await tester.pumpWidget(chatHost(state));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit and resend'));
    await tester.pumpAndSettle();
    // 编辑态输入框内的附件缩略图，与消息气泡里的同名图区分开。
    final surface = find.byKey(const ValueKey('composer-input-surface'));
    final second = find.descendant(
      of: surface,
      matching: find.byWidgetPredicate(
        (w) => w is Image && w.semanticLabel == 'att-1.png',
      ),
    );
    await tester.tap(second);
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
    await tester.fling(find.byType(PageView).last, const Offset(-400, 0), 1500);
    await tester.pumpAndSettle();
    expect(find.text('3 / 3'), findsOneWidget);
    await tester.fling(find.byType(PageView).last, const Offset(400, 0), 1500);
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
    await tester.fling(find.byType(PageView).last, const Offset(400, 0), 1500);
    await tester.pumpAndSettle();
    expect(find.text('1 / 3'), findsOneWidget);
  });

  testWidgets('直播结束切换渲染分支不改变用户图文消息的高度', (tester) async {
    final state = ChatPageState();
    addTearDown(state.dispose);
    state.history.items.add({
      't': 'user',
      'text': '用户长文本用于切换live和完成态时验证布局保持稳定。'.padRight(120, '继续验证。'),
      'images': [
        for (var i = 0; i < 5; i++)
          {
            'name': 'image-$i.png',
            'type': 'image/png',
            'data': 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=',
          },
      ],
    });
    state.history.live = true;
    await tester.pumpWidget(chatHost(state));
    await tester.pump();
    final bubble = find.byKey(const ValueKey('user-message-bubble'));
    final liveSize = tester.getSize(bubble);
    final liveElement = tester.element(bubble);
    state.history.live = false;
    state.update();
    await tester.pump();
    expect(tester.getSize(bubble), liveSize);
    expect(identical(tester.element(bubble), liveElement), isTrue);
  });
}
