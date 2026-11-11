import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/state/app_state.dart';
import 'package:baocode_mobile/theme/app_theme.dart';
import 'package:baocode_mobile/ui/tasks/changes_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _State extends AppState {
  _State() : super(demo: true);
  final history = SessionBuffer('desktop', 'session');
  final calls = <(String, Map<String, Object?>)>[];
  bool online = true;
  String root = '/Users/test/work/mobile';

  @override
  String tr(String zh, String en) => zh;
  @override
  bool isOnline(String desktopId) => online;
  @override
  List<ProjectRef> get projects => [
    ProjectRef(
      'desktop',
      ProjectInfo(id: 'project', name: 'Mobile', path: root),
    ),
  ];
  @override
  SessionBuffer buffer(String desktopId, String sessionId) => history;
  @override
  Future<Object?> request(
    String desktopId,
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    calls.add((method, params));
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _State state;
  String? copied;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    state = _State();
    copied = null;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
  });
  tearDown(() {
    state.dispose();
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> showChanges(
    WidgetTester tester,
    String path, {
    double scale = 1,
  }) async {
    state.history.changes = [
      {'path': path, 'added': 123, 'removed': 45},
    ];
    await tester.pumpWidget(
      MaterialApp(
        theme: MobileTheme.build(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: ChangesPage(
          state: state,
          desktopId: 'desktop',
          sessionId: 'session',
          projectId: 'project',
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('常见长文件名完整显示，项目相对目录与计数不挤占标题', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await showChanges(
      tester,
      '/Users/test/work/mobile/lib/ui/conversations/conversation_filter_sheet.dart',
    );
    final title = find.text('conversation_filter_sheet.dart');
    final paragraph = tester.renderObject<RenderParagraph>(title);
    expect(paragraph.didExceedMaxLines, isFalse);
    final directory = tester.widget<Text>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text && (widget.data ?? '').endsWith('conversations'),
      ),
    );
    expect(directory.data, isNot(contains('/Users/test/work/mobile')));
    final count = find.descendant(
      of: find.byType(ChangeFileRow),
      matching: find.byType(ChangeCounts),
    );
    expect(
      tester.getTopLeft(count).dy,
      greaterThan(tester.getTopLeft(title).dy),
    );
    expect(
      find.byTooltip(
        '保留 /Users/test/work/mobile/lib/ui/conversations/conversation_filter_sheet.dart',
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('跨平台路径正确拆分，Windows项目根匹配不区分大小写', (tester) async {
    state.root = r'C:\Work\Mobile';
    await showChanges(tester, r'c:\work\mobile\lib\ui\changes_page.dart');
    expect(find.text('changes_page.dart'), findsOneWidget);
    expect(find.text('lib/ui'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('空间充足时显示完整目录，不误裁掉与项目同名的前缀', (tester) async {
    state.root = '/Users/test/work/mobile';
    await showChanges(
      tester,
      '/Users/test/work/mobile-other/lib/ui/tasks/view.dart',
    );
    expect(find.text('~/work/mobile-other/lib/ui/tasks'), findsOneWidget);
    expect(find.text('view.dart'), findsOneWidget);
  });

  testWidgets('相对路径不固定裁成三级，仅在实际宽度不足时省略', (tester) async {
    await showChanges(tester, 'apps/mobile/lib/ui/devices/view.dart');
    expect(find.text('apps/mobile/lib/ui/devices'), findsOneWidget);
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpAndSettle();
    final labels = tester.widgetList<Text>(
      find.descendant(
        of: find.byType(ChangeFileRow),
        matching: find.byType(Text),
      ),
    );
    expect(
      labels.any(
        (text) =>
            (text.data ?? '').startsWith('…') &&
            (text.data ?? '').endsWith('devices'),
      ),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('完整路径可查看和复制，展示缩略不改变真实路径也不发写请求', (tester) async {
    const path = '/Users/test/work/mobile/lib/ui/tasks/文件 甲.dart';
    await showChanges(tester, path);
    await tester.tap(find.byTooltip('文件操作 $path'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看完整路径'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(SelectableText, path), findsOneWidget);
    await tester.tap(find.text('复制路径'));
    await tester.pumpAndSettle();
    expect(copied, path);
    expect(state.calls, isEmpty);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    await tester.tap(find.byTooltip('文件操作 $path'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('复制完整路径'));
    await tester.pumpAndSettle();
    expect(copied, path);
    expect(state.calls, isEmpty);
  });

  testWidgets('离线仍可读复制路径，但菜单内保留和撤回不可用', (tester) async {
    state.online = false;
    await showChanges(tester, 'lib/a.dart');
    await tester.tap(find.byTooltip('文件操作 lib/a.dart'));
    await tester.pumpAndSettle();
    for (final label in ['保留改动', '撤回改动']) {
      final item = tester.widget<PopupMenuItem<Object?>>(
        find.ancestor(
          of: find.text(label),
          matching: find.byWidgetPredicate((widget) => widget is PopupMenuItem),
        ),
      );
      expect(item.enabled, isFalse);
    }
    await tester.tap(find.text('复制完整路径'));
    await tester.pumpAndSettle();
    expect(copied, 'lib/a.dart');
    expect(state.calls, isEmpty);
  });

  testWidgets('窄屏大字号下长文件名与大计数不溢出，操作按钮保留触控宽度', (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await showChanges(
      tester,
      '/tmp/project/some/very/long/folder/device_filter_sheets_test.dart',
      scale: 1.5,
    );
    state.history.changes.single.addAll({'added': 1234567, 'removed': 9876543});
    state.notifyListeners();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final menu = find.byTooltip(
      '文件操作 /tmp/project/some/very/long/folder/device_filter_sheets_test.dart',
    );
    expect(tester.getSize(menu).width, greaterThanOrEqualTo(48));
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('保留改动'));
    await tester.pumpAndSettle();
    expect(state.calls.single.$1, LinkMethods.keep);
    expect(state.calls.single.$2, {
      'session': 'session',
      'paths': [
        '/tmp/project/some/very/long/folder/device_filter_sheets_test.dart',
      ],
    });
    expect(tester.takeException(), isNull);
  });
}
