import 'package:baocode_mobile/ui/tasks/chat_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/chat_test_state.dart';

typedef _State = ChatTestState;

Future<_State> _open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final state = _State();
  addTearDown(state.dispose);
  state.history.items.addAll([
    for (var i = 0; i < 40; i++) {'t': 'text', 'text': '历史消息 $i\n第二行\n第三行'},
  ]);
  await tester.pumpWidget(
    MaterialApp(
      home: ChatPage(
        state: state,
        desktopId: 'desktop',
        sessionId: 'session',
        title: '键盘测试',
      ),
    ),
  );
  await tester.pumpAndSettle();
  return state;
}

Future<void> _keyboard(WidgetTester tester, double height) async {
  tester.view.viewInsets = FakeViewPadding(bottom: height * 3);
  await tester.pumpAndSettle();
}

double _composerTop(WidgetTester tester) =>
    tester.getTopLeft(find.byKey(const ValueKey('composer-input-surface'))).dy;

void main() {
  testWidgets('在底部时弹出键盘，最后一条消息仍紧贴输入框上方', (tester) async {
    await _open(tester);
    final list = tester
        .widget<CustomScrollView>(find.byType(CustomScrollView))
        .controller!;
    expect(list.offset, list.position.maxScrollExtent);

    await _keyboard(tester, 300);
    expect(list.offset, closeTo(list.position.maxScrollExtent, 1));
    expect(find.textContaining('历史消息 39').hitTestable(), findsOneWidget);

    await _keyboard(tester, 0);
    expect(list.offset, closeTo(list.position.maxScrollExtent, 1));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('停在中间时弹出键盘，输入框上方原来那几行原地不动', (tester) async {
    await _open(tester);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 900));
    await tester.pumpAndSettle();
    final list = tester
        .widget<CustomScrollView>(find.byType(CustomScrollView))
        .controller!;
    expect(list.offset, lessThan(list.position.maxScrollExtent - 200));

    // 紧贴输入框上方、完整可见的那一条
    String? anchor;
    var gap = 0.0;
    final top = _composerTop(tester);
    for (var i = 39; i >= 0; i--) {
      final row = find.textContaining('历史消息 $i\n');
      if (row.evaluate().isEmpty) continue;
      final bottom = tester.getBottomLeft(row).dy;
      if (bottom <= top) {
        anchor = '历史消息 $i\n';
        gap = top - bottom;
        break;
      }
    }
    expect(anchor, isNotNull);

    await _keyboard(tester, 300);
    final row = find.textContaining(anchor!);
    expect(row.hitTestable(), findsOneWidget);
    expect(
      _composerTop(tester) - tester.getBottomLeft(row).dy,
      closeTo(gap, 1),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
