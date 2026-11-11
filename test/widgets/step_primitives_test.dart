// YCode — GPL-3.0-only.
// Tests for the batch-2 leaf components ported from the desktop chat.
import 'package:baocode_mobile/chat/widgets/fade_curve.dart';
import 'package:baocode_mobile/chat/widgets/flip_switcher.dart';
import 'package:baocode_mobile/chat/widgets/shell_highlight.dart';
import 'package:baocode_mobile/chat/widgets/shimmer_text.dart';
import 'package:baocode_mobile/chat/widgets/thinking_spark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('easedFade rises monotonically from 0 to 1', () {
    final samples = easedFade().toList();
    expect(samples.first, (0.0, 0.0));
    expect(samples.last, (1.0, 1.0));
    for (var i = 1; i < samples.length; i++) {
      expect(samples[i].$2, greaterThan(samples[i - 1].$2));
    }
  });

  test('highlightShell marks program, option and string runs', () {
    final spans = highlightShell('grep -i "中文 正则" pkg/file.dart && echo done');
    String textOf(int index) => spans[index].text!;
    expect(spans, hasLength(greaterThan(3)));
    expect(textOf(0), 'grep');
    expect(spans[0].style!.color, isNotNull);
    final joined = spans.map((span) => span.text).join();
    expect(joined, 'grep -i "中文 正则" pkg/file.dart && echo done');
    // The quoted string keeps its inner spaces as one run.
    expect(spans.any((span) => span.text == '"中文 正则"'), isTrue);
    // The lone `&` of `2>&1` survives as plain text.
    final redirect = highlightShell('cmd 2>&1');
    expect(redirect.map((span) => span.text).join(), 'cmd 2>&1');
  });

  testWidgets('ShimmerText shows the text with an ellipsis and renders still '
      'with animations off', (tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: MaterialApp(home: Scaffold(body: ShimmerText('生成中'))),
      ),
    );
    await tester.pump();
    expect(find.text('生成中…'), findsOneWidget);
  });

  testWidgets('ThinkingSpark draws a square CustomPaint', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: ThinkingSpark(size: 20))),
      ),
    );
    await tester.pump();
    expect(find.byType(CustomPaint), findsWidgets);
    expect(ThinkingSpark.shapeAt(Duration.zero), 0);
    // One shape per frame, up and back down: 6 shapes over a bounce of 10.
    expect(ThinkingSpark.shapeAt(ThinkingSpark.frameTime * 5), 5);
    expect(ThinkingSpark.shapeAt(ThinkingSpark.frameTime * 7), 3);
  });

  testWidgets('FlipSwitcher shows the first child and flips to a new key', (
    tester,
  ) async {
    Widget flipper(String value) => MaterialApp(
      home: Scaffold(
        body: FlipSwitcher(
          dwell: Duration.zero,
          child: Text(value, key: ValueKey(value)),
        ),
      ),
    );
    await tester.pumpWidget(flipper('第一页'));
    await tester.pump();
    expect(find.text('第一页'), findsOneWidget);
    await tester.pumpWidget(flipper('第二页'));
    await tester.pumpAndSettle();
    expect(find.text('第二页'), findsOneWidget);
    expect(find.text('第一页'), findsNothing);
  });
}
