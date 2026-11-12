import 'dart:convert';

import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/chat/chat_models.dart';
import 'package:baocode_mobile/chat/chat_output.dart';
import 'package:baocode_mobile/chat/message_view.dart';
import 'package:baocode_mobile/chat/widgets/turn_footer.dart';
import 'package:baocode_mobile/link/link_store.dart';
import 'package:baocode_mobile/state/app_state.dart';
import 'package:baocode_mobile/theme/app_theme.dart';
import 'package:baocode_mobile/ui/tasks/chat_page.dart';
import 'package:baocode_mobile/ui/widgets/formats.dart';
import 'package:baocode_mobile/ui/widgets/image_gallery.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _BotState extends AppState {
  _BotState() : super(store: MemoryLinkStore());
  final history = SessionBuffer('电脑', '会话');
  @override
  List<BotRef> get bots => [const BotRef('电脑', LinkBot(id: '宝', name: '小宝'))];
  @override
  SessionBuffer buffer(String desktopId, String sessionId) => history;
  @override
  Future<void> openSession(String desktopId, String sessionId) async {}
  @override
  Future<void> closeSession(String desktopId, String sessionId) async {}
}

class _Reading extends AppState {
  _Reading() : super(store: MemoryLinkStore());
  final reads = <Map<String, Object?>>[];
  @override
  Future<Object?> request(
    String desktopId,
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    reads.add(params);
    return {'text': '内容'};
  }
}

class _Sessions extends AppState {
  _Sessions() : super(store: MemoryLinkStore());

  @override
  String tr(String zh, String en) => zh;

  @override
  List<ProjectRef> get projects => const [
    ProjectRef('电脑', ProjectInfo(id: 'p', name: '项目甲', path: '/甲')),
  ];

  @override
  List<SessionRef> get sessions => [
    SessionRef(
      '电脑',
      SessionSummary(
        id: 'new-1',
        project: 'p',
        title: '修复电脑图标',
        updatedAt: DateTime(2026),
        status: LinkSessionStatus.running,
      ),
    ),
    SessionRef(
      '电脑',
      SessionSummary(
        id: 'new-2',
        project: 'p',
        title: ' ',
        updatedAt: DateTime(2026),
      ),
    ),
  ];
}

