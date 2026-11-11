import 'dart:async';

import 'package:bao_link/bao_link.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Native DNS-SD adapter. Advertisements are hints, never trust decisions.
///
/// The native platform browses `_baocode._tcp` on discoveryStart and stops on
/// discoveryStop, using local.baocode.mobile/platform. Events on
/// local.baocode.mobile/discovery are resolved records
/// {name, port, attributes: {v, k, p}, addresses: [host, ...]}, or {lost: id}.
/// Errors are exposed, including missing platform implementations.
class DesktopDiscovery extends ChangeNotifier {
  static const _platform = MethodChannel('local.baocode.mobile/platform');
  static const _channel = EventChannel('local.baocode.mobile/discovery');
  final _nearby = <String, LinkAdvert>{};
  StreamSubscription<dynamic>? _subscription;
  bool _disposed = false;
  bool _running = false;
  Object? _error;

  List<LinkAdvert> get desktops => List.unmodifiable(_nearby.values);
  bool get running => _running;
  Object? get error => _error;

  Future<void> start() async {
    if (_disposed) throw StateError('DesktopDiscovery is disposed');
    if (_subscription != null) return;
    _error = null;
    _subscription = _channel.receiveBroadcastStream().listen(
      _receive,
      onError: (Object error) {
        if (_disposed) return;
        _error = error;
        _running = false;
        notifyListeners();
      },
    );
    try {
      await _platform.invokeMethod<void>('discoveryStart', {
        'type': LinkDiscovery.type,
      });
      if (_disposed || _subscription == null) return;
      _running = _error == null;
      notifyListeners();
    } catch (error) {
      await _subscription?.cancel();
      _subscription = null;
      if (!_disposed) {
        _error = error;
        _running = false;
        notifyListeners();
      }
      rethrow;
    }
  }

  /// Reads every nearby desktop's record again, restarting discovery if it
  /// stopped. Discovery reports only appearing and leaving desktops, not one
  /// that opens pairing.
  Future<void> refresh() async {
    if (_disposed) return;
    if (_running) {
      await _platform.invokeMethod<void>('discoveryRefresh');
      return;
    }
    if (_subscription != null && _error == null) return; // Starting.
    await stop();
    await start();
  }

  void _receive(dynamic event) {
    if (_disposed || event is! Map) return;
    if (event['lost'] case final String id) {
      if (_nearby.remove(id) != null) notifyListeners();
      return;
    }
    try {
      final advert = LinkAdvert.parse(
        name: event['name'] as String,
        port: event['port'] as int,
        attributes: Map<String, String>.from(event['attributes'] as Map),
        addresses: (event['addresses'] as List).cast<String>(),
      );
      if (advert == null) return;
      _nearby[advert.id] = advert;
      notifyListeners();
    } on Object {
      // Incomplete resolutions and non-BaoCode service records are ignored.
    }
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _running = false;
    _nearby.clear();
    try {
      await _platform.invokeMethod<void>('discoveryStop');
    } finally {
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(stop().catchError((Object _) {}));
    super.dispose();
  }
}
