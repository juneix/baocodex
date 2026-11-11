import 'dart:async';

import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/state/task_output_subscriptions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late TaskOutputSubscriptions outputs;
  late List<(String, String)> calls;
  late Future<Object?> Function(String, String, Map<String, Object?>) respond;
  var online = true;
  setUp(() {
    calls = [];
    online = true;
    respond = (_, method, _) async =>
        method == LinkMethods.watchOutput ? {'text': 'abc', 'offset': 3} : null;
    outputs = TaskOutputSubscriptions(
      request: (desktop, method, params) {
        calls.add((desktop, method));
        return respond(desktop, method, params);
      },
      isOnline: (_) => online,
      onChanged: () {},
      tr: (zh, _) => zh,
    );
  });
  tearDown(() => outputs.dispose());

  void event(
    int offset,
    String text, {
    bool reset = false,
    String desktop = 'a',
  }) => outputs.accept(
    desktop,
    LinkOutput(
      session: 's',
      task: 't',
      offset: offset,
      text: text,
      reset: reset,
    ).toJson(),
  );

  test('共享订阅仅建立一次，追加去重并隔离电脑和任务', () async {
    await outputs.retain('a', 's', 't');
    await outputs.retain('a', 's', 't');
    event(5, 'de');
    event(5, 'de');
    event(6, 'f', desktop: 'b');
    expect(outputs.buffer('a', 's', 't').text, 'abcde');
    expect(calls, [('a', LinkMethods.watchOutput)]);
    await outputs.release('a', 's', 't');
    expect(calls, hasLength(1));
    await outputs.release('a', 's', 't');
    expect(calls.last, ('a', LinkMethods.unwatchOutput));
  });

  test('reset 替换旧内容，输出缓存有界，偏移缺口重新读取', () async {
    await outputs.retain('a', 's', 't');
    event(1, 'x', reset: true);
    expect(outputs.buffer('a', 's', 't').text, 'x');
    event(LinkLimits.output + 1, 'z' * LinkLimits.output);
    expect(outputs.buffer('a', 's', 't').text.length, LinkLimits.output);
    event(LinkLimits.output + 4, 'q');
    await pumpEventQueue();
    expect(
      calls.where((call) => call.$2 == LinkMethods.watchOutput),
      hasLength(2),
    );
    expect(outputs.buffer('a', 's', 't').text, 'abc');
  });

  test('快照期间的事件在快照之后应用，销毁后忽略迟到回复', () async {
    final read = Completer<Object?>();
    respond = (_, method, _) async =>
        method == LinkMethods.watchOutput ? read.future : null;
    final started = outputs.retain('a', 's', 't');
    await pumpEventQueue();
    event(5, 'de');
    read.complete({'text': 'abc', 'offset': 3});
    await started;
    expect(outputs.buffer('a', 's', 't').text, 'abcde');
    final late = Completer<Object?>();
    respond = (_, _, _) => late.future;
    final refresh = outputs.refresh('a', 's', 't');
    await pumpEventQueue();
    outputs.dispose();
    late.complete({'text': 'stale', 'offset': 5});
    await refresh;
  });

  test('只有 unknown 或 unsupported 回退轮询，网络错误仍显示失败', () async {
    respond = (_, method, _) async {
      if (method == LinkMethods.watchOutput) {
        throw const LinkRemoteException(LinkErrors.unknown, '旧端未支持');
      }
      return {'text': '旧端输出'};
    };
    await outputs.retain('a', 's', 't');
    expect(outputs.buffer('a', 's', 't').polling, isTrue);
    expect(outputs.buffer('a', 's', 't').text, '旧端输出');
    await outputs.release('a', 's', 't');
    respond = (_, _, _) async => throw const LinkClosedException();
    await outputs.retain('b', 's', 't');
    expect(outputs.buffer('b', 's', 't').polling, isFalse);
    expect(outputs.buffer('b', 's', 't').error, isNotNull);
  });

  test('最后一个页面释放后清除缓存，只读访问不重建缓存', () async {
    await outputs.retain('a', 's', 't');
    expect(outputs.peek('a', 's', 't')!.text, 'abc');
    await outputs.release('a', 's', 't');
    expect(outputs.peek('a', 's', 't'), isNull);
    expect(outputs.peek('a', 's', 'unknown'), isNull);
  });

  test('旧页面取消与新页面订阅串行，新缓存不被旧取消清除', () async {
    final first = Completer<Object?>();
    var watches = 0;
    respond = (_, method, _) async {
      if (method == LinkMethods.watchOutput) {
        if (++watches == 1) return first.future;
        return {'text': 'new', 'offset': 3};
      }
      return null;
    };
    final initial = outputs.retain('a', 's', 't');
    await pumpEventQueue();
    final release = outputs.release('a', 's', 't');
    final next = outputs.retain('a', 's', 't');
    first.complete({'text': 'old', 'offset': 3});
    await Future.wait([initial, release, next]);
    expect(calls.map((call) => call.$2), [
      LinkMethods.watchOutput,
      LinkMethods.unwatchOutput,
      LinkMethods.watchOutput,
    ]);
    expect(outputs.peek('a', 's', 't')!.text, 'new');
  });

  testWidgets('订阅瞬时失败退避后恢复，不伪装成轮询', (tester) async {
    var attempts = 0;
    respond = (_, _, _) async {
      if (++attempts == 1) throw const LinkClosedException();
      return {'text': 'recovered', 'offset': 9};
    };
    await outputs.retain('a', 's', 't');
    expect(outputs.peek('a', 's', 't')!.error, isNotNull);
    await tester.pump(const Duration(seconds: 2));
    expect(attempts, 2);
    expect(outputs.peek('a', 's', 't')!.text, 'recovered');
    expect(outputs.peek('a', 's', 't')!.error, isNull);
    expect(outputs.peek('a', 's', 't')!.polling, isFalse);
  });

  testWidgets('只读订阅最多重试三次，释放后没有重试计时器', (tester) async {
    respond = (_, _, _) async => throw const LinkClosedException();
    await outputs.retain('a', 's', 't');
    for (final seconds in [2, 4, 8, 16]) {
      await tester.pump(Duration(seconds: seconds));
    }
    expect(
      calls.where((call) => call.$2 == LinkMethods.watchOutput),
      hasLength(4),
    );
    await outputs.release('a', 's', 't');
    final before = calls.length;
    await tester.pump(const Duration(seconds: 16));
    expect(calls.length, before);
    expect(outputs.peek('a', 's', 't'), isNull);
  });

  test('断线丢弃旧回复，重连仅恢复只读订阅', () async {
    final old = Completer<Object?>();
    respond = (_, _, _) => old.future;
    final first = outputs.retain('a', 's', 't');
    await pumpEventQueue();
    online = false;
    outputs.connectionChanged('a', online: false);
    old.complete({'text': 'old', 'offset': 3});
    await first;
    expect(outputs.buffer('a', 's', 't').text, isEmpty);
    respond = (_, _, _) async => {'text': 'new', 'offset': 3};
    online = true;
    outputs.connectionChanged('a', online: true);
    await pumpEventQueue();
    expect(outputs.buffer('a', 's', 't').text, 'new');
    expect(calls.every((call) => call.$2 == LinkMethods.watchOutput), isTrue);
  });
}
