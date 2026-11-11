// YCode — GPL-3.0-only.
import 'dart:async';

import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/ui/tasks/rewind_files.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/chat_page_harness.dart';

void main() {
  /// 编辑第一条消息后点重新发送，停在确认框上。
  Future<ChineseChatPageState> editAndResend(
    WidgetTester tester,
    Object? Function(Map<String, Object?> params) plan,
  ) async {
    await tester.pumpWidget(const SizedBox.shrink());
    final state = ChineseChatPageState();
    addTearDown(state.dispose);
    state.answers[LinkMethods.rewindPlan] = plan;
    state.history
      ..items.add({'t': 'user', 'text': '旧要求'})
      ..items.add({'t': 'assistant', 'text': '改好了'});
    await tester.pumpWidget(chatHost(state));
    await tester.pump();
    await tester.tap(find.byTooltip('编辑并重新发送'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '新要求');
    await tester.pump();
    await tester.tap(find.byTooltip('重新发送'));
    await tester.pumpAndSettle();
    return state;
  }

  Map<String, Object?>? sentEdit(ChineseChatPageState state) =>
      state.calls.where((call) => call.$1 == LinkMethods.edit).lastOrNull?.$2;

  Map<String, Object?> files(String setting) => {
    'files': [
      {'name': 'lib/a.dart', 'outcome': 'restore'},
      {'name': 'lib/b.dart', 'outcome': 'merge'},
    ],
    'setting': setting,
  };

  testWidgets('改过文件时询问：撤回带 revertFiles，保留不带，取消继续编辑', (tester) async {
    for (final (button, revert) in [
      (find.widgetWithText(FilledButton, '撤回'), true),
      (find.widgetWithText(OutlinedButton, '保留'), false),
      (find.widgetWithText(OutlinedButton, '取消').last, null),
    ]) {
      final state = await editAndResend(tester, (_) => files('ask'));
      expect(state.calls.firstWhere((c) => c.$1 == LinkMethods.rewindPlan).$2, {
        'session': 'session',
        'index': 0,
      });
      expect(find.text('撤回这条消息之后的文件改动？'), findsOneWidget);
      expect(find.text('a.dart'), findsOneWidget);
      expect(find.textContaining('其中 1 个后来在别处也改过'), findsOneWidget);
      await tester.tap(button);
      await tester.pumpAndSettle();
      final edit = sentEdit(state);
      if (revert == null) {
        expect(edit, isNull);
        expect(find.textContaining('正在编辑'), findsOneWidget);
      } else {
        expect(edit!['text'], '新要求');
        expect(edit['revertFiles'] == true, revert);
      }
    }
  });

  testWidgets('电脑端设好了、旧电脑端或问不到时不弹撤回框', (tester) async {
    for (final (answer, note, revert) in [
      (files('revert'), '会撤回（电脑端设置）', true),
      (files('keep'), '会保留（电脑端设置）', false),
      (const LinkRemoteException(LinkErrors.unknown, 'old'), null, false),
      (TimeoutException('slow'), null, null),
    ]) {
      final state = await editAndResend(
        tester,
        (_) => answer is Map ? answer : throw answer,
      );
      expect(find.text('撤回这条消息之后的文件改动？'), findsNothing);
      if (revert == null) {
        // 问失败：提示错误，不发送，继续编辑。
        expect(find.text('重新发送？'), findsNothing);
        expect(find.textContaining('正在编辑'), findsOneWidget);
        expect(sentEdit(state), isNull);
        continue;
      }
      expect(
        find.textContaining('电脑端设置'),
        note == null ? findsNothing : findsOneWidget,
      );
      if (note != null) expect(find.textContaining(note), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '丢弃并发送'));
      await tester.pumpAndSettle();
      expect(sentEdit(state)!['revertFiles'] == true, revert);
    }
  });

  testWidgets('窄屏大字号下按钮不折行；长路径只显示文件名和缩写目录，多了只列 8 个', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = ChineseChatPageState();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => askResend(
              context,
              state,
              live: false,
              plan: RewindPlan([
                for (var i = 0; i < 10; i++)
                  (
                    '/Users/developer/Desktop/project/app/lib/f$i.dart',
                    'restore',
                  ),
                ('locked.dart', 'conflict'),
              ]),
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final line = tester.getSize(find.text('取消')).height;
    for (final label in ['保留', '撤回']) {
      expect(
        tester.getSize(find.text(label)).height,
        line,
        reason: '$label 不折行',
      );
    }
    expect(find.text('f7.dart'), findsOneWidget);
    expect(find.text('f8.dart'), findsNothing);
    expect(find.textContaining('……还有 2 个'), findsOneWidget);
    expect(find.textContaining('~/Desktop/project'), findsNWidgets(8));
    expect(find.textContaining('/Users/developer'), findsNothing);
    expect(find.text('1 个文件无法自动撤回，会保持不变：'), findsOneWidget);
    expect(find.text('locked.dart'), findsOneWidget);
  });
}
