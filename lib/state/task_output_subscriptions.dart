import 'dart:async';

import 'package:bao_link/bao_link.dart';

import 'session_subscriptions.dart' show SessionRequest, SessionTr;

typedef TaskOutputKey = (String, String, String);

class TaskOutputBuffer {
  String text = '';
  int offset = 0;
  bool loading = false, polling = false;
  String? error;
}

/// 每个电脑、会话和任务共享一个订阅；只重试读取，绝不重放写操作。
class TaskOutputSubscriptions {
  TaskOutputSubscriptions({
    required this.request,
    required this.isOnline,
    required this.onChanged,
    required this.tr,
  });

  final SessionRequest request;
  final bool Function(String desktop) isOnline;
  final void Function() onChanged;
  final SessionTr tr;
  final _buffers = <TaskOutputKey, TaskOutputBuffer>{};
  final _references = <TaskOutputKey, int>{};
  final _operations = <TaskOutputKey, _OutputRead>{};
  final _queues = <TaskOutputKey, Future<void>>{};
  final _timers = <TaskOutputKey, Timer>{};
  final _retryTimers = <TaskOutputKey, Timer>{};
  final _retryAttempts = <TaskOutputKey, int>{};
  bool _disposed = false;

  TaskOutputBuffer buffer(String desktop, String session, String task) =>
      _buffers.putIfAbsent((desktop, session, task), TaskOutputBuffer.new);

  TaskOutputBuffer? peek(String desktop, String session, String task) =>
      _buffers[(desktop, session, task)];

  Future<void> retain(String desktop, String session, String task) {
    if (_disposed) throw StateError('任务输出订阅已关闭');
    final key = (desktop, session, task);
    _references.update(key, (n) => n + 1, ifAbsent: () => 1);
    if (_references[key]! > 1) {
      return _operations[key]?.done.future ?? Future<void>.value();
    }
    return refresh(desktop, session, task);
  }

  Future<void> release(String desktop, String session, String task) async {
    final key = (desktop, session, task);
    final count = _references[key];
    if (count == null) return;
    if (count > 1) {
      _references[key] = count - 1;
      return;
    }
    _references.remove(key);
    _invalidate(key);
    await _enqueue(key, () async {
      try {
        if (_disposed || !isOnline(desktop)) return;
        await request(desktop, LinkMethods.unwatchOutput, {
          'session': session,
          'task': task,
        });
      } on LinkClosedException {
        // 连接关闭时，桌面已释放该连接的订阅。
      } on LinkRemoteException catch (error) {
        if (error.code != LinkErrors.unknown &&
            error.code != LinkErrors.unsupported) {
          _buffers[key]?.error = tr(
            '输出没有更新，请重试',
            'Could not refresh the output. Try again.',
          );
          if (!_disposed) onChanged();
        }
      } on Object {
        _buffers[key]?.error = tr(
          '输出没有更新，请重试',
          'Could not refresh the output. Try again.',
        );
        if (!_disposed) onChanged();
      } finally {
        if (!_references.containsKey(key)) _buffers.remove(key);
      }
    });
  }

  Future<void> refresh(
    String desktop,
    String session,
    String task, {
    bool automatic = false,
  }) {
    final key = (desktop, session, task);
    if (_disposed || !_references.containsKey(key)) return Future<void>.value();
    final pending = _operations[key];
    if (pending != null) return pending.done.future;
    if (!automatic) {
      _retryTimers.remove(key)?.cancel();
      _retryAttempts.remove(key);
    }
    final target = buffer(desktop, session, task);
    if (!isOnline(desktop)) {
      target.error = tr('电脑离线', 'Desktop offline');
      onChanged();
      return Future<void>.value();
    }
    final operation = _OutputRead();
    _operations[key] = operation;
    target.loading = true;
    target.error = null;
    onChanged();
    unawaited(
      _enqueue(key, () async {
        var resync = false, retry = false;
        try {
          if (!_current(key, operation)) return;
          Object? result;
          if (!target.polling) {
            try {
              result = await request(desktop, LinkMethods.watchOutput, {
                'session': session,
                'task': task,
              });
            } on LinkRemoteException catch (error) {
              if (error.code != LinkErrors.unknown &&
                  error.code != LinkErrors.unsupported) {
                rethrow;
              }
              if (!_current(key, operation)) return;
              target.polling = true;
            }
          }
          if (target.polling) {
            result = await request(desktop, LinkMethods.output, {
              'session': session,
              'task': task,
            });
          }
          if (!_current(key, operation)) return;
          if (result is! Map || result['text'] is! String) {
            throw const FormatException('任务输出响应无效');
          }
          final text = result['text'] as String;
          final offset = target.polling ? text.length : result['offset'];
          if (offset is! int || offset < text.length) {
            throw const FormatException('任务输出偏移无效');
          }
          target.text = _tail(text);
          target.offset = offset;
          target.error = null;
          _retryAttempts.remove(key);
          for (final update in operation.updates) {
            if (!_apply(target, update)) resync = true;
          }
          resync |= operation.resync;
        } on Object catch (error) {
          if (_current(key, operation)) {
            target.error = tr(
              '输出没有更新，请重试',
              'Could not refresh the output. Try again.',
            );
            retry =
                !target.polling &&
                (error is TimeoutException ||
                    error is LinkClosedException ||
                    error is LinkRemoteException &&
                        (error.code == LinkErrors.unreachable ||
                            error.code == LinkErrors.busy));
          }
        } finally {
          if (_current(key, operation)) {
            _operations.remove(key);
            target.loading = false;
            if (target.polling) {
              _poll(key);
            } else if (retry) {
              _retry(key);
            }
            onChanged();
            if (resync) unawaited(refresh(desktop, session, task));
          }
          operation.done.complete();
        }
      }),
    );
    return operation.done.future;
  }

