import 'package:baocode_mobile/chat/chat_models.dart';
import 'package:baocode_mobile/chat/widgets/turn_footer.dart';
import 'package:baocode_mobile/ui/tasks/chat_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/chat_test_state.dart';

class _State extends ChatTestState {
  _State() : super(zh: true);
}

const _tool = ToolCallItem(
  kind: ToolKind.read,
  target: '文件',
  status: ToolStatus.succeeded,
);

List<Object?> _turn({TurnUsage? usage}) => [
  UserMessageItem(
    text: '问题',
    worked: usage == null ? null : const Duration(seconds: 9),
    usage: usage,
  ),
  const AssistantTextItem('第一段'),
  _tool,
  const AssistantTextItem('第二段'),
  _tool,
  const AssistantTextItem('最终段'),
];

Future<void> _pump(WidgetTester tester, _State state) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ChatPage(
        state: state,
        desktopId: 'desktop',
        sessionId: 'session',
        title: '对话',
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('运行中不出现复制；结束后只有最后一段下有一个', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    state.history.items.addAll(_turn(usage: const TurnUsage(outputTokens: 5)));
    state.history.live = true;
    await _pump(tester, state);
    expect(find.byTooltip('复制回答'), findsNothing);

    state.history.live = false;
    state.update();
    await tester.pumpAndSettle();
    expect(find.byTooltip('复制回答'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byTooltip('复制回答')).dy,
      greaterThan(tester.getTopLeft(find.text('最终段')).dy),
    );
  });

  testWidgets('没有统计的老历史回合：最后一段有一个，中间段没有', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    state.history.items.addAll([
      const AssistantTextItem('老一'),
      _tool,
      const AssistantTextItem('老二'),
      const UserMessageItem(text: '新问题'),
      ..._turn().skip(1),
    ]);
    await _pump(tester, state);
    // One per finished turn: the old one's last, and the second turn's last.
    expect(find.byTooltip('复制回答'), findsNWidgets(2));
  });

  testWidgets('末尾是工具时，唯一的尾巴在工具行下面，复制内容是最后一段文字', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    state.history.items.addAll([
      const UserMessageItem(text: '问题', worked: Duration(seconds: 4)),
      const AssistantTextItem('先说'),
      _tool,
      const AssistantTextItem('最后的话'),
      const ToolCallItem(
        kind: ToolKind.read,
        target: '尾部工具文件',
        status: ToolStatus.succeeded,
      ),
    ]);
    await _pump(tester, state);
    expect(find.byTooltip('复制回答'), findsOneWidget);
    final footer = tester.widget<TurnFooter>(find.byType(TurnFooter));
    expect(footer.answer, '最后的话');
    expect(footer.worked, const Duration(seconds: 4));
  });
}
