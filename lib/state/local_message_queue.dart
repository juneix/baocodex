// YCode — GPL-3.0-only.
import 'dart:async';

import 'package:bao_link/bao_link.dart';

import '../models/session_buffer.dart';
import 'conversation_input.dart';

typedef QueueTr = String Function(String zh, String en);

/// Sends one queued message; the answer is the session it went to, as
/// `AppState.sendMessage` gives it.
typedef QueueSend = Future<String?> Function(
  String desktopId, {
  String? session,
  String? project,
  String? bot,
  required String text,
  List<Map<String, Object?>> images,
  List<String> mentions,
  bool now,
  String? id,
});

/// A message the user wrote while the agent was working. It waits on the
/// phone — the desktop knows nothing of it — and `id` is its own on the wire,
/// so one sent twice (its answer lost) is taken once.
class LocalQueuedMessage {
  const LocalQueuedMessage({
    required this.id,
    required this.text,
    this.images = const [],
    this.mentions = const [],
    this.project,
    this.bot,
  });

  final String id, text;
  final List<DraftImage> images;
  final List<String> mentions;
  final String? project, bot;
}

/// The messages sent from the phone while a turn runs, kept in memory per
/// conversation (they outlive the chat page, not the app). When the turn has
/// ended they go out one at a time, in order; the next waits for the one
/// just sent to start its turn. What cannot be sent stays, with the reason.
class LocalMessageQueue {
  LocalMessageQueue({
    required this.isOnline,
    required this.bufferOf,
    required this.send,
    required this.onChanged,
    required this.tr,
    this.startGrace = const Duration(seconds: 4),
  });

  final bool Function(String desktopId) isOnline;
  final SessionBuffer Function(String desktopId, String sessionId) bufferOf;
  final QueueSend send;
  final void Function() onChanged;
  final QueueTr tr;

  /// How long a sent message is given to start its turn before the next may
  /// go; a turn that began and ended between two updates is never seen live.
  final Duration startGrace;

  final _lanes = <(String, String), _Lane>{};
  int _serial = 0;
  bool _disposed = false;

  List<LocalQueuedMessage> messages(String desktopId, String sessionId) =>
      List.unmodifiable(_lanes[(desktopId, sessionId)]?.items ?? const []);

  /// Sent to go now, and not in the conversation yet: the desktop holds it
  /// behind the call under way (or its background tasks) and lists it
  /// nowhere the phone sees, so the chat shows it from here meanwhile.
  List<LocalQueuedMessage> inserting(String desktopId, String sessionId) => [
    for (final (message, _)
        in _lanes[(desktopId, sessionId)]?.inserting ??
            const <(LocalQueuedMessage, int)>[])
      message,
  ];

  /// Why the queue is not going out, until it does; null otherwise.
  String? failure(String desktopId, String sessionId) =>
      _lanes[(desktopId, sessionId)]?.failure;

  /// A message is on its way; the queue cannot be changed meanwhile.
  bool busy(String desktopId, String sessionId) =>
      _lanes[(desktopId, sessionId)]?.sending ?? false;

  LocalQueuedMessage add(
    String desktopId,
    String sessionId, {
    required String text,
    List<DraftImage> images = const [],
    List<String> mentions = const [],
    String? project,
    String? bot,
  }) {
    final message = LocalQueuedMessage(
      id: 'phone-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${_serial++}',
      text: text,
      images: List.unmodifiable(images),
      mentions: List.unmodifiable(mentions),
      project: project,
      bot: bot,
    );
    _lanes.putIfAbsent((desktopId, sessionId), _Lane.new).items.add(message);
    onChanged();
    drain(desktopId, sessionId);
    return message;
  }

  /// Takes [id] off the queue, to edit it or drop it; null when it is not
  /// there or is being sent.
  LocalQueuedMessage? take(String desktopId, String sessionId, String id) {
    final key = (desktopId, sessionId);
    final lane = _lanes[key];
    if (lane == null || lane.sending) return null;
    final index = lane.items.indexWhere((message) => message.id == id);
    if (index < 0) return null;
    final message = lane.items.removeAt(index);
    _tidy(key, lane);
    onChanged();
    return message;
  }

  /// Sends [id] now, the turn running stopped for it. False when it was not
  /// sent: the reason is the queue's [failure].
  Future<bool> sendNow(String desktopId, String sessionId, String id) async {
    final lane = _lanes[(desktopId, sessionId)];
    if (lane == null || lane.sending) return false;
    final message = lane.items.where((item) => item.id == id).firstOrNull;
    if (message == null) return false;
    if (!isOnline(desktopId)) {
      lane.failure = _offline();
      onChanged();
      return false;
    }
    return _dispatch((desktopId, sessionId), lane, message, now: true);
  }

  /// Goes on after a failure, as the user asked.
  void retry(String desktopId, String sessionId) {
    final lane = _lanes[(desktopId, sessionId)];
    if (lane == null) return;
    lane
      ..blocked = false
      ..failure = null;
    onChanged();
    drain(desktopId, sessionId);
  }

