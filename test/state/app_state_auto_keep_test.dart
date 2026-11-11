import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/link/phone_link.dart';
import 'package:baocode_mobile/state/app_state.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('local.baocode.mobile/platform');

class _FakeLink extends PhoneLink {
  _FakeLink(LinkStore store) : super(store: store);
  Set<String> online = {'d1'};
  Map<String, Map<String, Object?>> snapshots = {};
  final calls = <(String, String, Map<String, Object?>)>[];

  @override
  List<KeptDesktop> get desktops => const [
    KeptDesktop(id: 'd1', name: '电脑', publicKey: ''),
  ];
  @override
  Set<String> get onlineIds => online;
  @override
  Map<String, Map<String, Object?>> get states => snapshots;
  @override
  Future<void> initialize() async {}
  @override
  Future<Object?> call(
    String desktopId,
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    calls.add((desktopId, method, params));
    return null;
  }

  void publish(Map<String, LinkSessionStatus> statuses) {
    snapshots = {
      'd1': LinkState(
        device: const DeviceInfo(name: 'n', kind: 'mac', system: 's'),
        sessions: [
          for (final MapEntry(:key, :value) in statuses.entries)
            SessionSummary(
              id: key,
              project: '/p',
              title: key,
              updatedAt: DateTime(2026),
              status: value,
            ),
        ],
      ).toJson(),
    };
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _FakeLink link;
  late AppState state;

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (_) async => null);
    final store = MemoryLinkStore();
    link = _FakeLink(store);
    state = AppState(store: store, link: link);
    state.foreground = true;
    await state.initialize();
  });

  tearDown(() {
    state.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  Future<void> publish(Map<String, LinkSessionStatus> statuses) async {
    link.publish(statuses);
    await Future<void>.delayed(Duration.zero);
  }

  List<(String, String, Map<String, Object?>)> keeps() => [
    for (final call in link.calls)
      if (call.$2 == LinkMethods.keep) call,
  ];

  test('开启后每轮结束（运行中→空闲）都整份保留，等你处理不算结束', () async {
    state.settings.autoKeep = true;
    await publish({
      'a': LinkSessionStatus.running,
      'b': LinkSessionStatus.running,
    });
    expect(keeps(), isEmpty);
    await publish({
      'a': LinkSessionStatus.idle,
      'b': LinkSessionStatus.needsInput,
    });
    expect(keeps(), hasLength(1));
    expect(keeps().single.$1, 'd1');
    expect(keeps().single.$3, {'session': 'a'});
    await publish({
      'a': LinkSessionStatus.idle,
      'b': LinkSessionStatus.running,
    });
    await publish({'a': LinkSessionStatus.idle, 'b': LinkSessionStatus.idle});
    expect(keeps().map((call) => call.$3['session']), ['a', 'b']);
  });

  test('关闭时、首次看到的空闲、电脑离线时都不保留', () async {
    await publish({'a': LinkSessionStatus.idle});
    await publish({'a': LinkSessionStatus.running});
    await publish({'a': LinkSessionStatus.idle});
    expect(keeps(), isEmpty);
    state.settings.autoKeep = true;
    await publish({'a': LinkSessionStatus.running});
    link.online = {};
    await publish({'a': LinkSessionStatus.idle});
    expect(keeps(), isEmpty);
  });
}
