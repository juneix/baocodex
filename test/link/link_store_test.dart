import 'package:baocode_mobile/link/link_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('platform store uses the native secure-storage contract', () async {
    const channel = MethodChannel('local.baocode.mobile/platform');
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'secureRead' ? 'private' : null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final store = PlatformLinkStore();
    expect(await store.read('identity'), 'private');
    await store.write('desktops', '[]');
    await store.remove('desktops');
    expect(calls.map((c) => c.method), [
      'secureRead',
      'secureWrite',
      'secureRemove',
    ]);
    expect(calls[0].arguments, {'key': 'identity'});
    expect(calls[1].arguments, {'key': 'desktops', 'value': '[]'});
    expect(calls[2].arguments, {'key': 'desktops'});
  });

  test(
    'platform storage failures propagate rather than losing credentials',
    () async {
      const channel = MethodChannel('local.baocode.mobile/platform');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(code: 'locked');
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      expect(
        PlatformLinkStore().read('identity'),
        throwsA(isA<PlatformException>()),
      );
    },
  );
}
