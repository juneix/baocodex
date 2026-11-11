import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/models/user_facing_error.dart';
import 'package:baocode_mobile/state/app_state.dart';
import 'package:baocode_mobile/ui/tasks/changes_page.dart';
import 'package:baocode_mobile/ui/files/files_tab.dart';
import 'package:flutter/material.dart';
import 'package:baocode_mobile/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingState extends AppState {
  _RecordingState() : super(demo: true);
  final history = SessionBuffer('desk-A', 'session-B');
  final calls = <(String, String, Map<String, Object?>)>[];
  bool online = true;
  bool fail = false;
  Map<String, Object?>? file;
  List<SessionRef> sessionRefs = const [];

  @override
  List<SessionRef> get sessions => sessionRefs;
  @override
  String tr(String zh, String en) => zh;
  @override
  bool isOnline(String desktopId) => online;
  @override
  SessionBuffer buffer(String desktopId, String sessionId) => history;
  @override
  Future<Object?> request(
    String desktopId,
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    calls.add((desktopId, method, params));
    if (fail) throw const UserFacingError('请求失败');
    return method == LinkMethods.read ? file : null;
  }
}

Widget _page(_RecordingState state) => MaterialApp(
  home: ChangesPage(state: state, desktopId: 'desk-A', sessionId: 'session-B'),
);

SessionRef _ref(String desktop, String session, String project) => SessionRef(
  desktop,
  SessionSummary(
    id: session,
    project: project,
    title: 't',
    updatedAt: DateTime(2026),
  ),
);

Widget _pageWith(_RecordingState state, {String? projectId}) => MaterialApp(
  home: ChangesPage(
    state: state,
    desktopId: 'desk-A',
    sessionId: 'session-B',
    projectId: projectId,
  ),
);

