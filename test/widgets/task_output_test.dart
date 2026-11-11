import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/link/link_store.dart';
import 'package:baocode_mobile/state/app_state.dart';
import 'package:baocode_mobile/ui/tasks/task_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _State extends AppState {
  _State() : super(store: MemoryLinkStore());
  final methods = <String>[];
  @override
  String tr(String zh, String en) => zh;
  @override
  bool isOnline(String desktopId) => true;
  @override
  Future<Object?> request(
    String desktop,
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    methods.add(method);
    if (method == LinkMethods.watchOutput) {
      return {'text': 'initial', 'offset': 7};
    }
    return null;
  }
}

void main() {
  testWidgets('任务详情使用红色停止入口且确认后才发送请求', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: TaskPage(
          state: state,
          desktopId: 'a',
          sessionId: 's',
          task: LinkTask(
            id: 't',
            kind: 'agent',
            description: '检查布局',
            status: 'running',
            startedAt: DateTime(2026),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final stop = find.byTooltip('停止任务');
    expect(
      find.descendant(
        of: stop,
        matching: find.byKey(const ValueKey('hollow-stop')),
      ),
      findsOneWidget,
    );
    await tester.tap(stop);
    await tester.pumpAndSettle();
    expect(state.methods, isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, '停止'));
    await tester.pumpAndSettle();
    expect(state.methods, [LinkMethods.stopTask]);
  });

  testWidgets('监听同一应用状态的页面 push 任务页时不触发构建期通知断言', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedBuilder(
          animation: state,
          builder: (context, _) => Scaffold(
            body: TextButton(
              child: const Text('打开任务'),
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => TaskPage(
                    state: state,
                    desktopId: 'a',
                    sessionId: 's',
                    task: LinkTask(
                      id: 't',
                      kind: 'command',
                      description: '合成任务',
                      status: 'running',
                      startedAt: DateTime(2026),
                      output: true,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开任务'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('initial', findRichText: true), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('任务页显示增量输出，后台释放，前台恢复订阅，离页取消', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: TaskPage(
          state: state,
          desktopId: 'a',
          sessionId: 's',
          task: LinkTask(
            id: 't',
            kind: 'command',
            description: '合成任务',
            status: 'running',
            startedAt: DateTime(2026),
            output: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('initial', findRichText: true), findsOneWidget);
    state.taskOutputs.accept(
      'a',
      const LinkOutput(
        session: 's',
        task: 't',
        offset: 12,
        text: '-next',
      ).toJson(),
    );
    await tester.pump();
    expect(find.text('initial-next', findRichText: true), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    expect(state.methods.last, LinkMethods.unwatchOutput);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(
      state.methods.where((method) => method == LinkMethods.watchOutput),
      hasLength(2),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(state.methods.last, LinkMethods.unwatchOutput);
  });

  testWidgets('任务详情和列表用中文状态与类型，没有描述时用命令当标题', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    final buffer = state.buffer('a', 's');
    buffer.tasks = [
      LinkTask(
        id: 'c',
        kind: 'command',
        description: '',
        command: 'npm run build',
        status: 'succeeded',
        startedAt: DateTime(2026),
      ),
      LinkTask(
        id: 'o',
        kind: 'other',
        description: '监控部署',
        status: 'running',
        startedAt: DateTime(2026),
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: TasksPage(state: state, desktopId: 'a', sessionId: 's'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('npm run build'), findsOneWidget);
    expect(find.textContaining('已完成 · 命令', findRichText: true), findsOneWidget);
    expect(
      find.textContaining('运行中 · 后台任务', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('succeeded', findRichText: true), findsNothing);
    expect(find.textContaining('other', findRichText: true), findsNothing);
    await tester.tap(find.text('npm run build'));
    await tester.pumpAndSettle();
    expect(find.text('命令'), findsOneWidget);
    expect(find.text('已完成'), findsOneWidget);
    expect(find.textContaining('command ·'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('停止失败显示中文原因，不露出原始错误', (tester) async {
    final state = _Refusing();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: TaskPage(
          state: state,
          desktopId: 'a',
          sessionId: 's',
          task: LinkTask(
            id: 't',
            kind: 'command',
            description: '构建',
            status: 'running',
            startedAt: DateTime(2026),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('停止任务'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '停止'));
    await tester.pumpAndSettle();
    expect(find.textContaining('电脑端不支持从手机停止这个任务'), findsOneWidget);
    expect(find.textContaining('synthetic-private'), findsNothing);
  });
}

class _Refusing extends _State {
  @override
  Future<Object?> request(
    String desktop,
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    if (method == LinkMethods.stopTask) {
      throw const LinkRemoteException(
        LinkErrors.unsupported,
        'synthetic-private',
      );
    }
    return super.request(desktop, method, params);
  }
}
