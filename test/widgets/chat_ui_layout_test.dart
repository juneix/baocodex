import 'dart:async';

import 'package:bao_link/bao_link.dart';
import 'package:clock/clock.dart';
import 'package:baocode_mobile/link/phone_link.dart';
import 'package:baocode_mobile/state/app_state.dart';
import 'package:baocode_mobile/theme/app_theme.dart';
import 'package:baocode_mobile/ui/tasks/chat_page.dart';
import 'package:baocode_mobile/ui/tasks/session_sync_notice.dart';
import 'package:baocode_mobile/ui/widgets/mobile_widgets.dart';
import 'package:baocode_mobile/ui/tasks/changes_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:baocode_mobile/models/user_facing_error.dart';

class _State extends AppState {
  _State() : super(store: MemoryLinkStore());
  final history = SessionBuffer('desktop', 'session');
  final calls = <String>[];
  String saved = '';
  bool pinned = false;
  bool online = true;
  bool fail = false;
  bool planGone = false;
  bool withBot = false;
  DesktopLinkStatus? linkOverride;
  int refreshes = 0;
  Completer<void>? refreshing;

  @override
  Future<void> refreshSession(String desktop, String session) async {
    refreshes++;
    history.loading = true;
    history.error = null;
    update();
    await refreshing?.future;
    history.loading = false;
    update();
  }

  Map<String, Object?> lastParams = const {};
  @override
  List<SessionRef> get sessions => [
    SessionRef(
      'desktop',
      SessionSummary(
        id: 'session',
        project: 'project',
        title: '对话',
        updatedAt: DateTime(2026),
        pinned: pinned,
      ),
    ),
  ];
  @override
  List<BotRef> get bots => [
    if (withBot)
      const BotRef('desktop', LinkBot(
        id: 'bot', name: '测试助理', session: 'session',
      )),
  ];

  void update() {
    history.revision++;
    notifyListeners();
  }

  @override
  String tr(String zh, String en) => zh;
  @override
  bool isOnline(String desktop) => online;
  @override
  DesktopLinkStatus linkStatus(String desktopId) =>
      linkOverride ??
      (online ? DesktopLinkStatus.online : DesktopLinkStatus.offline);
  @override
  String desktopName(String desktop) => '联调电脑';
  @override
  List<ProjectRef> get projects => [
    const ProjectRef(
      'desktop',
      ProjectInfo(
        id: 'project',
        name: '测试项目',
        path: 'E:/project/测试项目',
        branch: '真实分支',
      ),
    ),
  ];
  @override
  SessionBuffer buffer(String desktop, String session) => history;
  @override
  String draft(String desktop, String session) => saved;
  @override
  Future<void> setDraft(String desktop, String session, String text) async {
    saved = text;
  }

  @override
  Future<void> openSession(String desktop, String session) async {}
  @override
  Future<void> closeSession(String desktop, String session) async {}
  @override
  Future<Object?> request(
    String desktop,
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    calls.add(method);
    lastParams = params;
    // 停止没有通用错误；它有自己的说法，原始异常不该露出来。
    if (fail && method == LinkMethods.stopTask) {
      throw StateError('原始错误细节');
    }
    if (fail) throw const UserFacingError('请求失败');
    if (planGone && method == LinkMethods.startPlan) {
      throw const LinkRemoteException(LinkErrors.notFound, 'no plan');
    }
    if (method == LinkMethods.read) return {'original': 'old', 'text': 'new'};
    if (method == LinkMethods.draft) return {'session': 'new-session'};
    return null;
  }
}

Widget _host(
  _State state, {
  bool dark = false,
  double scale = 1,
  double keyboard = 0,
  bool bot = false,
}) => MaterialApp(
  theme: MobileTheme.build(
    dark ? Brightness.dark : Brightness.light,
    codeFontSize: 14,
  ),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(scale),
      viewInsets: EdgeInsets.only(bottom: keyboard),
    ),
    child: child!,
  ),
  home: ChatPage(
    state: state,
    desktopId: 'desktop',
    sessionId: 'session',
    title: '很长的中文对话标题需要合理省略而不是挤占操作区域',
    projectId: 'project',
    botId: bot ? 'bot' : null,
  ),
);

