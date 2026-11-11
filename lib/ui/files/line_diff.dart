import 'dart:typed_data';

enum LineChange { context, added, removed }

class ChangedLine {
  const ChangedLine(this.kind, this.text, this.before, this.after);
  final LineChange kind;
  final String text;
  final int? before;
  final int? after;
}

/// 每段连续改动的首行下标；相邻的删除和新增算同一处改动。
List<int> changeStarts(List<ChangedLine> lines) => [
  for (var i = 0; i < lines.length; i++)
    if (lines[i].kind != LineChange.context &&
        (i == 0 || lines[i - 1].kind == LineChange.context))
      i,
];

/// 改动超过这么多行就不再逐行对齐，中间整段算删了再加：再多也看不过来，
/// 对齐的花费却随它的平方涨。
const _maxEdits = 1000;

List<ChangedLine> lineDiff(String before, String after) {
  final a = before.isEmpty ? <String>[] : before.split('\n');
  final b = after.isEmpty ? <String>[] : after.split('\n');
  var prefix = 0;
  while (prefix < a.length && prefix < b.length && a[prefix] == b[prefix]) {
    prefix++;
  }
  var suffix = 0;
  while (suffix < a.length - prefix &&
      suffix < b.length - prefix &&
      a[a.length - suffix - 1] == b[b.length - suffix - 1]) {
    suffix++;
  }
  final x = a.sublist(prefix, a.length - suffix);
  final y = b.sublist(prefix, b.length - suffix);
  final middle =
      _myers(x, y) ??
      [
        for (final _ in x) LineChange.removed,
        for (final _ in y) LineChange.added,
      ];
  final output = [
    for (var i = 0; i < prefix; i++)
      ChangedLine(LineChange.context, a[i], i + 1, i + 1),
  ];
  var i = prefix, j = prefix;
  for (final change in middle) {
    switch (change) {
      case LineChange.context:
        output.add(ChangedLine(change, a[i], i + 1, j + 1));
        i++;
        j++;
      case LineChange.removed:
        output.add(ChangedLine(change, a[i], i + 1, null));
        i++;
      case LineChange.added:
        output.add(ChangedLine(change, b[j], null, j + 1));
        j++;
    }
  }
  for (; i < a.length; i++, j++) {
    output.add(ChangedLine(LineChange.context, a[i], i + 1, j + 1));
  }
  return output;
}

/// Myers 的最短编辑：花费随改动多少涨，不随文件长短涨；改动超过
/// [_maxEdits] 时是 null。
List<LineChange>? _myers(List<String> a, List<String> b) {
  final n = a.length, m = b.length;
  final limit = n + m < _maxEdits ? n + m : _maxEdits;
  final offset = limit + 1;
  final v = Int32List(2 * limit + 3);
  final trace = <Int32List>[];
  for (var d = 0; d <= limit; d++) {
    trace.add(Int32List.fromList(v));
    for (var k = -d; k <= d; k += 2) {
      var x = k == -d || (k != d && v[offset + k - 1] < v[offset + k + 1])
          ? v[offset + k + 1]
          : v[offset + k - 1] + 1;
      var y = x - k;
      while (x < n && y < m && a[x] == b[y]) {
        x++;
        y++;
      }
      v[offset + k] = x;
      if (x >= n && y >= m) return _path(trace, offset, n, m);
    }
  }
  return null;
}

List<LineChange> _path(List<Int32List> trace, int offset, int n, int m) {
  final changes = <LineChange>[];
  var x = n, y = m;
  for (var d = trace.length - 1; d >= 0; d--) {
    final v = trace[d];
    final k = x - y;
    final previous =
        k == -d || (k != d && v[offset + k - 1] < v[offset + k + 1])
        ? k + 1
        : k - 1;
    final previousX = v[offset + previous];
    final previousY = previousX - previous;
    while (x > previousX && y > previousY) {
      changes.add(LineChange.context);
      x--;
      y--;
    }
    if (d > 0) {
      changes.add(x == previousX ? LineChange.added : LineChange.removed);
    }
    x = previousX;
    y = previousY;
  }
  return changes.reversed.toList();
}
