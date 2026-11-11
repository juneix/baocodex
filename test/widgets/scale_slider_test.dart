import 'package:baocode_mobile/ui/widgets/scale_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host({
    required double value,
    required ValueChanged<double> onChanged,
    ValueChanged<double>? onChangeEnd,
    VoidCallback? onTick,
    bool enabled = true,
    List<double> marks = const [],
  }) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 300,
          child: ScaleSlider(
            value: value,
            min: 0,
            max: 4,
            divisions: 4,
            marks: marks,
            enabled: enabled,
            onTick: onTick,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ),
      ),
    ),
  );
  testWidgets('按格变化时才报告，拖到同一格不重复', (tester) async {
    final seen = <double>[];
    var ticks = 0;
    await tester.pumpWidget(
      host(value: 0, onChanged: seen.add, onTick: () => ticks++),
    );
    await tester.drag(find.byType(Slider), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(seen, isNotEmpty);
    // 每一格一次，从 0 走到 4 一共四次；同一格重复报不会再多。
    expect(seen.length, ticks);
    expect(seen.every((value) => value == value.roundToDouble()), isTrue);
    expect(seen.last, 4);
  });
  testWidgets('松手才给 onChangeEnd，拖的路上不给', (tester) async {
    final ends = <double>[];
    await tester.pumpWidget(
      host(value: 0, onChanged: (_) {}, onChangeEnd: ends.add),
    );
    await tester.drag(find.byType(Slider), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(ends, [4]);
  });
  testWidgets('禁用时拖不动', (tester) async {
    var moved = false;
    await tester.pumpWidget(
      host(value: 2, enabled: false, onChanged: (_) => moved = true),
    );
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
    await tester.drag(find.byType(Slider), const Offset(200, 0));
    await tester.pumpAndSettle();
    expect(moved, isFalse);
  });
}
