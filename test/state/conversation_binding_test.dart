import 'dart:async';

import 'package:baocode_mobile/state/conversation_binding.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('占位不订阅，真实会话切换严格释放旧订阅，迟到发送不覆盖新目标', () async {
    final calls = <String>[];
    final binding = ConversationBinding(
      retain: (id) async {
        calls.add('open:$id');
      },
      release: (id) async {
        calls.add('close:$id');
      },
      refreshSession: (_) async {},
    );
    binding.update(sessionId: null, online: true);
    await binding.settled;
    expect(calls, isEmpty);
    final sentAt = binding.generation;
    expect(binding.acceptSent('first', sentAt), isTrue);
    await binding.settled;
    final oldGeneration = binding.generation;
    binding.update(sessionId: 'after-clear', online: true);
    await binding.settled;
    expect(binding.acceptSent('first', oldGeneration), isFalse);
    expect(binding.sessionId, 'after-clear');
    expect(calls, ['open:first', 'close:first', 'open:after-clear']);
    binding.dispose();
    await binding.settled;
    expect(calls.last, 'close:after-clear');
  });

  test('普通固定会话拒绝其他会话的发送结果，不进入无法核对的改绑状态', () async {
    final binding = ConversationBinding(
      retain: (_) async {},
      release: (_) async {},
      refreshSession: (_) async {},
    );
    binding.update(sessionId: 'fixed', online: true);
    await binding.settled;
    expect(binding.acceptSent('other', binding.generation), isFalse);
    expect(binding.sessionId, 'fixed');
    binding.update(sessionId: 'fixed', online: true);
    expect(binding.sessionId, 'fixed');
    binding.dispose();
    await binding.settled;
  });

  test('断线重连换的是连接状态，不是会话身份', () async {
    final binding = ConversationBinding(
      retain: (_) async {},
      release: (_) async {},
      refreshSession: (_) async {},
    );
    binding.update(sessionId: 'session', online: true);
    await binding.settled;
    final identity = binding.identity;
    final generation = binding.generation;

    binding.update(sessionId: 'session', online: false);
    await binding.settled;
    // 掉线：读写版本推进，会话身份不变——开着的设置弹层不用关掉重开。
    expect(binding.generation, greaterThan(generation));
    expect(binding.identity, identity);

    binding.update(sessionId: 'session', online: true);
    await binding.settled;
    expect(binding.identity, identity);

    // 真的换了会话，身份才推进。
    binding.update(sessionId: 'other', online: true);
    await binding.settled;
    expect(binding.identity, greaterThan(identity));
    binding.dispose();
    await binding.settled;
  });

  test('会话变得不可用时身份推进', () async {
    final binding = ConversationBinding(
      retain: (_) async {},
      release: (_) async {},
      refreshSession: (_) async {},
    );
    binding.update(sessionId: 'session', online: true);
    await binding.settled;
    final identity = binding.identity;
    binding.update(sessionId: 'session', online: true, available: false);
    await binding.settled;
    expect(binding.identity, greaterThan(identity));
    binding.dispose();
    await binding.settled;
  });

  test('迟到 open 完成后必须关闭，销毁后不能再建立订阅', () async {
    final opened = Completer<void>();
    final calls = <String>[];
    final binding = ConversationBinding(
      retain: (id) async {
        calls.add('open:$id');
        await opened.future;
      },
      release: (id) async {
        calls.add('close:$id');
      },
      refreshSession: (_) async {},
    );
    binding.update(sessionId: 'old', online: true);
    await pumpEventQueue();
    binding.update(sessionId: 'new', online: true);
    binding.dispose();
    opened.complete();
    await binding.settled;
    expect(calls, ['open:old', 'close:old']);
  });

  test('发送返回新会话后，矛盾快照必须只读核对，不能静默切回旧会话', () async {
    final verification = Completer<ConversationTarget>();
    final binding = ConversationBinding(
      retain: (_) async {},
      release: (_) async {},
      refreshSession: (_) async {},
      verifyTarget: () => verification.future,
    );
    binding.update(sessionId: 'old', online: true);
    await binding.settled;
    expect(binding.acceptSent('new', binding.generation), isTrue);
    binding.update(sessionId: 'old', online: true);
    expect(binding.sessionId, 'new');
    verification.complete(const ConversationTarget(sessionId: 'new'));
    await pumpEventQueue();
    expect(binding.sessionId, 'new');
    expect(binding.error, isNull);
    binding.dispose();
    await binding.settled;
  });

  test('删除与断线使发送代次失效，不接纳同名目标旧回复', () async {
    final binding = ConversationBinding(
      retain: (_) async {},
      release: (_) async {},
      refreshSession: (_) async {},
    );
    binding.update(sessionId: 's', online: true);
    final old = binding.generation;
    binding.update(sessionId: 's', online: false);
    expect(binding.acceptSent('s', old), isFalse);
    binding.update(sessionId: null, online: true, available: false);
    expect(binding.available, isFalse);
    expect(binding.acceptSent('s', old), isFalse);
    binding.dispose();
    await binding.settled;
  });
}