void main() {
  testWidgets('全部操作位于文件列表上方且长列表无需滚动即可操作', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = _RecordingState();
    addTearDown(state.dispose);
    state.history.changes = [
      {'path': 'a.dart', 'added': 2, 'removed': 1},
    ];
    await tester.pumpWidget(_page(state));
    await tester.pumpAndSettle();
    final row = tester.getRect(find.byType(ChangeFileRow));
    final keep = tester.getRect(find.widgetWithText(FilledButton, '全部保留'));
    expect(keep.bottom, lessThanOrEqualTo(row.top));
    state.history.changes = [
      for (var i = 0; i < 30; i++) {'path': 'file-$i.dart', 'added': 1},
    ];
    state.notifyListeners();
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(FilledButton, '全部保留').hitTestable(),
      findsOneWidget,
    );
    final top = tester.getTopLeft(find.widgetWithText(FilledButton, '全部保留'));
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.widgetWithText(FilledButton, '全部保留')), top);
    await tester.tap(find.widgetWithText(FilledButton, '全部保留'));
    await tester.pumpAndSettle();
    expect(state.calls, hasLength(1));
    expect(state.calls.single.$1, 'desk-A');
    expect(state.calls.single.$2, LinkMethods.keep);
    expect(state.calls.single.$3, {'session': 'session-B'});
    expect(tester.takeException(), isNull);
  });

  testWidgets('批量按钮在窄屏大字号下自然换行且撤回仍须确认', (tester) async {
    tester.view.physicalSize = const Size(300, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = _RecordingState();
    addTearDown(state.dispose);
    state.history.changes = [
      {'path': 'lib/a.dart', 'added': 2},
    ];
    await tester.pumpWidget(
      MaterialApp(
        theme: MobileTheme.build(Brightness.dark),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(1.8)),
          child: child!,
        ),
        home: ChangesPage(
          state: state,
          desktopId: 'desk-A',
          sessionId: 'session-B',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester.getTopLeft(find.widgetWithText(FilledButton, '全部保留')).dy,
      greaterThan(
        tester.getTopLeft(find.widgetWithText(OutlinedButton, '全部撤回')).dy,
      ),
    );
    await tester.tap(find.widgetWithText(OutlinedButton, '全部撤回'));
    await tester.pumpAndSettle();
    expect(find.text('撤回全部改动？'), findsOneWidget);
    expect(state.calls, isEmpty);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(state.calls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('内嵌文件面板在小高度大字及错误提示下仍可滚动操作', (tester) async {
    final state = _RecordingState()..fail = true;
    state.history.changes = [
      {'path': 'a.dart', 'added': 1, 'removed': 0},
    ];
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(1.4)),
          child: child!,
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              height: 72,
              child: ChangesPanel(
                state: state,
                desktopId: 'desk-A',
                sessionId: 'session-B',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // 懒加载项可能尚未构建；滚到按钮真正可点击，而非仅进入缓存区。
    await tester.scrollUntilVisible(
      find.byTooltip('文件操作 a.dart').hitTestable(),
      24,
      scrollable: find.byType(Scrollable),
    );
    await tester.tap(find.byTooltip('文件操作 a.dart'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保留改动'));
    await tester.pumpAndSettle();
    expect(state.calls.single.$1, 'desk-A');
    expect(state.calls.single.$2, LinkMethods.keep);
    expect(state.calls.single.$3, {
      'session': 'session-B',
      'paths': ['a.dart'],
    });
    await tester.ensureVisible(find.textContaining('请求失败'));
    expect(find.textContaining('请求失败'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('未传projectId时按同电脑同会话解析项目并进入差异', (tester) async {
    final state = _RecordingState()
      ..file = {'original': 'old line', 'text': 'new line'}
      ..sessionRefs = [
        _ref('desk-X', 'session-B', 'wrong-project'),
        _ref('desk-A', 'other-session', 'wrong-project-2'),
        _ref('desk-A', 'session-B', 'proj-1'),
      ];
    state.history.changes = [
      {'path': 'lib/a.dart', 'added': 1, 'removed': 1},
    ];
    addTearDown(state.dispose);
    await tester.pumpWidget(_pageWith(state));
    expect(find.text('a.dart'), findsWidgets);
    await tester.tap(find.text('a.dart'));
    await tester.pumpAndSettle();
    expect(state.calls, hasLength(1));
    expect(state.calls.single.$1, 'desk-A');
    expect(state.calls.single.$2, LinkMethods.read);
    expect(state.calls.single.$3, {'project': 'proj-1', 'path': 'lib/a.dart'});
    expect(find.byType(DiffView), findsOneWidget);
    expect(find.text('old line'), findsOneWidget);
    expect(find.text('new line'), findsOneWidget);
    expect(find.text('−'), findsOneWidget);
    expect(find.text('+'), findsOneWidget);
  });

  testWidgets('其他电脑的同名会话不能被误匹配，无法解析时给出原因且不读取', (tester) async {
    final state = _RecordingState()
      ..sessionRefs = [
        _ref('desk-X', 'session-B', 'wrong-project'),
        _ref('desk-A', 'session-B', '  '),
      ];
    state.history.changes = [
      {'path': 'lib/a.dart'},
    ];
    addTearDown(state.dispose);
    await tester.pumpWidget(_pageWith(state, projectId: ' '));
    await tester.tap(find.text('a.dart'));
    await tester.pumpAndSettle();
    expect(find.textContaining('无法确定'), findsOneWidget);
    expect(find.byType(DiffView), findsNothing);
    expect(state.calls, isEmpty);
  });

  testWidgets('显式projectId优先于会话解析', (tester) async {
    final state = _RecordingState()
      ..file = {'original': 'a', 'text': 'b'}
      ..sessionRefs = [_ref('desk-A', 'session-B', 'from-session')];
    state.history.changes = [
      {'path': 'x.txt'},
    ];
    addTearDown(state.dispose);
    await tester.pumpWidget(_pageWith(state, projectId: 'explicit'));
    await tester.tap(find.text('x.txt'));
    await tester.pumpAndSettle();
    expect(state.calls.single.$3, {'project': 'explicit', 'path': 'x.txt'});
  });

  testWidgets('缺少原文时明确说明并仅显示当前内容，不伪装成差异', (tester) async {
    final state = _RecordingState()..file = {'text': 'only current'};
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ProjectFilePage(
          state: state,
          desktopId: 'desk-A',
          projectId: 'p',
          path: 'a.txt',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('无法取得修改前内容'), findsOneWidget);
    expect(find.byType(DiffView), findsNothing);
    expect(find.textContaining('only current'), findsOneWidget);
  });

  testWidgets('读取失败、二进制和过大文件保留可见状态', (tester) async {
    final state = _RecordingState()..fail = true;
    addTearDown(state.dispose);
    Widget file() => MaterialApp(
      home: ProjectFilePage(
        state: state,
        desktopId: 'desk-A',
        projectId: 'p',
        path: 'a.bin',
      ),
    );
    await tester.pumpWidget(file());
    await tester.pumpAndSettle();
    expect(find.textContaining('请求失败'), findsOneWidget);
    expect(find.byType(DiffView), findsNothing);
    state
      ..fail = false
      ..file = {'binary': true};
    await tester.pumpWidget(MaterialApp(home: Container()));
    await tester.pumpWidget(file());
    await tester.pumpAndSettle();
    expect(find.textContaining('二进制'), findsOneWidget);
    state.file = {'tooLarge': true};
    await tester.pumpWidget(MaterialApp(home: Container()));
    await tester.pumpWidget(file());
    await tester.pumpAndSettle();
    expect(find.textContaining('过大'), findsOneWidget);
    expect(find.byType(DiffView), findsNothing);
  });

  testWidgets('删除后的空内容仍显示真实删除差异而不是降级提示', (tester) async {
    final state = _RecordingState()
      ..file = {'original': 'removed content', 'text': ''};
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ProjectFilePage(
          state: state,
          desktopId: 'desk-A',
          projectId: 'p',
          path: 'removed.txt',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DiffView), findsOneWidget);
    expect(find.text('removed content'), findsOneWidget);
    expect(find.text('−'), findsOneWidget);
    expect(find.textContaining('无法取得修改前内容'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('差异页标题只显示文件名，目录在下方', (tester) async {
    final state = _RecordingState()..file = {'original': 'a', 'text': 'b'};
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ProjectFilePage(
          state: state,
          desktopId: 'desk-A',
          projectId: 'p',
          path: 'E:/project/app/lib/main.dart',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('main.dart'), findsOneWidget);
    expect(find.text('E:/project/app/lib'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏深色大字号下查看入口及增删内容不溢出', (tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = _RecordingState()
      ..file = {
        'original': 'removed line\nsame line',
        'text': 'same line\nadded line',
      }
      ..sessionRefs = [_ref('desk-A', 'session-B', 'p')];
    state.history.changes = [
      {'path': 'lib/a.dart', 'added': 1, 'removed': 1},
    ];
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(1.4)),
          child: child!,
        ),
        home: ChangesPage(
          state: state,
          desktopId: 'desk-A',
          sessionId: 'session-B',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('a.dart'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('a.dart'));
    await tester.pumpAndSettle();
    expect(find.byType(DiffView), findsOneWidget);
    expect(find.text('removed line'), findsOneWidget);
    expect(find.text('added line'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('单文件保留携带当前会话和单一路径', (tester) async {
    final state = _RecordingState();
    state.history.changes = [
      {'path': 'lib/a.dart', 'added': 2, 'removed': 1},
    ];
    addTearDown(state.dispose);
    await tester.pumpWidget(_page(state));
    await tester.tap(find.byTooltip('文件操作 lib/a.dart'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保留改动'));
    await tester.pumpAndSettle();
    expect(state.calls, hasLength(1));
    expect(state.calls.single.$1, 'desk-A');
    expect(state.calls.single.$2, LinkMethods.keep);
    expect(state.calls.single.$3, {
      'session': 'session-B',
      'paths': ['lib/a.dart'],
    });
  });

  testWidgets('单文件撤回确认前不发请求，确认后只撤销对应路径', (tester) async {
    final state = _RecordingState();
    state.history.changes = [
      {'path': 'src/a.dart'},
    ];
    addTearDown(state.dispose);
    await tester.pumpWidget(_page(state));
    await tester.tap(find.byTooltip('文件操作 src/a.dart'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('撤回改动'));
    await tester.pumpAndSettle();
    expect(state.calls, isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, '撤回'));
    await tester.pumpAndSettle();
    expect(state.calls.single.$2, LinkMethods.undo);
    expect(state.calls.single.$3, {
      'session': 'session-B',
      'paths': ['src/a.dart'],
    });
  });

  testWidgets('取消全部撤回不请求，确认的全部撤回不带 paths', (tester) async {
    final state = _RecordingState();
    state.history.changes = [
      {'path': 'a'},
      {'path': 'b'},
    ];
    addTearDown(state.dispose);
    await tester.pumpWidget(_page(state));
    await tester.tap(find.text('全部撤回'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(state.calls, isEmpty);
    await tester.tap(find.text('全部撤回'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '撤回'));
    await tester.pumpAndSettle();
    expect(state.calls.single.$2, LinkMethods.undo);
    expect(state.calls.single.$3, {'session': 'session-B'});
  });

  testWidgets('失败信息可见且离线时所有写操作不可用', (tester) async {
    final state = _RecordingState()..fail = true;
    state.history.changes = [
      {'path': 'a'},
    ];
    addTearDown(state.dispose);
    await tester.pumpWidget(_page(state));
    await tester.tap(find.text('全部保留'));
    await tester.pumpAndSettle();
    expect(find.textContaining('请求失败'), findsOneWidget);
    state.online = false;
    await tester.pumpWidget(_page(state));
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '全部保留'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('全部保留')); // disabled; no request
    await tester.pump();
    expect(state.calls, hasLength(1));
  });
}
