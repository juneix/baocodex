// YCode — GPL-3.0-only.
// Tests for the batch-2 step rows ported from the desktop chat, and the
// dispatcher's plain-text/isStep/defaultExpanded logic.
import 'package:baocode_mobile/chat/chat_models.dart';
import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/chat/message_view.dart';
import 'package:baocode_mobile/chat/widgets/chat_item_view.dart';
import 'package:baocode_mobile/chat/widgets/command_step.dart';
import 'package:baocode_mobile/chat/widgets/agent_step.dart';
import 'package:baocode_mobile/chat/widgets/edit_step.dart';
import 'package:baocode_mobile/chat/widgets/plan_card.dart';
import 'package:baocode_mobile/chat/widgets/notice_row.dart';
import 'package:baocode_mobile/chat/widgets/terminal_text.dart';
import 'package:baocode_mobile/chat/widgets/live_selectable_text.dart';
import 'package:baocode_mobile/chat/widgets/tool_call_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/chat_test_state.dart';

class _State extends ChatTestState {
  _State() : super(zh: false, demo: true);
}

void main() {
  testWidgets('模型切换命令中文细行显示，英文保留原文', (tester) async {
    for (final zh in [true, false]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NoticeRow(
              item: const NoticeItem(
                NoticeKind.command,
                'Set model to `gpt-6.1-sol(high)`',
              ),
              zh: zh,
            ),
          ),
        ),
      );
      final text = find.text(
        zh ? '已切换模型为 gpt-6.1-sol(high)' : 'Set model to `gpt-6.1-sol(high)`',
      );
      expect(text, findsOneWidget);
      // 居中，两侧各一条分割线：换模型是段落分界，不是靠左的命令输出。
      expect(tester.widget<Text>(text).textAlign, TextAlign.center);
      expect(
        find.descendant(
          of: find.byType(NoticeRow),
          matching: find.byType(Divider),
        ),
        findsNWidgets(2),
      );
    }
    expect(tester.takeException(), isNull);
  });
  testWidgets('压缩分隔线的长说明占满中间宽度，两侧仍留短线', (tester) async {
    tester.view.physicalSize = const Size(390, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const long = 'Conversation compacted automatically · 595.0k → 16.6k tokens';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: NoticeRow(item: NoticeItem(NoticeKind.compaction, long)),
        ),
      ),
    );
    expect(tester.getSize(find.text(long)).width, greaterThan(390 * .6));
    for (final line in tester.widgetList(find.byType(Divider))) {
      expect(
        tester.getSize(find.byWidget(line)).width,
        greaterThanOrEqualTo(24),
      );
    }
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: NoticeRow(item: NoticeItem(NoticeKind.compaction, '已压缩')),
        ),
      ),
    );
    final short = tester.getSize(find.text('已压缩'));
    expect(short.height, lessThan(short.width));
    expect(tester.takeException(), isNull);
  });
  for (final status in [ToolStatus.denied, ToolStatus.failed]) {
    testWidgets('工具$status不使用成功态Wrote标签', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ToolCallRow(
              kind: ToolKind.edit,
              target: '独立测试.txt',
              label: 'Wrote',
              status: status,
              strings: ToolStrings.zhCN,
            ),
          ),
        ),
      );
      expect(find.textContaining('Wrote'), findsNothing);
      expect(
        find.textContaining(status == ToolStatus.denied ? '已拒绝' : '失败'),
        findsOneWidget,
      );
    });
  }
  test('terminalText replays carriage returns and backspaces', () {
    final progress = terminalText('Downloading.. 10%\rDownloading.. 50%\rDone');
    expect(progress.styled, isFalse);
    expect(progress.text, 'Done');
    final erased = terminalText('abc\b\bX');
    expect(erased.text, 'aX');
    final colored = terminalText('\x1b[32mgreen\x1b[0m plain');
    expect(colored.styled, isTrue);
    expect(colored.text, 'green plain');
  });

  test('chatItemPlainText mirrors the step rows', () {
    final tool = const ToolCallItem(
      kind: ToolKind.read,
      target: 'lib/main.dart',
      detail: 'L1-20',
      results: ['line one', 'line two'],
    );
    expect(
      chatItemPlainText(tool, expanded: true),
      'Read lib/main.dart L1-20\nline one\nline two',
    );
    expect(chatItemPlainText(tool), 'Read lib/main.dart L1-20');
    expect(isStep(tool), isTrue);
    expect(isStep(const NoticeItem(NoticeKind.info, 'hi')), isFalse);
    final streaming = const ThinkingItem(text: 'hmm', tokens: 0, seconds: null);
    expect(defaultExpanded(streaming), isTrue);
    expect(
      defaultExpanded(const ThinkingItem(text: 'hmm', tokens: 0, seconds: 3)),
      isFalse,
    );
    final done = const ThinkingItem(text: 'hmm', tokens: 0, seconds: 3);
    expect(chatItemPlainText(done), 'Thought 3s');
  });

  testWidgets('ToolCallRow shows the verb and target, opening to results', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ToolCallRow(
            kind: ToolKind.read,
            target: 'lib/main.dart',
            detail: 'L1-20',
            results: ['first line', 'second line'],
            expanded: true,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Read lib/main.dart L1-20'), findsOneWidget);
    expect(find.text('first line\nsecond line'), findsOneWidget);
  });

  testWidgets('ToolCallRow renders a todo list with its marks', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ToolCallRow(
            kind: ToolKind.todo,
            target: '修复',
            tool: 'TodoWrite',
            input: {
              'todos': [
                {'content': '写测试', 'status': 'completed'},
                {'content': '跑测试', 'status': 'in_progress'},
                {'content': '收尾', 'status': 'pending'},
              ],
            },
            expanded: true,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('Todos 1/3'), findsOneWidget);
    expect(find.text('写测试'), findsOneWidget);
    expect(find.text('跑测试'), findsOneWidget);
    final done = tester.widget<Text>(find.text('写测试'));
    expect(done.style?.decoration, TextDecoration.lineThrough);
  });

  testWidgets('EditStep shows the tally and the colored diff', (tester) async {
    final item = CodeDiffItem(
      fileName: 'main.dart',
      directory: 'pkg/lib',
      added: 2,
      removed: 1,
      lines: const [
        DiffLine(DiffLineType.context, 1, 'void main() {'),
        DiffLine(DiffLineType.added, 2, "  print('hi');"),
        DiffLine(DiffLineType.removed, 3, '  old();'),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditStep(item: item, expanded: true, onToggle: () {}),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Edited main.dart'), findsOneWidget);
    expect(find.textContaining('+2'), findsOneWidget);
    expect(find.textContaining('-1'), findsOneWidget);
    expect(find.text("  print('hi');"), findsOneWidget);
  });

  testWidgets('EditStep 按应用语言显示动词，绝对路径只显示文件名', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditStep(
            item: CodeDiffItem(
              fileName: r'E:\project\测试项目\独立文件.txt',
              directory: '',
              added: 2,
              removed: 0,
              lines: const [],
            ),
            tr: (zh, en) => zh,
          ),
        ),
      ),
    );
    expect(find.text('已编辑 独立文件.txt'), findsOneWidget);
  });

  testWidgets('AgentStep formats its meta and opens on a tap', (tester) async {
    final item = AgentItem(
      description: 'Explore the repo',
      agentType: 'Explore',
      toolUses: 12,
      tokens: 8200,
      status: CommandStatus.succeeded,
    );
    expect(AgentStep.formatTokens(8200), '8.2k');
    expect(AgentStep.meta(item), 'Explore · 12 tools · 8.2k tokens');
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgentStep(item: item, onOpen: () => opened = true),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Explore the repo'), findsOneWidget);
    await tester.tap(find.text('Explore the repo'));
    expect(opened, isTrue);
  });

  testWidgets('PlanCard shows the round card and folds one sent back', (
    tester,
  ) async {
    final plan = PlanItem(
      title: '重构聊天渲染',
      round: 2,
      status: PlanStatus.awaiting,
      path: '',
      text: '# 重构聊天渲染\n- 第一步\n- 第二步',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PlanCard(item: plan)),
      ),
    );
    await tester.pump();
    expect(find.text('重构聊天渲染'), findsOneWidget);
    expect(find.text('v2'), findsOneWidget);
    final sentBack = PlanItem(
      title: '重构聊天渲染',
      round: 1,
      status: PlanStatus.sentBack,
      path: '',
      feedback: '把状态卡并进消息',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PlanCard(item: sentBack)),
      ),
    );
    await tester.pump();
    expect(find.textContaining('sent back'), findsOneWidget);
    expect(find.textContaining('把状态卡并进消息'), findsOneWidget);
  });

  testWidgets('CommandStep heads with its description and shows the command', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CommandStep(
            command: 'flutter test',
            description: '跑一遍测试',
            output: 'All tests passed!',
            expanded: true,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Ran 跑一遍测试'), findsOneWidget);
    expect(find.text('\$ flutter test'), findsOneWidget);
    expect(find.text('All tests passed!'), findsOneWidget);
  });

  testWidgets('MessageView renders a tool item as a step row with a live '
      'thought open by default', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    state.history.apply(
      LinkSessionUpdate(
        session: 'session',
        start: 0,
        count: 1,
        items: [
          {'t': 'thinking', 'text': '正在想方案', 'tokens': 0},
        ],
      ),
      snapshot: true,
    );
    state.history.live = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageView(
            state: state,
            desktopId: 'desktop',
            item: state.history.items.first,
            index: 0,
            projectId: 'project',
          ),
        ),
      ),
    );
    await tester.pump();
    // Streaming: the thought is open without anyone opening it (its body
    // renders through the live selectable text).
    expect(find.byType(LiveSelectableText), findsOneWidget);
    // Closing it by hand keeps it closed.
    await tester.tap(find.text('Thinking'));
    await tester.pump();
    expect(find.byType(LiveSelectableText), findsNothing);
  });
}
