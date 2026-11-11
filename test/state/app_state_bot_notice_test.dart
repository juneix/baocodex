import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/link/phone_link.dart';
import 'package:baocode_mobile/state/app_state.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('local.baocode.mobile/platform');

class _RecordingStore extends MemoryLinkStore {
  final writes = <String>[];
  @override
  Future<void> write(String key, String value) {
    writes.add(key);
    return super.write(key, value);
  }
}

class _FakeLink extends PhoneLink {
  _FakeLink(this.store) : super(store: store);
  final LinkStore store;
  List<KeptDesktop> kept = const [];
  Set<String> online = {};
  Map<String, Map<String, Object?>> snapshots = {};

  @override
  List<KeptDesktop> get desktops => kept;
  @override
  Set<String> get onlineIds => online;
  @override
  Map<String, Map<String, Object?>> get states => snapshots;
  @override
  Future<void> initialize() async {}

  void publish() => notifyListeners();
}

KeptDesktop desktop(String id) =>
    KeptDesktop(id: id, name: '电脑$id', publicKey: '');

LinkBotNotice notice(
  int id, {
  String kind = 'done',
  String detail = '内部错误细节',
}) => LinkBotNotice(
  id: id,
  kind: kind,
  chat: 'chat-$id',
  title: '秘密任务$id',
  project: '秘密项目',
  detail: detail,
);

