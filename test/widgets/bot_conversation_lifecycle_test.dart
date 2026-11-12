import 'dart:async';

import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/chat/chat_models.dart';
import 'package:baocode_mobile/chat/chat_output.dart';
import 'package:baocode_mobile/chat/widgets/pixel_loader.dart';
import 'package:baocode_mobile/link/link_store.dart';
import 'package:baocode_mobile/state/app_state.dart';
import 'package:baocode_mobile/ui/tasks/bot_working_line.dart';
import 'package:baocode_mobile/ui/tasks/chat_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _State extends AppState {
  _State() : super(store: MemoryLinkStore(), demo: true) {
    ready = true;
  }
  String current = 'first';
  bool removed = false, noSession = false;
  BotStatus botStatus = BotStatus.idle;
  Completer<void>? sending;
  String? sendReply;
  final calls = <(String, Map<String, Object?>)>[];
  @override
  String tr(String zh, String en) => zh;
  @override
  String desktopName(String id) => '电脑';
  @override
  bool isOnline(String desktop) => true;
  @override
  Map<String, LinkState> get snapshots => {
    'desktop': LinkState(
      device: const DeviceInfo(name: '电脑', kind: 'windows', system: 'Windows'),
      bots: [
        if (!removed)
          LinkBot(
            id: 'bot',
            name: '助手',
            session: noSession ? null : current,
            status: botStatus,
          ),
      ],
    ),
  };
  @override
  Future<Object?> request(
    String desktop,
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    calls.add((method, params));
    switch (method) {
      case LinkMethods.state:
        return snapshots['desktop']!.toJson();
      case LinkMethods.open:
        return {
          'session': params['session'],
          'start': 0,
          'count': 0,
          'items': [],
          'live': false,
        };
      case LinkMethods.send:
        await sending?.future;
        return {'session': sendReply ?? current};
      default:
        return null;
    }
  }

  void publish(String session) {
    current = session;
    notifyListeners();
  }
}

