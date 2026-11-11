import 'dart:async';
import 'dart:typed_data';

import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/models/session_buffer.dart';
import 'package:baocode_mobile/state/conversation_input.dart';
import 'package:baocode_mobile/state/local_message_queue.dart';
import 'package:flutter_test/flutter_test.dart';

class Sent {
  Sent(this.session, this.text, this.images, this.mentions, this.now, this.id);
  final String? session, id;
  final String text;
  final List<Map<String, Object?>> images;
  final List<String> mentions;
  final bool now;
}

class Harness {
  Harness({this.grace = const Duration(milliseconds: 50)}) {
    queue = LocalMessageQueue(
      isOnline: (_) => online,
      bufferOf: (desktop, session) =>
          buffers.putIfAbsent(session, () => SessionBuffer(desktop, session)),
      send: send,
      onChanged: () => changes++,
      tr: (zh, _) => zh,
      startGrace: grace,
    );
  }

  final Duration grace;
  late final LocalMessageQueue queue;
  final buffers = <String, SessionBuffer>{};
  final sent = <Sent>[];
  final pending = <Completer<String?>>[];
  bool online = true, hold = false;
  Object? failWith;
  int changes = 0;

  SessionBuffer get buffer =>
      buffers.putIfAbsent('s', () => SessionBuffer('d', 's'));

  Future<String?> send(
    String desktopId, {
    String? session,
    String? project,
    String? bot,
    required String text,
    List<Map<String, Object?>> images = const [],
    List<String> mentions = const [],
    bool now = false,
    String? id,
  }) {
    sent.add(Sent(session, text, images, mentions, now, id));
    if (failWith != null) return Future.error(failWith!);
    if (hold) {
      final completer = Completer<String?>();
      pending.add(completer);
      return completer.future;
    }
    return Future.value(session);
  }

  LocalQueuedMessage add(String text, {List<DraftImage> images = const []}) =>
      queue.add('d', 's', text: text, images: images);
  Future<void> settle() => Future<void>.delayed(Duration.zero);
  Future<void> pastGrace() =>
      Future<void>.delayed(grace + const Duration(milliseconds: 40));
}

