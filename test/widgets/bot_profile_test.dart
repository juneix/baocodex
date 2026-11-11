import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/link/link_store.dart';
import 'package:baocode_mobile/state/app_state.dart';
import 'package:baocode_mobile/theme/app_theme.dart';
import 'package:baocode_mobile/ui/bots/bots_tab.dart';
import 'package:baocode_mobile/ui/tasks/chat_page.dart';
import 'package:baocode_mobile/ui/tasks/model_settings_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Model extends AppState {
  _Model() : super(store: MemoryLinkStore());
  final opened = <String>[], closed = <String>[];
  Map<String, Object?>? saved;
  bool online = true;
  @override
  String tr(String zh, String en) => zh;
  @override
  bool isOnline(String desktop) => online;
  @override
  Future<void> openSession(String desktopId, String sessionId) async =>
      opened.add(sessionId);
  @override
  Future<void> closeSession(String desktopId, String sessionId) async =>
      closed.add(sessionId);
  @override
  Future<Object?> request(
    String desktopId,
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    if (method == LinkMethods.saveBot) saved = params;
    return null;
  }
}

void main() {
  const chatting = BotRef(
    'desktop',
    LinkBot(id: 'assistant', name: '小宝', model: '测试模型', session: 'bot-session'),
  );

  testWidgets('点模型原地打开选择器，不进聊天页，关掉后退订', (tester) async {
    final state = _Model();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: MobileTheme.build(Brightness.light),
        home: BotProfilePage(state: state, ref: chatting),
      ),
    );
    await tester.tap(find.text('测试模型'));
    await tester.pumpAndSettle();
    expect(find.byType(ModelSettingsSheet), findsOneWidget);
    expect(find.byType(ChatPage), findsNothing);
    expect(state.opened, ['bot-session']);
    expect(state.closed, isEmpty);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byType(ModelSettingsSheet), findsNothing);
    expect(state.closed, ['bot-session']);
  });

  testWidgets('点性别和模型都不弹键盘，选了性别才保存', (tester) async {
    final state = _Model();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: MobileTheme.build(Brightness.light),
        home: BotProfilePage(
          state: state,
          ref: const BotRef(
            'desktop',
            LinkBot(
              id: 'assistant',
              name: '小宝',
              gender: '机器人',
              model: '测试模型',
              session: 's',
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('机器人'));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);
    expect(find.text('男'), findsOneWidget);
    expect(find.text('女'), findsOneWidget);
    expect(find.text('不填'), findsOneWidget);
    // 手写的旧值也在选项里。
    expect(find.text('机器人'), findsNWidgets(2));
    await tester.tap(find.text('女'));
    await tester.pumpAndSettle();
    expect(state.saved?['gender'], '女');

    await tester.tap(find.text('测试模型'));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('还没有会话或电脑离线时点模型只提示，不开页面', (tester) async {
    final state = _Model();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: MobileTheme.build(Brightness.light),
        home: BotProfilePage(
          state: state,
          ref: const BotRef(
            'desktop',
            LinkBot(id: 'assistant', name: '小宝', model: '测试模型'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('测试模型'));
    await tester.pump();
    expect(find.text('先和它说句话，再换模型。'), findsOneWidget);
    expect(find.byType(ChatPage), findsNothing);
    expect(state.opened, isEmpty);

    state.online = false;
    await tester.tap(find.text('测试模型'));
    await tester.pump();
    expect(find.text('电脑不在线，不能换模型。'), findsOneWidget);
    expect(state.opened, isEmpty);
  });

  testWidgets('从聊天进资料页，发消息是返回而不是再开一个聊天页', (tester) async {
    final state = _Model();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: MobileTheme.build(Brightness.light),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    BotProfilePage(state: state, ref: chatting, fromChat: true),
              ),
            ),
            child: const Text('聊天页'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('聊天页'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('发消息'));
    await tester.pumpAndSettle();
    expect(find.byType(BotProfilePage), findsNothing);
    expect(find.byType(ChatPage), findsNothing);
    expect(find.text('聊天页'), findsOneWidget);
  });

  testWidgets('资料展示真实身份、模型、能力与消息入口', (tester) async {
    final state = AppState(store: MemoryLinkStore());
    addTearDown(state.dispose);
    state.settings.language = 'zh';
    await tester.pumpWidget(
      MaterialApp(
        theme: MobileTheme.build(Brightness.light),
        home: BotProfilePage(
          state: state,
          ref: const BotRef(
            'desktop',
            LinkBot(
              id: 'assistant',
              name: '小宝',
              assistant: true,
              identity: '帮我照看电脑上的任务。',
              model: '测试模型',
              abilities: {BotAbility.agents, BotAbility.browser},
            ),
          ),
        ),
      ),
    );
    expect(find.text('资料'), findsOneWidget);
    expect(find.text('发消息'), findsOneWidget);
    expect(find.text('测试模型'), findsOneWidget);
    expect(find.text('帮我照看电脑上的任务。'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('管智能体'), 160);
    expect(find.text('使用浏览器'), findsOneWidget);
    expect(find.text('删除 Bot'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('资料页直接切换能力，整份资料一起保存，不丢名字和图片头像', (tester) async {
    final state = _Recording();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: MobileTheme.build(Brightness.light),
        home: BotProfilePage(state: state, ref: _bot),
      ),
    );
    final toggle = find.byKey(const ValueKey('bot-ability-browser'));
    await tester.scrollUntilVisible(toggle, 160);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    final (method, params) = state.calls.single;
    expect(method, LinkMethods.saveBot);
    expect(params['bot'], 'helper');
    expect(params['name'], '小助手');
    expect(params['avatar'], 'avatar-0123456789ab.png');
    expect(params['identity'], '帮我看着构建。');
    expect(params['abilities'], ['agents', 'browser']);
    expect(params['proactive'], const BotProactive(perDay: 3).toJson());
    expect(params.containsKey('chatOnly'), isFalse);
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
  });

  testWidgets('记忆页同时列出关于你和关于它自己两份', (tester) async {
    final state = _Recording();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: MobileTheme.build(Brightness.light),
        home: BotMemoryPage(state: state, ref: _bot),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('关于你'), findsOneWidget);
    expect(find.text('关于它自己'), findsOneWidget);
    expect(find.text('叫我阿涛'), findsOneWidget);
    expect(find.text('答应每天汇总一次'), findsOneWidget);
    expect(find.textContaining('小助手 记下的关于你的事'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

const _bot = BotRef(
  'desktop',
  LinkBot(
    id: 'helper',
    name: '小助手',
    avatar: 'avatar-0123456789ab.png',
    identity: '帮我看着构建。',
    abilities: {BotAbility.agents},
    proactive: BotProactive(perDay: 3),
  ),
);

class _Recording extends AppState {
  _Recording() : super(store: MemoryLinkStore()) {
    settings.language = 'zh';
  }
  final calls = <(String, Map<String, Object?>)>[];
  @override
  bool isOnline(String desktop) => true;
  @override
  Future<Object?> request(
    String desktop,
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    if (method == LinkMethods.botMemory) {
      return {'text': '叫我阿涛', 'self': '答应每天汇总一次'};
    }
    if (method == LinkMethods.botAvatar) {
      throw const LinkRemoteException(LinkErrors.notFound, 'none');
    }
    calls.add((method, params));
    final bot = _bot.bot.toJson()
      ..['abilities'] = params['abilities']
      ..['name'] = params['name'];
    return {'bot': bot};
  }
}