  /// Sends the first message if the turn has ended and nothing holds it.
  /// Safe to call at any time and from anywhere: it does nothing unless
  /// everything is in order.
  void drain(String desktopId, String sessionId) {
    if (_disposed) return;
    final key = (desktopId, sessionId);
    final lane = _lanes[key];
    if (lane == null) return;
    final buffer = bufferOf(desktopId, sessionId);
    // Taken up once a message of the user's more is in the conversation; or
    // given up on, the turn over and none to show for it.
    final users = _userMessages(buffer);
    lane.inserting.removeWhere(
      (entry) =>
          users > entry.$2 ||
          (!buffer.live && !buffer.loading && !lane.awaitingStart),
    );
    _tidy(key, lane);
    if (buffer.live) {
      // A turn is running; a failure may be tried again when it ends. The
      // one just sent has begun — unless it was sent over the turn already
      // running, whose liveness says nothing of it: that waits out the grace.
      lane.blocked = false;
      if (lane.liveStartsIt) {
        lane.awaitingStart = false;
        lane.startTimer?.cancel();
        lane.startTimer = null;
      }
      _tidy(key, lane);
      return;
    }
    if (lane.items.isEmpty ||
        lane.sending ||
        lane.blocked ||
        lane.awaitingStart ||
        !isOnline(desktopId) ||
        buffer.loading ||
        buffer.error != null) {
      return;
    }
    unawaited(_dispatch(key, lane, lane.items.first, now: false));
  }

  void drainAll() {
    for (final key in _lanes.keys.toList()) {
      drain(key.$1, key.$2);
    }
  }

  /// A desktop came back: what failed on the way may be tried again.
  void reconnected(String desktopId) {
    for (final entry in _lanes.entries) {
      if (entry.key.$1 == desktopId) entry.value.blocked = false;
    }
  }

  void forget(String desktopId) {
    for (final key
        in _lanes.keys.where((key) => key.$1 == desktopId).toList()) {
      _lanes.remove(key)?.startTimer?.cancel();
    }
  }

  void dispose() {
    _disposed = true;
    for (final lane in _lanes.values) {
      lane.startTimer?.cancel();
    }
    _lanes.clear();
  }

  Future<bool> _dispatch(
    (String, String) key,
    _Lane lane,
    LocalQueuedMessage message, {
    required bool now,
  }) async {
    lane
      ..sending = true
      ..failure = null;
    onChanged();
    var sent = false;
    try {
      final actual = await send(
        key.$1,
        session: key.$2,
        project: message.project,
        bot: message.bot,
        text: message.text,
        images: [for (final image in message.images) image.wire],
        mentions: message.mentions,
        now: now,
        id: message.id,
      );
      if (actual == null) {
        throw StateError(
          tr('电脑返回的会话未确认', 'The desktop did not confirm the conversation'),
        );
      }
      sent = true;
      lane.items.remove(message);
      if (now) {
        lane.inserting.add((message, _userMessages(bufferOf(key.$1, key.$2))));
      }
      // Its turn has not shown yet: the next waits for it.
      lane.awaitingStart = true;
      lane.liveStartsIt = !now;
      lane.startTimer?.cancel();
      lane.startTimer = Timer(startGrace, () {
        lane.startTimer = null;
        lane.awaitingStart = false;
        drain(key.$1, key.$2);
        _tidy(key, lane);
        onChanged();
      });
    } on Object catch (error) {
      lane
        ..blocked = true
        ..failure = error is LinkClosedException || error is TimeoutException
            ? tr(
                '连接中断，排队消息已保留；重连后继续发送，不会重复。',
                'The connection dropped. Queued messages are kept and sent after reconnecting, without duplicates.',
              )
            : tr(
                '排队消息发送失败，已保留在队列。',
                'A queued message was not sent and is kept in the queue.',
              );
    } finally {
      lane.sending = false;
      _tidy(key, lane);
      if (!_disposed) onChanged();
    }
    return sent;
  }

  String _offline() => tr(
    '未连接电脑，排队消息已保留，连上后继续发送。',
    'Not connected. Queued messages are kept and sent once connected.',
  );

  /// The user's messages taken up in [buffer]'s conversation.
  static int _userMessages(SessionBuffer buffer) => buffer.items
      .where(
        (item) => item is Map && item['t'] == 'user' && item['queued'] != true,
      )
      .length;

  /// A lane with nothing to send and nothing awaited is forgotten.
  void _tidy((String, String) key, _Lane lane) {
    if (lane.items.isEmpty) lane.failure = null;
    if (lane.items.isEmpty &&
        lane.inserting.isEmpty &&
        !lane.sending &&
        !lane.awaitingStart) {
      lane.startTimer?.cancel();
      if (identical(_lanes[key], lane)) _lanes.remove(key);
    }
  }
}

class _Lane {
  final items = <LocalQueuedMessage>[];

  /// Sent to go now, with how many of the user's messages the conversation
  /// had then.
  final inserting = <(LocalQueuedMessage, int)>[];
  bool sending = false, blocked = false, awaitingStart = false;
  bool liveStartsIt = true;
  String? failure;
  Timer? startTimer;
}
