import 'dart:async';

import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/models/user_facing_error.dart';
import 'package:baocode_mobile/state/app_state.dart';
import 'package:baocode_mobile/ui/tasks/interaction_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingState extends AppState {
  _RecordingState() : super(demo: true);
  final calls = <(String, Map<String, Object?>)>[];
  bool fail = false;
  Completer<void>? pending;
  @override
  String tr(String zh, String en) => zh;
  @override
  Future<Object?> request(
    String desktopId,
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    calls.add((method, params));
    await pending?.future;
    if (fail) throw const UserFacingError('审批提交失败');
    return null;
  }
}

Widget _question(_RecordingState state, {bool other = false}) => MaterialApp(
  home: Scaffold(
    body: InteractionPanel(
      state: state,
      desktopId: 'desk-A',
      sessionId: 'session-B',
      request: {
        't': 'question',
        'id': 'question-3',
        'title': '选择方案',
        'questions': [
          {
            'header': '实现方式',
            'prompt': '选择一个选项',
            'options': [
              {'label': '快速实现'},
              {'label': '稳妥实现'},
            ],
            if (other) 'other': '',
          },
        ],
      },
    ),
  ),
);

Widget _approval(
  _RecordingState state, {
  Map<String, Object?> overrides = const {},
  double scale = 1,
  double keyboard = 0,
}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(scale),
      viewInsets: EdgeInsets.only(bottom: keyboard),
    ),
    child: child!,
  ),
  home: Scaffold(
    body: InteractionPanel(
      state: state,
      desktopId: 'desk-A',
      sessionId: 'session-B',
      request: {
        't': 'approval',
        'id': 'approval-7',
        'title': '审批',
        'tool': 'Shell',
        'always': 'always allow Bash(grep -n "requestFocus" routes.dart)',
        'preview': {
          't': 'command',
          'command': 'grep -n "requestFocus" routes.dart',
        },
        ...overrides,
      },
    ),
  ),
);

const _command = <String, Object?>{
  'title': 'Run this command?',
  'tool': 'Bash',
  'reason': "A variable in this command can't be checked before it runs",
  'always': null,
  'preview': {
    't': 'command',
    'command': 'flutter test test/widgets/example_test.dart',
  },
};

