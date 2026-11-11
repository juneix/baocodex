// YCode — GPL-3.0-only.
import 'dart:async';

import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/models/user_facing_error.dart';
import 'package:baocode_mobile/state/app_state.dart';
import 'package:baocode_mobile/ui/tasks/goal_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingState extends AppState {
  _RecordingState({this.fail = false, this.online = true}) : super(demo: true);

  final bool fail;
  final bool online;
  Completer<void>? pending;
  final calls = <(String, String, Map<String, Object?>)>[];

  @override
  bool isOnline(String desktopId) => online;

  @override
  Future<Object?> request(
    String desktopId,
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    calls.add((desktopId, method, params));
    await pending?.future;
    if (fail) throw const UserFacingError('Stop request failed');
    return null;
  }
}

void main() {
  final stop = find.byKey(const ValueKey('hollow-stop'));

  Widget page(
    AppState state, {
    String? sessionId = 'session',
    String goalState = 'active',
  }) => MaterialApp(
    home: GoalPage(
      state: state,
      desktopId: 'desktop',
      sessionId: sessionId,
      goal: {'condition': 'x', 'state': goalState},
    ),
  );

  Future<void> confirm(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Stop'));
    await tester.pump();
  }

  testWidgets('stop asks first, then targets the displayed session', (
    tester,
  ) async {
    final state = _RecordingState()..pending = Completer<void>();
    addTearDown(state.dispose);
    await tester.pumpWidget(page(state));

    await tester.tap(stop);
    await tester.pumpAndSettle();
    expect(state.calls, isEmpty);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(state.calls, isEmpty);

    await tester.tap(stop);
    await tester.pumpAndSettle();
    await confirm(tester);
    await tester.pump(const Duration(milliseconds: 300));

    expect(state.calls, hasLength(1));
    expect(state.calls.single.$1, 'desktop');
    expect(state.calls.single.$2, LinkMethods.stop);
    expect(state.calls.single.$3, {'session': 'session'});
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    state.pending!.complete();
    await tester.pumpAndSettle();
    expect(stop, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stop failures are shown instead of escaping the callback', (
    tester,
  ) async {
    final state = _RecordingState(fail: true);
    addTearDown(state.dispose);
    await tester.pumpWidget(page(state));

    await tester.tap(stop);
    await tester.pumpAndSettle();
    await confirm(tester);
    await tester.pump();

    expect(find.textContaining('Stop request failed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stop is disabled without a session or offline', (tester) async {
    IconButton button() => tester.widget<IconButton>(
      find.ancestor(of: stop, matching: find.byType(IconButton)),
    );
    final state = _RecordingState();
    addTearDown(state.dispose);
    await tester.pumpWidget(page(state, sessionId: null));
    expect(button().onPressed, isNull);

    final offline = _RecordingState(online: false);
    addTearDown(offline.dispose);
    await tester.pumpWidget(page(offline));
    expect(button().onPressed, isNull);
    expect(state.calls, isEmpty);
    expect(offline.calls, isEmpty);
  });

  testWidgets('a goal that is over has no stop', (tester) async {
    final state = _RecordingState();
    addTearDown(state.dispose);
    for (final over in ['met', 'failed', 'stopped']) {
      await tester.pumpWidget(page(state, goalState: over));
      expect(stop, findsNothing, reason: over);
    }
    await tester.pumpWidget(page(state, goalState: 'running'));
    expect(stop, findsOneWidget);
  });

  testWidgets('goal page shows condition, state chip, reason, counters', (
    tester,
  ) async {
    final state = AppState(demo: true);
    state.settings.language = 'zh';
    addTearDown(state.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: GoalPage(
          state: state,
          desktopId: 'desktop',
          sessionId: 'session',
          goal: const {
            'condition': '把示例项目的测试都跑绿，不引入新的失败。',
            'state': 'active',
            'reason': '还有 2 个测试未通过；其余全部绿了。',
            'checks': 3,
            'tokens': 5400,
          },
        ),
      ),
    );
    await tester.pump();

    expect(find.text('目标'), findsOneWidget);
    expect(find.text('进行中'), findsOneWidget);
    expect(find.text('把示例项目的测试都跑绿，不引入新的失败。'), findsOneWidget);
    expect(find.text('最近一次检查'), findsOneWidget);
    expect(find.text('还有 2 个测试未通过；其余全部绿了。'), findsOneWidget);
    expect(find.textContaining('检查次数: 3'), findsOneWidget);
    expect(find.textContaining('累计 token: 5400'), findsOneWidget);
    expect(stop, findsOneWidget);
  });

  testWidgets('unknown goal states pass through without guessing', (
    tester,
  ) async {
    final state = AppState(demo: true);
    state.settings.language = 'zh';
    addTearDown(state.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: GoalPage(
          state: state,
          desktopId: 'desktop',
          goal: const {'condition': 'x', 'state': 'weird-state'},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('weird-state'), findsOneWidget);
    expect(stop, findsNothing);
  });
}
