import 'package:baocode_mobile/chat/markdown/mermaid_code_block.dart';
import 'package:baocode_mobile/chat/markdown/code_citation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mermaid_flutter/mermaid_flutter.dart';

void main() {
  final diagrams = {
    'flowchart': 'flowchart LR\n A[Start] --> B[Finish]',
    'sequence': 'sequenceDiagram\n Alice->>Bob: Hello\n Bob-->>Alice: Hi',
    'class': 'classDiagram\n class Animal\n Animal : +eat()',
    'state': 'stateDiagram-v2\n [*] --> Ready\n Ready --> [*]',
    'entity relationship': 'erDiagram\n ACCOUNT ||--o{ ORDER : owns',
  };
  for (final entry in diagrams.entries) {
    testWidgets('${entry.key} renders offline and keeps a source alternative', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MermaidCodeBlock(code: entry.value),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (widget) => widget is CustomPaint && widget.painter is ScenePainter,
        ),
        findsOneWidget,
      );
      expect(find.byType(MarkdownCodeBlock), findsNothing);
      await tester.tap(find.byTooltip('Source'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<MarkdownCodeBlock>(find.byType(MarkdownCodeBlock)).code,
        entry.value,
      );
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('full view leaves the composer unfocused once closed', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              MermaidCodeBlock(code: diagrams['flowchart']!),
              TextField(focusNode: focus),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    focus.requestFocus();
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(
        find.byWidgetPredicate(
          (widget) => widget is CustomPaint && widget.painter is ScenePainter,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(find.text('Mermaid'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Mermaid'), findsNothing);
    expect(focus.hasFocus, isFalse);
  });
  testWidgets('incomplete diagrams retain source without a crashing painter', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: MermaidCodeBlock(code: 'unsupported-diagram')),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<MarkdownCodeBlock>(find.byType(MarkdownCodeBlock)).code,
      'unsupported-diagram',
    );
    expect(tester.takeException(), isNull);
  });
}
