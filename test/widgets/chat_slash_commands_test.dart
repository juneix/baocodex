// YCode — GPL-3.0-only.
import 'package:bao_link/bao_link.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/chat_page_harness.dart';

class _CommandsState extends ChineseChatPageState {
  _CommandsState({this.folderUnknown = false});

  final bool folderUnknown;

  /// 前几次问技能时断线。
  int failExtensions = 0;

  @override
  Future<Object?> request(
    String desktopId,
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    calls.add((method, params));
    switch (method) {
      case LinkMethods.extensions:
        if (failExtensions > 0) {
          failExtensions--;
          throw const LinkRemoteException('timeout', '超时');
        }
        return {
          'items': [
            {'kind': 'skill', 'scope': 'user', 'name': 'work-report'},
            {
              'kind': 'skill',
              'scope': 'project',
              'name': 'other-skill',
              'project': 'other',
            },
            {'kind': 'mcp', 'scope': 'user', 'name': 'browser'},
          ],
        };
      case LinkMethods.folder:
        if (folderUnknown) {
          throw const LinkRemoteException(LinkErrors.unknown, '旧电脑端');
        }
        return {
          'folders': const <String>[],
          'files': ['deploy.md', 'README.txt'],
        };
      case LinkMethods.read:
        return {
          'text': '---\ndescription: 部署到测试环境\nargument-hint: [环境]\n---\n',
        };
    }
    return null;
  }
}

void main() {
  testWidgets('打 / 列出内置命令、电脑上的技能和项目 .claude/commands', (tester) async {
    final state = _CommandsState();
    addTearDown(state.dispose);
    await tester.pumpWidget(chatHost(state));
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, '/');
    await tester.pumpAndSettle();

    final folder = state.calls.firstWhere(
      (call) => call.$1 == LinkMethods.folder,
    );
    expect(folder.$2, {'project': 'project', 'path': '.claude/commands'});
    expect(
      state.calls
          .where((call) => call.$1 == LinkMethods.read)
          .map((call) => call.$2['path']),
      ['.claude/commands/deploy.md'],
    );

    await tester.enterText(find.byType(TextField).first, '/dep');
    await tester.pumpAndSettle();
    expect(find.text('/deploy'), findsOneWidget);
    expect(find.text('[环境]  部署到测试环境'), findsOneWidget);
    expect(find.text('项目'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '/work');
    await tester.pumpAndSettle();
    expect(find.text('/work-report'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '/other');
    await tester.pumpAndSettle();
    expect(find.text('/other-skill'), findsNothing, reason: '别的项目的技能不列');

    await tester.enterText(find.byType(TextField).first, '/');
    await tester.pumpAndSettle();
    expect(
      state.calls.where((call) => call.$1 == LinkMethods.extensions).length,
      1,
      reason: '只在第一次打 / 时问电脑',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('技能没拿到的，过一会儿再打 / 时只重问技能', (tester) async {
    final state = _CommandsState()..failExtensions = 1;
    addTearDown(state.dispose);
    int asked(String method) =>
        state.calls.where((call) => call.$1 == method).length;
    await tester.pumpWidget(chatHost(state));
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, '/');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '/w');
    await tester.pumpAndSettle();
    expect(find.text('/work-report'), findsNothing);
    expect(asked(LinkMethods.extensions), 1);

    // 刚失败：接着打字不重问，免得每次重画都发请求。
    await tester.enterText(find.byType(TextField).first, '/wo');
    await tester.pumpAndSettle();
    expect(asked(LinkMethods.extensions), 1);

    await tester.pump(const Duration(seconds: 11));
    await tester.enterText(find.byType(TextField).first, '/wor');
    await tester.pumpAndSettle();
    expect(find.text('/work-report'), findsOneWidget);
    expect(asked(LinkMethods.extensions), 2);
    expect(asked(LinkMethods.folder), 1, reason: '项目命令已经拿到，不再问');

    await tester.pump(const Duration(seconds: 11));
    await tester.enterText(find.byType(TextField).first, '/');
    await tester.pumpAndSettle();
    expect(asked(LinkMethods.extensions), 2, reason: '都拿到了就不再问');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('电脑端不认 folder 时照样列内置命令和技能', (tester) async {
    final state = _CommandsState(folderUnknown: true);
    addTearDown(state.dispose);
    await tester.pumpWidget(chatHost(state));
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, '/re');
    await tester.pumpAndSettle();
    expect(find.text('/recap'), findsOneWidget);
    expect(find.text('/work-report'), findsOneWidget);
    expect(find.text('/review'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
