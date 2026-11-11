import 'package:baocode_mobile/theme/app_theme.dart';
import 'package:baocode_mobile/theme/code_highlight.dart';
import 'package:baocode_mobile/ui/files/file_source_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) => MaterialApp(
  theme: MobileTheme.build(Brightness.light),
  home: Scaffold(body: child),
);

Finder _line(int number) => find.byKey(ValueKey('file-source-line-$number'));
Finder _text(int number) => find.byKey(ValueKey('file-source-text-$number'));

void main() {
  for (final search in [false, true]) {
    testWidgets('${search ? '搜索' : '跳行'}后手动滚走，字号和换行变化保留当前阅读行', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final text = List.generate(
        650,
        (i) => 'row ${i + 1}: ${'source ' * 10}',
      ).join('\n');
      Widget view(double size, bool wrap) => _app(
        FileSourceView(
          text: text,
          path: 'reading.txt',
          fontSize: size,
          wrap: wrap,
          targetLine: search ? null : 100,
          query: search ? 'row 100:' : '',
          activeMatchOffset: search ? text.indexOf('row 100:') : null,
        ),
      );
      await tester.pumpWidget(view(14, false));
      await tester.pumpAndSettle();
      final height = tester.getSize(_line(100)).height;
      final vertical = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      vertical.position.jumpTo(12 + 499 * height);
      await tester.pumpAndSettle();
      expect(_line(500), findsOneWidget);
      await tester.pumpWidget(view(20, false));
      await tester.pumpAndSettle();
      expect(_line(100), findsNothing);
      expect(
        tester
            .getRect(_line(500))
            .overlaps(tester.getRect(find.byType(FileSourceView))),
        isTrue,
      );
      await tester.pumpWidget(view(20, true));
      await tester.pumpAndSettle();
      expect(_line(100), findsNothing);
      expect(
        tester
            .getRect(_line(500))
            .overlaps(tester.getRect(find.byType(FileSourceView))),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('横向滚动后字号变化不把阅读位置重置到行首', (tester) async {
    final text = List.generate(
      650,
      (i) => 'row ${i + 1}: ${'source ' * 30}',
    ).join('\n');
    Widget view(double size) =>
        _app(FileSourceView(text: text, path: 'wide.txt', fontSize: size));
    await tester.pumpWidget(view(14));
    await tester.pumpAndSettle();
    final horizontal = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(SingleChildScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    horizontal.position.jumpTo(600);
    await tester.pumpAndSettle();
    await tester.pumpWidget(view(20));
    await tester.pumpAndSettle();
    expect(horizontal.position.pixels, greaterThan(400));
    expect(tester.takeException(), isNull);
  });

  for (final source in [
    'alpha\nbeta',
    'alpha\n\nbeta',
    'alpha\nbeta\n',
    'alpha\r\n\r\nbeta\r\n',
  ]) {
    testWidgets(
      '选择并复制跨行源码保留换行且不包含行号：${source.replaceAll('\r', r'\r').replaceAll('\n', r'\n')}',
      (tester) async {
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
        await tester.pumpWidget(
          _app(FileSourceView(text: source, path: 'plain.txt')),
        );
        await tester.pumpAndSettle();
        final context = tester.element(_text(1));
        Actions.invoke(
          context,
          const SelectAllTextIntent(SelectionChangedCause.keyboard),
        );
        await tester.pump();
        Actions.invoke(context, CopySelectionTextIntent.copy);
        await tester.pump();
        expect(copied, source);
      },
    );
  }

  testWidgets('跳到尚未构建的远处行，长文件末尾完整而且仍然虚拟化', (tester) async {
    final text = List.generate(1200, (i) => 'row ${i + 1}: 完整内容').join('\n');
    await tester.pumpWidget(
      _app(FileSourceView(text: text, path: 'large.dart', targetLine: 1198)),
    );
    await tester.pumpAndSettle();
    expect(_line(1198), findsOneWidget);
    expect(find.textContaining('row 1198: 完整内容'), findsOneWidget);
    expect(
      tester
          .getRect(_line(1198))
          .overlaps(tester.getRect(find.byType(FileSourceView))),
      isTrue,
    );
    expect(find.byType(Text).evaluate().length, lessThan(120));
    await tester.drag(find.byType(FileSourceView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.textContaining('row 1200: 完整内容'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('换行后的目标行定位准确，增大字号后仍保留在视窗内', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final text = List.generate(
      90,
      (i) =>
          i == 74 ? '目标行 75' : '第${i + 1}行：这是很长的中文源码内容，'.padRight(160, '换行内容'),
    ).join('\n');
    Widget view(double size) => _app(
      FileSourceView(
        text: text,
        path: 'wrapped.txt',
        wrap: true,
        fontSize: size,
        targetLine: 75,
      ),
    );
    await tester.pumpWidget(view(14));
    await tester.pumpAndSettle();
    expect(_line(75), findsOneWidget);
    expect(
      tester
          .getRect(_line(75))
          .overlaps(tester.getRect(find.byType(FileSourceView))),
      isTrue,
    );
    await tester.pumpWidget(view(22));
    await tester.pumpAndSettle();
    expect(_line(75), findsOneWidget);
    expect(
      tester
          .getRect(_line(75))
          .overlaps(tester.getRect(find.byType(FileSourceView))),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('短源码继续使用现成 Monaco 高亮，不降级为词法颜色', (tester) async {
    const source = 'const answer = 42;';
    final colored = await tester.runAsync(
      () => colorizeCode('dart', source, dark: false),
    );
    expect(colored, isNotNull);
    await tester.pumpWidget(
      _app(const FileSourceView(text: source, path: 'main.dart')),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    final span = tester.widget<Text>(_text(1)).textSpan! as TextSpan;
    expect(
      (span.children!.first as TextSpan).style!.color,
      colored!.first.first.style!.color,
    );
    expect(span.toPlainText(), source);
  });

  testWidgets('搜索大小写不敏感，跨语法片段的命中也全部高亮', (tester) async {
    await tester.pumpWidget(
      _app(
        const FileSourceView(
          text: 'return "value";\nRETURN "VALUE";',
          path: 'main.dart',
          query: 'URN "va',
          activeMatchOffset: 3,
        ),
      ),
    );
    await tester.pumpAndSettle();
    String highlighted(InlineSpan span, [bool marked = false]) {
      if (span is! TextSpan) return '';
      final active = marked || span.style?.backgroundColor != null;
      return '${active ? span.text ?? '' : ''}'
          '${span.children?.map((child) => highlighted(child, active)).join() ?? ''}';
    }

    expect(highlighted(tester.widget<Text>(_text(1)).textSpan!), 'urn "va');
    expect(highlighted(tester.widget<Text>(_text(2)).textSpan!), 'URN "VA');
    expect(tester.takeException(), isNull);
  });

  testWidgets('CRLF 搜索偏移仍按原始文本定位并高亮正确行', (tester) async {
    final text = List.generate(
      100,
      (i) => i == 74 ? 'needle' : 'row ${i + 1}',
    ).join('\r\n');
    await tester.pumpWidget(
      _app(
        FileSourceView(
          text: text,
          path: 'windows.txt',
          query: 'needle',
          activeMatchOffset: text.indexOf('needle'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(_line(75), findsOneWidget);
    expect(
      tester.widget<Text>(_text(75)).textSpan!.toPlainText(),
      'needle\r\n',
    );
    final span = tester.widget<Text>(_text(75)).textSpan! as TextSpan;
    expect(
      (span.children!.first as TextSpan).style!.backgroundColor,
      isNotNull,
    );
    expect(
      tester
          .getRect(_line(75))
          .overlaps(tester.getRect(find.byType(FileSourceView))),
      isTrue,
    );
  });

  testWidgets('源码暂时切换到预览再回来恢复滚动位置', (tester) async {
    final text = List.generate(650, (i) => 'row ${i + 1}').join('\n');
    Widget view() => _app(FileSourceView(text: text, path: 'keep.txt'));
    await tester.pumpWidget(view());
    await tester.pumpAndSettle();
    ScrollableState vertical() => tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    vertical().position.jumpTo(6000);
    await tester.pumpAndSettle();
    final offset = vertical().position.pixels;
    await tester.pumpWidget(_app(const Center(child: Text('预览'))));
    await tester.pumpAndSettle();
    await tester.pumpWidget(view());
    await tester.pumpAndSettle();
    expect(vertical().position.pixels, closeTo(offset, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('换行后行号和行正文的高度一致，不覆盖下一行', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _app(
        FileSourceView(
          text: '${'中文长内容' * 20}\n第二行',
          path: 'wrapped.txt',
          wrap: true,
          fontSize: 18,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(_line(1)).height,
      closeTo(tester.getSize(_text(1)).height, .01),
    );
    expect(
      tester.getTopLeft(_line(2)).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(_line(1)).dy),
    );
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('重复跳到同一行可以由修订号再次定位', (tester) async {
    final text = List.generate(650, (i) => 'row ${i + 1}').join('\n');
    Widget view(int revision) => _app(
      FileSourceView(
        text: text,
        path: 'rows.txt',
        targetLine: 600,
        navigationRevision: revision,
      ),
    );
    await tester.pumpWidget(view(0));
    await tester.pumpAndSettle();
    final vertical = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    vertical.position.jumpTo(0);
    await tester.pumpAndSettle();
    expect(_line(600), findsNothing);
    await tester.pumpWidget(view(1));
    await tester.pumpAndSettle();
    expect(_line(600), findsOneWidget);
    expect(
      tester
          .getRect(_line(600))
          .overlaps(tester.getRect(find.byType(FileSourceView))),
      isTrue,
    );
  });

  testWidgets('换行开关保留真实行号，超长单行不会生成极宽布局', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final text = '${'中文长行' * 800}\n最后一行';
    await tester.pumpWidget(
      _app(
        FileSourceView(
          text: text,
          path: 'minified.json',
          fontSize: 22,
          targetLine: 2,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(_line(2), findsOneWidget);
    expect(find.text('最后一行'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('定位长行的搜索命中时也横向滚到命中区域', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final text = '${'x' * 180} TARGET';
    await tester.pumpWidget(
      _app(
        FileSourceView(
          text: text,
          path: 'wide.txt',
          query: 'target',
          activeMatchOffset: 181,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final horizontal = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(SingleChildScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(horizontal.position.pixels, greaterThan(500));
    expect(tester.takeException(), isNull);
  });
}
