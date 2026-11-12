import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/link/link_store.dart';
import 'package:baocode_mobile/state/app_state.dart';
import 'package:baocode_mobile/ui/bots/bots_tab.dart';
import 'package:baocode_mobile/ui/files/files_tab.dart';
import 'package:baocode_mobile/ui/home_shell.dart';
import 'package:baocode_mobile/ui/settings/settings_page.dart';
import 'package:baocode_mobile/ui/tasks/chat_page.dart';
import 'package:baocode_mobile/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Unread extends AppState {
  _Unread() : super(demo: true, store: MemoryLinkStore());
  @override
  List<ProjectRef> get projects => const [
    ProjectRef('demo-desktop', ProjectInfo(id: 'p', name: '测试工作区', path: '/p')),
  ];
  @override
  List<SessionRef> get sessions => [
    SessionRef('demo-desktop', SessionSummary(
      id: 'a', project: 'p', title: '未读', updatedAt: DateTime(2026), unread: true,
    )),
    SessionRef('demo-desktop', SessionSummary(
      id: 'b', project: 'p', title: '已读', updatedAt: DateTime(2026),
    )),
    SessionRef('demo-desktop', SessionSummary(
      id: 'c', project: 'p', title: '后台还在跑', updatedAt: DateTime(2026),
      status: LinkSessionStatus.running, unread: true,
    )),
    SessionRef('demo-desktop', SessionSummary(
      id: 'd', project: 'p', title: '在等你', updatedAt: DateTime(2026),
      status: LinkSessionStatus.needsInput,
    )),
  ];
  @override
  List<BotRef> get bots => const [
    BotRef('demo-desktop', LinkBot(id: 'x', name: '测试 Bot', unread: 2)),
  ];
}

Future<void> _mount(WidgetTester tester, AppState state) async {
  await state.initialize();
  state.settings.language = 'zh';
  await tester.pumpWidget(MaterialApp(
    theme: MobileTheme.build(Brightness.light),
    home: HomeShell(state: state),
  ));
  await tester.pumpAndSettle();
}

Future<void> _drawer(WidgetTester tester) async {
  await tester.tap(find.byTooltip('项目与对话').first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('启动新对话且没有底部栏和横向标签容器', (tester) async {
    final state = AppState(demo: true, store: MemoryLinkStore());
    addTearDown(state.dispose);
    await _mount(tester, state);
    expect(find.byType(PageView), findsNothing);
    expect(find.byKey(const ValueKey('tab-badge-0')), findsNothing);
    expect(tester.widget<Scaffold>(find.byType(Scaffold).first).bottomNavigationBar, isNull);
    expect(tester.widget<ChatPage>(find.byType(ChatPage)).sessionId, isNull);
    expect(find.byTooltip('新对话'), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-open-files')), findsOneWidget);
    expect(find.text('今天想做点什么？'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('右滑开工作区侧栏，左滑开会话抽屉并通过返回回到对话', (tester) async {
    final state = AppState(demo: true, store: MemoryLinkStore());
    addTearDown(state.dispose);
    await _mount(tester, state);
    Finder swipeArea() => find.descendant(
      of: find.byType(ChatPage),
      matching: find.byWidgetPredicate((widget) =>
          widget is GestureDetector && widget.onHorizontalDragEnd != null),
    );
    await tester.fling(swipeArea().first, const Offset(200, 0), 1200);
    await tester.pumpAndSettle();
    final drawer = find.byKey(const ValueKey('conversation-drawer'));
    final width = MediaQuery.sizeOf(tester.element(find.byType(HomeShell))).width;
    expect(tester.getSize(drawer).width, closeTo(width * .8, 1));
    expect(find.text('BaoCodeX'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.fling(swipeArea().first, const Offset(-200, 0), 1200);
    await tester.pumpAndSettle();
    final sessionDrawer = find.byKey(const ValueKey('session-drawer'));
    expect(sessionDrawer, findsOneWidget);
    expect(tester.getSize(sessionDrawer).width, closeTo(width * .8, 1));
    expect(find.byKey(const ValueKey('session-menu-files')), findsOneWidget);
    expect(find.byKey(const ValueKey('session-menu-changes')), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('session-drawer')), findsNothing);
    expect(find.byType(ChatPage), findsOneWidget);
    expect(find.byType(PageView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('移除底栏不丢失项目待处理和 Bot 未读提示', (tester) async {
    final state = _Unread();
    addTearDown(state.dispose);
    await _mount(tester, state);
    await _drawer(tester);
    final project = find.byKey(const ValueKey('project-demo-desktop-p'));
    final badge = tester.widget<Badge>(find.descendant(
      of: project,
      matching: find.byType(Badge),
    ).first);
    expect(badge.isLabelVisible, isTrue);
    expect(find.descendant(of: project, matching: find.text('2')), findsOneWidget);
    expect(find.byKey(const ValueKey('bot-demo-desktop-x')), findsOneWidget);
    expect(find.byKey(const ValueKey('drawer-bots')), findsOneWidget);
    expect(find.byKey(const ValueKey('drawer-settings')), findsOneWidget);
    expect(find.byKey(const ValueKey('tab-badge-0')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Bot 和文件从独立路由进入，返回保留当前草稿', (tester) async {
    final state = AppState(demo: true, store: MemoryLinkStore());
    addTearDown(state.dispose);
    await _mount(tester, state);
    await tester.enterText(find.byType(TextField).first, '保留这份草稿');
    await _drawer(tester);
    await tester.tap(find.byKey(const ValueKey('drawer-bots')));
    await tester.pumpAndSettle();
    expect(find.byType(BotsTab), findsOneWidget);
    expect(find.byType(BackButton), findsWidgets);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        '保留这份草稿');
    await tester.tap(find.byKey(const ValueKey('chat-open-files')));
    await tester.pumpAndSettle();
    expect(find.byType(FilesPage), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        '保留这份草稿');
    expect(tester.takeException(), isNull);
  });

  testWidgets('设置、关于和版本页显示新品牌并保持原子路由', (tester) async {
    final state = AppState(demo: true, store: MemoryLinkStore());
    addTearDown(state.dispose);
    await _mount(tester, state);
    await _drawer(tester);
    await tester.tap(find.byKey(const ValueKey('drawer-settings')));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.byType(BackButton), findsWidgets);
    await tester.scrollUntilVisible(find.text('关于 BaoCodeX').hitTestable(), 100);
    await tester.tap(find.text('关于 BaoCodeX'));
    await tester.pumpAndSettle();
    expect(find.text('BaoCodeX'), findsOneWidget);
    expect(find.text('版本 $appVersion'), findsOneWidget);
    await tester.tap(find.text('开源许可'));
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
    expect(find.text('BaoCodeX'), findsWidgets);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('当前版本'));
    await tester.pumpAndSettle();
    expect(find.text('BaoCodeX $appVersion'), findsOneWidget);
    expect(find.text('检查更新'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('检查更新'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(ChatPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
