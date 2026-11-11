import 'dart:async';

import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/link/phone_link.dart';
import 'package:baocode_mobile/state/app_state.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Link extends PhoneLink {
  _Link() : super(store: MemoryLinkStore());
  int checks = 0;
  @override
  List<KeptDesktop> get desktops => const [];
  @override
  void networkChanged() {}
  @override
  Future<void> verifyConnections({
    Duration timeout = const Duration(seconds: 4),
    Duration quietFor = const Duration(milliseconds: 800),
  }) async {
    checks++;
  }
}

class _State extends AppState {
  _State(_Link link) : super(store: MemoryLinkStore(), link: link);
  final opens = <String>[];
  Completer<void>? pending;
  bool fail = false;
  String text = '旧内容';
  @override
  bool isOnline(String desktopId) => true;
  @override
  Future<Object?> request(
    String desktopId,
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    if (method == LinkMethods.close) return null;
    if (method != LinkMethods.open) throw StateError('这里只允许同步读取：$method');
    opens.add(params['session']! as String);
    await pending?.future;
    if (fail) throw StateError('会话同步失败');
    return {
      'session': params['session'],
      'start': 0,
      'count': 1,
      'items': [
        {'t': 'text', 'text': text},
      ],
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const platform = MethodChannel('local.baocode.mobile/platform');
  const discovery = MethodChannel('local.baocode.mobile/discovery');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    messenger.setMockMethodCallHandler(platform, (_) async => null);
    messenger.setMockMethodCallHandler(discovery, (_) async => null);
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(platform, null);
    messenger.setMockMethodCallHandler(discovery, null);
  });

  test('回前台即使连接一直在线也同步活跃会话，重复唤醒合并且不拉无订阅缓存', () async {
    final link = _Link();
    final state = _State(link);
    addTearDown(state.dispose);
    await state.openSession('desk', 'active');
    state.buffer('desk', 'closed').items.add({'t': 'text', 'text': '旧缓存'});
    state.opens.clear();
    state.text = '最新内容';
    state.pending = Completer<void>();
    final first = state.resume();
    final second = state.resume();
    await Future<void>.delayed(Duration.zero);
    expect(state.opens, ['active']);
    expect(link.checks, 1);
    expect(state.buffer('desk', 'active').loading, isTrue);
    expect(state.buffer('desk', 'active').items.single, {
      't': 'text',
      'text': '旧内容',
    });
    state.pending!.complete();
    await Future.wait([first, second]);
    expect(state.buffer('desk', 'active').items.single, {
      't': 'text',
      'text': '最新内容',
    });
    expect(state.buffer('desk', 'active').loading, isFalse);
    expect(state.buffer('desk', 'closed').items.single, {
      't': 'text',
      'text': '旧缓存',
    });
  });

  test('回前台同步失败保留旧内容与错误，不自动重放请求', () async {
    final state = _State(_Link());
    addTearDown(state.dispose);
    await state.openSession('desk', 'active');
    state.opens.clear();
    state.fail = true;
    await state.resume();
    final buffer = state.buffer('desk', 'active');
    expect(state.opens, ['active']);
    expect(buffer.items.single, {'t': 'text', 'text': '旧内容'});
    expect(buffer.loading, isFalse);
    // 界面显示归类后的一句话，原始异常不再直接铺在界面上。
    expect(buffer.error, isNotEmpty);
    expect(buffer.error, isNot(contains('会话同步失败')));
  });
}
