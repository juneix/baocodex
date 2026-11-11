import 'dart:async';
import 'dart:convert';

import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/models/user_facing_error.dart';
import 'package:baocode_mobile/state/app_state.dart';
import 'package:baocode_mobile/state/conversation_input.dart';
import 'package:baocode_mobile/link/link_store.dart';
import 'package:baocode_mobile/link/phone_link.dart'
    show DesktopLinkStatus, KeptDesktop;
import 'package:baocode_mobile/ui/conversations/chats_tab.dart';
import 'package:baocode_mobile/ui/files/files_tab.dart';
import 'package:baocode_mobile/ui/tasks/chat_page.dart';
import 'package:baocode_mobile/ui/tasks/chat_activity_card.dart';
import 'package:baocode_mobile/chat/widgets/pixel_loader.dart';
import 'package:baocode_mobile/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _State extends AppState {
  _State({LinkStore? store}) : super(store: store ?? MemoryLinkStore()) {
    settings.language = 'zh';
  }
  bool pinned = true;
  bool withBot = false;
  bool otherRecent = false;
  bool projectRemoved = false;
  bool draftFails = false;
  Completer<Object?>? draftGate;
  final calls = <Map<String, Object?>>[];
  final methods = <String>[];
  final opened = <String>[];
  @override
  List<KeptDesktop> get desktops => const [
    KeptDesktop(id: '在线', name: '在线电脑', publicKey: ''),
    KeptDesktop(id: '离线', name: '离线设备', publicKey: ''),
  ];
  @override
  bool isOnline(String id) => id == '在线';
  @override
  List<ProjectRef> get projects => [
    if (!projectRemoved)
      const ProjectRef('在线', ProjectInfo(id: 'p', name: '项目甲', path: '/p')),
    if (withBot)
      const ProjectRef('在线', ProjectInfo(id: 'e', name: '空项目', path: '/e')),
  ];
  @override
  List<BotRef> get bots => [
    if (withBot) ...[
      BotRef('在线', LinkBot(id: 'b', name: '小宝', assistant: true,
          updatedAt: DateTime(2026, 6))),
      BotRef('在线', LinkBot(id: 'c', name: '审稿 Bot',
          updatedAt: DateTime(2026, 3))),
    ],
  ];
  @override
  List<SessionRef> get sessions => [
    SessionRef('在线', SessionSummary(
      id: '会话甲', project: 'p', title: '置顶任务',
      updatedAt: DateTime(2026), pinned: pinned,
    )),
    SessionRef('在线', SessionSummary(
      id: '会话乙', project: 'p', title: '审批任务',
      updatedAt: DateTime(2025), status: LinkSessionStatus.needsInput,
    )),
    if (otherRecent)
      SessionRef('在线', SessionSummary(
        id: '另一项任务', project: 'e', title: '另一项目更新',
        updatedAt: DateTime(2027),
      )),
  ];
  @override
  LinkPath pathOf(String desktopId) => desktopId == '在线'
      ? const LinkPath(LinkPathKind.relay, rtt: Duration(milliseconds: 399))
      : LinkPath.none;
  @override
  DesktopLinkStatus linkStatus(String desktopId) => isOnline(desktopId)
      ? DesktopLinkStatus.online : DesktopLinkStatus.offline;
  @override
  void retryConnection(String desktopId) {}
  @override
  Future<Object?> request(String desktopId, String method,
      [Map<String, Object?> params = const {}]) async {
    calls.add(Map.of(params));
    methods.add(method);
    if (method == LinkMethods.draft) {
      if (draftFails) throw const UserFacingError('无法创建会话');
      if (draftGate != null) return await draftGate!.future;
      return {'session': 'draft-${params['project']}'};
    }
    if (method == LinkMethods.send) return {'session': params['session']};
    if (method == LinkMethods.pin) {
      pinned = params['pinned'] as bool;
      notifyListeners();
    }
    return null;
  }
  @override
  Future<void> openSession(String desktopId, String sessionId) async {
    opened.add(sessionId);
  }
  @override
  Future<void> closeSession(String desktopId, String sessionId) async {}
}

class _EmptyState extends _State {
  DesktopLinkStatus linkState = DesktopLinkStatus.connecting;
  final retries = <String>[];
  @override
  bool isOnline(String id) => false;
  @override
  List<ProjectRef> get projects => const [];
  @override
  List<SessionRef> get sessions => const [];
  @override
  DesktopLinkStatus linkStatus(String desktopId) => linkState;
  @override
  void retryConnection(String desktopId) => retries.add(desktopId);
}

class _OfflineState extends _State {
  DesktopLinkStatus linkState = DesktopLinkStatus.connecting;
  @override
  bool isOnline(String id) => false;
  @override
  DesktopLinkStatus linkStatus(String desktopId) => linkState;
}