void main() {
  testWidgets('Bot仅对已有时间戳分组，不为无时间消息造时间', (tester) async {
    final state = _BotState();
    addTearDown(state.dispose);
    state.history.items.addAll([
      {
        't': 'user',
        'text': '上午好',
        'at': DateTime.utc(2026, 10, 1, 9).millisecondsSinceEpoch,
      },
      {'t': 'text', 'text': '你好'},
      {
        't': 'user',
        'text': '继续',
        'at': DateTime.utc(2026, 10, 1, 9, 6).millisecondsSinceEpoch,
      },
      {'t': 'text', 'text': '好的'},
      {'t': 'user', 'text': '没有时间'},
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: ChatPage(
          state: state,
          desktopId: '电脑',
          sessionId: '会话',
          title: '小宝',
          botId: '宝',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('bot-message-time')), findsNWidgets(2));
    for (final minute in [0, 6]) {
      final local = DateTime.utc(2026, 10, 1, 9, minute).toLocal();
      final label = formatDay(state, local);
      final clock =
          '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
      expect(find.text('$label $clock'), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (final dark in [false, true]) {
    testWidgets('Bot气泡左右对齐且隐藏统计，深色=$dark', (tester) async {
      // 自己的气泡是黑金：浅金底，和回答的白色气泡分得开。
      final state = AppState(store: MemoryLinkStore());
      addTearDown(state.dispose);
      state.settings.language = 'zh';
      const bot = BotRef('电脑', LinkBot(id: '宝', name: '小宝'));
      await tester.pumpWidget(
        MaterialApp(
          theme: MobileTheme.build(dark ? Brightness.dark : Brightness.light),
          home: Scaffold(
            body: Column(
              children: [
                MessageView(
                  state: state,
                  desktopId: '电脑',
                  bot: bot,
                  item: const UserMessageItem(text: '你好'),
                ),
                MessageView(
                  state: state,
                  desktopId: '电脑',
                  bot: bot,
                  item: const AssistantTextItem('你好呀'),
                  footer: const TurnFooterData(
                    answer: '你好呀',
                    worked: Duration(seconds: 32),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      final user = find.byKey(const ValueKey('bot-user-bubble'));
      final answer = find.byKey(const ValueKey('bot-answer-bubble'));
      expect(
        tester.getTopLeft(user).dx,
        greaterThan(tester.getTopLeft(answer).dx),
      );
      expect(
        (tester.widget<Container>(user).decoration as BoxDecoration).color,
        botUserBubbleColor(tester.element(user)),
      );
      expect(
        (tester.widget<Container>(answer).decoration as BoxDecoration).color,
        isNot(botUserBubbleColor(tester.element(user))),
      );
      expect(find.text('我'), findsOneWidget);
      expect(find.byType(TurnFooter), findsNothing);
      expect(find.byKey(const ValueKey('bot-message-time')), findsNothing);
      await tester.longPress(user);
      await tester.pumpAndSettle();
      expect(find.text('复制'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  group('长按气泡的菜单', () {
    Future<Finder> open(
      WidgetTester tester, {
      required AlignmentGeometry alignment,
      ValueChanged<UserMessageItem>? onEdit,
    }) async {
      final state = AppState(store: MemoryLinkStore());
      addTearDown(state.dispose);
      state.settings.language = 'zh';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: alignment,
              child: MessageView(
                state: state,
                desktopId: '电脑',
                bot: const BotRef('电脑', LinkBot(id: '宝', name: '小宝')),
                item: const UserMessageItem(text: '你好'),
                onEdit: onEdit,
              ),
            ),
          ),
        ),
      );
      final bubble = find.byKey(const ValueKey('bot-user-bubble'));
      await tester.longPress(bubble);
      await tester.pumpAndSettle();
      return bubble;
    }

    testWidgets('有空间时贴在气泡上方', (tester) async {
      final bubble = await open(tester, alignment: Alignment.center);
      final rect = tester.getRect(bubble);
      expect(tester.getBottomLeft(find.text('复制')).dy, lessThan(rect.top));
      expect(rect.top - tester.getBottomLeft(find.text('复制')).dy, lessThan(40));
      expect(tester.takeException(), isNull);
    });

    testWidgets('顶部放不下时翻到气泡下方', (tester) async {
      final bubble = await open(tester, alignment: Alignment.topCenter);
      expect(
        tester.getTopLeft(find.text('复制')).dy,
        greaterThan(tester.getRect(bubble).bottom),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('点编辑重发先关菜单再回调，点外面只关闭', (tester) async {
      UserMessageItem? edited;
      await open(
        tester,
        alignment: Alignment.center,
        onEdit: (item) => edited = item,
      );
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.text('编辑重发'), findsNothing);
      expect(edited, isNull);

      await tester.longPress(find.byKey(const ValueKey('bot-user-bubble')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑重发'));
      await tester.pumpAndSettle();
      expect(find.text('编辑重发'), findsNothing);
      expect(edited?.text, '你好');
    });
  });
  testWidgets('自己的气泡始终白底，不随主题色变化', (tester) async {
    for (final accent in [MobileAccent.amber, MobileAccent.indigo]) {
      for (final dark in [false, true]) {
        final state = AppState(store: MemoryLinkStore());
        addTearDown(state.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: MobileTheme.build(
              dark ? Brightness.dark : Brightness.light,
              accent: accent,
            ),
            home: Scaffold(
              body: MessageView(
                state: state,
                desktopId: '电脑',
                bot: const BotRef('电脑', LinkBot(id: '宝', name: '小宝')),
                item: const UserMessageItem(text: '你好'),
              ),
            ),
          ),
        );
        final bubble = find.byKey(const ValueKey('bot-user-bubble'));
        final color =
            (tester.widget<Container>(bubble).decoration as BoxDecoration)
                .color!;
        final scheme = Theme.of(tester.element(bubble)).colorScheme;
        expect(
          color,
          scheme.surfaceContainerLowest,
          reason: '主题色 $accent 深色 $dark',
        );
        // 白底：没有掺主题色的色相，浅色下就是纯白。
        if (!dark) expect(color.computeLuminance(), greaterThan(.85));
      }
    }
  });

  testWidgets('Bot说话分成独立气泡，卡片旁白保留且不显示标签', (tester) async {
    final state = AppState(store: MemoryLinkStore());
    addTearDown(state.dispose);
    String? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageView(
            state: state,
            desktopId: '电脑',
            bot: const BotRef('电脑', LinkBot(id: '宝', name: '小宝')),
            item: const AssistantTextItem(
              '<bot_say>第一条</bot_say><bot_narrate>轻声说</bot_narrate><bot_show_chat>会话甲</bot_show_chat><bot_say>第二条</bot_say>',
            ),
            onOpenSession: (id) => opened = id,
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('bot-answer-bubble')), findsNWidgets(2));
    expect(find.textContaining('<bot_'), findsNothing);
    expect(find.text('第一条'), findsOneWidget);
    expect(find.text('第二条'), findsOneWidget);
    expect(find.text('轻声说'), findsOneWidget);
    await tester.tap(find.text('会话甲'));
    expect(opened, '会话甲');
    expect(tester.takeException(), isNull);
  });
  testWidgets('卡片和旁白与气泡左对齐，卡片显示对话标题而不是 id', (tester) async {
    final state = _Sessions();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageView(
            state: state,
            desktopId: '电脑',
            bot: const BotRef('电脑', LinkBot(id: '宝', name: '小宝')),
            item: const AssistantTextItem(
              '<bot_say>第一条</bot_say><bot_narrate>轻声说</bot_narrate>'
              '<bot_show_chat>new-1</bot_show_chat>'
              '<bot_show_chat>new-2</bot_show_chat>',
            ),
            onOpenSession: (_) {},
          ),
        ),
      ),
    );
    final left = tester
        .getTopLeft(find.byKey(const ValueKey('bot-answer-bubble')))
        .dx;
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('bot-agent-card')).first).dx,
      left,
    );
    expect(tester.getTopLeft(find.text('轻声说')).dx, left);
    expect(find.textContaining('[运行中]', findRichText: true), findsOneWidget);
    expect(find.textContaining('项目甲', findRichText: true), findsNWidgets(2));
    expect(find.text('修复电脑图标'), findsOneWidget);
    expect(find.text('新对话'), findsOneWidget);
    expect(find.text('new-1'), findsNothing);
    expect(find.text('new-2'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=',
  );
  Widget message(AppState state, ChatItem item) => MaterialApp(
    home: Scaffold(
      body: MessageView(
        state: state,
        desktopId: '电脑',
        bot: const BotRef('电脑', LinkBot(id: '宝', name: '小宝')),
        item: item,
      ),
    ),
  );
  List<ImageAttachment> pictures(int count) => [
    for (var i = 0; i < count; i++)
      ImageAttachment(bytes: png, name: '图$i.png', mediaType: 'image/png'),
  ];

  testWidgets('图片和文字分开，图片不进气泡', (tester) async {
    final state = _Sessions();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      message(state, UserMessageItem(text: '看这个', images: pictures(1))),
    );
    final bubble = find.byKey(const ValueKey('bot-user-bubble'));
    final picture = find.byWidgetPredicate(
      (widget) => widget is Image && widget.semanticLabel == '图0.png',
    );
    expect(
      find.descendant(of: bubble, matching: find.text('看这个')),
      findsOneWidget,
    );
    expect(find.descendant(of: bubble, matching: picture), findsNothing);
    expect(picture, findsOneWidget);
    expect(
      tester.getTopLeft(picture).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(bubble).dy),
    );
  });

  testWidgets('只有图片时没有空气泡', (tester) async {
    final state = _Sessions();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      message(state, UserMessageItem(text: '', images: pictures(1))),
    );
    expect(find.byKey(const ValueKey('bot-user-bubble')), findsNothing);
  });

  testWidgets('多张图叠放，左边展开，可滑动，展开后竖着排开，点开进画廊', (tester) async {
    // 真实聊天在可滚动列表里；这里页面要放得下五张图竖着排开。
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = _Sessions();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      message(state, UserMessageItem(text: '', images: pictures(5))),
    );
    await tester.pumpAndSettle();
    final deck = find.byKey(const ValueKey('image-deck'));
    final expand = find.byKey(const ValueKey('image-deck-expand'));
    expect(find.text('展开 5'), findsOneWidget);
    expect(
      tester.getTopRight(expand).dx,
      lessThanOrEqualTo(tester.getTopLeft(deck).dx),
    );

    await tester.drag(deck, const Offset(-200, 0));
    await tester.pumpAndSettle();
    final view = tester.widget<PageView>(find.byType(PageView));
    expect(view.controller!.page, 1);

    await tester.tap(deck);
    await tester.pumpAndSettle();
    expect(find.byType(ImageGalleryPage), findsOneWidget);
    expect(
      tester
          .widget<ImageGalleryPage>(find.byType(ImageGalleryPage))
          .initialIndex,
      1,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(expand);
    await tester.pumpAndSettle();
    expect(deck, findsNothing);
    expect(find.byType(Image), findsNWidgets(5));
    // 一张张竖着排，和分开发的一样大；“收起”在第一张旁边。
    final rects = [
      for (var i = 0; i < 5; i++) tester.getRect(find.byType(Image).at(i)),
    ];
    for (var i = 1; i < 5; i++) {
      expect(rects[i].top, greaterThan(rects[i - 1].bottom));
      expect(rects[i].left, rects[0].left);
      // 样例图是正方形：高度随图片比例，不裁剪。
      expect(rects[i].size, const Size(136, 136));
    }
    final collapse = find.byKey(const ValueKey('image-deck-collapse'));
    expect(find.text('折叠'), findsNWidgets(2));
    expect(tester.getTopRight(collapse).dx, lessThanOrEqualTo(rects[0].left));
    expect(
      tester
          .getTopRight(find.byKey(const ValueKey('image-deck-collapse-end')))
          .dx,
      lessThanOrEqualTo(rects[4].left),
    );
    await tester.tap(collapse);
    await tester.pumpAndSettle();
    expect(find.text('展开 5'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Bot 回复里的文件链接按 Bot 读，不要项目', (tester) async {
    final state = _Reading();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showLinkedFile(
              context,
              state,
              '电脑',
              null,
              'C:/Users/me/简历.md',
              botId: '宝',
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(state.reads.single, {'bot': '宝', 'path': 'C:/Users/me/简历.md'});
    expect(find.text('C:/Users/me/简历.md'), findsOneWidget);
  });
  testWidgets('既不是项目也不是 Bot 时不发读取请求', (tester) async {
    final state = _Reading();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showLinkedFile(context, state, '电脑', null, 'a.md'),
            child: const Text('打开'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(state.reads, isEmpty);
  });
  testWidgets('项目对话的回答没有气泡，自己的消息是白的', (tester) async {
    final state = AppState(store: MemoryLinkStore());
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: MobileTheme.build(Brightness.light),
        home: Scaffold(
          body: ListView(
            children: [
              MessageView(
                state: state,
                desktopId: '电脑',
                item: const UserMessageItem(text: '你好'),
              ),
              MessageView(
                state: state,
                desktopId: '电脑',
                item: const AssistantTextItem('好的'),
                footer: const TurnFooterData(
                  answer: '好的',
                  worked: Duration(seconds: 1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final user = find.byKey(const ValueKey('user-message-bubble'));
    final theme = Theme.of(tester.element(user));
    expect(
      (tester.widget<Container>(user).decoration as BoxDecoration).color,
      theme.colorScheme.surfaceContainerLowest,
    );
    expect(find.byKey(const ValueKey('bot-answer-bubble')), findsNothing);
    expect(find.byType(TurnFooter), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