  static String _tail(String text) => text.length <= LinkLimits.output
      ? text
      : text.substring(text.length - LinkLimits.output);

  bool _apply(TaskOutputBuffer target, LinkOutput update) {
    if (update.offset < update.text.length) return false;
    if (update.reset) {
      target.text = _tail(update.text);
      target.offset = update.offset;
      return true;
    }
    if (update.offset <= target.offset) return true;
    final start = update.offset - update.text.length;
    if (start > target.offset) return false;
    target.text = _tail(
      target.text + update.text.substring(target.offset - start),
    );
    target.offset = update.offset;
    return true;
  }

  void accept(String desktop, Object? json) {
    if (_disposed || !isOnline(desktop)) return;
    final update = LinkOutput.fromJson(json);
    if (update == null) return;
    final key = (desktop, update.session, update.task);
    if (!_references.containsKey(key)) return;
    final operation = _operations[key];
    if (operation != null) {
      // 等快照时最多暂存有限批事件，过量时重新读取，不无限积压。
      if (operation.updates.length >= 100 ||
          update.text.length > LinkLimits.output) {
        operation.updates.clear();
        operation.resync = true;
      } else if (!operation.resync) {
        operation.updates.add(update);
      }
    } else if (!_apply(buffer(desktop, update.session, update.task), update)) {
      unawaited(refresh(desktop, update.session, update.task));
    }
    onChanged();
  }

  void _poll(TaskOutputKey key) {
    _timers.putIfAbsent(
      key,
      () => Timer.periodic(const Duration(seconds: 1), (_) {
        if (!_disposed && _references.containsKey(key) && isOnline(key.$1)) {
          unawaited(refresh(key.$1, key.$2, key.$3));
        }
      }),
    );
  }

  void _retry(TaskOutputKey key) {
    final attempt = _retryAttempts[key] ?? 0;
    if (attempt >= 3 || _retryTimers.containsKey(key)) return;
    _retryAttempts[key] = attempt + 1;
    // 只重试只读订阅，2/4/8 秒后停止；用户刷新可重新尝试。
    _retryTimers[key] = Timer(Duration(seconds: 2 << attempt), () {
      _retryTimers.remove(key);
      if (!_disposed && _references.containsKey(key) && isOnline(key.$1)) {
        unawaited(refresh(key.$1, key.$2, key.$3, automatic: true));
      }
    });
  }

  void _invalidate(TaskOutputKey key) {
    _operations.remove(key);
    _timers.remove(key)?.cancel();
    _retryTimers.remove(key)?.cancel();
    _retryAttempts.remove(key);
    _buffers[key]?.loading = false;
  }

  bool _current(TaskOutputKey key, _OutputRead operation) =>
      !_disposed &&
      isOnline(key.$1) &&
      _references.containsKey(key) &&
      identical(_operations[key], operation);

  // 同一任务的 watch/unwatch 串行，旧页面的取消不能覆盖新页面订阅。
  Future<void> _enqueue(TaskOutputKey key, Future<void> Function() action) {
    final next = (_queues[key] ?? Future<void>.value()).then((_) => action());
    _queues[key] = next;
    unawaited(
      next.then((_) {
        if (identical(_queues[key], next)) _queues.remove(key);
      }),
    );
    return next;
  }

  void connectionChanged(String desktop, {required bool online}) {
    for (final key
        in _references.keys.where((key) => key.$1 == desktop).toList()) {
      _invalidate(key);
      final target = _buffers[key];
      if (target != null) {
        target.polling = false;
        target.error = online ? null : tr('电脑离线', 'Desktop offline');
      }
      if (online) unawaited(refresh(key.$1, key.$2, key.$3));
    }
  }

  void forget(String desktop) {
    for (final key
        in _buffers.keys.where((key) => key.$1 == desktop).toList()) {
      _invalidate(key);
      _references.remove(key);
      _buffers.remove(key);
    }
  }

  void dispose() {
    _disposed = true;
    for (final timer in _timers.values) {
      timer.cancel();
    }
    for (final timer in _retryTimers.values) {
      timer.cancel();
    }
    _timers.clear();
    _retryTimers.clear();
    _retryAttempts.clear();
    _references.clear();
    _operations.clear();
    _buffers.clear();
  }
}

class _OutputRead {
  final done = Completer<void>();
  final updates = <LinkOutput>[];
  bool resync = false;
}
