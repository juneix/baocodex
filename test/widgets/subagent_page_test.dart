// YCode — GPL-3.0-only.
import 'dart:async';

import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/models/user_facing_error.dart';
import 'package:baocode_mobile/chat/chat_models.dart';
import 'package:baocode_mobile/chat/message_view.dart';
import 'package:baocode_mobile/link/chat_codec.dart';
import 'package:baocode_mobile/state/app_state.dart';
import 'package:baocode_mobile/ui/tasks/subagent_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AgentItem _agent() => const AgentItem(
  description: '查找所有用到协议的地方',
  id: 'tool-1',
  agentType: 'explore',
  prompt: '把引用 LinkMethods 的文件都列出来',
  status: CommandStatus.succeeded,
  tokens: 4200,
  toolUses: 7,
  activity: 'Reading a.txt',
  duration: Duration(minutes: 2, seconds: 30),
  model: 'glm-5.3',
  children: [
    ToolCallItem(
      kind: ToolKind.read,
      tool: 'read',
      target: 'lib/link/chat_codec.dart',
      status: ToolStatus.succeeded,
    ),
  ],
  result: '一共有 3 个文件直接引用 LinkMethods。',
);

class _LiveState extends AppState {
  _LiveState() : super(demo: true);
  final held = SessionBuffer('desktop', 'session');
  final calls = <(String, String, Map<String, Object?>)>[];
  bool online = true;
  bool fail = false;
  Completer<Object?>? pending;
  @override
  bool isOnline(String desktopId) => online;
  @override
  Future<Object?> request(
    String desktopId,
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    calls.add((desktopId, method, params));
    if (fail) throw const UserFacingError('停止请求失败');
    return await pending?.future;
  }

  @override
  SessionBuffer? peekBuffer(String desktopId, String sessionId) =>
      desktopId == 'desktop' && sessionId == 'session' ? held : null;
  void changed() => notifyListeners();
}

