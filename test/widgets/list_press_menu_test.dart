import 'dart:async';

import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/models/user_facing_error.dart';
import 'package:baocode_mobile/link/phone_link.dart';
import 'package:baocode_mobile/state/app_state.dart';
import 'package:baocode_mobile/theme/app_theme.dart';
import 'package:baocode_mobile/ui/bots/bots_tab.dart';
import 'package:baocode_mobile/ui/conversations/chats_tab.dart';
import 'package:baocode_mobile/ui/files/files_tab.dart';
import 'package:baocode_mobile/ui/widgets/mobile_widgets.dart' show ListRow;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _State extends AppState {
  _State() : super(store: MemoryLinkStore()) {
    settings.language = 'zh';
  }

  bool online = true;
  bool? projectPinned = false;
  bool sessionPinned = false;
  bool hidden = false;
  bool deleted = false;
  bool fail = false;
  List<LinkBot> botList = const [];
  Completer<void>? pending;
  final calls = <(String, String, Map<String, Object?>)>[];

  @override
  String? get selectedDesktopId => 'desk';
  @override
  List<KeptDesktop> get desktops => const [
    KeptDesktop(id: 'desk', name: '测试电脑', publicKey: ''),
  ];
  @override
  bool isOnline(String desktopId) => online;
  @override
  List<BotRef> get bots => [for (final bot in botList) BotRef('desk', bot)];
  @override
  List<ProjectRef> get projects => [
    if (!hidden)
      ProjectRef(
        'desk',
        ProjectInfo(
          id: 'project',
          name: '项目甲',
          path: '/project',
          pinned: projectPinned,
        ),
      ),
  ];
  @override
  List<SessionRef> get sessions => [
    if (!deleted)
      SessionRef(
        'desk',
        SessionSummary(
          id: 'session',
          project: 'project',
          title: '对话甲',
          updatedAt: DateTime(2026),
          pinned: sessionPinned,
        ),
      ),
    SessionRef(
      'desk',
      SessionSummary(
        id: 'other',
        project: 'project',
        title: '对话乙',
        updatedAt: DateTime(2025),
      ),
    ),
  ];
  @override
  Future<Object?> request(
    String desktop,
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    calls.add((desktop, method, params));
    await pending?.future;
    if (fail) throw const UserFacingError('合成操作失败');
    if (method == LinkMethods.pinProject) {
      projectPinned = params['pinned'] as bool;
    }
    if (method == LinkMethods.hideProject) hidden = true;
    if (method == LinkMethods.pin) sessionPinned = params['pinned'] as bool;
    if (method == LinkMethods.delete) deleted = true;
    notifyListeners();
    return null;
  }
}

Widget _host(
  _State state, {
  bool project = false,
  bool files = false,
  bool botsTab = false,
  double scale = 1,
}) => MaterialApp(
  theme: MobileTheme.build(Brightness.light),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: AnimatedBuilder(
    animation: state,
    builder: (_, _) => files
        ? FilesTab(state: state)
        : botsTab
        ? BotsTab(state: state)
        : project
        ? ProjectChatsPage(state: state, project: state.projects.first)
        : ChatsTab(state: state),
  ),
);

Finder _row(String title) => find.byWidgetPredicate(
  (widget) => widget is ListRow && widget.title.startsWith(title),
);

Finder get _menu => find.byKey(const ValueKey('dropdown-panel'));

Future<void> _navigation(WidgetTester tester) async {
  await tester.tap(find.byTooltip('项目与对话').first);
  await tester.pumpAndSettle();
}

Future<void> _press(WidgetTester tester, String title) async {
  final host = find.byType(ChatsTab);
  if (host.evaluate().isNotEmpty) {
    final scaffold = find.descendant(of: host, matching: find.byType(Scaffold)).first;
    if (!tester.state<ScaffoldState>(scaffold).isDrawerOpen) {
      await _navigation(tester);
    }
    if (_row(title).evaluate().isEmpty) {
      final scroll = find.descendant(
        of: find.byKey(const ValueKey('conversation-navigation-list')),
        matching: find.byType(Scrollable),
      ).first;
      await tester.scrollUntilVisible(_row(title), 80, scrollable: scroll);
    }
  }
  await tester.ensureVisible(_row(title).first);
  await tester.pumpAndSettle();
  await tester.longPress(_row(title).first);
  await tester.pumpAndSettle();
}

Future<void> _pick(WidgetTester tester, String title, String item) async {
  await _press(tester, title);
  await tester.tap(find.text(item));
  await tester.pumpAndSettle();
}

