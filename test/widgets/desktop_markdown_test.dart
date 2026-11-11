import 'package:baocode_mobile/chat/markdown/code_citation.dart';
import 'package:baocode_mobile/chat/markdown/markdown_math.dart';
import 'package:baocode_mobile/chat/markdown/markdown_tags.dart';
import 'package:baocode_mobile/chat/markdown/markdown_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;

Widget host(String text, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: const [Locale('zh')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(brightness: brightness),
      home: Scaffold(
        body: SingleChildScrollView(
          child: SelectionArea(child: MarkdownView(text)),
        ),
      ),
    );

Iterable<md.Element> elements(Iterable<md.Node> nodes) sync* {
  for (final node in nodes) {
    if (node is md.Element) {
      yield node;
      yield* elements(node.children ?? const []);
    }
  }
}

String visibleText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
    .join('\n');

void main() {
  test('中文强调与桌面语法相同，价格不被误解析为公式', () {
    final nodes = MarkdownView.document().parse(
      '**新版应遵循。**这条规则。价格为 \$5 和 \$10。',
    );
    expect(
      elements(nodes).where((node) => node.tag == 'strong').single.textContent,
      '新版应遵循。',
    );
    expect(elements(nodes).where((node) => node.tag == 'math'), isEmpty);
  });

  test('增长分段保留旧前缀，分段解析与整体解析结果一致', () {
    final first = List.generate(
      70,
      (index) => '## 第 $index 节\n\n${'中文段落。' * 15}\n\n',
    ).join();
    final before = markdownSegments(first);
    expect(before.length, greaterThan(1));
    final grown = markdownSegmentsGrown('$first## 新一节\n\n新增内容。', before);
    expect(grown.take(before.length - 1), before.take(before.length - 1));
    final whole = md.renderToHtml(
      MarkdownView.document(tags: true).parse(grown.join()),
    );
    final segmented = grown
        .map(
          (part) =>
              md.renderToHtml(MarkdownView.document(tags: true).parse(part)),
        )
        .join('\n');
    expect(segmented, whole);
  });

  test('流式围栏状态不会被代码中的普通反引号误判', () {
    expect(endsInOpenFence('```dart\nfinal text = "你好";'), isTrue);
    expect(endsInOpenFence('```dart\nfinal text = "你好";\n```'), isFalse);
    expect(endsInOpenFence('普通 `行内代码` 和中文。'), isFalse);
  });

  testWidgets('中文逐行正文保留换行而不是压成一段', (tester) async {
    await tester.pumpWidget(host('第一行：准备开始\n第二行：正在处理\n第三行：处理完成'));
    expect(visibleText(tester), contains('第一行：准备开始\n第二行：正在处理\n第三行：处理完成'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('同一消息逐步增长，已完成段落不丢失', (tester) async {
    await tester.pumpWidget(host('## 中文流式回复\n\n这是第一段。'));
    expect(visibleText(tester), contains('这是第一段。'));
    await tester.pumpWidget(host('## 中文流式回复\n\n这是第一段。\n\n这是第二段，正在追加。'));
    expect(visibleText(tester), contains('这是第一段。'));
    expect(visibleText(tester), contains('这是第二段，正在追加。'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('未闭合代码块使用桌面代码卡，闭合后正文继续正常解析', (tester) async {
    await tester.pumpWidget(host('说明文字。\n\n```dart\nvoid main() {}'));
    expect(
      tester.widget<MarkdownCodeBlock>(find.byType(MarkdownCodeBlock)).code,
      'void main() {}',
    );
    await tester.pumpWidget(
      host('说明文字。\n\n```dart\nvoid main() {}\n```\n\n后续中文说明。'),
    );
    expect(visibleText(tester), contains('后续中文说明。'));
    expect(find.byType(MarkdownCodeBlock), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('表格列表引用与数学沿用同一桌面 block 渲染', (tester) async {
    await tester.pumpWidget(
      host('''# 功能检查

- 第一项
- 第二项

| 功能 | 结果 |
| --- | --- |
| 流式 | 正常 |

> 这是引用。

\$\$x^2 + y^2\$\$
'''),
    );
    expect(find.byType(Table), findsOneWidget);
    expect(find.byType(MarkdownQuoteBlock), findsOneWidget);
    expect(find.byType(MathView), findsOneWidget);
    expect(visibleText(tester), contains('第一项'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('详情折叠解析与交互保留桌面行为', (tester) async {
    await tester.pumpWidget(
      host('<details>\n<summary>查看详情</summary>\n\n内部中文内容。\n</details>'),
    );
    expect(find.byType(TagSection), findsOneWidget);
    expect(visibleText(tester), isNot(contains('内部中文内容。')));
    await tester.tap(find.text('查看详情'));
    await tester.pump();
    expect(visibleText(tester), contains('内部中文内容。'));
  });
}
