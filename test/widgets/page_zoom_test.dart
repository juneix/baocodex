import 'package:baocode_mobile/theme/app_theme.dart';
import 'package:baocode_mobile/ui/files/file_source_view.dart';
import 'package:baocode_mobile/ui/files/files_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String _zh(String zh, String en) => zh;

const _page = Size(400, 600);

Future<void> _pump(WidgetTester tester, Widget body) async {
  tester.view.physicalSize = _page;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: MobileTheme.build(Brightness.light),
      home: Scaffold(body: body),
    ),
  );
  await tester.pump();
}

/// 两指从中点上下分开 [from]，再移动到 [to]。
Future<void> _pinch(WidgetTester tester, double from, double to) async {
  const center = Offset(200, 300);
  final top = await tester.startGesture(center - Offset(0, from), pointer: 1);
  final bottom = await tester.startGesture(
    center + Offset(0, from),
    pointer: 2,
  );
  await tester.pump();
  await top.moveTo(center - Offset(0, to));
  await bottom.moveTo(center + Offset(0, to));
  await tester.pump();
  await top.up();
  await bottom.up();
  await tester.pump();
}

double _layoutWidth(WidgetTester tester) =>
    tester.getSize(find.byKey(const ValueKey('page-zoom-content'))).width;

ScrollController _vertical(WidgetTester tester) =>
    tester.widget<ListView>(find.byType(ListView)).controller!;

void main() {
  final lines = [for (var i = 1; i <= 300; i++) 'line $i'];
  final before = lines.join('\n');
  final after = ([...lines]..[150] = 'line 151 changed').join('\n');

  testWidgets('双指缩小整页：字号不变，能看到更多行', (tester) async {
    await _pump(tester, DiffView(before: before, after: after, tr: _zh));
    final rowsBefore = find.textContaining('line ').evaluate().length;
    final fontSize = tester
        .widget<Text>(find.text('line 151 changed'))
        .style!
        .fontSize;

    await _pinch(tester, 100, 50);

    expect(_layoutWidth(tester), closeTo(_page.width * 2, .01));
    expect(
      tester.widget<Text>(find.text('line 151 changed')).style!.fontSize,
      fontSize,
    );
    expect(
      find.textContaining('line ').evaluate().length,
      greaterThan(rowsBefore),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('双指放大时两指中间的内容留在原处', (tester) async {
    await _pump(tester, DiffView(before: before, after: after, tr: _zh));
    final row = find.text('line 151 changed');
    final y = tester.getCenter(row).dy;
    const center = Offset(200, 300);
    // 中点选在这一行上，放大后它不该跑开。
    final focal = Offset(center.dx, y);
    final top = await tester.startGesture(
      focal - const Offset(0, 40),
      pointer: 1,
    );
    final bottom = await tester.startGesture(
      focal + const Offset(0, 40),
      pointer: 2,
    );
    await tester.pump();
    await top.moveTo(focal - const Offset(0, 80));
    await bottom.moveTo(focal + const Offset(0, 80));
    await tester.pump();
    await top.up();
    await bottom.up();
    await tester.pump();

    expect(_layoutWidth(tester), closeTo(_page.width / 2, .01));
    expect(tester.getCenter(row).dy, closeTo(y, 2));
  });

  testWidgets('捏到接近原大时吸附回 100%，倍率有上下限', (tester) async {
    await _pump(tester, DiffView(before: before, after: after, tr: _zh));
    await _pinch(tester, 100, 103);
    expect(_layoutWidth(tester), _page.width);

    await _pinch(tester, 100, 5);
    expect(_layoutWidth(tester), closeTo(_page.width * 2, .01));
    await _pinch(tester, 20, 200);
    await _pinch(tester, 20, 200);
    expect(_layoutWidth(tester), closeTo(_page.width / 3, .01));
  });

  testWidgets('缩放不影响单指滚动和上下切换', (tester) async {
    await _pump(tester, DiffView(before: before, after: after, tr: _zh));
    await _pinch(tester, 50, 100);
    final scroll = _vertical(tester);
    final offset = scroll.offset;
    await tester.drag(find.byType(ListView), const Offset(0, -60));
    await tester.pump();
    expect(scroll.offset, greaterThan(offset));

    await tester.tap(find.byKey(const ValueKey('diff-previous-change')));
    await tester.pump();
    expect(find.text('line 151 changed'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('diff-change-count'))).data,
      '1 / 1',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('在文件末尾缩小不会滚出内容范围', (tester) async {
    await _pump(tester, DiffView(before: before, after: after, tr: _zh));
    final scroll = _vertical(tester);
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump();
    await _pinch(tester, 100, 50);
    expect(scroll.offset, lessThanOrEqualTo(scroll.position.maxScrollExtent));
    expect(find.text('line 300'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('源码视图同样整页缩放', (tester) async {
    await _pump(tester, FileSourceView(text: before, path: 'a.txt'));
    await _pinch(tester, 100, 50);
    expect(_layoutWidth(tester), closeTo(_page.width * 2, .01));
    expect(tester.takeException(), isNull);
  });
}