const _assistant = LinkBot(id: 'xb', name: '小宝', assistant: true);
const _helper = LinkBot(id: 'hp', name: '帮手');

void main() {
  testWidgets('首页项目长按置顶和取消置顶，只更新所选项目', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    await tester.pumpWidget(_host(state));
    expect(find.text('置顶'), findsNothing);
    await _press(tester, '项目甲');
    expect(state.calls, isEmpty);
    expect(find.text('删除该项目'), findsOneWidget);
    await tester.tap(find.text('置顶'));
    await tester.pumpAndSettle();
    expect(_menu, findsNothing);
    expect(state.calls.single.$1, 'desk');
    expect(state.calls.single.$2, LinkMethods.pinProject);
    expect(state.calls.single.$3, {'project': 'project', 'pinned': true});
    await _pick(tester, '项目甲', '取消置顶');
    expect(state.calls.last.$3, {'project': 'project', 'pinned': false});
  });

  testWidgets('删除该项目须确认且明确不删除文件和对话', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    await tester.pumpWidget(_host(state));
    await _pick(tester, '项目甲', '删除该项目');
    expect(find.textContaining('不删除文件或对话'), findsOneWidget);
    expect(state.calls, isEmpty);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(state.calls, isEmpty);
    await _pick(tester, '项目甲', '删除该项目');
    await tester.tap(find.widgetWithText(FilledButton, '移除'));
    await tester.pumpAndSettle();
    expect(state.calls.single.$2, LinkMethods.hideProject);
    expect(state.calls.single.$3, {'project': 'project'});
  });

  testWidgets('文件页项目也能长按，旧电脑不显示不支持的置顶', (tester) async {
    final state = _State()..projectPinned = null;
    addTearDown(state.dispose);
    await tester.pumpWidget(_host(state, files: true));
    await _press(tester, '项目甲');
    expect(find.text('置顶'), findsNothing);
    expect(find.text('删除该项目'), findsOneWidget);
  });

  testWidgets('项目内对话长按置顶与删除，取消删除不发请求', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    await tester.pumpWidget(_host(state, project: true));
    await _pick(tester, '对话甲', '置顶');
    expect(state.calls.single.$2, LinkMethods.pin);
    expect(state.calls.single.$3, {'session': 'session', 'pinned': true});
    await _press(tester, '对话甲');
    expect(find.text('取消置顶'), findsOneWidget);
    await tester.tap(find.text('删除该聊天'));
    await tester.pumpAndSettle();
    expect(find.textContaining('无法撤销'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(state.calls, hasLength(1));
    await _pick(tester, '对话甲', '删除该聊天');
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(state.calls.last.$1, 'desk');
    expect(state.calls.last.$2, LinkMethods.delete);
    expect(state.calls.last.$3, {'session': 'session'});
    expect(find.text('对话甲'), findsNothing);
    expect(find.text('对话乙'), findsOneWidget);
  });

  testWidgets('移除常用不删除项目内或电脑上的会话', (tester) async {
    final state = _State();
    state.settings.homeSessions.add(('desk', 'session'));
    addTearDown(state.dispose);
    await tester.pumpWidget(_host(state));
    await _pick(tester, '对话甲', '从常用移除');
    expect(state.calls, isEmpty);
    expect(state.settings.homeSessions, isEmpty);
    expect(_row('对话甲'), findsOneWidget);
    expect(state.sessions.map((ref) => ref.session.id), contains('session'));
  });

  testWidgets('菜单贴着手指：下方放不下翻到上方，右边放不下收回来', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = _State();
    addTearDown(state.dispose);
    await tester.pumpWidget(_host(state, files: true));
    Future<Rect> at(Offset point) async {
      await tester.longPressAt(point);
      await tester.pumpAndSettle();
      final rect = tester.getRect(_menu);
      await tester.tapAt(const Offset(2, 2));
      await tester.pumpAndSettle();
      expect(_menu, findsNothing);
      return rect;
    }

    final row = tester.getRect(_row('项目甲'));
    final below = await at(row.center);
    expect(below.topLeft, row.center);

    final right = await at(Offset(396, row.center.dy));
    expect(right.right, lessThanOrEqualTo(392));

    // 同一套算法，把行挪到屏幕底部来测翻转。
    tester.view.physicalSize = Size(400, row.center.dy + 40);
    await tester.pumpAndSettle();
    final above = await at(tester.getRect(_row('项目甲')).center);
    expect(above.bottom, tester.getRect(_row('项目甲')).center.dy);
    expect(state.calls, isEmpty);
  });

  testWidgets('菜单打开时这一行高亮，关闭后恢复', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    await tester.pumpWidget(_host(state, project: true));
    Color? shade() => tester
        .widgetList<DecoratedBox>(
          find.ancestor(of: _row('对话甲'), matching: find.byType(DecoratedBox)),
        )
        .map((box) => (box.decoration as BoxDecoration).color)
        .firstOrNull;
    expect(shade(), isNull);
    await _press(tester, '对话甲');
    expect(shade(), isNotNull);
    await tester.tapAt(const Offset(2, 590));
    await tester.pumpAndSettle();
    expect(shade(), isNull);
  });

  testWidgets('离线只留手机自己的操作，失败后保留行并显示错误', (tester) async {
    final state = _State()..online = false;
    addTearDown(state.dispose);
    await tester.pumpWidget(_host(state, project: true));
    await _press(tester, '对话甲');
    expect(find.text('删除该聊天'), findsNothing);
    expect(find.text('置顶'), findsNothing);
    expect(find.text('加入常用'), findsOneWidget);
    await tester.tapAt(const Offset(2, 590));
    await tester.pumpAndSettle();
    state
      ..online = true
      ..fail = true;
    state.notifyListeners();
    await tester.pumpAndSettle();
    await _pick(tester, '对话甲', '置顶');
    expect(find.textContaining('合成操作失败'), findsOneWidget);
    expect(find.text('对话甲'), findsOneWidget);
  });

  testWidgets('窄屏大字号不溢出，进行中的请求不会重复提交', (tester) async {
    tester.view.physicalSize = const Size(300, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = _State()..pending = Completer<void>();
    addTearDown(state.dispose);
    await tester.pumpWidget(_host(state, project: true, scale: 1.8));
    await _press(tester, '对话甲');
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('置顶'));
    await tester.pumpAndSettle();
    await _press(tester, '对话甲');
    expect(_menu, findsNothing);
    expect(state.calls, hasLength(1));
    state.pending!.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('侧栏 Bot 组内置顶，不与项目混排且只存手机', (tester) async {
    final state = _State()..botList = const [_assistant, _helper];
    addTearDown(state.dispose);
    await tester.pumpWidget(_host(state));
    await _navigation(tester);
    expect(
      tester.getTopLeft(_row('项目甲')).dy,
      lessThan(tester.getTopLeft(_row('小宝')).dy),
    );
    await _pick(tester, '帮手', '置顶');
    expect(state.settings.pinnedBots, {('desk', 'hp')});
    expect(
      tester.getTopLeft(_row('帮手')).dy,
      lessThan(tester.getTopLeft(_row('小宝')).dy),
    );
    expect(state.calls, isEmpty);
    await _pick(tester, '帮手', '取消置顶');
    expect(state.settings.pinnedBots, isEmpty);
    expect(state.calls, isEmpty);
  });

  testWidgets('助理只能删聊天，须确认，不会被删除', (tester) async {
    final state = _State()..botList = const [_assistant];
    addTearDown(state.dispose);
    await tester.pumpWidget(_host(state));
    await _press(tester, '小宝');
    expect(find.text('删除该 Bot'), findsNothing);
    await tester.tap(find.text('删除该聊天'));
    await tester.pumpAndSettle();
    expect(state.calls, isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, '清空'));
    await tester.pumpAndSettle();
    expect(state.calls.single.$2, LinkMethods.clearBotChat);
    expect(state.calls.single.$3, {'bot': 'xb'});
  });

  testWidgets('Bot 页置顶排到最前，普通 Bot 能删除并清掉置顶，也能进资料', (tester) async {
    final state = _State()..botList = const [_assistant, _helper];
    addTearDown(state.dispose);
    await tester.pumpWidget(_host(state, botsTab: true));
    await _pick(tester, '帮手', '置顶');
    expect(
      tester.getTopLeft(_row('帮手')).dy,
      lessThan(tester.getTopLeft(_row('小宝')).dy),
    );
    await _press(tester, '帮手');
    expect(find.text('Bot 资料'), findsOneWidget);
    await tester.tap(find.text('删除该 Bot'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(state.calls.single.$2, LinkMethods.deleteBot);
    expect(state.calls.single.$3, {'bot': 'hp'});
    expect(state.settings.pinnedBots, isEmpty);
  });

  testWidgets('离线时 Bot 仍能置顶，不显示删除', (tester) async {
    final state = _State()
      ..botList = const [_helper]
      ..online = false;
    addTearDown(state.dispose);
    await tester.pumpWidget(_host(state, botsTab: true));
    await _press(tester, '帮手');
    expect(find.text('置顶'), findsOneWidget);
    expect(find.text('删除该 Bot'), findsNothing);
  });
}
