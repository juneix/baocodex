import 'package:baocode_mobile/chat/ansi_text.dart';
import 'package:baocode_mobile/theme/code_highlight.dart';
import 'package:flutter/material.dart';
import 'package:baocode_mobile/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget child, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

List<TextSpan> leaves(InlineSpan root) {
  final result = <TextSpan>[];
  void visit(InlineSpan span) {
    if (span is TextSpan) {
      if (span.text != null) result.add(span);
      for (final child in span.children ?? <InlineSpan>[]) {
        visit(child);
      }
    }
  }

  visit(root);
  return result;
}

void main() {
  // 这些文字跟着界面语言走；测试里按中文看。
  setUp(() => AppState.debugLanguage = 'zh');
  tearDown(() => AppState.debugLanguage = null);

  testWidgets('code uses language highlighting and preserves copyable text', (
    tester,
  ) async {
    const source = 'const answer = 42;\n// comment';
    await tester.pumpWidget(
      host(
        const HighlightedCode(
          code: source,
          language: 'dart',
          lineNumbers: true,
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pumpAndSettle();
    final text = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(text.textSpan!.toPlainText(), source);
    expect(leaves(text.textSpan!).any((s) => s.style?.color != null), isTrue);
    expect(find.text('1\n2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('short Windows text is normalized without a truncation warning', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const HighlightedCode(
          code: '这是测试文档txt\r\n',
          language: 'txt',
          lineNumbers: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final text = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(text.textSpan!.toPlainText(), '这是测试文档txt\n');
    expect(find.textContaining('预览已截断'), findsNothing);
  });

  testWidgets('empty, wrapped and dark code fit an outer scroll view', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const Column(
          children: [
            HighlightedCode(code: '', wrap: true),
            HighlightedCode(
              code: 'return true;',
              language: 'js',
              wrap: true,
              lineNumbers: true,
            ),
          ],
        ),
        brightness: Brightness.dark,
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('unsupported language falls back visibly and code is bounded', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        HighlightedCode(
          code: List.filled(1000, 'hello').join('\n'),
          language: 'not-a-language',
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pumpAndSettle();
    expect(find.text('基础词法高亮'), findsOneWidget);
    final text = tester
        .widget<SelectableText>(find.byType(SelectableText))
        .textSpan!
        .toPlainText();
    expect(text.split('\n').length, lessThanOrEqualTo(300));
    expect(find.textContaining('预览已截断'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ANSI SGR colors bold reset and newlines survive selection', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const AnsiText(text: '\x1b[31;1mred\x1b[0m\nnormal')),
    );
    final span = tester
        .widget<SelectableText>(find.byType(SelectableText))
        .textSpan!;
    expect(span.toPlainText(), 'red\nnormal');
    final parts = leaves(span);
    expect(parts.first.style!.fontWeight, FontWeight.bold);
    expect(parts.first.style!.color, isNotNull);
    expect(parts.last.style!.color, isNull);
    expect(parts.last.style!.fontWeight, FontWeight.normal);
  });

  testWidgets('OSC links clipboard DCS and unknown controls are inert', (
    tester,
  ) async {
    const source =
        '\x1b]8;;https://example.com\x1b\\label\x1b]8;;\x07'
        '\x1b]52;c;SECRET\x07\x1bPpayload\x1b\\\x1b[2J\x1b(B\x00\x7f\nend';
    await tester.pumpWidget(host(const AnsiText(text: source)));
    final span = tester
        .widget<SelectableText>(find.byType(SelectableText))
        .textSpan!;
    expect(span.toPlainText(), 'label\nend');
    expect(leaves(span).every((s) => s.recognizer == null), isTrue);
  });

  testWidgets('ANSI extended colors and nonselectable output', (tester) async {
    await tester.pumpWidget(
      host(
        const AnsiText(
          selectable: false,
          text: '\x1b[38;2;1;2;3mRGB\x1b[48;5;196mBG\x1b[49;39mplain',
        ),
      ),
    );
    final rich = tester
        .widgetList<Text>(find.byType(Text))
        .singleWhere((t) => t.textSpan != null);
    final parts = leaves(rich.textSpan!);
    expect(parts.first.style!.color, const Color(0xff010203));
    expect(parts[1].style!.backgroundColor, const Color(0xffff0000));
    expect(parts.last.style!.backgroundColor, isNull);
    expect(find.byType(SelectableText), findsNothing);
  });

  testWidgets('long ANSI output and incomplete controls stay bounded', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(AnsiText(text: '${'x' * 40000}\x1b]unfinished')),
    );
    final span = tester
        .widget<SelectableText>(find.byType(SelectableText))
        .textSpan!;
    expect(span.toPlainText().length, lessThan(33000));
    expect(span.toPlainText(), contains('[输出已截断]'));
    await tester.pumpWidget(host(const AnsiText(text: 'safe\x1b]unfinished')));
    expect(
      tester
          .widget<SelectableText>(find.byType(SelectableText))
          .textSpan!
          .toPlainText(),
      'safe',
    );
    expect(tester.takeException(), isNull);
  });
}