void main() {
  test('运行中加入队列：不调用 send，保留文本、图片与提及', () async {
    final h = Harness()..buffer.live = true;
    final image = DraftImage('a.png', 'image/png', Uint8List.fromList([1, 2]));
    h.queue.add('d', 's', text: '第一条', images: [image], mentions: const ['@a']);
    await h.settle();
    expect(h.sent, isEmpty);
    final message = h.queue.messages('d', 's').single;
    expect(message.text, '第一条');
    expect(message.images.single, same(image));
    expect(message.mentions, ['@a']);
    expect(h.changes, greaterThan(0));
  });

  test('本轮结束后只发出一条，下一条等它开始；开始后继续，且 id 不重复', () async {
    final h = Harness()..buffer.live = true;
    h.add('一');
    h.add('二');
    h.add('三');
    h.queue.drain('d', 's');
    expect(h.sent, isEmpty);

    h.buffer.live = false;
    h.queue.drain('d', 's');
    await h.settle();
    expect(h.sent.map((e) => e.text), ['一']);
    expect(h.sent.single.now, false);
    expect(h.sent.single.id, startsWith('phone-'));
    expect(h.queue.messages('d', 's').map((e) => e.text), ['二', '三']);

    // 已发的那条尚未开始：再次 drain 不会发下一条。
    h.queue.drain('d', 's');
    h.queue.drainAll();
    await h.settle();
    expect(h.sent, hasLength(1));

    // 它的回合开始（live），随后结束：才轮到第二条。
    h.buffer.live = true;
    h.queue.drain('d', 's');
    expect(h.sent, hasLength(1));
    h.buffer.live = false;
    h.queue.drain('d', 's');
    await h.settle();
    expect(h.sent.map((e) => e.text), ['一', '二']);
    expect(h.sent.map((e) => e.id).toSet(), hasLength(2));

    // 即使没有观察到 live，宽限期过后也会继续。
    await h.pastGrace();
    expect(h.sent.map((e) => e.text), ['一', '二', '三']);
    await h.pastGrace();
    expect(h.queue.messages('d', 's'), isEmpty);
  });

  test('未运行时队列里已有消息，新消息排在后面而不越过', () async {
    final h = Harness();
    h.add('先');
    await h.settle();
    expect(h.sent.map((e) => e.text), ['先']);
    h.add('后');
    await h.settle();
    expect(h.sent, hasLength(1));
    expect(h.queue.messages('d', 's').single.text, '后');
    await h.pastGrace();
    expect(h.sent.map((e) => e.text), ['先', '后']);
    await h.pastGrace();
  });

  test('立即发送带 now:true 与稳定 id，并移出队列；后一条等宽限期', () async {
    final h = Harness()..buffer.live = true;
    final first = h.add('甲');
    h.add('乙');
    final ok = await h.queue.sendNow('d', 's', first.id);
    expect(ok, true);
    expect(h.sent.single.now, true);
    expect(h.sent.single.id, first.id);
    expect(h.queue.messages('d', 's').map((e) => e.text), ['乙']);
    // 旧回合仍显示运行：不会误发下一条。
    h.queue.drain('d', 's');
    await h.settle();
    expect(h.sent, hasLength(1));
    await h.pastGrace();
    expect(h.sent, hasLength(1));
    h.buffer.live = false;
    h.queue.drain('d', 's');
    await h.settle();
    expect(h.sent.map((e) => e.text), ['甲', '乙']);
    await h.pastGrace();
  });

  test('编辑取回：take 取出并移除；不存在返回 null', () async {
    final h = Harness()..buffer.live = true;
    final image = DraftImage('a.png', 'image/png', Uint8List(1));
    final a = h.queue.add('d', 's', text: 'A', images: [image]);
    h.add('B');
    final taken = h.queue.take('d', 's', a.id)!;
    expect(taken.text, 'A');
    expect(taken.images.single, same(image));
    expect(h.queue.messages('d', 's').map((e) => e.text), ['B']);
    expect(h.queue.take('d', 's', a.id), isNull);
    final b = h.queue.messages('d', 's').single;
    expect(h.queue.take('d', 's', b.id)!.text, 'B');
    expect(h.queue.messages('d', 's'), isEmpty);
    expect(h.sent, isEmpty);
  });

  test('发送中不能取回或再次发送同一条', () async {
    final h = Harness()..hold = true;
    final m = h.add('慢');
    await h.settle();
    expect(h.queue.busy('d', 's'), true);
    expect(h.queue.take('d', 's', m.id), isNull);
    expect(await h.queue.sendNow('d', 's', m.id), false);
    expect(h.sent, hasLength(1));
    h.pending.single.complete('s');
    await h.settle();
    expect(h.queue.busy('d', 's'), false);
    expect(h.queue.messages('d', 's'), isEmpty);
    await h.pastGrace();
  });

  test('离线：队列保留，不发送；上线后继续', () async {
    final h = Harness()
      ..buffer.live = true
      ..online = false;
    h.add('留着');
    h.buffer.live = false;
    h.queue.drain('d', 's');
    await h.settle();
    expect(h.sent, isEmpty);
    expect(h.queue.messages('d', 's'), hasLength(1));

    h.online = true;
    h.queue.reconnected('d');
    h.queue.drainAll();
    await h.settle();
    expect(h.sent.map((e) => e.text), ['留着']);
    await h.pastGrace();
  });

  test('离线时立即发送：保留并给出提示，不丢', () async {
    final h = Harness()..buffer.live = true;
    final m = h.add('急');
    h.online = false;
    expect(await h.queue.sendNow('d', 's', m.id), false);
    expect(h.sent, isEmpty);
    expect(h.queue.failure('d', 's'), contains('未连接'));
    expect(h.queue.messages('d', 's'), hasLength(1));
  });

  test('发送失败：保留并提示；连接中断后重连继续，沿用同一 id', () async {
    final h = Harness();
    h.failWith = const LinkClosedException('gone');
    final m = h.add('断');
    await h.settle();
    expect(h.queue.messages('d', 's'), hasLength(1));
    expect(h.queue.failure('d', 's'), contains('连接中断'));
    // 失败后不会自行反复重试。
    h.queue.drainAll();
    await h.settle();
    expect(h.sent, hasLength(1));

    h.failWith = null;
    h.queue.reconnected('d');
    h.queue.drainAll();
    await h.settle();
    expect(h.sent, hasLength(2));
    expect(h.sent.last.id, m.id);
    expect(h.sent.first.id, h.sent.last.id);
    expect(h.queue.failure('d', 's'), isNull);
    await h.pastGrace();
    expect(h.queue.messages('d', 's'), isEmpty);
  });

  test('其它失败：手动重试才继续，提示不露出原始错误', () async {
    final h = Harness()..failWith = StateError('boom');
    h.add('错');
    await h.settle();
    expect(h.queue.failure('d', 's'), contains('排队消息发送失败'));
    expect(h.queue.failure('d', 's'), isNot(contains('boom')));
    h.failWith = null;
    h.queue.retry('d', 's');
    await h.settle();
    expect(h.sent, hasLength(2));
    expect(h.queue.failure('d', 's'), isNull);
    await h.pastGrace();
  });

  test('会话加载中或出错时不发送', () async {
    final h = Harness();
    h.buffer.loading = true;
    h.queue.add('d', 's', text: '等');
    await h.settle();
    expect(h.sent, isEmpty);
    h.buffer
      ..loading = false
      ..error = 'x';
    h.queue.drain('d', 's');
    expect(h.sent, isEmpty);
    h.buffer.error = null;
    h.queue.drain('d', 's');
    await h.settle();
    expect(h.sent, hasLength(1));
    await h.pastGrace();
  });

  test('队列按桌面与会话分开；forget 清掉某桌面的队列', () async {
    final h = Harness()..buffer.live = true;
    h.queue.add('d', 's', text: '一');
    h.buffers['t'] = SessionBuffer('d', 't')..live = true;
    h.queue.add('d', 't', text: '二');
    expect(h.queue.messages('d', 's').single.text, '一');
    expect(h.queue.messages('d', 't').single.text, '二');
    h.queue.forget('d');
    expect(h.queue.messages('d', 's'), isEmpty);
    expect(h.queue.messages('d', 't'), isEmpty);
  });

  test('dispose 后不再发送', () async {
    final h = Harness()..buffer.live = true;
    h.add('x');
    h.queue.dispose();
    h.buffer.live = false;
    h.queue.drain('d', 's');
    await h.settle();
    expect(h.sent, isEmpty);
  });
}
