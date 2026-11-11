import 'package:baocode_mobile/chat/markdown/code_citation.dart';
import 'package:baocode_mobile/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;

Widget host(Widget child) => MaterialApp(
  theme: ThemeData(
    platform: TargetPlatform.android,
    extensions: const [CodeTypography(15)],
  ),
  home: Scaffold(
    body: SingleChildScrollView(child: SelectionArea(child: child)),
  ),
);

String renderedCode(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .where((widget) => widget.textSpan != null)
    .map((widget) => widget.textSpan!.toPlainText())
    .join('\n');

void main() {
  test('citation parser and containment follow the remote path style', () {
    final citation = CodeCitation.parse('12:15:lib/sample.dart')!;
    expect(citation.start, 12);
    expect(citation.end, 15);
    expect(citation.fileName, 'sample.dart');
    expect(citation.pathIn('/workspace'), '/workspace/lib/sample.dart');
    expect(
      citation.pathIn(r'E:\project\workspace'),
      r'E:\project\workspace\lib\sample.dart',
    );
    expect(
      const CodeCitation(1, 1, '../outside.dart').pathIn('/workspace'),
      isNull,
    );
    expect(
      const CodeCitation(
        1,
        1,
        r'..\outside.dart',
      ).pathIn(r'E:\project\workspace'),
      isNull,
    );
    expect(
      const CodeCitation(
        1,
        1,
        r'C:\outside.dart',
      ).pathIn(r'E:\project\workspace'),
      isNull,
    );
    expect(CodeCitation.parse('dart'), isNull);
    expect(CodeCitation.parse('0:5:file.dart'), isNull);
  });

  test('citation fences retain a bare fence within the cited lines', () {
    final document = md.Document(
      blockSyntaxes: [const CodeCitationFenceSyntax()],
    );
    final nodes = document.parseLines([
      '```1:3:sample.md',
      'first',
      '```',
      'third',
      '```',
      '',
      'outside',
    ]);
    final code = (nodes.first as md.Element).children!.single as md.Element;
    expect(code.textContent, 'first\n```\nthird\n');
    expect(nodes.last.textContent, 'outside');
  });

  testWidgets(
    'mobile code copy remains visible and copies the complete block',
    (tester) async {
      final code = List.generate(330, (index) => '第 $index 行').join('\n');
      String? copied;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await tester.pumpWidget(host(MarkdownCodeBlock(code: code)));
      expect(renderedCode(tester), code);
      await tester.tap(find.byType(CodeBlockIconButton));
      await tester.pump();
      expect(copied, code);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('language card folds and restores the original code', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const MarkdownCodeBlock(code: 'final answer = 42;', language: 'dart'),
      ),
    );
    expect(renderedCode(tester), 'final answer = 42;');
    await tester.tap(find.text('dart'));
    await tester.pump();
    expect(renderedCode(tester), isEmpty);
    await tester.tap(find.text('dart'));
    await tester.pump();
    expect(renderedCode(tester), 'final answer = 42;');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'citation title opens only through the injected remote callback',
    (tester) async {
      (String, int, int)? opened;
      await tester.pumpWidget(
        host(
          CodeCitationScope(
            root: r'E:\project\workspace',
            onOpen: (path, start, end) => opened = (path, start, end),
            child: const CodeCitationCard(
              citation: CodeCitation(12, 13, 'lib/sample.dart'),
              code: 'first\nsecond',
            ),
          ),
        ),
      );
      await tester.tap(find.text('sample.dart'));
      await tester.pump();
      expect(opened, (r'E:\project\workspace\lib\sample.dart', 12, 13));
      expect(find.text('12\n13'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('out-of-root citations cannot invoke the open callback', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      host(
        CodeCitationScope(
          root: '/workspace',
          onOpen: (_, _, _) => opened = true,
          child: const CodeCitationCard(
            citation: CodeCitation(1, 1, '../outside.dart'),
            code: 'outside',
          ),
        ),
      ),
    );
    await tester.tap(find.text('outside.dart'));
    await tester.pump();
    expect(opened, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'block colorizer is injectable while the desktop layout stays intact',
    (tester) async {
      final calls = <(String, String)>[];
      await tester.pumpWidget(
        host(
          CodeCitationScope(
            colorizeBlock: (language, code) async {
              calls.add((language, code));
              return [
                [
                  TextSpan(
                    text: code,
                    style: const TextStyle(color: Colors.blue),
                  ),
                ],
              ];
            },
            child: const MarkdownCodeBlock(
              code: 'final answer = 42;',
              language: 'dart',
            ),
          ),
        ),
      );
      await tester.pump();
      expect(calls, [('dart', 'final answer = 42;')]);
      expect(renderedCode(tester), 'final answer = 42;');
      expect(tester.takeException(), isNull);
    },
  );
}
