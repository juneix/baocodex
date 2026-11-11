import 'package:baocode_mobile/chat/markdown/code_citation.dart';
import 'package:baocode_mobile/chat/markdown/mermaid_code_block.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mermaid_flutter/mermaid_flutter.dart';

Widget host(Widget child) => MaterialApp(
  locale: const Locale('zh'),
  supportedLocales: const [Locale('zh')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  theme: ThemeData(platform: TargetPlatform.android),
  home: Scaffold(
    body: SingleChildScrollView(child: SelectionArea(child: child)),
  ),
);

Finder get scene => find.byWidgetPredicate(
  (widget) => widget is CustomPaint && widget.painter is ScenePainter,
);

void main() {
  testWidgets('未闭合流式图表先显示生成状态，不解析半写入内容', (tester) async {
    await tester.pumpWidget(
      host(
        const MermaidCodeBlock(code: 'flowchart LR\n A[尚未结束', writing: true),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('图表生成中…'), findsOneWidget);
    expect(scene, findsNothing);
    expect(find.byType(MarkdownCodeBlock), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('流式围栏闭合后立即显示完整离线图形', (tester) async {
    const code = 'flowchart LR\n A[开始] --> B[完成]';
    await tester.pumpWidget(
      host(const MermaidCodeBlock(code: code, writing: true)),
    );
    expect(scene, findsNothing);
    await tester.pumpWidget(host(const MermaidCodeBlock(code: code)));
    await tester.pumpAndSettle();
    expect(scene, findsOneWidget);
    expect(find.text('图表生成中…'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('长时间不再增长的未闭合围栏恢复源码而非永久等待', (tester) async {
    const code = 'unsupported-diagram';
    await tester.pumpWidget(
      host(const MermaidCodeBlock(code: code, writing: true)),
    );
    await tester.pump(
      MermaidCodeBlock.quietFor + const Duration(milliseconds: 1),
    );
    await tester.pumpAndSettle();
    expect(find.text('图表生成中…'), findsNothing);
    final fallback = tester.widget<MarkdownCodeBlock>(
      find.byType(MarkdownCodeBlock),
    );
    expect(fallback.code, code);
    expect(scene, findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('图形提供触屏源码切换及源码复制', (tester) async {
    const code = 'sequenceDiagram\n Alice->>Bob: 你好';
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(host(const MermaidCodeBlock(code: code)));
    await tester.pumpAndSettle();
    expect(scene, findsOneWidget);
    expect(find.byTooltip('源代码'), findsOneWidget);
    await tester.tap(find.byTooltip('复制'));
    await tester.pump();
    expect(copied, code);
    await tester.tap(find.byTooltip('源代码'));
    await tester.pumpAndSettle();
    expect(scene, findsNothing);
    final fallback = tester.widget<MarkdownCodeBlock>(
      find.byType(MarkdownCodeBlock),
    );
    expect(fallback.code, code);
    expect(fallback.onPreview, isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('无效或超限图表使用完整源码卡，保留安全上限', (tester) async {
    for (final code in [
      'unsupported-diagram',
      'flowchart LR\n${List.generate(101, (i) => 'N$i[节点$i]').join('\n')}',
      'flowchart LR\n${'x' * 16001}',
    ]) {
      await tester.pumpWidget(host(MermaidCodeBlock(code: code)));
      await tester.pumpAndSettle();
      final fallback = tester.widget<MarkdownCodeBlock>(
        find.byType(MarkdownCodeBlock),
      );
      expect(fallback.code, code);
      expect(scene, findsNothing);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('桌面流向、ELK 与边标签兼容算法保留', () {
    expect(mermaidAcross('flowchart TD\n A --> B'), 'flowchart LR\n A --> B');
    expect(mermaidAcross('sequenceDiagram\n A->>B: 你好'), isNull);
    expect(mermaidSquare('flowchart LR\n A --> B'), startsWith('%%{init:'));
    expect(
      mermaidLinksSpaced('flowchart LR\n A--同意-->B'),
      'flowchart LR\n A-- 同意 -->B',
    );
  });
}
