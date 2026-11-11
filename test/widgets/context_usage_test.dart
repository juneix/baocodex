// YCode — GPL-3.0-only.
import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/ui/tasks/context_usage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/chat_page_harness.dart';

void main() {
  testWidgets('电脑告诉上下文占用后输入栏才有圆环，点开按电脑端的顺序列各部分', (tester) async {
    final state = ChineseChatPageState();
    addTearDown(state.dispose);
    await tester.pumpWidget(chatHost(state));
    await tester.pump();
    expect(find.byType(ContextRing), findsNothing);
    state.tail(
      const LinkSessionUpdate(
        session: 'session',
        start: 0,
        count: 0,
        items: [],
        context: {
          'window': 200000,
          'used': 38600,
          'parts': [
            {'part': 'messages', 'tokens': 18000},
            {'part': 'system', 'tokens': 3200},
            {'part': 'tools', 'tokens': 14800},
            {'part': 'Custom thing', 'tokens': 2600},
          ],
          'compactAt': 167000,
        },
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('上下文已用 19%'));
    await tester.pumpAndSettle();
    expect(find.text('39k / 200k token · 19%'), findsOneWidget);
    expect(find.text('距自动压缩 128k'), findsOneWidget);
    final rows = ['系统提示词', '工具定义', '对话消息', 'Custom thing', '剩余'];
    final tops = [for (final row in rows) tester.getTopLeft(find.text(row)).dy];
    expect(tops, [...tops]..sort(), reason: '已知部分按电脑端的顺序，不认识的在后');
    // 分段条的色块没有内容，要撑满高度才画得出来。
    final segments = find.descendant(
      of: find.byType(ContextUsageView),
      matching: find.byType(ColoredBox),
    );
    for (final segment in segments.evaluate()) {
      expect(segment.size!.height, greaterThan(0));
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
