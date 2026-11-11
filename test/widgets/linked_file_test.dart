import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/chat/chat_links.dart';
import 'package:baocode_mobile/chat/markdown/file_link.dart';
import 'package:baocode_mobile/state/app_state.dart';
import 'package:baocode_mobile/ui/files/files_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/chat_test_state.dart';

class _State extends ChatTestState {
  _State() : super(zh: true);

  @override
  List<ProjectRef> get projects => const [
    ProjectRef('desktop', ProjectInfo(id: 'project', name: 'p', path: 'D:/p')),
  ];

  @override
  Future<Object?> request(
    String desktopId,
    String method, [
    Map<String, Object?> params = const {},
  ]) async => switch (method) {
    LinkMethods.files => {
      'paths': ['README.md', 'docs/upstream-baseline.json', 'a/x.md', 'b/x.md'],
    },
    LinkMethods.read => {'text': '内容'},
    _ => null,
  };
}

void main() {
  Future<void> open(WidgetTester tester, _State state, String path) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showLinkedFile(context, state, 'desktop', 'project', path),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
  }

  String viewing(WidgetTester tester) =>
      tester.widget<FileViewerPage>(find.byType(FileViewerPage)).path;

  testWidgets('聊天里的项目文件用文件页的查看器打开，只给文件名时按名字找', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    await open(tester, state, 'upstream-baseline.json');
    expect(viewing(tester), 'docs/upstream-baseline.json');
  });

  testWidgets('同名文件有几个时让人挑', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    await open(tester, state, 'x.md');
    expect(find.byType(FileViewerPage), findsNothing);
    await tester.tap(find.text('b/x.md'));
    await tester.pumpAndSettle();
    expect(viewing(tester), 'b/x.md');
  });

  testWidgets('项目里没有这个文件就说找不到，不打开查看器', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    await open(tester, state, 'nowhere.md');
    expect(find.byType(FileViewerPage), findsNothing);
    expect(find.text('项目里没有找到 nowhere.md。'), findsOneWidget);
  });

  test('Windows 模型写的 /D:/路径 去掉盘符前的斜杠', () {
    expect(
      FileLink.parseHref('/D:/Desktop/ctf/a.svg'),
      const FileLink('D:/Desktop/ctf/a.svg'),
    );
    expect(
      FileLink.parseHref(r'/D:\p\a.dart#L4'),
      const FileLink(r'D:\p\a.dart'),
    );
    expect(
      FileLink.parseHref('file:///C:/p/a.dart'),
      const FileLink('C:/p/a.dart'),
    );
    expect(FileLink.parseHref('/home/a.dart'), const FileLink('/home/a.dart'));
  });
}