class _Many extends _State {
  @override
  List<SessionRef> get sessions => [
    for (var i = 0; i < 7; i++)
      SessionRef('在线', SessionSummary(
        id: '任务$i', project: 'p', title: '任务$i',
        updatedAt: DateTime(2026, 1, i + 1), pinned: i == 6,
        status: i < 2 ? LinkSessionStatus.needsInput : LinkSessionStatus.idle,
      )),
  ];
}

class _SlowStore extends MemoryLinkStore {
  final gate = Completer<void>();
  bool blocked = false;
  @override
  Future<void> write(String key, String value) async {
    if (key == 'drafts' && !blocked) {
      blocked = true;
      await gate.future;
    }
    await super.write(key, value);
  }
}

Future<void> _mount(WidgetTester tester, AppState state) async {
  await tester.pumpWidget(MaterialApp(
    theme: MobileTheme.build(Brightness.light),
    home: ChatsTab(state: state),
  ));
  await tester.pump();
}

Future<void> _drawer(WidgetTester tester) async {
  await tester.tap(find.byTooltip('项目与对话').first);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  testWidgets('默认进入可编辑的新对话，打开和填建议都不创建远端会话', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    await _mount(tester, state);
    expect(tester.widget<ChatPage>(find.byType(ChatPage)).sessionId, isNull);
    expect(find.byType(PixelLoader), findsNothing);
    expect(find.byType(ChatActivityCard), findsNothing);
    expect(state.calls, isEmpty);
    expect(state.opened, isEmpty);
    await tester.tap(find.text('讲讲这个项目的整体结构'));
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField).first)
        .controller!.text, '讲讲这个项目的整体结构');
    expect(state.calls, isEmpty);
  });

  testWidgets('首屏说明当前电脑和连接状态，离线输入只保存草稿', (tester) async {
    final state = _OfflineState();
    addTearDown(state.dispose);
    await _mount(tester, state);
    expect(find.textContaining('在线电脑'), findsOneWidget);
    expect(find.textContaining('连接中…'), findsOneWidget);
    state.linkState = DesktopLinkStatus.offline;
    state.notifyListeners();
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, '离线任务');
    await tester.pump(const Duration(milliseconds: 350));
    expect(state.inputDraft('在线', AppState.newConversationDraftKey('p')).text,
        '离线任务');
    expect(find.text('草稿已保留'), findsOneWidget);
    expect(state.calls, isEmpty);
  });

  testWidgets('项目下直接列对话，选择项目不经过文件夹页也不发请求', (tester) async {
    final state = _State()..withBot = true;
    addTearDown(state.dispose);
    await _mount(tester, state);
    await _drawer(tester);
    expect(find.text('置顶任务'), findsOneWidget);
    expect(find.text('审批任务'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('project-在线-p')));
    await tester.pump();
    expect(find.byType(ProjectChatsPage), findsNothing);
    expect(find.text('审批任务'), findsOneWidget);
    expect(state.calls, isEmpty);
    expect(state.settings.lastProjectByDesktop['在线'], 'p');
    await tester.ensureVisible(find.byKey(const ValueKey('project-在线-e')));
    await tester.tap(find.byKey(const ValueKey('project-在线-e')));
    await tester.pump();
    expect(tester.widget<ChatPage>(find.byType(ChatPage)).projectId, 'e');
    expect(state.calls, isEmpty);
  });

  testWidgets('每组默认五条，折叠外的待处理仍计数，展开后可收起', (tester) async {
    final state = _Many();
    addTearDown(state.dispose);
    await _mount(tester, state);
    await _drawer(tester);
    expect(find.text('任务0'), findsNothing);
    expect(find.text('任务1'), findsNothing);
    expect(find.textContaining('2 个待处理'), findsOneWidget);
    final more = find.byKey(const ValueKey('project-more-在线-p'));
    await tester.ensureVisible(more);
    await tester.tap(more);
    await tester.pump();
    expect(find.text('任务0'), findsOneWidget);
    expect(find.text('任务1'), findsOneWidget);
    await tester.ensureVisible(more);
    await tester.tap(more);
    await tester.pump();
    expect(find.text('任务0'), findsNothing);
    expect(find.textContaining('2 个待处理'), findsOneWidget);
  });

  testWidgets('项目折叠独立保存，点项目名称直接重新展开', (tester) async {
    final state = _State()..withBot = true;
    addTearDown(state.dispose);
    await _mount(tester, state);
    await _drawer(tester);
    await tester.tap(find.byKey(const ValueKey('project-fold-在线-p')));
    await tester.pump();
    expect(find.text('审批任务'), findsNothing);
    expect(find.byKey(const ValueKey('project-在线-e')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('project-在线-p')));
    await tester.pump();
    expect(find.text('审批任务'), findsOneWidget);
    expect(state.calls, isEmpty);
  });

  testWidgets('选会话仍能打开共享侧栏，切换不堆叠，返回新对话', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    await _mount(tester, state);
    await _drawer(tester);
    await tester.tap(find.byKey(const ValueKey('session-在线-会话甲')));
    await tester.pumpAndSettle();
    expect(tester.widget<ChatPage>(find.byType(ChatPage)).sessionId, '会话甲');
    await _drawer(tester);
    await tester.tap(find.byKey(const ValueKey('session-在线-会话乙')));
    await tester.pumpAndSettle();
    expect(find.byType(ChatPage), findsOneWidget);
    expect(tester.widget<ChatPage>(find.byType(ChatPage)).sessionId, '会话乙');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(tester.widget<ChatPage>(find.byType(ChatPage)).sessionId, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('旧首页选择成为常用，移除常用不删除项目内会话', (tester) async {
    final state = _State()..settings.homeSessions.add(('在线', '会话甲'));
    addTearDown(state.dispose);
    await _mount(tester, state);
    await _drawer(tester);
    final favorite = find.byKey(const ValueKey('home-在线-会话甲'));
    await tester.longPress(favorite);
    await tester.pumpAndSettle();
    await tester.tap(find.text('从常用移除'));
    await tester.pumpAndSettle();
    expect(favorite, findsNothing);
    expect(find.byKey(const ValueKey('session-在线-会话甲')), findsOneWidget);
    expect(state.settings.homeSessions, isEmpty);
    expect(state.calls, isEmpty);
  });

  testWidgets('辅助筛选不再提供第二套项目选择，也不发送请求', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    await _mount(tester, state);
    await _drawer(tester);
    await tester.tap(find.byTooltip('筛选对话'));
    await tester.pumpAndSettle();
    expect(find.text('SSH / WSL'), findsOneWidget);
    expect(find.text('全部项目'), findsNothing);
    await tester.tap(find.text('进行中'));
    await tester.pump();
    expect(state.calls, isEmpty);
  });

  testWidgets('侧栏电脑切换只显示所选电脑，已有项目草稿不串过去', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    await _mount(tester, state);
    await tester.enterText(find.byType(TextField).first, '电脑甲的任务');
    await _drawer(tester);
    await tester.tap(find.byTooltip('切换电脑').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('离线设备'));
    await tester.pumpAndSettle();
    expect(state.selectedDesktopId, '离线');
    expect(find.byKey(const ValueKey('project-在线-p')), findsNothing);
    expect(state.inputDraft('在线', AppState.newConversationDraftKey('p')).text,
        '电脑甲的任务');
    expect(state.inputDraft('离线', AppState.newConversationDraftKey('p')).text,
        isEmpty);
    expect(state.calls, isEmpty);
  });

  testWidgets('无项目时保留连接说明与重试入口', (tester) async {
    final state = _EmptyState();
    addTearDown(state.dispose);
    await _mount(tester, state);
    expect(find.text('正在连接 在线电脑…'), findsOneWidget);
    state.linkState = DesktopLinkStatus.offline;
    state.notifyListeners();
    await tester.pump();
    await tester.tap(find.text('重试'));
    expect(state.retries, ['在线']);
  });

  testWidgets('首次发送只创建一次，刷新不会清空真实会话或重新创建', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    await _mount(tester, state);
    await tester.enterText(find.byType(TextField).first, '检查当前改动');
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();
    expect(state.methods, [LinkMethods.draft, LinkMethods.send]);
    expect(state.calls.last['session'], 'draft-p');
    expect(state.calls.last['text'], '检查当前改动');
    expect(state.opened, ['draft-p']);
    state.notifyListeners();
    await tester.pump();
    expect(tester.widget<ChatPage>(find.byType(ChatPage)).sessionId, 'draft-p');
    await tester.enterText(find.byType(TextField).first, '继续检查');
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();
    expect(state.methods.where((method) => method == LinkMethods.draft),
        hasLength(1));
    expect(state.calls.last['session'], 'draft-p');
  });

  testWidgets('创建失败保留文字且不发送任务', (tester) async {
    final state = _State()..draftFails = true;
    addTearDown(state.dispose);
    await _mount(tester, state);
    await tester.enterText(find.byType(TextField).first, '不能丢失的任务');
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();
    expect(state.methods, [LinkMethods.draft]);
    expect(find.textContaining('无法创建会话'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField).first)
        .controller!.text, '不能丢失的任务');
    expect(tester.widget<ChatPage>(find.byType(ChatPage)).sessionId, isNull);
  });

  testWidgets('其他项目活动刷新不会改变正在输入的项目', (tester) async {
    final state = _State()..withBot = true;
    addTearDown(state.dispose);
    await _mount(tester, state);
    await tester.enterText(find.byType(TextField).first, '项目甲的输入');
    state.otherRecent = true;
    state.notifyListeners();
    await tester.pump(const Duration(milliseconds: 350));
    expect(tester.widget<ChatPage>(find.byType(ChatPage)).projectId, 'p');
    expect(state.inputDraft('在线', AppState.newConversationDraftKey('p')).text,
        '项目甲的输入');
    expect(state.settings.lastProjectByDesktop['在线'], 'p');
    expect(state.calls, isEmpty);
  });

  testWidgets('项目失效保留原输入，不自动改到其他项目执行', (tester) async {
    final state = _State()..withBot = true;
    addTearDown(state.dispose);
    await _mount(tester, state);
    await tester.enterText(find.byType(TextField).first, '原项目任务');
    state.projectRemoved = true;
    state.notifyListeners();
    await tester.pump();
    expect(tester.widget<ChatPage>(find.byType(ChatPage)).projectId, 'p');
    expect(find.textContaining('所选项目暂不可用'), findsOneWidget);
    await tester.tap(find.byTooltip('发送'));
    await tester.pump();
    expect(state.calls, isEmpty);
    expect(tester.widget<TextField>(find.byType(TextField).first)
        .controller!.text, '原项目任务');
  });

  testWidgets('切换项目后迟到的草稿结果不绑定也不发送', (tester) async {
    final state = _State()
      ..withBot = true
      ..draftGate = Completer<Object?>();
    addTearDown(state.dispose);
    await _mount(tester, state);
    await tester.enterText(find.byType(TextField).first, '项目甲草稿');
    await tester.tap(find.byTooltip('模型与权限'));
    await tester.pump();
    await _drawer(tester);
    final other = find.byKey(const ValueKey('project-在线-e'));
    await tester.ensureVisible(other);
    await tester.tap(other);
    await tester.pump();
    await tester.tap(find.byTooltip('关闭菜单'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '空项目草稿');
    state.draftGate!.complete({'session': '过期会话'});
    await tester.pumpAndSettle();
    final page = tester.widget<ChatPage>(find.byType(ChatPage));
    expect(page.projectId, 'e');
    expect(page.sessionId, isNull);
    expect(state.opened, isEmpty);
    expect(state.methods, [LinkMethods.draft]);
    expect(tester.widget<TextField>(find.byType(TextField).first)
        .controller!.text, '空项目草稿');
  });

  testWidgets('安全存储慢写不阻塞首发，也不清掉后来的同项目输入', (tester) async {
    final store = _SlowStore();
    final state = _State(store: store);
    addTearDown(state.dispose);
    addTearDown(() {
      if (!store.gate.isCompleted) store.gate.complete();
    });
    await _mount(tester, state);
    await tester.enterText(find.byType(TextField).first, '第一项任务');
    await tester.pump(const Duration(milliseconds: 350));
    expect(store.blocked, isTrue);
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();
    expect(state.methods, [LinkMethods.draft, LinkMethods.send]);
    await tester.tap(find.byTooltip('新对话'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '下一项任务');
    await tester.pump(const Duration(milliseconds: 350));
    store.gate.complete();
    await tester.pumpAndSettle();
    final key = AppState.newConversationDraftKey('p');
    expect(state.inputDraft('在线', key).text, '下一项任务');
    final stored = jsonDecode((await store.read('drafts'))!) as Map;
    expect(InputDraft.fromStored(stored[jsonEncode(['在线', key])]).text,
        '下一项任务');
  });

  testWidgets('冷启动使用每台电脑上次有效项目', (tester) async {
    final state = _State()..withBot = true;
    state.settings.lastProjectByDesktop['在线'] = 'e';
    addTearDown(state.dispose);
    await _mount(tester, state);
    expect(tester.widget<ChatPage>(find.byType(ChatPage)).projectId, 'e');
    expect(state.calls, isEmpty);
  });

  testWidgets('文件页仍只列所选电脑的项目，不显示对话状态', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    await tester.pumpWidget(MaterialApp(home: AnimatedBuilder(
      animation: state, builder: (_, _) => FilesTab(state: state),
    )));
    expect(find.text('项目甲'), findsOneWidget);
    expect(find.textContaining('待处理'), findsNothing);
    state.selectDesktop('离线');
    await tester.pump();
    expect(find.text('项目甲'), findsNothing);
    expect(find.text('电脑离线'), findsOneWidget);
  });
}
