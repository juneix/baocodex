import 'package:baocode_mobile/platform/permission_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('local.baocode.mobile/platform');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Future<BuildContext> anchor(WidgetTester tester) async {
    late BuildContext found;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            found = context;
            return const SizedBox(width: 120, height: 48);
          },
        ),
      ),
    );
    return found;
  }

  testWidgets('只传选项 ID 和第一行文案，选中值随结果返回', (tester) async {
    Map<Object?, Object?>? sent;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'permissionMenu');
      sent = call.arguments as Map<Object?, Object?>;
      return 'acceptEdits';
    });
    final context = await anchor(tester);
    final selected = await showNativePermissionMenu(
      context,
      options: const [
        (id: 'default', label: '逐项批准'),
        (id: 'acceptEdits', label: '自动接受编辑'),
      ],
      selected: 'default',
    );
    expect(selected, 'acceptEdits');
    expect(sent?['selected'], 'default');
    final options = (sent?['options'] as List).cast<Map<Object?, Object?>>();
    expect(options, hasLength(2));
    expect(options[0]['id'], 'default');
    expect(options[0]['label'], '逐项批准');
    expect(options[1]['id'], 'acceptEdits');
    expect(options[1]['label'], '自动接受编辑');
    expect(sent?['dark'], isFalse);
    expect(sent?['width'], greaterThan(0));
    expect(sent?['height'], greaterThan(0));
  });

  testWidgets('取消时返回空值，不伪造选择', (tester) async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    final context = await anchor(tester);
    expect(
      await showNativePermissionMenu(
        context,
        options: const [(id: 'a', label: 'A')],
        selected: null,
      ),
      isNull,
    );
  });
}
