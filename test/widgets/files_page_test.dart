import 'package:baocode_mobile/link/link_store.dart';
import 'package:baocode_mobile/state/app_state.dart';
import 'package:baocode_mobile/theme/app_theme.dart';
import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/ui/files/files_tab.dart';
import 'package:flutter/material.dart';
import 'package:baocode_mobile/theme/material_file_icons.dart'
    as material_icons;
import 'package:flutter_test/flutter_test.dart';

class _Disk extends AppState {
  _Disk({this.failure}) : super(store: MemoryLinkStore());
  final String? failure;
  final folders = <Object?>[];
  @override
  String tr(String zh, String en) => zh;
  @override
  Future<Object?> request(
    String desktopId,
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    if (method == LinkMethods.files) {
      return {
        'paths': ['lib/main.dart', 'README.md'],
      };
    }
    if (method != LinkMethods.folder) return null;
    folders.add(params['path']);
    if (failure case final code?) throw LinkRemoteException(code, code);
    return params['path'] == ''
        ? {
            'folders': ['lib', 'build'],
            'files': ['README.md', '.env'],
          }
        : {
            'folders': <String>[],
            'files': ['out.txt'],
          };
  }
}

const _project = ProjectRef(
  'desktop',
  ProjectInfo(id: 'p', name: '工程', path: '/工程'),
);

