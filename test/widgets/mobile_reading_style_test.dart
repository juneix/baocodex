import 'package:baocode_mobile/chat/chat_models.dart';
import 'package:baocode_mobile/chat/message_view.dart';
import 'package:baocode_mobile/chat/widgets/thinking_section.dart';
import 'package:baocode_mobile/link/link_store.dart';
import 'package:baocode_mobile/state/app_state.dart';
import 'package:baocode_mobile/theme/app_theme.dart';
import 'package:baocode_mobile/ui/files/files_tab.dart';
import 'package:baocode_mobile/ui/files/line_diff.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String _zh(String zh, String en) => zh;

void main() {
  testWidgets('用户正文与展开思考正文都跟随阅读倍率', (tester) async {
    final state = AppState(demo: true, store: MemoryLinkStore());
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: MobileTheme.build(Brightness.light, messageScale: 1.6),
        home: Scaffold(
          body: ListView(
            children: [
              MessageView(
                state: state,
                desktopId: 'test',
                item: const UserMessageItem(text: '用户正文'),
              ),
              ThinkingSection(
                text: '思考正文',
                seconds: 1,
                expanded: true,
                onToggle: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    final user = tester.widget<SelectableText>(
      find.byWidgetPredicate(
        (widget) => widget is SelectableText && widget.data == '用户正文',
      ),
    );
    expect(user.style?.fontSize, closeTo(MobileType.body * 1.6, .001));
    final thought = tester.widget<Text>(find.text('思考正文'));
    expect(thought.style?.fontSize, closeTo(MobileType.secondary * 1.6, .001));
    expect(tester.takeException(), isNull);
  });
  testWidgets('Diff 在窄屏大代码字号下保留变化标记和正文', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: MobileTheme.build(
          Brightness.dark,
          codeFontSize: 24,
          messageScale: 1.6,
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: Scaffold(
          body: DiffView(before: 'old line', after: 'new line', tr: _zh),
        ),
      ),
    );
    expect(find.text('+'), findsOneWidget);
    expect(find.text('−'), findsOneWidget);
    expect(tester.widget<Text>(find.text('new line')).style?.fontSize, 24);
    expect(tester.widget<Text>(find.text('new line')).softWrap, isFalse);
    expect(tester.takeException(), isNull);
  });
  testWidgets('超长单行差异保持换行而不生成极宽布局', (tester) async {
    final long = 'x' * 2000;
    await tester.pumpWidget(
      MaterialApp(
        theme: MobileTheme.build(Brightness.light),
        home: Scaffold(
          body: DiffView(before: '', after: long, tr: _zh),
        ),
      ),
    );
    expect(tester.widget<Text>(find.text(long)).softWrap, isTrue);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SingleChildScrollView &&
            widget.scrollDirection == Axis.horizontal,
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('Diff 只有一列行号：删除行用原行号，其余用新行号', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: MobileTheme.build(Brightness.light),
        home: Scaffold(
          body: DiffView(before: 'a\nb\nc', after: 'a\nB\nc\nd', tr: _zh),
        ),
      ),
    );
    final numbers = [
      for (final widget in tester.widgetList<Text>(find.byType(Text)))
        if (RegExp(r'^\d*$').hasMatch(widget.data ?? 'x')) widget.data,
    ];
    // a、−b、+B、c、+d：每行一个行号。
    expect(numbers, ['1', '2', '2', '3', '4']);
    expect(tester.takeException(), isNull);
  });

  Future<void> pumpDiff(
    WidgetTester tester,
    String before,
    String after,
  ) async {
    tester.view.physicalSize = const Size(360, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: MobileTheme.build(Brightness.light),
        home: Scaffold(
          body: DiffView(before: before, after: after, tr: _zh),
        ),
      ),
    );
    await tester.pump();
  }

  String counter(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey('diff-change-count')))
      .data!;
  IconButton button(WidgetTester tester, String key) =>
      tester.widget<IconButton>(find.byKey(ValueKey(key)));

  // 第 100、200、300 行各改一处，彼此隔着好几屏。
  final base = [for (var i = 1; i <= 400; i++) 'line $i'];
  final edited = [
    for (final line in base)
      if (const {'line 100', 'line 200', 'line 300'}.contains(line))
        '$line changed'
      else
        line,
  ];

  testWidgets('打开差异时定位到第一处改动，上下按钮逐处跳转', (tester) async {
    await pumpDiff(tester, base.join('\n'), edited.join('\n'));
    expect(counter(tester), '1 / 3');
    expect(find.text('line 100 changed'), findsOneWidget);
    expect(button(tester, 'diff-previous-change').onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('diff-next-change')));
    await tester.pump();
    expect(counter(tester), '2 / 3');
    expect(find.text('line 200 changed'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('diff-next-change')));
    await tester.pump();
    expect(counter(tester), '3 / 3');
    expect(find.text('line 300 changed'), findsOneWidget);
    expect(button(tester, 'diff-next-change').onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('diff-previous-change')));
    await tester.pump();
    expect(counter(tester), '2 / 3');
    expect(find.text('line 200 changed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('手动滚动后序号跟随，上一处回到刚滑过的改动', (tester) async {
    await pumpDiff(tester, base.join('\n'), edited.join('\n'));
    final list = tester.widget<ListView>(find.byType(ListView));
    final scroll = list.controller!;
    final first = scroll.offset;

    scroll.jumpTo(first + 40);
    await tester.pump();
    expect(counter(tester), '1 / 3');
    expect(button(tester, 'diff-previous-change').onPressed, isNotNull);
    await tester.tap(find.byKey(const ValueKey('diff-previous-change')));
    await tester.pump();
    expect(scroll.offset, first);
    expect(counter(tester), '1 / 3');

    scroll.jumpTo(0);
    await tester.pump();
    expect(counter(tester), '– / 3');
    await tester.tap(find.byKey(const ValueKey('diff-next-change')));
    await tester.pump();
    expect(scroll.offset, first);
    expect(counter(tester), '1 / 3');
  });

  testWidgets('文件末尾落点重合的改动也能逐处走完', (tester) async {
    final before = [for (var i = 1; i <= 100; i++) 'line $i'];
    final after = [
      for (final line in before)
        if (const {'line 95', 'line 97', 'line 99'}.contains(line))
          '$line changed'
        else
          line,
    ];
    await pumpDiff(tester, before.join('\n'), after.join('\n'));
    expect(counter(tester), '1 / 3');
    await tester.tap(find.byKey(const ValueKey('diff-next-change')));
    await tester.pump();
    expect(counter(tester), '2 / 3');
    await tester.tap(find.byKey(const ValueKey('diff-next-change')));
    await tester.pump();
    expect(counter(tester), '3 / 3');
    expect(find.text('line 99 changed'), findsOneWidget);
  });

  testWidgets('超长行换行时也能跳到后面的改动', (tester) async {
    final long = 'x' * 2000;
    // 开头都是短行，列表按它们估算总高度，会比夹着超长行的真实高度短得多。
    final before = [
      for (var i = 1; i <= 30; i++) 'line $i',
      for (var i = 0; i < 20; i++) '$long$i',
      for (var i = 51; i <= 200; i++) 'line $i',
    ];
    final after = [...before]..[149] = 'line 150 changed';
    await pumpDiff(tester, before.join('\n'), after.join('\n'));
    expect(counter(tester), '1 / 1');
    expect(find.text('line 150 changed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('没有改动时不显示跳转按钮', (tester) async {
    await pumpDiff(tester, 'a\nb', 'a\nb');
    expect(find.byKey(const ValueKey('diff-change-count')), findsNothing);
  });

  test('相邻的删除和新增算同一处改动', () {
    final lines = lineDiff('a\nb\nc\nd', 'a\nB\nc\nD\ne');
    expect(changeStarts(lines), [1, 4]);
  });
}