void main() {
  testWidgets('审批卡直接显示要执行的命令，不重复英文原文，看命令不等于批准', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = _RecordingState();
    addTearDown(state.dispose);
    await tester.pumpWidget(_approval(state, overrides: _command));
    expect(find.byType(TextField), findsNothing);
    expect(find.text('允许执行此命令？'), findsOneWidget);
    expect(find.text('命令包含运行前无法检查的变量。'), findsOneWidget);
    expect(find.text('查看操作'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('approval-command')),
        matching: find.text('flutter test test/widgets/example_test.dart'),
      ),
      findsOneWidget,
    );
    expect(find.text('Run this command?'), findsNothing);
    expect(find.text(_command['reason']! as String), findsNothing);
    expect(find.widgetWithText(OutlinedButton, '拒绝'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '允许一次'), findsOneWidget);
    expect(state.calls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏大字键盘下可展开详情和拒绝说明，审批按钮保持可点', (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = _RecordingState();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      _approval(state, scale: 1.4, keyboard: 240, overrides: _command),
    );
    await tester.tap(find.widgetWithText(OutlinedButton, '拒绝'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(TextField));
    await tester.enterText(find.byType(TextField), '请先说明用途');
    await tester.pump();
    await tester.ensureVisible(find.text('拒绝并发送'));
    await tester.tap(find.text('拒绝并发送'));
    await tester.pump();
    expect(state.calls.single.$2, {
      'session': 'session-B',
      'request': 'approval-7',
      'answer': {'t': 'approval', 'decision': 'deny', 'message': '请先说明用途'},
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('审批提交中不可重复操作，失败明确显示并允许手动重试', (tester) async {
    final state = _RecordingState()
      ..pending = Completer<void>()
      ..fail = true;
    addTearDown(state.dispose);
    await tester.pumpWidget(_approval(state));
    await tester.tap(find.text('允许一次'));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '允许一次'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '拒绝'))
          .onPressed,
      isNull,
    );
    state.pending!.complete();
    await tester.pump();
    await tester.pump();
    expect(state.calls, hasLength(1));
    expect(find.textContaining('审批提交失败'), findsOneWidget);
    state.fail = false;
    await tester.tap(find.text('允许一次'));
    await tester.pump();
    expect(state.calls, hasLength(2));
    expect(state.calls.last.$2['answer'], {
      't': 'approval',
      'decision': 'allowOnce',
    });
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('点拒绝先展开说明框，不立即拒绝；填写后拒绝并发送带上说明', (tester) async {
    final state = _RecordingState();
    addTearDown(state.dispose);
    await tester.pumpWidget(_approval(state));
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('拒绝'));
    await tester.pumpAndSettle();
    expect(state.calls, isEmpty);
    expect(find.byType(TextField), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '拒绝并发送'))
          .onPressed,
      isNull,
    );
    expect(find.text('允许一次'), findsNothing);
    await tester.enterText(find.byType(TextField), '仅允许读取，不允许写入');
    await tester.pump();
    await tester.tap(find.text('拒绝并发送'));
    await tester.pump();
    expect(state.calls, hasLength(1));
    expect(state.calls.single.$1, LinkMethods.answer);
    expect(state.calls.single.$2, {
      'session': 'session-B',
      'request': 'approval-7',
      'answer': {'t': 'approval', 'decision': 'deny', 'message': '仅允许读取，不允许写入'},
    });
  });

  testWidgets('直接拒绝不带说明；返回后不发请求、可以改为允许', (tester) async {
    final state = _RecordingState();
    addTearDown(state.dispose);
    await tester.pumpWidget(_approval(state));
    await tester.tap(find.text('拒绝'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('返回'));
    await tester.pumpAndSettle();
    expect(state.calls, isEmpty);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('允许一次'), findsOneWidget);
    await tester.tap(find.text('拒绝'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('直接拒绝'));
    await tester.pump();
    expect(state.calls.single.$2['answer'], {
      't': 'approval',
      'decision': 'deny',
    });
  });

  testWidgets('选择提问选项并提交', (tester) async {
    final state = _RecordingState();
    addTearDown(state.dispose);
    await tester.pumpWidget(_question(state));
    expect(find.byType(CheckboxListTile), findsNWidgets(2));
    await tester.tap(find.text('快速实现'));
    await tester.pump();
    await tester.tap(find.text('回答'));
    await tester.pump();
    expect(state.calls, hasLength(1));
    expect(state.calls.single.$1, LinkMethods.answer);
    expect(state.calls.single.$2['answer'], {
      't': 'question',
      'picks': [
        ['快速实现'],
      ],
    });
  });

  testWidgets('其他回答可输入自定义内容并提交', (tester) async {
    final state = _RecordingState();
    addTearDown(state.dispose);
    final widget = MaterialApp(
      home: Scaffold(
        body: InteractionPanel(
          state: state,
          desktopId: 'desk-A',
          sessionId: 'session-B',
          request: {
            't': 'question',
            'id': 'question-other',
            'questions': [
              {
                'prompt': '选一个方案',
                'options': [
                  {'label': '固定选项'},
                ],
                'other': '自定义',
              },
            ],
          },
        ),
      ),
    );
    await tester.pumpWidget(widget);
    final otherTile = find.byType(CheckboxListTile).last;
    expect(tester.widget<CheckboxListTile>(otherTile).value, isFalse);
    await tester.tap(otherTile);
    await tester.pumpAndSettle();
    expect(tester.widget<CheckboxListTile>(otherTile).value, isTrue);
    expect(find.byType(TextField), findsOneWidget);
    final answerField = find.byType(TextField);
    await tester.ensureVisible(answerField);
    await tester.enterText(answerField, '自定义方案');
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '回答'))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.widgetWithText(FilledButton, '回答'));
    await tester.pump();
    expect(state.calls, hasLength(1));
    expect(state.calls.single.$2['answer'], {
      't': 'question',
      'picks': [
        ['自定义方案'],
      ],
    });
  });

  testWidgets('窄屏大字提问面板不溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = _RecordingState();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            size: const Size(320, 700),
            textScaler: const TextScaler.linear(1.6),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: InteractionPanel(
            state: state,
            desktopId: 'desk-A',
            sessionId: 'session-B',
            request: {
              't': 'question',
              'id': 'question-3',
              'title': '选择方案',
              'questions': [
                {
                  'header': '实现方式',
                  'prompt': '选择一个选项',
                  'options': [
                    {'label': '快速实现'},
                    {'label': '稳妥实现'},
                  ],
                },
              ],
            },
          ),
        ),
      ),
    );
    expect(
      MediaQuery.textScalerOf(
        tester.element(find.byType(CheckboxListTile).first),
      ).scale(10),
      16,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('始终允许发送allowAlways wire决策', (tester) async {
    final state = _RecordingState();
    addTearDown(state.dispose);
    await tester.pumpWidget(_approval(state));
    await tester.tap(find.text('总是允许'));
    await tester.pump();
    expect(state.calls, hasLength(1));
    expect(state.calls.single.$1, LinkMethods.answer);
    expect(state.calls.single.$2, {
      'session': 'session-B',
      'request': 'approval-7',
      'answer': {'t': 'approval', 'decision': 'allowAlways'},
    });
  });

  testWidgets('总是允许的规则单独列在按钮上方，规则再长也看得到命令和按钮', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = _RecordingState();
    addTearDown(state.dispose);
    final rule =
        'always allow Bash(grep -n "requestFocus" '
        '/e/flutter/packages/flutter/lib/src/widgets/routes.dart | head -20)';
    await tester.pumpWidget(
      _approval(
        state,
        overrides: {
          'always': [for (var i = 0; i < 5; i++) '$rule $i'].join(', '),
        },
      ),
    );
    // 按钮只写三个字，不再是整句规则。
    expect(find.widgetWithText(OutlinedButton, '总是允许'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '总是允许'), findsNothing);
    // 规则在按钮上方，最多三行，剩下的写成还有几项。
    final rules = find.byKey(const ValueKey('approval-always-rules'));
    expect(rules, findsOneWidget);
    expect(
      tester.getRect(rules).bottom,
      lessThanOrEqualTo(
        tester.getRect(find.widgetWithText(OutlinedButton, '总是允许')).top,
      ),
    );
    expect(find.textContaining('还有 2 项'), findsOneWidget);
    // 卡片不超过它惯常的高度，命令预览和按钮都在。
    expect(
      tester.getSize(find.byType(InteractionPanel)).height,
      lessThanOrEqualTo(360),
    );
    expect(find.byKey(const ValueKey('approval-command')), findsOneWidget);
    expect(find.text('允许一次'), findsOneWidget);
    // 点开看全部。
    await tester.tap(rules);
    await tester.pumpAndSettle();
    expect(find.textContaining('always allow Bash'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('长选项提问：标题本地化，回答按钮仍在屏幕内', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = _RecordingState();
    addTearDown(state.dispose);
    final long = '很长的说明' * 20;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: InteractionPanel(
              state: state,
              desktopId: 'desk-A',
              sessionId: 'session-B',
              request: {
                't': 'question',
                'id': 'question-long',
                'title': 'Claude has a question',
                'questions': [
                  {
                    'header': '恢复远程',
                    'prompt': '确认执行吗？',
                    'options': [
                      for (var i = 0; i < 4; i++)
                        {'label': '选项$i', 'description': long},
                    ],
                    'other': '',
                  },
                ],
              },
            ),
          ),
        ),
      ),
    );
    expect(find.text('Claude has a question'), findsNothing);
    expect(find.text('需要你回答'), findsOneWidget);
    // 选项很多时按钮仍在屏幕内，无需滚动。
    final answer = tester.getRect(find.widgetWithText(FilledButton, '回答'));
    expect(answer.bottom, lessThanOrEqualTo(640));
    await tester.tap(find.text('选项0'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '回答'));
    await tester.pump();
    expect(state.calls.single.$2['answer'], {
      't': 'question',
      'picks': [
        ['选项0'],
      ],
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('跳过要再确认一次，返回不发请求，确认后才跳过', (tester) async {
    final state = _RecordingState();
    addTearDown(state.dispose);
    await tester.pumpWidget(_question(state));
    await tester.tap(find.text('跳过'));
    await tester.pump();
    expect(state.calls, isEmpty);
    expect(find.text('回答'), findsNothing);
    await tester.tap(find.text('返回'));
    await tester.pump();
    expect(find.text('回答'), findsOneWidget);
    expect(state.calls, isEmpty);
    await tester.tap(find.text('跳过'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('question-skip-confirm')));
    await tester.pump();
    expect(state.calls.single.$2['answer'], {'t': 'question', 'skipped': true});
  });

  testWidgets('勾选其他后输入框自动获得焦点', (tester) async {
    final state = _RecordingState();
    addTearDown(state.dispose);
    await tester.pumpWidget(_question(state, other: true));
    await tester.tap(find.text('其他'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.autofocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
  });
}