void main() {
  testWidgets('目录和文件使用桌面专用图标与未知项回退', (tester) async {
    final icons = material_icons.MaterialFileIcons.instance;
    await tester.runAsync(() => icons.load());
    expect(icons.folderIcon('.github'), isNot(icons.folderIcon('未知目录')));
    expect(icons.folderIcon('lib'), isNot(icons.folderIcon('未知目录')));
    expect(icons.folderIcon('未知目录'), 'folder');
    expect(icons.fileIcon('main.dart'), isNot(icons.fileIcon('unknown.zzzz')));
  });
  testWidgets('文件页可切换列表和网格视图并进入文件夹', (tester) async {
    final state = AppState(demo: true, store: MemoryLinkStore());
    addTearDown(state.dispose);
    await state.initialize();
    state.settings.language = 'zh';

    await tester.pumpWidget(
      MaterialApp(
        theme: MobileTheme.build(Brightness.light),
        home: FilesPage(
          state: state,
          project: const ProjectRef(
            'demo-desktop',
            ProjectInfo(id: 'p', name: '工程', path: 'E:/工程'),
          ),
          listing: const {
            'paths': [
              'lib/main.dart',
              'lib/ui.dart',
              'lib/nested/a.dart',
              'lib/nested/b.dart',
              'lib/nested/deep/c.dart',
              'README.md',
            ],
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('lib'), findsOneWidget);
    expect(find.text('README.md'), findsOneWidget);
    expect(find.text('3 项'), findsOneWidget);
    expect(find.descendant(
      of: find.byType(AppBar),
      matching: find.byKey(const ValueKey('file-view-switch')),
    ), findsOneWidget);

    await tester.tap(find.byTooltip('网格视图'));
    await tester.pumpAndSettle();
    expect(find.byType(GridView), findsOneWidget);

    await tester.tap(find.text('lib'));
    await tester.pumpAndSettle();
    expect(find.text('工程 › lib'), findsOneWidget);
    expect(find.text('main.dart'), findsOneWidget);
    expect(find.text('ui.dart'), findsOneWidget);
  });

  testWidgets('文件搜索仍可定位匹配路径', (tester) async {
    final state = AppState(demo: true, store: MemoryLinkStore());
    addTearDown(state.dispose);
    await state.initialize();
    state.settings.language = 'zh';

    await tester.pumpWidget(
      MaterialApp(
        theme: MobileTheme.build(Brightness.light),
        home: FilesPage(
          state: state,
          project: const ProjectRef(
            'demo-desktop',
            ProjectInfo(id: 'p', name: '工程', path: 'E:/工程'),
          ),
          listing: const {
            'paths': ['lib/main.dart', 'README.md'],
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'README');
    await tester.pumpAndSettle();
    expect(find.text('README.md'), findsOneWidget);
    expect(find.text('lib'), findsNothing);
  });

  testWidgets('列表每行等高：文件夹项数在右侧，改动文件显示 Git 字母，根目录不重复项目名', (tester) async {
    final state = AppState(demo: true, store: MemoryLinkStore());
    addTearDown(state.dispose);
    await state.initialize();
    state.settings.language = 'zh';
    await tester.pumpWidget(
      MaterialApp(
        theme: MobileTheme.build(Brightness.light),
        home: FilesPage(
          state: state,
          project: const ProjectRef(
            'demo-desktop',
            ProjectInfo(id: 'p', name: '工程', path: 'E:/工程'),
          ),
          listing: const {
            'paths': [
              'configs/a.json',
              'configs/b.json',
              'README.md',
              'new.md',
              'a-really-long-file-name-that-will-never-fit-on-one-phone-line.config.json',
            ],
            'changes': {'README.md': 'modified', 'new.md': 'added'},
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('工程'), findsOneWidget);
    final heights = {
      for (final name in ['configs', 'README.md', 'new.md'])
        tester.getSize(find.byKey(ValueKey('file-row-$name'))).height,
    };
    expect(heights, hasLength(1));
    final folder = find.byKey(const ValueKey('file-row-configs'));
    expect(
      find.descendant(of: folder, matching: find.text('2 项')),
      findsOneWidget,
    );
    expect(
      tester.getCenter(find.text('2 项')).dy,
      closeTo(tester.getCenter(find.text('configs')).dy, 1),
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('file-row-README.md')),
        matching: find.text('M'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('file-row-new.md')),
        matching: find.text('A'),
      ),
      findsOneWidget,
    );
    final long = find.byKey(
      const ValueKey(
        'file-row-a-really-long-file-name-that-will-never-fit-on-one-phone-line.config.json',
      ),
    );
    expect(
      find.descendant(of: long, matching: find.text('.json')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  double opacity(WidgetTester tester, String name) => tester
      .widget<Opacity>(
        find.descendant(
          of: find.byKey(ValueKey('file-row-$name')),
          matching: find.byType(Opacity),
        ),
      )
      .opacity;

  testWidgets('Git 忽略的文件灰着列出，也能进入忽略的文件夹', (tester) async {
    final state = _Disk();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: MobileTheme.build(Brightness.light),
        home: FilesPage(state: state, project: _project),
      ),
    );
    await tester.pumpAndSettle();
    expect(state.folders, ['']);
    expect(opacity(tester, 'lib'), 1);
    expect(opacity(tester, 'README.md'), 1);
    expect(opacity(tester, 'build'), lessThan(1));
    expect(opacity(tester, '.env'), lessThan(1));

    await tester.tap(find.byKey(const ValueKey('file-row-build')));
    await tester.pumpAndSettle();
    expect(state.folders, ['', 'build']);
    expect(find.byKey(const ValueKey('file-row-out.txt')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('旧电脑端没有 folder 时照常只列 files', (tester) async {
    final state = _Disk(failure: LinkErrors.unknown);
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: MobileTheme.build(Brightness.light),
        home: FilesPage(state: state, project: _project),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('file-row-lib')), findsOneWidget);
    expect(find.byKey(const ValueKey('file-row-build')), findsNothing);
  });

  testWidgets('folder 的其他错误不当作空目录吞掉', (tester) async {
    final state = _Disk(failure: 'failed');
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: MobileTheme.build(Brightness.light),
        home: FilesPage(state: state, project: _project),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('@ 文件复用文件页：点进文件夹选中文件，一路退回并带回路径', (tester) async {
    final state = _Disk();
    addTearDown(state.dispose);
    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        theme: MobileTheme.build(Brightness.light),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => picked = await Navigator.push<String>(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    FilesPage(state: state, project: _project, picking: true),
              ),
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('选择要引用的文件'), findsOneWidget);
    await tester.tap(find.text('lib'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('main.dart'));
    await tester.pumpAndSettle();
    // 两层页面都退掉了，没有打开文件查看页。
    expect(find.byType(FilesPage), findsNothing);
    expect(find.byType(FileViewerPage), findsNothing);
    expect(picked, 'lib/main.dart');
  });
}
