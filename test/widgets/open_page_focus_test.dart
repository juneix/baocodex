import 'package:baocode_mobile/ui/widgets/mobile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('打开子页面再返回，输入框不重新聚焦、不弹键盘，草稿保留', (tester) async {
    final controller = TextEditingController();
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                TextField(controller: controller, focusNode: focus),
                TextButton(
                  onPressed: () => openPage<void>(
                    context,
                    Scaffold(appBar: AppBar(), body: const Text('子代理详情')),
                  ),
                  child: const Text('打开'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), '草稿');
    await tester.pump();
    expect(focus.hasFocus, isTrue);

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('子代理详情'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
    expect(controller.text, '草稿');
  });
}