Map<String, Object?> snapshot(
  List<LinkBotNotice> notices, {
  String botId = 'b',
  String name = '小宝',
}) => LinkState(
  device: const DeviceInfo(name: 'n', kind: 'mac', system: 's'),
  bots: [LinkBot(id: botId, name: name, notices: notices)],
).toJson();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _RecordingStore store;
  late _FakeLink link;
  late AppState state;
  final started = <AppState>[];
  late List<Map<Object?, Object?>> shown;
  late List<String> channelCalls;
  Object? failure;

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  Future<void> start() async {
    state = AppState(store: store, link: link);
    started.add(state);
    state.settings.language = 'zh';
    state.foreground = false;
    await state.initialize();
  }

  Future<void> publish(Map<String, Map<String, Object?>> snapshots) async {
    link.snapshots = snapshots;
    link.publish();
    await settle();
  }

  setUp(() {
    store = _RecordingStore();
    link = _FakeLink(store)
      ..kept = [desktop('d1')]
      ..online = {'d1'};
    shown = [];
    channelCalls = [];
    failure = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          channelCalls.add(call.method);
          if (call.method == 'notify') {
            shown.add(Map<Object?, Object?>.from(call.arguments as Map));
            if (failure != null) throw failure!;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    for (final item in started) {
      item.dispose();
    }
    started.clear();
  });

  test('首次状态与应用重启后的旧通知不补发，之后的新通知发一次', () async {
    await start();
    await publish({
      'd1': snapshot([notice(1), notice(2)]),
    });
    expect(shown, isEmpty);
    await publish({
      'd1': snapshot([notice(1), notice(2), notice(3)]),
    });
    expect(shown, hasLength(1));
    final restarted = _FakeLink(store)
      ..kept = [desktop('d1')]
      ..online = {'d1'};
    link = restarted;
    await start();
    await publish({
      'd1': snapshot([notice(1), notice(2), notice(3)]),
    });
    expect(shown, hasLength(1));
  });

  test('通知只含 Bot 名称与事件类别，不含 detail、标题或项目', () async {
    await start();
    await publish({'d1': snapshot([])});
    await publish({
      'd1': snapshot([notice(1, kind: 'failed', detail: 'token=SECRET-123')]),
    });
    expect(shown, hasLength(1));
    expect(shown.single['title'], '小宝');
    final body = shown.single['body'] as String;
    expect(body, isNotEmpty);
    for (final leaked in ['SECRET', '秘密', 'chat-1', 'token']) {
      expect(body, isNot(contains(leaked)));
      expect(shown.single['title'], isNot(contains(leaked)));
    }
    expect(body, contains('出错'));
  });

  test('不同事件类别使用不同的通用正文', () async {
    await start();
    await publish({'d1': snapshot([])});
    await publish({
      'd1': snapshot([
        notice(1, kind: 'waiting'),
        notice(2, kind: 'failed'),
        notice(3, kind: 'done'),
        notice(4, kind: 'running'),
        notice(5, kind: 'something-new'),
      ]),
    });
    final bodies = [for (final item in shown) item['body']];
    expect(bodies, hasLength(5));
    expect(bodies.toSet(), hasLength(5));
  });

  test('同时到达的多条新通知按 ID 顺序各发一次，系统通知 ID 互不相同', () async {
    await start();
    await publish({'d1': snapshot([])});
    await publish({
      'd1': snapshot([notice(7, kind: 'done'), notice(5, kind: 'waiting')]),
    });
    expect(shown, hasLength(2));
    expect(shown.map((e) => e['id']).toSet(), hasLength(2));
    expect(shown.first['body'], isNot(shown.last['body']));
  });

  test('重复快照与同一进程内重连不重发', () async {
    await start();
    await publish({'d1': snapshot([])});
    final withNotice = {
      'd1': snapshot([notice(1)]),
    };
    await publish(withNotice);
    expect(shown, hasLength(1));
    await publish(withNotice);
    link.online = {};
    await publish(withNotice);
    link.online = {'d1'};
    await publish({
      'd1': snapshot([notice(1)]),
    });
    expect(shown, hasLength(1));
    await publish({
      'd1': snapshot([notice(1), notice(2)]),
    });
    expect(shown, hasLength(2));
  });

  test('前台时不发系统通知但推进水位，之后进入后台不补发', () async {
    await start();
    await publish({'d1': snapshot([])});
    state.foreground = true;
    await publish({
      'd1': snapshot([notice(1)]),
    });
    expect(shown, isEmpty);
    state.foreground = false;
    await publish({
      'd1': snapshot([notice(1)]),
    });
    expect(shown, isEmpty);
    await publish({
      'd1': snapshot([notice(1), notice(2)]),
    });
    expect(shown, hasLength(1));
  });

  test('关闭通知开关时推进水位，重新开启不补发旧通知', () async {
    await start();
    await publish({'d1': snapshot([])});
    state.settings.notifications = false;
    await publish({
      'd1': snapshot([notice(1)]),
    });
    expect(shown, isEmpty);
    state.settings.notifications = true;
    await publish({
      'd1': snapshot([notice(1)]),
    });
    expect(shown, isEmpty);
    await publish({
      'd1': snapshot([notice(1), notice(2)]),
    });
    expect(shown, hasLength(1));
  });

  test('权限被拒时不抛出、不重试，后续新通知仍可发送', () async {
    await start();
    channelCalls.clear();
    await publish({'d1': snapshot([])});
    failure = PlatformException(code: 'denied');
    await publish({
      'd1': snapshot([notice(1)]),
    });
    expect(shown, hasLength(1));
    await publish({
      'd1': snapshot([notice(1)]),
    });
    expect(shown, hasLength(1));
    failure = null;
    await publish({
      'd1': snapshot([notice(1), notice(2)]),
    });
    expect(shown, hasLength(2));
    expect(state.ready, isTrue);
    expect(state.startupError, isNull);
    expect(store.writes, isEmpty, reason: '拒绝通知不写入存储');
    expect(channelCalls.toSet(), {
      'notify',
    }, reason: '只调用 notify，不请求通知权限或其他平台方法');
  });

  test('忘记电脑只清除该电脑的内存水位', () async {
    link
      ..kept = [desktop('d1'), desktop('d2')]
      ..online = {'d1', 'd2'};
    await start();
    await publish({
      'd1': snapshot([notice(1)]),
      'd2': snapshot([notice(1)]),
    });
    link.kept = [desktop('d2')];
    link.online = {'d2'};
    await publish({
      'd2': snapshot([notice(1)]),
    });
    link.kept = [desktop('d1'), desktop('d2')];
    link.online = {'d1', 'd2'};
    await publish({
      'd1': snapshot([notice(1), notice(2)]),
      'd2': snapshot([notice(1)]),
    });
    expect(shown, isEmpty, reason: '被忘记的电脑重新加回后只重建基线，不补发更高 ID');
    await publish({
      'd1': snapshot([notice(1), notice(2)]),
      'd2': snapshot([notice(1), notice(2)]),
    });
    expect(shown, hasLength(1), reason: '未被忘记的电脑仍保留水位，只通知新 ID');
    expect(shown.single['title'], '小宝');
    final d2Id = shown.single['id'];
    await publish({
      'd1': snapshot([notice(1), notice(2), notice(3)]),
      'd2': snapshot([notice(1), notice(2)]),
    });
    expect(shown, hasLength(2));
    expect(shown.last['id'], isNot(d2Id));
  });

  test('旧端没有 notices 字段时照常运行', () async {
    await start();
    final legacy = {
      'device': {'name': 'n', 'kind': 'mac', 'system': 's'},
      'bots': [
        {'id': 'b', 'name': '小宝'},
      ],
    };
    await publish({'d1': legacy});
    await publish({'d1': legacy});
    expect(shown, isEmpty);
    expect(state.bots.single.bot.notices, isEmpty);
  });
}
