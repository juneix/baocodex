import 'dart:convert';

import 'package:flutter/foundation.dart';

/// The link request funnel, normally [AppState.request].
typedef LinkRequest = Future<Object?> Function(
  String desktopId,
  String method,
  Map<String, Object?> params,
);

/// Requests small pictures (project icons, bot avatars) over the link and
/// keeps the decoded bytes in a memory cache, so scrolling between pages does
/// not re-request the same picture and concurrent widgets share one call.
///
/// The server side is the public protocol: `icon` takes `{"id"}` and
/// `botAvatar` takes `{"bot"}`; both answer `{"data" (base64), "type"}`.
class IconCache {
  IconCache({this.maxEntries = 128});

  final int maxEntries;
  final Map<String, Uint8List> _bytes = {};
  final Map<String, Future<Uint8List?>> _inFlight = {};

  static String keyOf(String desktopId, String method, String id) =>
      '$desktopId\u0000$method\u0000$id';

  /// Cached bytes, or a single shared request; failures return null instead
  /// of throwing so callers can fall back to a letter/emoji placeholder.
  Future<Uint8List?> get(
    String desktopId,
    String method,
    String id, {
    Map<String, Object?> params = const {},
    required LinkRequest request,
  }) {
    final key = keyOf(desktopId, method, id);
    final cached = _bytes[key];
    if (cached != null) {
      // Refresh recency for the eviction order.
      _bytes.remove(key);
      _bytes[key] = cached;
      return SynchronousFuture<Uint8List?>(cached);
    }
    return _inFlight.putIfAbsent(
      key,
      () => _fetch(desktopId, method, id, key, params, request),
    );
  }

  Future<Uint8List?> _fetch(
    String desktopId,
    String method,
    String id,
    String key,
    Map<String, Object?> params,
    LinkRequest request,
  ) async {
    try {
      final result = await request(desktopId, method, params);
      if (result is! Map) return null;
      final data = result['data'];
      if (data is! String || data.isEmpty) return null;
      final Uint8List bytes;
      try {
        bytes = base64Decode(data);
      } on FormatException {
        return null;
      }
      _bytes[key] = bytes;
      while (_bytes.length > maxEntries) {
        _bytes.remove(_bytes.keys.first);
      }
      return bytes;
    } on Object {
      // Offline, notFound, corrupt payload: the placeholder stays.
      return null;
    } finally {
      _inFlight.remove(key);
    }
  }

  /// Drops everything a forgotten desktop might still be showing.
  void invalidateDesktop(String desktopId) {
    final prefix = '$desktopId\u0000';
    _bytes.removeWhere((key, _) => key.startsWith(prefix));
  }
}
