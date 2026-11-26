import 'dart:convert';

import 'protocol.dart';

/// A session update as the desktop sends it after the first, slimmed
/// against what it sent before:
///
/// - `"partial": true`: of `live`, `interaction`, `choices`, `changes`,
///   `tasks`, `earlier`, `goal`, `context`, only those that changed are
///   there (null: gone);
/// - `"append": {"index", "path", "text"}`: the item at `index` (the one
///   before `start`) is as before but for `text` added at the end of the
///   string at `path` in it (keys and list indices); the items from `start`
///   follow whole as ever: the message streaming in (with the live line
///   after it), without sending all of it again each time.
///
/// [LinkSessionMirror] makes whole updates of these again on the phone.
abstract final class LinkSessionWire {
  static const rest = [
    'live',
    'interaction',
    'choices',
    'changes',
    'tasks',
    'earlier',
    'goal',
    'context',
    'quota',
  ];
}

/// The desktop's end of [LinkSessionWire]: slims a session's updates
/// against what it sent before.
class LinkSessionSlimmer {
  /// The rest as last sent, each field as JSON text.
  Map<String, String> _rest = const {};

  /// [update] for the wire: whole when [full]; else with only the rest
  /// that changed, and, when its first item is [before] (that item's JSON
  /// as sent last) with text added to one string of it, that text alone.
  Map<String, Object?> encode(
    LinkSessionUpdate update, {
    bool full = false,
    Object? before,
  }) {
    final json = update.toJson();
    final rest = {
      for (final key in LinkSessionWire.rest) key: jsonEncode(json[key]),
    };
    final previous = _rest;
    _rest = rest;
    if (full) return json;
    final slim = <String, Object?>{
      'session': update.session,
      'start': update.start,
      'count': update.count,
      'items': update.items,
      'partial': true,
      for (final key in LinkSessionWire.rest)
        if (rest[key] != previous[key]) key: json[key],
    };
    if (before != null && update.items.isNotEmpty) {
      if (jsonAppendPatch(before, update.items.first) case (
        final path,
        final text,
      )) {
        slim
          ..['start'] = update.start + 1
          ..['items'] = update.items.sublist(1)
          ..['append'] = {'index': update.start, 'path': path, 'text': text};
      }
    }
    return slim;
  }
}

/// A short digest of [json], the same on either end for the same raw
/// session item: two independent 32-bit hashes of its JSON text, in hex.
String linkDigest(Object? json) {
  final text = jsonEncode(json);
  var a = 0x811c9dc5;
  var b = 5381;
  for (var i = 0; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    a = _times((a ^ unit) & 0xffffffff, 0x01000193);
    b = (_times(b, 33) ^ unit) & 0xffffffff;
  }
  return a.toRadixString(16).padLeft(8, '0') +
      b.toRadixString(16).padLeft(8, '0');
}

/// 32-bit multiplication without exceeding the web's exact integer range.
int _times(int a, int b) {
  final low = (a & 0xffff) * b;
  final high = ((a >>> 16) * b) & 0xffff;
  return (low + (high << 16)) & 0xffffffff;
}

/// The phone's copy of each session, kept for one desktop across connections.
/// Chat items remain the raw JSON objects, not decoded presentation models.
class LinkSessionMirror {
  final Map<String, _Mirrored> _sessions = {};
  final Map<String, List<Object?>> _kept = {};
  static const _keptMost = 32;
  final Map<String, List<Object?>> _offered = {};

  /// The app's raw items from before, unless the session is followed already.
  void keep(String session, List<Object?> items) {
    if (_sessions.containsKey(session) || items.isEmpty) return;
    _keepAside(session, items);
  }

  void _keepAside(String session, List<Object?> items) {
    _kept
      ..remove(session)
      ..[session] = [...items];
    while (_kept.length > _keptMost) {
      _kept.remove(_kept.keys.first);
    }
  }

  /// What was offered for this particular open, before any later updates.
  List<String>? have(String session) {
    final items = _sessions[session]?.items ?? _kept[session];
    if (items == null || items.isEmpty) {
      _offered.remove(session);
      return null;
    }
    final offered = _offered[session] = [...items];
    return [for (final item in offered) linkDigest(item)];
  }

  /// Those closed since they were last opened: in-flight updates are stale.
  final Set<String> _closed = {};

  /// Discard an unusable baseline so the next open requests a full snapshot.
  void _forget(String session) {
    _sessions.remove(session);
    _kept.remove(session);
    _offered.remove(session);
  }

  /// An open answer with its offered prefix restored; null on a mismatch.
  Map<String, Object?>? opened(Map<String, Object?> update) {
    final session = update['session'];
    if (session is! String) return null;
    _closed.remove(session);
    final offered = _offered.remove(session) ?? const [];
    final start = update['start'];
    final count = update['count'];
    final items = update['items'];
    if (start is! int || count is! int || items is! List ||
        start < 0 || start > offered.length ||
        count != start + items.length ||
        update['partial'] == true || update['append'] != null) {
      _forget(session);
      return null;
    }
    final all = [...offered.take(start), ...items];
    _kept.remove(session);
    _sessions[session] = _Mirrored(
      [...all],
      {for (final key in LinkSessionWire.rest) key: update[key]},
    );
    return {...update, 'start': 0, 'items': all};
  }