void main() {
  testWidgets('已连接但仍在同步时延迟显示文字，旧内容保留且完成后收起', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    state.history
      ..items.add({'t': 'user', 'text': '缓存中的旧消息'})
      ..loading = true;
    await tester.pumpWidget(_host(state));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('同步中…'), findsNothing);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('同步中…'), findsOneWidget);
    expect(find.text('缓存中的旧消息'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    state.history.loading = false;
    state.update();
    await tester.pump();
    expect(find.text('同步中…'), findsNothing);
    expect(find.text('缓存中的旧消息'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('连接中、同步中到完成，全程只有标题下一行状态且无独立同步行', (tester) async {
    final semantics = tester.ensureSemantics();
    final state = _State()
      ..online = false
      ..linkOverride = DesktopLinkStatus.connecting;
    addTearDown(state.dispose);
    state.history
      ..items.add({'t': 'user', 'text': '缓存中的旧消息'})
      ..loading = true;
    await tester.pumpWidget(_host(state));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('连接中…'), findsOneWidget);
    expect(find.text('同步中…'), findsNothing);
    expect(find.byType(SessionSyncNotice), findsOneWidget);
    expect(tester.getSize(find.byType(SessionSyncNotice)).height, 0);
    state
      ..online = true
      ..linkOverride = null;
    state.update();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('连接中…'), findsNothing);
    expect(find.text('同步中…'), findsOneWidget);
    expect(find.byType(ConnectingSpinner), findsOneWidget);
    // 只有转圈用主题色，文字仍是那行灰：不同错误状态的红混在一起。
    final scheme = Theme.of(tester.element(find.byType(ConnectingSpinner)))
        .colorScheme;
    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .color,
      scheme.primary,
    );
    expect(
      tester.widget<Text>(find.text('同步中…')).style?.color,
      scheme.onSurfaceVariant,
    );
    expect(find.bySemanticsLabel(RegExp('正在同步最新消息')), findsOneWidget);
    expect(tester.getSize(find.byType(SessionSyncNotice)).height, 0);
    state.history.loading = false;
    state.update();
    await tester.pump();
    expect(find.text('同步中…'), findsNothing);
    expect(find.text('对话项目'), findsNothing);
    expect(find.byType(ConnectingSpinner), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    semantics.dispose();
  });

  testWidgets('很快完成的内容同步不闪提示，也不留下延迟计时器', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    state.history
      ..items.add({'t': 'user', 'text': '缓存中的旧消息'})
      ..loading = true;
    await tester.pumpWidget(_host(state));
    await tester.pump(const Duration(milliseconds: 100));
    state.history.loading = false;
    state.update();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('同步中…'), findsNothing);
    expect(find.text('缓存中的旧消息'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('内容同步失败与连接状态区分，可重试且保留原消息', (tester) async {
    final state = _State()..refreshing = Completer<void>();
    addTearDown(state.dispose);
    state.history
      ..items.add({'t': 'user', 'text': '缓存中的旧消息'})
      ..error = '拉取会话超时';
    await tester.pumpWidget(_host(state));
    await tester.pump();
    expect(find.text('内容未更新'), findsOneWidget);
    expect(find.byType(MaterialBanner), findsNothing);
    await tester.tap(find.text('重试'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(state.refreshes, 1);
    expect(find.text('同步中…'), findsOneWidget);
    expect(find.text('缓存中的旧消息'), findsOneWidget);
    state.refreshing!.complete();
    await tester.pumpAndSettle();
    expect(find.text('同步中…'), findsNothing);
    expect(find.text('内容未更新'), findsNothing);
    expect(find.text('缓存中的旧消息'), findsOneWidget);
  });

  testWidgets('同步提示出现和收起不改变正在阅读消息的位置', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    state.history.items.addAll([
      for (var i = 0; i < 30; i++) {'t': 'user', 'text': '历史消息 $i'},
    ]);
    await tester.pumpWidget(_host(state));
    await tester.pumpAndSettle();
    final list = find.byWidgetPredicate(
      (widget) => widget is CustomScrollView && widget.controller != null,
    );
    await tester.drag(list, const Offset(0, 350));
    await tester.pumpAndSettle();
    final bounds = tester.getRect(list);
    final index = List.generate(30, (i) => i).firstWhere((i) {
      final row = find.byKey(ValueKey(i));
      return row.evaluate().isNotEmpty &&
          bounds.contains(tester.getRect(row).center);
    });
    final row = find.byKey(ValueKey(index));
    final before = tester.getTopLeft(row).dy;
    state.history.loading = true;
    state.update();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    expect(find.text('同步中…'), findsOneWidget);
    expect(tester.getTopLeft(row).dy, closeTo(before, 1));
    state.history.loading = false;
    state.update();
    await tester.pump();
    await tester.pump();
    expect(tester.getTopLeft(row).dy, closeTo(before, 1));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final contextLabel in ['1M', '']) {
    testWidgets(
      '模型显示名称与图标，${contextLabel.isEmpty ? '缺少容量时不编数字' : '提示上下文 $contextLabel'}',
      (tester) async {
        final state = _State();
        addTearDown(state.dispose);
        state.history.choices = [
          const LinkChoice(
            kind: 'model',
            selected: 'claude-test',
            options: [LinkOption(id: 'claude-test', label: '测试模型')],
          ),
          if (contextLabel.isNotEmpty)
            LinkChoice(
              kind: 'context',
              selected: 'chosen',
              options: [LinkOption(id: 'chosen', label: contextLabel)],
            ),
        ];
        await tester.pumpWidget(_host(state));
        await tester.pumpAndSettle();
        final model = find.byTooltip(
          contextLabel.isEmpty ? '模型: 测试模型' : '模型: 测试模型 · 上下文 $contextLabel',
        );
        expect(model, findsOneWidget);
        expect(
          find.descendant(of: model, matching: find.byType(SvgPicture)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: model, matching: find.byType(Text)),
          findsOneWidget,
        );
        expect(find.text('测试模型'), findsOneWidget);
        if (contextLabel.isNotEmpty) {
          expect(find.text(contextLabel), findsNothing);
        }
        final bar = find.byKey(const ValueKey('composer-input-surface'));
        expect(
          find.descendant(
            of: bar,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is SingleChildScrollView &&
                  widget.scrollDirection == Axis.horizontal,
            ),
          ),
          findsNothing,
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('加号弹层第一行四个入口，权限和模式各在独立设置行', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = _State();
    addTearDown(state.dispose);
    state.history.choices = const [
      LinkChoice(kind: 'model', selected: 'model',
          options: [LinkOption(id: 'model', label: '测试模型')]),
      LinkChoice(kind: 'mode', selected: 'agent', options: [
        LinkOption(id: 'agent', label: 'Agent'),
        LinkOption(id: 'ask', label: 'Ask'),
        LinkOption(id: 'plan', label: 'Plan'),
      ]),
      LinkChoice(kind: 'permission', selected: 'acceptEdits', options: [
        LinkOption(id: 'default', label: '逐项批准'),
        LinkOption(id: 'acceptEdits', label: '自动接受编辑'),
      ]),
    ];
    await tester.pumpWidget(_host(state, scale: 1.4));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更多输入选项'));
    await tester.pumpAndSettle();
    Rect tile(String id) =>
        tester.getRect(find.byKey(ValueKey('chat-action-$id')));
    final album = tile('album');
    final camera = tile('camera');
    final file = tile('file');
    final command = tile('command');
    // 四个入口同一行、等宽，按图片、相机、文件、命令排序。
    expect(camera.top, closeTo(album.top, .01));
    expect(file.top, closeTo(album.top, .01));
    expect(command.top, closeTo(album.top, .01));
    expect(camera.width, closeTo(album.width, .01));
    expect(file.width, closeTo(album.width, .01));
    expect(command.width, closeTo(album.width, .01));
    expect(camera.left, greaterThan(album.right));
    expect(file.left, greaterThan(camera.right));
    expect(command.left, greaterThan(file.right));
    expect(find.byType(BottomSheet), findsOneWidget);
    // 弹层使用同一边距，设置不重复放成附件图标。
    final panel = find.byKey(const ValueKey('chat-actions'));
    expect(
      tester.getSize(panel).width,
      closeTo(tester.view.physicalSize.width, .01),
    );
    expect(tester.getRect(panel).left, closeTo(album.left - 16, .01));
    expect(find.byKey(const ValueKey('composer-setting-permission')), findsOneWidget);
    expect(find.byKey(const ValueKey('composer-mode')), findsOneWidget);
    expect(find.text('自动接受编辑'), findsOneWidget);
    // 模型在输入栏，权限和模式在弹层中，不重复放成附件图标。
    for (final id in ['model', 'mode', 'permission', 'stickers']) {
      expect(find.byKey(ValueKey('chat-action-$id')), findsNothing);
    }
    expect(
      tester.getBottomLeft(find.byKey(const ValueKey('chat-actions'))).dy,
      lessThanOrEqualTo(tester.view.physicalSize.height),
    );
    expect(tester.takeException(), isNull);
  });

  LinkTask task0(
    String id,
    String kind,
    String title, {
    String? tool,
    String? summary,
    int at = 1,
  }) => LinkTask(
    id: id,
    kind: kind,
    description: title,
    status: 'running',
    startedAt: DateTime(2026, 1, 1, 0, at),
    toolUseId: tool,
    summary: summary,
  );

  Finder stopOf(String key) => find.byKey(ValueKey('task-stop-$key'));

  /// Opens the pill over the composer into its panel.
  Future<void> openTray(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('activity-tasks-expand')));
    // The tray grows from the next frame on.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('改动摘要进入独立页面且返回后保留任务展开状态，不触发写入', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    state.history.items.addAll([
      {'t': 'agent', 'id': 'one', 'description': '检查布局', 'status': 'running'},
      {'t': 'agent', 'id': 'two', 'description': '检查交互', 'status': 'running'},
    ]);
    state.history.changes = [
      {'path': 'lib/a.dart', 'added': 4, 'removed': 2},
    ];
    await tester.pumpWidget(_host(state));
    await tester.pump();
    final card = find.byKey(const ValueKey('chat-activity-card'));
    // Over the composer, as the desktop's strip, not under the app bar.
    expect(
      tester.getBottomLeft(card).dy,
      lessThanOrEqualTo(
        tester
            .getTopLeft(find.byKey(const ValueKey('composer-input-surface')))
            .dy,
      ),
    );
    expect(
      tester.getBottomLeft(card).dy,
      closeTo(
        tester
            .getTopLeft(find.byKey(const ValueKey('composer-input-surface')))
            .dy,
        8,
      ),
    );
    // Folded to a pill: nothing in it to hit by accident.
    expect(find.byKey(const ValueKey('activity-changes-toggle')), findsNothing);
    expect(find.text('保留'), findsNothing);
    expect(find.text('2 个任务'), findsOneWidget);
    expect(find.text('a.dart'), findsNothing);
    await openTray(tester);
    expect(find.text('2 个子代理运行中'), findsOneWidget);
    expect(find.text('保留'), findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.text('检查布局')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('检查交互')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('activity-changes-toggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(ChangesPage), findsOneWidget);
    expect(find.text('全部改动'), findsOneWidget);
    expect(find.text('a.dart'), findsOneWidget);
    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('a.dart'), findsNothing);
    expect(
      find.descendant(of: card, matching: find.text('检查布局')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('activity-tasks-collapse')));
    // The tray grows from the next frame on.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('activity-tasks-collapse')), findsNothing);
    expect(state.calls, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('任务行去掉 Running 前缀，与文件行等高，圆圈里没有图标', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    state.history.tasks = [
      task0(
        't1',
        'agent',
        '实现文件源码阅读',
        tool: 'u1',
        summary: 'Running 复验导航仅消费新请求',
      ),
    ];
    state.history.changes = [
      {'path': 'lib/a.dart', 'added': 244, 'removed': 39},
    ];
    await tester.pumpWidget(_host(state));
    await tester.pump();
    await openTray(tester);
    expect(find.text('复验导航仅消费新请求'), findsOneWidget);
    expect(find.textContaining('Running'), findsNothing);
    final row = find.byKey(const ValueKey('task-card-agent:u1'));
    final block = find.byKey(const ValueKey('activity-changes-block'));
    expect(tester.getSize(row).height, tester.getSize(block).height);
    expect(
      find.descendant(
        of: row,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.byType(SvgPicture)),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('任务很多时面板内滚动，文件块固定在最下面', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = _State();
    addTearDown(state.dispose);
    state.history.tasks = [
      for (var i = 0; i < 8; i++)
        task0('t$i', 'agent', '任务 $i', tool: 'u$i', at: i),
    ];
    state.history.changes = [
      {'path': 'lib/a.dart', 'added': 1, 'removed': 0},
    ];
    await tester.pumpWidget(_host(state));
    await tester.pump();
    expect(find.text('8 个任务'), findsOneWidget);
    await openTray(tester);
    final list = find.byKey(const ValueKey('activity-task-list'));
    expect(tester.getSize(list).height, lessThanOrEqualTo(220));
    final changes = find.byKey(const ValueKey('activity-changes-block'));
    final top = tester.getTopLeft(changes).dy;
    await tester.drag(list, const Offset(0, -200));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byKey(const ValueKey('activity-tasks-collapse')),
      findsOneWidget,
    );
    expect(tester.getTopLeft(changes).dy, top);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('滚动消息和返回键都先收起面板', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    for (var i = 0; i < 30; i++) {
      state.history.items.add({'t': 'text', 'text': '消息 $i\n第二行\n第三行'});
    }
    state.history.tasks = [task0('t1', 'agent', '检查布局', tool: 'u1')];
    await tester.pumpWidget(_host(state));
    await tester.pump(const Duration(milliseconds: 300));
    await openTray(tester);
    expect(stopOf('agent:u1'), findsOneWidget);
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, 200),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(stopOf('agent:u1'), findsNothing);
    expect(find.byKey(const ValueKey('activity-pill')), findsOneWidget);

    await openTray(tester);
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(ChatPage), findsOneWidget);
    expect(stopOf('agent:u1'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('需要处理时胶囊转圈换成红点', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    state.history.tasks = [task0('t1', 'agent', '检查布局', tool: 'u1')];
    await tester.pumpWidget(_host(state));
    await tester.pump();
    final dot = find.byKey(const ValueKey('activity-attention'));
    expect(dot, findsNothing);
    state.history.interaction = {'kind': 'approval', 'id': 'a'};
    state.update();
    await tester.pump();
    expect(dot, findsOneWidget);
    final box = tester.widget<Container>(dot);
    expect(
      (box.decoration! as BoxDecoration).color,
      Theme.of(tester.element(dot)).colorScheme.error,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('多个任务折叠只显示最近一张加数量，展开列出全部并可收起', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    state.history.tasks = [
      task0('t1', 'agent', '较早的子代理', tool: 'u1', at: 1),
      task0('t2', 'command', '构建脚本', at: 3),
      task0('t3', 'agent', '最近的子代理', tool: 'u3', at: 5),
    ];
    await tester.pumpWidget(_host(state));
    await tester.pump();
    expect(find.text('3 个任务'), findsOneWidget);
    expect(find.text('最近的子代理'), findsNothing);
    expect(find.text('构建脚本'), findsNothing);
    expect(find.text('较早的子代理'), findsNothing);
    expect(stopOf('agent:u3'), findsNothing);
    await openTray(tester);
    expect(find.text('3 个后台任务运行中'), findsOneWidget);
    expect(find.text('最近的子代理'), findsOneWidget);
    expect(find.text('构建脚本'), findsOneWidget);
    expect(find.text('较早的子代理'), findsOneWidget);
    expect(stopOf('task:t2'), findsOneWidget);
    expect(stopOf('agent:u1'), findsOneWidget);
    await tester.tap(find.text('收起'));
    // The tray grows from the next frame on.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('3 个任务'), findsOneWidget);
    expect(find.text('收起'), findsNothing);
    expect(find.text('构建脚本'), findsNothing);
    expect(find.text('最近的子代理'), findsNothing);
    expect(state.calls, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('子代理卡片隐藏与标题相同的摘要，保留不同的活动', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    state.history.tasks = [
      task0(
        't1',
        'agent',
        '实现 Android 图文剪贴板接口',
        tool: 'tool-1',
        summary: '  实现 Android 图文剪贴板接口  ',
      ),
    ];
    await tester.pumpWidget(_host(state));
    await tester.pump();
    await openTray(tester);
    final card = find.byKey(const ValueKey('chat-activity-card'));
    expect(
      find.descendant(of: card, matching: find.text('实现 Android 图文剪贴板接口')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('  实现 Android 图文剪贴板接口  ')),
      findsNothing,
    );
    state.history.tasks = [
      task0(
        't1',
        'agent',
        '实现 Android 图文剪贴板接口',
        tool: 'tool-1',
        summary: '正在验证图片粘贴',
      ),
    ];
    state.update();
    await tester.pump();
    expect(
      find.descendant(of: card, matching: find.text('正在验证图片粘贴')),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('单个任务的停止需确认，子代理传 agent，命令传 task，取消不发请求', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    state.history.tasks = [
      task0('t1', 'agent', '检查布局', tool: 'tool-1', summary: '正在对比'),
    ];
    await tester.pumpWidget(_host(state));
    await tester.pump();
    await openTray(tester);
    expect(find.text('正在对比'), findsOneWidget);
    await tester.tap(stopOf('agent:tool-1'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('停止这个任务？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(state.calls, isEmpty);
    await tester.tap(stopOf('agent:tool-1'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('停止').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(state.calls, [LinkMethods.stopTask]);
    expect(state.lastParams, {'session': 'session', 'agent': 'tool-1'});

    state.history.tasks = [task0('cmd', 'command', 'npm test')];
    state.update();
    await tester.pump();
    await tester.tap(stopOf('task:cmd'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('停止').last);
    await tester.pump(const Duration(milliseconds: 300));
    expect(state.calls, [LinkMethods.stopTask, LinkMethods.stopTask]);
    expect(state.lastParams, {'session': 'session', 'task': 'cmd'});
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('停止失败时显示错误提示', (tester) async {
    final state = _State()..fail = true;
    addTearDown(state.dispose);
    state.history.tasks = [task0('cmd', 'command', 'npm test')];
    await tester.pumpWidget(_host(state));
    await tester.pump();
    await openTray(tester);
    await tester.tap(stopOf('task:cmd'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('停止').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('停止请求没有确认送达'), findsOneWidget);
    expect(find.textContaining('原始错误细节'), findsNothing);
    expect(stopOf('task:cmd'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('其他类型的后台任务也上卡片，可停止；混合前台子代理时不叫后台任务', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    state.history.tasks = [
      LinkTask(
        id: 'mon',
        kind: 'other',
        description: '',
        status: 'running',
        startedAt: DateTime(2026, 1, 1, 0, 2),
        summary: '盯着部署日志',
      ),
    ];
    await tester.pumpWidget(_host(state));
    await tester.pump();
    await openTray(tester);
    final card = find.byKey(const ValueKey('task-card-task:mon'));
    expect(card, findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.text('后台任务')),
      findsOneWidget,
    );
    expect(find.text('盯着部署日志'), findsOneWidget);

    state.history.items.add({
      't': 'agent',
      'id': 'fg',
      'description': '本轮的子代理',
      'status': 'running',
    });
    state.update();
    await tester.pump();
    // Past the card growing to hold the second.
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('2 个任务运行中'), findsOneWidget);
    expect(find.textContaining('后台任务运行中'), findsNothing);

    await tester.tap(stopOf('task:mon'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('停止').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(state.lastParams, {'session': 'session', 'task': 'mon'});
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('自动保留开启时改动行只显示条数，点进去可关开关', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    state.settings.autoKeep = true;
    state.history.changes = [
      {'path': 'lib/a.dart', 'added': 4, 'removed': 2},
    ];
    await tester.pumpWidget(_host(state));
    await tester.pump();
    await openTray(tester);
    expect(find.byKey(const ValueKey('activity-auto-keep')), findsOneWidget);
    expect(find.text('保留'), findsNothing);
    expect(find.text('撤回'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('activity-auto-keep')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(ChangesPage), findsOneWidget);
    final toggle = find.byKey(const ValueKey('auto-keep-changes'));
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    expect(find.text('对所有对话生效，需连着电脑'), findsOneWidget);
    await tester.tap(toggle);
    await tester.pump();
    expect(state.settings.autoKeep, isFalse);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('保留'), findsOneWidget);
    expect(find.byKey(const ValueKey('activity-auto-keep')), findsNothing);
    expect(state.calls, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('无任务不显示，非运行命令不显示，改动行独立存在', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    await tester.pumpWidget(_host(state));
    await tester.pump();
    expect(find.byKey(const ValueKey('chat-activity-card')), findsNothing);
    state.history.tasks = [
      LinkTask(
        id: 'done',
        kind: 'command',
        description: '已结束',
        status: 'exited',
        startedAt: DateTime(2026),
      ),
    ];
    state.history.changes = [
      {'path': 'lib/a.dart', 'added': 4, 'removed': 2},
    ];
    state.update();
    await tester.pump();
    expect(find.text('已结束'), findsNothing);
    await openTray(tester);
    expect(
      find.byKey(const ValueKey('activity-changes-toggle')),
      findsOneWidget,
    );
    state.history.tasks = [task0('cmd', 'command', 'npm test')];
    state.update();
    await tester.pump();
    final task = tester.getRect(
      find.byKey(const ValueKey('task-card-task:cmd')),
    );
    final changes = tester.getRect(
      find.byKey(const ValueKey('activity-changes-toggle')),
    );
    expect(changes.top, greaterThan(task.bottom));
    state.history.tasks = [];
    state.update();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('task-card-task:cmd')), findsNothing);
    expect(
      find.byKey(const ValueKey('activity-changes-toggle')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('深色大字体下任务堆叠与展开不溢出', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = _State();
    addTearDown(state.dispose);
    state.history.tasks = [
      for (var i = 0; i < 6; i++)
        task0(
          't$i',
          i.isEven ? 'agent' : 'command',
          '很长很长的任务描述用来验证单行省略而不是换行溢出 $i',
          tool: 'u$i',
          summary: '很长很长的当前动作说明用来验证单行省略而不是换行溢出',
          at: i,
        ),
    ];
    state.history.changes = [
      {'path': 'lib/a.dart', 'added': 400, 'removed': 200},
    ];
    await tester.pumpWidget(_host(state, dark: true, scale: 1.6));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('activity-tasks-expand')));
    // The tray grows from the next frame on.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('activity-changes-toggle')),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('进入全部改动后可单独保留、确认或取消撤回，并查看差异', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    state.history.changes = [
      {'path': 'lib/a.dart', 'added': 4, 'removed': 2},
      {'path': 'lib/b.dart', 'added': 1, 'removed': 0},
    ];
    await tester.pumpWidget(_host(state));
    await tester.pumpAndSettle();
    await openTray(tester);
    await tester.tap(find.byKey(const ValueKey('activity-changes-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('文件操作 lib/a.dart'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保留改动'));
    await tester.pumpAndSettle();
    expect(state.calls, [LinkMethods.keep]);
    expect(state.lastParams, {
      'session': 'session',
      'paths': ['lib/a.dart'],
    });
    await tester.scrollUntilVisible(
      find.byTooltip('文件操作 lib/b.dart').hitTestable(),
      24,
      scrollable: find
          .descendant(
            of: find.byType(ChangesPage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.byTooltip('文件操作 lib/b.dart'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('撤回改动'));
    await tester.pumpAndSettle();
    expect(state.calls, [LinkMethods.keep]);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(state.calls, [LinkMethods.keep]);
    await tester.scrollUntilVisible(
      find.byTooltip('文件操作 lib/b.dart').hitTestable(),
      24,
      scrollable: find
          .descendant(
            of: find.byType(ChangesPage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.byTooltip('文件操作 lib/b.dart'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('撤回改动'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '撤回'));
    await tester.pumpAndSettle();
    expect(state.calls, [LinkMethods.keep, LinkMethods.undo]);
    expect(state.lastParams, {
      'session': 'session',
      'paths': ['lib/b.dart'],
    });
    await tester.ensureVisible(find.text('a.dart'));
    await tester.tap(find.text('a.dart'));
    await tester.pumpAndSettle();
    expect(state.calls.last, LinkMethods.read);
    expect(state.lastParams, {'project': 'project', 'path': 'lib/a.dart'});
  });

  testWidgets('聊天主页面保留全部操作，失败可见且断线后禁用写入', (tester) async {
    final state = _State()..fail = true;
    addTearDown(state.dispose);
    state.history.changes = [
      {'path': 'a.dart'},
    ];
    await tester.pumpWidget(_host(state));
    await tester.pumpAndSettle();
    await openTray(tester);
    await tester.tap(find.widgetWithText(FilledButton, '保留'));
    await tester.pumpAndSettle();
    expect(state.calls, [LinkMethods.keep]);
    expect(state.lastParams, {'session': 'session'});
    expect(find.byType(ChangesPage), findsNothing);
    expect(find.textContaining('请求失败'), findsOneWidget);
    state.fail = false;
    await tester.tap(find.widgetWithText(TextButton, '撤回'));
    await tester.pumpAndSettle();
    expect(state.calls, [LinkMethods.keep]);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(state.calls, [LinkMethods.keep]);
    await tester.tap(find.widgetWithText(TextButton, '撤回'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '撤回'));
    await tester.pumpAndSettle();
    expect(state.calls, [LinkMethods.keep, LinkMethods.undo]);
    expect(state.lastParams, {'session': 'session'});
    state.online = false;
    state.update();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '保留'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '撤回'))
          .onPressed,
      isNull,
    );
    expect(find.byType(ChangesPage), findsNothing);
  });

  for (final multiline in [false, true]) {
    testWidgets(multiline ? '多行输入增高时将末尾内容上推，不遮挡文件' : '键盘弹出时将末尾内容上推，不遮挡文件', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = _State();
      addTearDown(state.dispose);
      state.history.items.addAll([
        for (var i = 0; i < 25; i++) {'t': 'user', 'text': '消息 $i'},
        {
          't': 'diff',
          'fileName': '末尾文件.dart',
          'directory': 'lib',
          'added': 1,
          'removed': 1,
          'lines': <Object?>[],
        },
      ]);
      await tester.pumpWidget(_host(state));
      await tester.pumpAndSettle();
      for (var i = 0; i < 6; i++) {
        await tester.pump();
      }
      final list = find.byWidgetPredicate(
        (widget) => widget is CustomScrollView && widget.controller != null,
      );
      final controller = tester.widget<CustomScrollView>(list).controller!;
      expect(controller.position.extentAfter, closeTo(0, 1));
      final oldViewport = controller.position.viewportDimension;
      if (multiline) {
        await tester.enterText(find.byType(TextField), '第一行\n第二行\n第三行\n第四行');
      } else {
        await tester.tap(find.byType(TextField));
        await tester.pumpWidget(_host(state, keyboard: 280));
      }
      await tester.pumpAndSettle();
      expect(controller.position.viewportDimension, lessThan(oldViewport));
      expect(controller.position.extentAfter, closeTo(0, 1));
      expect(
        tester.getBottomLeft(find.textContaining('末尾文件.dart')).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.byType(TextField)).dy),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('多条待发消息在窄屏大字键盘下可滚动，输入框不被挤出', (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = _State();
    addTearDown(state.dispose);
    state.history
      ..live = true
      ..items.add({'t': 'user', 'text': '正在执行的要求'});
    for (var i = 0; i < 8; i++) {
      state.localQueue.add(
        'desktop',
        'session',
        text: '第 $i 条等待执行的长消息，请完成后继续检查文件和测试',
      );
    }
    await tester.pumpWidget(
      _host(state, dark: true, scale: 1.4, keyboard: 240),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final panel = find.byKey(const ValueKey('queued-messages'));
    expect(
      tester.getBottomLeft(panel).dy,
      lessThanOrEqualTo(tester.getTopLeft(find.byType(TextField)).dy),
    );
    final scroll = find.descendant(
      of: panel,
      matching: find.byType(Scrollable),
    );
    await tester.drag(scroll, const Offset(0, -1000));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: panel, matching: find.byTooltip('立即插入')).last,
    );
    await tester.pump();
    expect(state.calls.last, LinkMethods.send);
    expect(state.lastParams['text'], startsWith('第 7 条'));
    expect(state.lastParams['now'], isTrue);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('查看历史时弹出键盘不强制跳到末尾', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    state.history.items.addAll([
      for (var i = 0; i < 30; i++) {'t': 'user', 'text': '历史消息 $i'},
    ]);
    await tester.pumpWidget(_host(state));
    await tester.pumpAndSettle();
    final list = find.byWidgetPredicate(
      (widget) => widget is CustomScrollView && widget.controller != null,
    );
    final controller = tester.widget<CustomScrollView>(list).controller!;
    await tester.drag(list, const Offset(0, 350));
    await tester.pumpAndSettle();
    final offset = controller.offset;
    expect(controller.position.extentAfter, greaterThan(100));
    await tester.pumpWidget(_host(state, keyboard: 240));
    await tester.pumpAndSettle();
    // 底边对齐：输入框上方那几行原地不动，内容只上移键盘的高度，不跳到末尾。
    expect(controller.offset, closeTo(offset + 240, 1));
    expect(controller.position.extentAfter, greaterThan(100));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('加号弹层的模式分段复用真实选项并只提交所选ID', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    state.history.choices = const [
      LinkChoice(
        kind: 'mode',
        selected: 'agent',
        options: [
          LinkOption(id: 'agent', label: 'Agent'),
          LinkOption(id: 'ask', label: 'Ask'),
        ],
      ),
    ];
    await tester.pumpWidget(_host(state));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更多输入选项'));
    await tester.pumpAndSettle();
    expect(state.calls, isEmpty);
    await tester.tap(find.descendant(
      of: find.byKey(const ValueKey('composer-mode')),
      matching: find.text('Ask'),
    ));
    await tester.pumpAndSettle();
    expect(state.calls, [LinkMethods.choose]);
    expect(state.lastParams, {
      'session': 'session',
      'kind': 'mode',
      'option': 'ask',
    });
  });

  testWidgets('清空键只在有内容时出现，清掉就没了', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    await tester.pumpWidget(_host(state));
    await tester.pumpAndSettle();
    expect(find.byTooltip('清空输入'), findsNothing);

    final composer = find.byType(TextField).first;
    await tester.enterText(composer, '要清掉的草稿');
    await tester.pumpAndSettle();
    expect(find.byTooltip('清空输入'), findsOneWidget);

    await tester.tap(find.byTooltip('清空输入'));
    await tester.pumpAndSettle();
    expect(find.text('要清掉的草稿'), findsNothing);
    expect(find.byTooltip('清空输入'), findsNothing);
    // 清空不留撤销提示。
    expect(find.text('已清空输入'), findsNothing);
    expect(find.text('撤销'), findsNothing);
  });

  testWidgets('顶栏在项目后显示分支，未连接和空对话时不显示', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    await tester.pumpWidget(_host(state));
    await tester.pumpAndSettle();
    // 空对话的项目卡片已经有分支，顶栏不重复。
    expect(find.byKey(const ValueKey('chat-branch-icon')), findsNothing);

    state.history.items.add({'t': 'user', 'text': '你好'});
    state.update();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat-branch-icon')), findsOneWidget);
    expect(find.textContaining('测试项目', findRichText: true), findsWidgets);
    expect(find.textContaining('真实分支', findRichText: true), findsOneWidget);

    state.online = false;
    state.update();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat-branch-icon')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('空态展示真实项目和分支，建议只填空草稿不发送', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    await tester.pumpWidget(_host(state));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat-greeting')), findsOneWidget);
    expect(find.text('今天想做点什么？'), findsOneWidget);
    // 路径和分支在同一行，与官方的项目卡片一致；分支名完整显示。
    expect(find.text('E:/project/测试项目'), findsOneWidget);
    expect(find.byKey(const ValueKey('new-chat-branch')), findsOneWidget);
    expect(find.text('真实分支'), findsOneWidget);
    await tester.ensureVisible(find.text('讲讲这个项目的整体结构'));
    await tester.tap(find.text('讲讲这个项目的整体结构'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '讲讲这个项目的整体结构',
    );
    expect(state.calls, isEmpty);
    final suggestion = tester.widget<TextButton>(
      find.widgetWithText(TextButton, '给今天的改动补上测试'),
    );
    expect(suggestion.onPressed, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 400));
  });

  for (final (hour, greeting) in [
    (8, '早上好'),
    (12, '中午好'),
    (15, '下午好'),
    (20, '晚上好'),
    (2, '夜深了'),
  ]) {
    testWidgets('空态问候按本机时间显示$greeting', (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 11, 12, hour)), () async {
        final state = _State();
        addTearDown(state.dispose);
        await tester.pumpWidget(_host(state));
        await tester.pumpAndSettle();
        expect(
          tester.widget<Text>(find.byKey(const ValueKey('chat-greeting'))).data,
          greeting,
        );
        expect(find.text('今天想做点什么？'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 400));
      });
    });
  }

  testWidgets('换一换只轮换内置提示，不发送请求也不改动草稿', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    await tester.pumpWidget(_host(state));
    await tester.pumpAndSettle();
    expect(find.text('讲讲这个项目的整体结构'), findsOneWidget);
    expect(find.text('总结当前未提交的改动'), findsNothing);
    await tester.ensureVisible(find.byKey(const ValueKey('refresh-suggestions')));
    await tester.tap(find.byKey(const ValueKey('refresh-suggestions')));
    await tester.pumpAndSettle();
    expect(find.text('讲讲这个项目的整体结构'), findsNothing);
    expect(find.text('总结当前未提交的改动'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    expect(state.calls, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('附件、模式与次要操作都有明确入口', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    state.history.choices = [
      const LinkChoice(
        kind: 'mode',
        selected: 'agent',
        options: [LinkOption(id: 'agent', label: 'Agent')],
      ),
    ];
    await tester.pumpWidget(_host(state));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更多输入选项'));
    await tester.pumpAndSettle();
    expect(find.text('相册'), findsOneWidget);
    expect(find.text('@ 文件'), findsOneWidget);
    expect(find.text('贴纸'), findsNothing);
    // 模式改为弹层里的分段选择，不再是输入栏的胶囊。
    expect(find.byKey(const ValueKey('composer-mode')), findsOneWidget);
    expect(find.text('Agent'), findsOneWidget);
    // 返回键关掉弹层。
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('相册'), findsNothing);
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('session-drawer')), findsOneWidget);
    expect(find.byKey(const ValueKey('session-menu-tasks')), findsOneWidget);
    expect(find.byKey(const ValueKey('session-menu-changes')), findsOneWidget);
    expect(state.calls, isEmpty);
  });

  for (final online in [true, false]) {
    testWidgets('独立聊天在${online ? '在线' : '离线'}时打开本地新对话，不创建会话', (tester) async {
      final state = _State()..online = online;
      addTearDown(state.dispose);
      await tester.pumpWidget(_host(state));
      await tester.pumpAndSettle();
      expect(find.byTooltip('新对话'), findsNothing);
      await tester.tap(find.byTooltip('更多'));
      await tester.pumpAndSettle();
      final newRow = tester.widget<ListTile>(
        find.byKey(const ValueKey('session-menu-new')),
      );
      expect(newRow.enabled, isTrue);
      expect(state.calls, isEmpty);
      await tester.tap(find.byKey(const ValueKey('session-menu-new')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('session-drawer')), findsNothing);
      expect(state.calls, isEmpty);
      final page = tester.widget<ChatPage>(find.byType(ChatPage));
      expect(page.sessionId, isNull);
      // 默认当前项目，离线也能保留输入，不先创建远端会话。
      expect(page.projectId, 'project');
      expect(page.onSwitchProject, isNotNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final bot in [false, true]) {
    testWidgets('${bot ? 'Bot' : '编程对话'}运行中输入后仍可独立停止且保留草稿', (tester) async {
      final state = _State()..withBot = bot;
      addTearDown(state.dispose);
      state.history
        ..live = true
        ..items.add({'t': 'user', 'text': '正在执行的任务'});
      await tester.pumpWidget(_host(state, bot: bot));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byTooltip('停止生成'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, '准备排队的任务');
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byTooltip('停止生成'), findsOneWidget);
      expect(find.byTooltip('发送'), findsOneWidget);
      await tester.tap(find.byTooltip('停止生成'));
      await tester.pump();
      expect(state.calls, [LinkMethods.stop]);
      expect(state.lastParams['session'], 'session');
      expect(tester.widget<TextField>(find.byType(TextField).first)
          .controller!.text, '准备排队的任务');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('离线菜单明确禁用写操作，但仍可读取已同步任务和改动', (tester) async {
    final state = _State()..online = false;
    addTearDown(state.dispose);
    await tester.pumpWidget(_host(state));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    bool enabled(String action) => tester
        .widget<ListTile>(find.byKey(ValueKey('session-menu-$action')))
        .enabled;
    for (final action in ['files', 'pin', 'rename', 'archive', 'delete']) {
      expect(enabled(action), isFalse, reason: action);
    }
    for (final action in ['new', 'changes', 'tasks']) {
      expect(enabled(action), isTrue, reason: action);
    }
    expect(find.text('电脑离线，写操作暂不可用'), findsOneWidget);
    expect(state.calls, isEmpty);
  });

  testWidgets('菜单打开后掉线，写操作随界面变灰且不发请求', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    await tester.pumpWidget(_host(state));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    state.online = false;
    state.update();
    await tester.pump();
    expect(
      tester
          .widget<ListTile>(find.byKey(const ValueKey('session-menu-pin')))
          .enabled,
      isFalse,
    );
    await tester.tap(find.byKey(const ValueKey('session-menu-pin')));
    await tester.pumpAndSettle();
    expect(state.calls, isEmpty);
  });

  testWidgets('更多菜单按真实置顶状态切换置顶和取消置顶', (tester) async {
    final state = _State()..pinned = true;
    addTearDown(state.dispose);
    await tester.pumpWidget(_host(state));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    expect(find.text('置顶'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('session-menu-pin')));
    await tester.pumpAndSettle();
    expect(state.calls.last, LinkMethods.pin);
    expect(state.lastParams['pinned'], false);
    state.pinned = false;
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('session-menu-pin')));
    await tester.pumpAndSettle();
    expect(state.lastParams['pinned'], true);
  });

  testWidgets('窄屏大字号键盘和生成停止入口不溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = _State();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      _host(state, dark: true, scale: 1.4, keyboard: 240),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    state.history.items.add({
      't': 'user',
      'text': '很长的中文消息和路径 E:/project/测试项目/文件夹/独立文件.txt',
    });
    state.history
      ..live = true
      ..choices = const [
        LinkChoice(kind: 'model', options: []),
        LinkChoice(kind: 'mode', options: []),
        LinkChoice(kind: 'permission', options: []),
      ]
      ..context = {
        'window': 200000,
        'used': 40000,
        'parts': [{'part': 'messages', 'tokens': 40000}],
        'compactAt': 167000,
      };
    state.update();
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, '生成中准备下一条任务');
    await tester.pump();
    expect(find.byTooltip('停止生成'), findsOneWidget);
    expect(find.byTooltip('发送'), findsOneWidget);
    expect(find.byTooltip('上下文已用 20%'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('context-usage-value'))).data,
      '20%',
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('user-message-bubble'))).width,
      lessThan(290),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  bool composerFocused(WidgetTester tester) => tester
      .widget<TextField>(find.byType(TextField).first)
      .focusNode!
      .hasFocus;

  testWidgets('点加号收起键盘并弹出输入面板，点输入框回到键盘', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    await tester.pumpWidget(_host(state));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    expect(composerFocused(tester), isTrue);

    await tester.tap(find.byTooltip('更多输入选项'));
    await tester.pumpAndSettle();
    expect(composerFocused(tester), isFalse);
    expect(find.byKey(const ValueKey('chat-actions')), findsOneWidget);

    // 面板是模态弹层，返回键收起它，再点输入框把键盘叫回来。
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat-actions')), findsNothing);
    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    expect(composerFocused(tester), isTrue);
  });

  testWidgets('键盘还占着时点加号，弹出面板不溢出且留在屏内', (tester) async {
    tester.view.physicalSize = const Size(1080, 1800);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final state = _State();
    addTearDown(state.dispose);
    await tester.pumpWidget(_host(state));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField).first);
    await tester.pumpWidget(_host(state, keyboard: 300));
    await tester.pumpAndSettle();

    // The keyboard is still fully up when the panel opens.
    await tester.tap(find.byTooltip('更多输入选项'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final panel = find.byKey(const ValueKey('chat-actions'));
    expect(panel, findsOneWidget);
    final height = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(tester.getTopLeft(panel).dy, greaterThanOrEqualTo(0));
    expect(
      tester.getBottomLeft(panel).dy,
      lessThanOrEqualTo(height + .01),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('面板打开时返回键先关面板，再回到对话', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    await tester.pumpWidget(_host(state));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更多输入选项'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat-actions')), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat-actions')), findsNothing);
  });

  testWidgets('打开模型弹窗不动键盘，关掉后键盘还是开着', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    state.history.choices = const [
      LinkChoice(
        kind: 'model',
        selected: 'test',
        options: [LinkOption(id: 'test', label: '测试模型')],
      ),
    ];
    await tester.pumpWidget(_host(state));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    expect(composerFocused(tester), isTrue);
    await tester.tap(find.byTooltip('模型: 测试模型'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    // 打开和关闭都不碰键盘：原来开着，现在还是开着。
    expect(composerFocused(tester), isTrue);
    Navigator.of(tester.element(find.byType(BottomSheet))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(composerFocused(tester), isTrue);
  });

  testWidgets('模型弹窗开着时掉线重连，还是同一个会话，不必关掉重开', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    state.history.choices = const [
      LinkChoice(
        kind: 'model',
        selected: 'test',
        options: [
          LinkOption(id: 'test', label: '测试模型'),
          LinkOption(id: 'other', label: '另一个模型'),
        ],
      ),
    ];
    await tester.pumpWidget(_host(state));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('模型: 测试模型'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);

    // 掉线：只说电脑离线，不说换了会话。
    state.online = false;
    state.update();
    await tester.pumpAndSettle();
    expect(find.text('电脑已离线，连接后可修改设置。'), findsOneWidget);
    expect(find.textContaining('会话已变化'), findsNothing);

    // 重连：还是同一个会话，弹窗自己恢复可用，能直接选。
    state.online = true;
    state.update();
    await tester.pumpAndSettle();
    expect(find.textContaining('会话已变化'), findsNothing);
    expect(find.text('电脑已离线，连接后可修改设置。'), findsNothing);
    await tester.tap(find.widgetWithText(ListTile, '另一个模型'));
    await tester.pumpAndSettle();
    expect(state.calls, contains(LinkMethods.choose));
  });

  testWidgets('开始执行计划只认最近那条；电脑说不在等就收起按钮、说清原因、输入框给出路', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    Map<String, Object?> plan(int round) => {
      't': 'plan',
      'path': 'plan.md',
      'round': round,
      'title': '第 $round 版计划',
      'status': 'awaiting',
    };
    // 第 1 版没点开始就接着聊了：它不再算在等。
    state.history.items.addAll([
      plan(1),
      {'t': 'user', 'text': '先别改，再想想'},
      plan(2),
    ]);
    await tester.pumpWidget(_host(state));
    await tester.pumpAndSettle();
    // 第 2 版还在等：有按钮。
    final start = find.widgetWithText(FilledButton, '开始执行计划');
    expect(start, findsOneWidget);

    state.planGone = true;
    await tester.tap(start);
    await tester.pumpAndSettle();
    expect(state.calls.last, LinkMethods.startPlan);
    expect(start, findsNothing);
    expect(find.textContaining('不在等你确认'), findsOneWidget);
    expect(find.textContaining('找不到'), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '按计划开始执行',
    );
  });
}
