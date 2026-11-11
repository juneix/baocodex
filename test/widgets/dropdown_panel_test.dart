import 'package:baocode_mobile/theme/app_theme.dart';
import 'package:baocode_mobile/ui/widgets/dropdown_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Finder get _panel => find.byKey(const ValueKey('dropdown-panel'));

Future<void> _open(
  WidgetTester tester, {
  required Alignment at,
  double itemHeight = 40,
  int items = 3,
  double width = 200,
  DropdownAlign align = DropdownAlign.end,
}) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: MobileTheme.build(Brightness.light),
      home: Scaffold(
        body: Align(
          alignment: at,
          child: Builder(
            builder: (anchor) => TextButton(
              onPressed: () => showDropdownPanel<void>(
                anchor,
                width: width,
                align: align,
                builder: (_) => SingleChildScrollView(
                  child: Column(
                    children: [
                      for (var i = 0; i < items; i++)
                        SizedBox(height: itemHeight, child: Text('行$i')),
                    ],
                  ),
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
}

Rect _button(WidgetTester tester) => tester.getRect(find.byType(TextButton));

void main() {
  testWidgets('下方放得下就贴在按钮下面，点外面关闭', (tester) async {
    await _open(tester, at: Alignment.topRight);
    final panel = tester.getRect(_panel);
    expect(panel.top, greaterThan(_button(tester).bottom));
    expect(panel.top - _button(tester).bottom, lessThan(8));
    expect(panel.right, 392);
    await tester.tapAt(const Offset(2, 700));
    await tester.pumpAndSettle();
    expect(_panel, findsNothing);
  });

  testWidgets('按钮靠底部时翻到上方，不从屏幕底部升起', (tester) async {
    await _open(tester, at: Alignment.bottomLeft, align: DropdownAlign.start);
    final panel = tester.getRect(_panel);
    expect(panel.bottom, lessThan(_button(tester).top));
    expect(_button(tester).top - panel.bottom, lessThan(8));
    expect(panel.left, greaterThanOrEqualTo(8));
  });

  testWidgets('内容太长时放到空间大的一边并可滚动，不溢出屏幕', (tester) async {
    await _open(tester, at: const Alignment(0, .5), items: 60);
    final panel = tester.getRect(_panel);
    expect(panel.bottom, lessThan(_button(tester).top));
    expect(panel.top, greaterThanOrEqualTo(8));
    expect(tester.takeException(), isNull);
    await tester.drag(_panel, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('行0')).dy, lessThan(panel.top));
  });

  testWidgets('宽度超过屏幕时收在屏幕内', (tester) async {
    await _open(
      tester,
      at: Alignment.center,
      width: 640,
      align: DropdownAlign.center,
    );
    final panel = tester.getRect(_panel);
    expect(panel.left, 8);
    expect(panel.right, 392);
  });

  testWidgets('菜单返回所选的值，选中项打勾，禁用项点了不关', (tester) async {
    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (anchor) => TextButton(
              onPressed: () async =>
                  picked = await showMenuPanel<String>(anchor, [
                    const MenuPanelItem('a', '甲', selected: true),
                    const MenuPanelItem('b', '乙', enabled: false),
                    const MenuPanelItem('c', '丙'),
                  ]),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('乙'));
    await tester.pumpAndSettle();
    expect(_panel, findsOneWidget);
    await tester.tap(find.text('丙'));
    await tester.pumpAndSettle();
    expect(_panel, findsNothing);
    expect(picked, 'c');
  });
}