  /// [items] put before the first (an `earlier` answer).
  void earlier(String session, List<Object?> items) {
    final mirrored = _sessions[session];
    if (mirrored != null) mirrored.items.insertAll(0, items);
  }

  void closed(String session) {
    if (_sessions.remove(session) case final mirrored?) {
      _keepAside(session, mirrored.items);
    }
    _offered.remove(session);
    _closed.add(session);
  }

  /// Whether [update] is of a session closed, sent before the desktop
  /// heard: to let go, not to apply nor to open the session again for.
  bool stale(Map<String, Object?> update) =>
      _closed.contains(update['session']);

  /// The whole update [update] makes: what the phone used to be sent, its
  /// items from the first that changed. Null when it does not fit the
  /// copy kept (some update was missed): the session should be opened
  /// again.
  Map<String, Object?>? apply(Map<String, Object?> update) {
    final whole = _apply(update);
    if (whole == null && update['session'] is String) {
      _forget(update['session']! as String);
    }
    return whole;
  }

  Map<String, Object?>? _apply(Map<String, Object?> update) {
    final session = update['session'];
    if (session is! String) return null;
    final partial = update['partial'] == true;
    var mirrored = _sessions[session];
    if (mirrored == null) {
      if (partial || update['append'] != null || update['start'] != 0) {
        return null;
      }
      mirrored = _sessions[session] = _Mirrored([], {});
    }
    final start = update['start'];
    final count = update['count'];
    final items = update['items'];
    if (start is! int || count is! int || items is! List) return null;
    if (start < 0 || start > mirrored.items.length) return null;
    final next = [...mirrored.items.take(start), ...items];
    var from = start;
    if (update['append'] case final Object append) {
      if (append
          case {
            'index': final int index,
            'path': final List<Object?> path,
            'text': final String text,
          }
          when index >= 0 && index < next.length) {
        final patched = applyAppend(next[index], path, text);
        if (patched == null) return null;
        next[index] = patched;
        if (index < from) from = index;
      } else {
        return null;
      }
    }
    if (next.length != count) return null;
    mirrored.items
      ..clear()
      ..addAll(next);
    if (partial) {
      for (final key in LinkSessionWire.rest) {
        if (update.containsKey(key)) mirrored.rest[key] = update[key];
      }
    } else {
      mirrored.rest = {
        for (final key in LinkSessionWire.rest) key: update[key],
      };
    }
    return {
      'session': session,
      'start': from,
      'count': count,
      'items': next.sublist(from),
      for (final MapEntry(:key, :value) in mirrored.rest.entries) key: ?value,
    };
  }
}

class _Mirrored {
  _Mirrored(this.items, this.rest);

  final List<Object?> items;
  Map<String, Object?> rest;
}

/// Where [after] differs from [before] by text added at the end of one
/// string in it: that string's path (keys, list indices) and the text.
/// Null when it differs otherwise, or not at all.
(List<Object>, String)? jsonAppendPatch(Object? before, Object? after) {
  if (before is String && after is String) {
    if (after.length > before.length && after.startsWith(before)) {
      return (const [], after.substring(before.length));
    }
    return null;
  }
  if (before is Map && after is Map) {
    if (before.length != after.length) return null;
    Object? differing;
    for (final key in after.keys) {
      if (!before.containsKey(key)) return null;
      if (!_same(before[key], after[key])) {
        if (differing != null) return null;
        differing = key;
      }
    }
    if (differing is! String) return null;
    final inner = jsonAppendPatch(before[differing], after[differing]);
    if (inner == null) return null;
    return ([differing, ...inner.$1], inner.$2);
  }
  if (before is List && after is List) {
    if (before.length != after.length) return null;
    int? differing;
    for (var i = 0; i < after.length; i++) {
      if (!_same(before[i], after[i])) {
        if (differing != null) return null;
        differing = i;
      }
    }
    if (differing == null) return null;
    final inner = jsonAppendPatch(before[differing], after[differing]);
    if (inner == null) return null;
    return ([differing, ...inner.$1], inner.$2);
  }
  return null;
}

/// [json] with [text] added to the string at [path]; null when there is
/// no string there. What is not on the path is shared, not copied.
Object? applyAppend(Object? json, List<Object?> path, String text) {
  if (path.isEmpty) return json is String ? json + text : null;
  final [step, ...rest] = path;
  switch ((json, step)) {
    case (final Map<String, Object?> map, final String key)
        when map.containsKey(key):
      final inner = applyAppend(map[key], rest, text);
      if (inner == null) return null;
      return {...map, key: inner};
    case (final List<Object?> list, final int index)
        when index >= 0 && index < list.length:
      final inner = applyAppend(list[index], rest, text);
      if (inner == null) return null;
      return [...list]..[index] = inner;
  }
  return null;
}

bool _same(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !_same(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_same(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}
