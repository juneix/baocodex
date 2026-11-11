import 'dart:io';

import 'package:baocode_mobile/chat/chat_models.dart';
import 'package:baocode_mobile/chat/widgets/turn_footer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {double width = 360}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(size: Size(width, 700)),
    child: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  test('formats costs without inventing absent statistics', () {
    expect(TurnFooter.formatCost(1.2), r'$1.20');
    expect(TurnFooter.formatCost(0.0031), r'$0.0031');
    expect(TurnFooter.formatCost(0), r'$0.00');
  });

  testWidgets('shows copy when answer exists and leaves missing usage absent', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const TurnFooter(answer: '答案', zh: true)));
    expect(find.bySemanticsLabel('复制回答'), findsOneWidget);
    expect(find.textContaining('token'), findsNothing);
    expect(find.textContaining(r'$'), findsNothing);
  });

  group('真实字体度量', () {
    // 测试默认字体每个字形都是 1em 宽，无法判断真机上一行放不放得下；
    // 数字和英文用 Flutter 自带的 Roboto，中文仍按 1em 宽回退。
    setUpAll(() async {
      final root = Platform.environment['FLUTTER_ROOT'];
      final fonts = '$root/bin/cache/artifacts/material_fonts';
      final loader = FontLoader('Roboto')
        ..addFont(
          Future.value(
            ByteData.sublistView(
              File('$fonts/Roboto-Regular.ttf').readAsBytesSync(),
            ),
          ),
        );
      await loader.load();
    });

    testWidgets('手机常用宽度下完整统计与复制保持同一行', (tester) async {
      tester.view.physicalSize = const Size(360, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _host(
          const DefaultTextStyle(
            style: TextStyle(fontFamily: 'Roboto'),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: TurnFooter(
                answer: '回答',
                worked: Duration(minutes: 3, seconds: 31),
                usage: TurnUsage(
                  inputTokens: 3550000,
                  outputTokens: 10000,
                  tokensPerSecond: 159.86,
                  costUsd: 4.09,
                ),
                zh: true,
              ),
            ),
          ),
        ),
      );
      final copy = tester.getRect(find.byTooltip('复制回答'));
      for (final text in ['3分31秒', '160 tok/s', r'$4.09', '3.6M tok']) {
        expect(
          tester.getCenter(find.text(text)).dy,
          closeTo(copy.center.dy, 1),
          reason: '$text 应与复制同一行',
        );
      }
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('复制与统计的间距大于统计项间距，统计项间距大于图标与数字', (tester) async {
    await tester.pumpWidget(
      _host(
        const TurnFooter(
          answer: '回答',
          worked: Duration(seconds: 32),
          usage: TurnUsage(tokensPerSecond: 37.16, costUsd: .15),
          zh: true,
        ),
      ),
    );
    final copyIcon = tester.getRect(
      find
          .descendant(
            of: find.byTooltip('复制回答'),
            matching: find.byType(SvgPicture),
          )
          .first,
    );
    final duration = tester.getRect(find.byTooltip('耗时'));
    final speed = tester.getRect(find.byTooltip('生成速度'));
    final copyGap = duration.left - copyIcon.right;
    final statsGap = speed.left - duration.right;
    expect(copyGap, greaterThan(statsGap));
    final hit = tester.getRect(find.byTooltip('复制回答'));
    expect(hit.width, greaterThanOrEqualTo(40));
    expect(hit.height, greaterThanOrEqualTo(40));
    // 与统计开头重叠的那段仍点得到复制。
    expect(
      find.byTooltip('复制回答').hitTestable(at: const Alignment(.9, 0)),
      findsOneWidget,
    );
  });

  testWidgets('statistics wrap at narrow widths', (tester) async {
    tester.view.physicalSize = const Size(180, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _host(
        const TurnFooter(
          worked: Duration(seconds: 65),
          usage: TurnUsage(
            inputTokens: 1200,
            outputTokens: 3400,
            tokensPerSecond: 12.5,
            costUsd: 0.004,
          ),
          zh: true,
        ),
        width: 180,
      ),
    );
    expect(find.textContaining('1分5秒'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('完成统计换行左对齐且操作区保留四十八高', (tester) async {
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 260,
          child: TurnFooter(
            answer: '中文回答',
            worked: const Duration(seconds: 32),
            usage: const TurnUsage(
              inputTokens: 200000,
              outputTokens: 2070,
              tokensPerSecond: 37.16,
              costUsd: 0.15,
            ),
            zh: true,
            action: SizedBox(
              width: 40,
              height: 48,
              child: IconButton(
                tooltip: '引用',
                onPressed: () {},
                icon: const Icon(Icons.format_quote, size: 19),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('32秒'), findsOneWidget);
    expect(find.text('37 tok/s'), findsOneWidget);
    expect(find.text(r'$0.15'), findsOneWidget);
    expect(find.text('202k tok'), findsOneWidget);
    final wrap = find.descendant(
      of: find.byType(TurnFooter),
      matching: find.byType(Wrap),
    );
    final render = tester.renderObject(wrap) as RenderBox;
    final widget = tester.widget<Wrap>(wrap);
    expect(widget.runSpacing, 2);
    final statRects = widget.children
        .map((child) => tester.getRect(find.byWidget(child)))
        .toList();
    final firstLeft = statRects.first.left;
    final nextLine = statRects
        .where((rect) => rect.top > statRects.first.bottom)
        .first;
    expect(nextLine.left, firstLeft);
    final actionRect = tester.getRect(find.byTooltip('引用'));
    expect(actionRect.height, 48);
    expect(actionRect.width, 40);
    expect(render.size.height, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('live clock updates and its ticker is disposed', (tester) async {
    await tester.pumpWidget(
      _host(
        TurnFooter(
          since: DateTime.now().subtract(const Duration(seconds: 2)),
          live: const TurnOutput(tokens: 21, tokensPerSecond: 4.2),
          zh: true,
        ),
      ),
    );
    expect(find.text('秒'), findsOneWidget);
    await tester.pumpWidget(_host(const SizedBox.shrink()));
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('copy action writes answer to clipboard', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
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
      _host(const TurnFooter(answer: 'copy this', zh: true)),
    );
    await tester.tap(find.bySemanticsLabel('复制回答'));
    await tester.pump();
    expect(copied, 'copy this');
  });
}