void main() {
  testWidgets('Bot 清空换会话后关闭旧订阅，停止与后续发送指向新会话', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ChatPage(
          state: state,
          desktopId: 'desktop',
          sessionId: 'first',
          title: '助手',
          botId: 'bot',
        ),
      ),
    );
    await tester.pumpAndSettle();
    state.publish('after-clear');
    await tester.pumpAndSettle();
    expect(
      state.calls
          .where((call) => call.$1 == LinkMethods.close)
          .single
          .$2['session'],
      'first',
    );
    expect(
      state.calls
          .lastWhere((call) => call.$1 == LinkMethods.open)
          .$2['session'],
      'after-clear',
    );
    state.buffer('desktop', 'after-clear').live = true;
    state.publish('after-clear');
    await tester.pump();
    expect(find.byTooltip('停止生成'), findsOneWidget);
    expect(find.byTooltip('发送'), findsNothing);
    await tester.enterText(find.byType(TextField).first, '继续');
    await tester.pump();
    expect(find.byTooltip('停止生成'), findsOneWidget);
    expect(find.byTooltip('发送'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '');
    await tester.pump();
    await tester.tap(find.byTooltip('停止生成'));
    await tester.pump();
    expect(state.calls.last.$1, LinkMethods.stop);
    expect(state.calls.last.$2['session'], 'after-clear');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('打开已有记录的 Bot，首帧就在真实会话上，不闪加载中', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    state.buffer('desktop', 'first').items.add({'t': 'text', 'text': '上次的回复'});
    await tester.pumpWidget(
      MaterialApp(
        home: ChatPage(
          state: state,
          desktopId: 'desktop',
          sessionId: 'bot:bot',
          title: '助手',
          botId: 'bot',
        ),
      ),
    );
    expect(find.byType(PixelLoader), findsNothing);
    expect(find.byKey(const ValueKey('history-reveal')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('Bot 同步时标题高度不变，电脑连接行保持可见', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ChatPage(
          state: state,
          desktopId: 'desktop',
          sessionId: 'first',
          title: '助手',
          botId: 'bot',
        ),
      ),
    );
    await tester.pumpAndSettle();
    final height = tester.getSize(find.byType(AppBar)).height;
    state.buffer('desktop', 'first').loading = true;
    state.publish('first');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.getSize(find.byType(AppBar)).height, closeTo(height, 1));
    expect(find.textContaining('电脑'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('Bot 加号保留图片和表情，不出现项目命令权限和模式', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ChatPage(
          state: state,
          desktopId: 'desktop',
          sessionId: 'first',
          title: '助手',
          botId: 'bot',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('composer-add')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat-action-album')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-action-camera')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-action-emoji')), findsOneWidget);
    for (final id in ['file', 'command', 'model', 'mode', 'permission', 'stickers']) {
      expect(find.byKey(ValueKey('chat-action-$id')), findsNothing);
    }
    expect(find.byKey(const ValueKey('composer-mode')), findsNothing);
    expect(find.byKey(const ValueKey('composer-setting-permission')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('Bot 空态显示吉祥物和资料名回退，不显示项目建议', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ChatPage(
          state: state,
          desktopId: 'desktop',
          sessionId: 'first',
          title: '助手',
          botId: 'bot',
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Bot 保留自己的吉祥物，不换成应用标志。
    expect(find.byKey(const ValueKey('bot-mascot')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-logo')), findsNothing);
    expect(find.text('BaoCodeX，我帮你…'), findsOneWidget);
    expect(state.settings.name, isEmpty);
    state.settings.name = '测试资料';
    state.publish('first');
    await tester.pump();
    expect(find.text('测试资料，我帮你…'), findsOneWidget);
    expect(find.text('讲讲这个项目的整体结构'), findsNothing);
    expect(
      find.byKey(const ValueKey('composer-input-surface')),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  test('Bot 聊天只留说的话和贴纸，过程项不进聊天', () {
    final rows = botRows(const [
      UserMessageItem(text: '你好'),
      ThinkingItem(text: '想一想', tokens: 3, seconds: 1),
      ToolCallItem(kind: ToolKind.read, target: 'a.dart'),
      ToolCallItem(kind: ToolKind.read, target: '贴纸', input: {'sticker': 'hi'}),
      AssistantTextItem('好的'),
      LiveStatusItem('工作中'),
    ]);
    expect(rows.map((row) => row.index), [0, 3, 4]);
    expect(rows.any((row) => row.isFold), isFalse);
  });

  test('内部通知不显示，由它唤醒的回合在已处理行上带时间', () {
    final at = DateTime(2026, 11, 6, 12, 51);
    final rows = botRows([
      UserMessageItem(
        text: '<bao-event>\nSince you last heard\n</bao-event>',
        sentAt: at,
        worked: const Duration(minutes: 2, seconds: 36),
      ),
      const ToolCallItem(kind: ToolKind.read, target: 'a.dart'),
      const AssistantTextItem('看到了'),
    ]);
    expect(rows.length, 2);
    expect(rows.first.work?.worked, const Duration(minutes: 2, seconds: 36));
    expect(rows.first.at, at);
    expect(rows.first.foldItems.single, isA<ToolCallItem>());
    expect(rows.last.shown, isA<AssistantTextItem>());
  });

  test('已处理在最后一句话前，中间说的话都留着，过程不进聊天', () {
    final rows = botRows(const [
      UserMessageItem(text: '发送', worked: Duration(seconds: 200)),
      AssistantTextItem('发了'),
      ToolCallItem(kind: ToolKind.read, target: 'a.dart'),
      AssistantTextItem('改完告诉你'),
    ]);
    expect(rows.map((row) => (row.index, row.isFold)), [
      (0, false),
      (1, false),
      (3, true),
      (3, false),
    ]);
    expect(rows[2].foldItems.single, isA<ToolCallItem>());
  });

  testWidgets('Bot 打字时标题换成对方正在输入', (tester) async {
    final state = _State()..botStatus = BotStatus.typing;
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ChatPage(
          state: state,
          desktopId: 'desktop',
          sessionId: 'first',
          title: '助手',
          botId: 'bot',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('对方正在输入…'), findsOneWidget);
    state.botStatus = BotStatus.idle;
    state.publish('first');
    await tester.pumpAndSettle();
    expect(find.text('对方正在输入…'), findsNothing);
    expect(find.text('助手'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('已处理行居中，点开进工作过程页', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ChatPage(
          state: state,
          desktopId: 'desktop',
          sessionId: 'first',
          title: '助手',
          botId: 'bot',
        ),
      ),
    );
    await tester.pumpAndSettle();
    state.buffer('desktop', 'first').items.addAll([
      const UserMessageItem(
        text: '查一下',
        worked: Duration(minutes: 2, seconds: 12),
      ),
      const ToolCallItem(kind: ToolKind.read, target: 'a.dart', label: '读取'),
      const AssistantTextItem('查好了'),
    ]);
    state.publish('first');
    await tester.pumpAndSettle();
    final line = find.text('已处理 · 2分12秒');
    expect(line, findsOneWidget);
    expect(
      tester.getCenter(find.byKey(const ValueKey('bot-work-fold'))).dx,
      400,
    );
    expect(find.textContaining('a.dart'), findsNothing);
    await tester.tap(line);
    await tester.pumpAndSettle();
    expect(find.byType(BotWorkPage), findsOneWidget);
    expect(find.text('工作过程'), findsOneWidget);
    expect(find.text('1 步 · 2分12秒'), findsOneWidget);
    expect(find.textContaining('a.dart'), findsWidgets);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('查好了'), findsOneWidget);
    expect(find.textContaining('a.dart'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('Bot 工作计时和独立停止可达，表情附件不被挤占，结束后收起', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ChatPage(
          state: state,
          desktopId: 'desktop',
          sessionId: 'first',
          title: '助手',
          botId: 'bot',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('bot-working')), findsNothing);

    final buffer = state.buffer('desktop', 'first');
    buffer.items.addAll([
      const UserMessageItem(text: '查一下'),
      const ThinkingItem(text: '想一想', tokens: 3, seconds: 1),
      const ToolCallItem(kind: ToolKind.read, target: 'a.dart', label: '读取'),
      LiveStatusItem(
        '工作中',
        startedAt: DateTime.now().subtract(
          const Duration(minutes: 3, seconds: 11),
        ),
      ),
    ]);
    buffer.live = true;
    state.publish('first');
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('bot-working')), findsOneWidget);
    expect(find.textContaining('工作中 · 3分1'), findsOneWidget);
    expect(find.textContaining('已思考'), findsNothing);
    expect(find.textContaining('a.dart'), findsNothing);
    expect(find.text('查一下'), findsOneWidget);

    final input = tester.getRect(
      find.byKey(const ValueKey('composer-input-surface')),
    );
    // 空心：里面的方块只有边框，没有填充色。
    expect(find.byKey(const ValueKey('hollow-stop')), findsOneWidget);
    expect(find.byIcon(Icons.stop_circle_outlined), findsNothing);
    expect(input.contains(tester.getCenter(find.byKey(const ValueKey('composer-add')))), isTrue);
    expect(input.contains(tester.getCenter(find.byTooltip('停止生成'))), isTrue);
    expect(find.byKey(const ValueKey('composer-model')), findsOneWidget);
    // 停止独立可达，表情移入加号弹层，不再占输入栏的一列。
    expect(find.byTooltip('表情'), findsNothing);

    buffer.live = false;
    buffer.items.removeLast();
    state.publish('first');
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('bot-working')), findsNothing);
    expect(find.byTooltip('停止生成'), findsNothing);
    expect(find.textContaining('已思考'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('表情通过加号进入，插入和退格按完整字符并可切回输入', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ChatPage(
          state: state,
          desktopId: 'desktop',
          sessionId: 'first',
          title: '助手',
          botId: 'bot',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('composer-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat-action-emoji')));
    await tester.pumpAndSettle();
    final panel = find.byKey(const ValueKey('chat-emoji'));
    expect(panel, findsOneWidget);
    expect(find.byTooltip('键盘'), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
    expect(
      tester.getTopLeft(panel).dy,
      greaterThan(
        tester
            .getBottomLeft(find.byKey(const ValueKey('composer-input-surface')))
            .dy,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('emoji-0')));
    await tester.tap(find.byKey(const ValueKey('emoji-1')));
    await tester.pump();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, '😀😁');
    await tester.tap(find.byTooltip('删除'));
    await tester.pump();
    expect(field.controller!.text, '😀');
    await tester.tap(find.byTooltip('删除'));
    await tester.pump();
    expect(field.controller!.text, '');

    await tester.tap(find.byKey(const ValueKey('composer-add')));
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
    expect(find.byKey(const ValueKey('chat-actions')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('chat-action-emoji')));
    await tester.pumpAndSettle();
    expect(panel, findsOneWidget);

    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
    expect(find.byKey(const ValueKey('composer-add')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('Bot 暂无真实会话时不回退旧记录，后续新会话重新订阅', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ChatPage(
          state: state,
          desktopId: 'desktop',
          sessionId: 'first',
          title: '助手',
          botId: 'bot',
        ),
      ),
    );
    await tester.pumpAndSettle();
    state.buffer('desktop', 'first').items.add({'t': 'user', 'text': '旧内容'});
    state.publish('first');
    await tester.pump();
    expect(find.text('旧内容'), findsOneWidget);
    state.noSession = true;
    state.publish('first');
    await tester.pumpAndSettle();
    expect(find.text('旧内容'), findsNothing);
    state.noSession = false;
    state.publish('new');
    await tester.pumpAndSettle();
    expect(
      state.calls
          .lastWhere((call) => call.$1 == LinkMethods.open)
          .$2['session'],
      'new',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('发送等待期间会话变化，旧响应不切回旧会话且保留输入', (tester) async {
    final state = _State()
      ..sending = Completer<void>()
      ..sendReply = 'first';
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ChatPage(
          state: state,
          desktopId: 'desktop',
          sessionId: 'first',
          title: '助手',
          botId: 'bot',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '保留这条');
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pump();
    state.publish('after-clear');
    await tester.pump();
    state.sending!.complete();
    await tester.pumpAndSettle();
    expect(
      state.calls
          .lastWhere((call) => call.$1 == LinkMethods.open)
          .$2['session'],
      'after-clear',
    );
    expect(find.text('保留这条'), findsOneWidget);
    expect(find.textContaining('未确认'), findsOneWidget);
    expect(
      state.calls.where((call) => call.$1 == LinkMethods.send),
      hasLength(1),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