void main() {
  const running = AgentItem(
    id: 'tool-live',
    description: '实现剪贴板接口',
    status: CommandStatus.running,
  );
  Widget page(_LiveState state, {String? sessionId = 'session'}) => MaterialApp(
    home: SubagentPage(
      state: state,
      desktopId: 'desktop',
      sessionId: sessionId,
      item: running,
    ),
  );

  testWidgets('详情页红色停止按钮须确认，取消不发送且确认只停止当前代理', (tester) async {
    final state = _LiveState();
    state.settings.language = 'zh';
    addTearDown(state.dispose);
    await tester.pumpWidget(page(state));
    final stop = find.byTooltip('停止');
    expect(stop, findsOneWidget);
    expect(
      find.descendant(
        of: stop,
        matching: find.byKey(const ValueKey('hollow-stop')),
      ),
      findsOneWidget,
    );
    await tester.tap(stop);
    await tester.pumpAndSettle();
    expect(state.calls, isEmpty);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(state.calls, isEmpty);
    await tester.tap(stop);
    await tester.pumpAndSettle();
    state.pending = Completer<Object?>();
    await tester.tap(find.widgetWithText(FilledButton, '停止'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(state.calls, hasLength(1));
    expect(state.calls.single.$1, 'desktop');
    expect(state.calls.single.$2, LinkMethods.stopTask);
    expect(state.calls.single.$3, {'session': 'session', 'agent': 'tool-live'});
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    state.pending!.complete();
    await tester.pumpAndSettle();
    state.held.items.add(
      ChatCodec.encode(
        const AgentItem(
          id: 'tool-live',
          description: '实现剪贴板接口',
          status: CommandStatus.succeeded,
        ),
      ),
    );
    state.changed();
    await tester.pumpAndSettle();
    expect(find.byTooltip('停止'), findsNothing);
  });

  testWidgets('详情停止失败保留错误并可重试', (tester) async {
    final state = _LiveState()..fail = true;
    state.settings.language = 'zh';
    addTearDown(state.dispose);
    await tester.pumpWidget(page(state));
    await tester.tap(find.byTooltip('停止'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '停止'));
    await tester.pumpAndSettle();
    expect(find.textContaining('停止请求失败'), findsOneWidget);
    expect(find.byTooltip('停止').hitTestable(), findsOneWidget);
  });

  testWidgets('离线或未关联会话的详情不能停止代理', (tester) async {
    final state = _LiveState()..online = false;
    state.settings.language = 'zh';
    addTearDown(state.dispose);
    await tester.pumpWidget(page(state));
    final button = tester.widget<IconButton>(
      find.ancestor(
        of: find.byKey(const ValueKey('hollow-stop')),
        matching: find.byType(IconButton),
      ),
    );
    expect(button.onPressed, isNull);
    expect(state.calls, isEmpty);
    await tester.pumpWidget(page(state, sessionId: null));
    expect(find.byTooltip('停止'), findsNothing);
  });

  testWidgets('运行中的子代理页随会话实时更新它的步骤', (tester) async {
    final state = _LiveState();
    state.settings.language = 'zh';
    addTearDown(state.dispose);
    AgentItem running(List<ChatItem> children) => AgentItem(
      description: '实现附件图片连续预览',
      id: 'tool-live',
      status: CommandStatus.running,
      children: children,
    );
    state.held.items.add(ChatCodec.encode(running(const [])));
    await tester.pumpWidget(
      MaterialApp(
        home: SubagentPage(
          state: state,
          desktopId: 'desktop',
          sessionId: 'session',
          item: running(const []),
        ),
      ),
    );
    expect(find.textContaining('image_gallery.dart'), findsNothing);

    state.held.items[0] = ChatCodec.encode(
      running(const [
        ToolCallItem(
          kind: ToolKind.read,
          tool: 'read',
          target: 'lib/ui/widgets/image_gallery.dart',
          status: ToolStatus.succeeded,
        ),
      ]),
    );
    state.changed();
    await tester.pump();
    expect(find.textContaining('image_gallery.dart'), findsOneWidget);
    expect(find.text('进行中'), findsOneWidget);
  });

  testWidgets('subagent detail page shows meta, prompt, children, result', (
    tester,
  ) async {
    final state = AppState(demo: true);
    state.settings.language = 'zh';
    addTearDown(state.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SubagentPage(
          state: state,
          desktopId: 'desktop',
          projectId: 'project',
          sessionId: 'session',
          item: _agent(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('查找所有用到协议的地方'), findsOneWidget);
    expect(find.text('已完成'), findsOneWidget);
    expect(find.textContaining('explore'), findsOneWidget);
    expect(find.textContaining('glm-5.3'), findsOneWidget);
    expect(find.textContaining('2分30秒'), findsOneWidget);
    expect(find.textContaining('后台运行'), findsNothing);
    expect(find.text('把引用 LinkMethods 的文件都列出来'), findsOneWidget);
    expect(find.textContaining('chat_codec.dart'), findsOneWidget);
    expect(find.text('一共有 3 个文件直接引用 LinkMethods。'), findsOneWidget);
    expect(
      find.byType(TextField),
      findsNothing,
      reason: 'the detail page is strictly read-only',
    );
  });

  testWidgets('the stream card opens the read-only detail page', (
    tester,
  ) async {
    final state = AppState(demo: true);
    state.settings.language = 'zh';
    addTearDown(state.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              MessageView(
                state: state,
                desktopId: 'desktop',
                item: _agent(),
                projectId: 'project',
                sessionId: 'session',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(SubagentPage), findsNothing);
    await tester.tap(find.text('查找所有用到协议的地方'));
    await tester.pumpAndSettle();

    expect(find.byType(SubagentPage), findsOneWidget);
    expect(find.text('查找所有用到协议的地方'), findsOneWidget);
  });

  testWidgets('a running subagent shows its live activity line', (
    tester,
  ) async {
    final state = AppState(demo: true);
    state.settings.language = 'zh';
    addTearDown(state.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SubagentPage(
          state: state,
          desktopId: 'desktop',
          projectId: 'project',
          sessionId: 'session',
          item: const AgentItem(
            description: '跑长任务',
            status: CommandStatus.running,
            activity: 'Reading a.txt',
            background: true,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('进行中'), findsOneWidget);
    expect(find.text('Reading a.txt'), findsOneWidget);
    expect(find.textContaining('后台运行'), findsOneWidget);
  });
}
