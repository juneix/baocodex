import 'package:baocode_mobile/link/desktop_discovery.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const platform = MethodChannel('local.baocode.mobile/platform');
  const events = MethodChannel('local.baocode.mobile/discovery');
  late List<String> calls;

  setUp(() {
    calls = [];
    messenger.setMockMethodCallHandler(platform, (call) async {
      calls.add(call.method);
      return null;
    });
    messenger.setMockMethodCallHandler(events, (call) async => null);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(platform, null);
    messenger.setMockMethodCallHandler(events, null);
  });

  test('刷新时重新解析附近电脑，以便看到刚打开的配对窗口', () async {
    final discovery = DesktopDiscovery();
    addTearDown(discovery.dispose);
    await discovery.start();
    calls.clear();

    await discovery.refresh();

    expect(calls, ['discoveryRefresh']);
  });

  test('发现没在运行时，刷新会重新启动它', () async {
    final discovery = DesktopDiscovery();
    addTearDown(discovery.dispose);

    await discovery.refresh();

    expect(calls, ['discoveryStop', 'discoveryStart']);
    expect(discovery.running, isTrue);
  });
}
