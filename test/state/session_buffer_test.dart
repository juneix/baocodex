import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/models/session_buffer.dart';
import 'package:flutter_test/flutter_test.dart';

LinkSessionUpdate delta(
  int start,
  List<Object?> items, {
  int? count,
  bool? earlier,
}) => LinkSessionUpdate(
  session: 'session',
  start: start,
  count: count ?? start + items.length,
  items: items,
  earlier: earlier,
);

void main() {
  test('unknown wire entries keep their original edit indexes', () {
    final buffer = SessionBuffer('desktop', 'session');
    buffer.apply(
      delta(0, [
        null,
        {'t': 'future'},
        {'t': 'user', 'text': 'third'},
      ]),
      snapshot: true,
    );
    expect(buffer.items.length, 3);
    expect((buffer.items[2] as Map)['text'], 'third');
  });

  test('a delta replaces from its start and truncates a rewound tail', () {
    final buffer = SessionBuffer('desktop', 'session');
    buffer.apply(delta(0, [1, 2, 3, 4]), snapshot: true);
    buffer.apply(delta(1, [9]));
    expect(buffer.items, [1, 9]);
  });

  test('history prepend changes the base for following deltas', () {
    final buffer = SessionBuffer('desktop', 'session');
    buffer.apply(delta(0, [3, 4], earlier: true), snapshot: true);
    buffer.prepend({
      'items': [1, 2],
      'earlier': false,
    });
    buffer.apply(delta(3, [5]));
    expect(buffer.items, [1, 2, 3, 5]);
  });

  test(
    'invalid sparse or inconsistent updates fail without changing history',
    () {
      final buffer = SessionBuffer('desktop', 'session');
      buffer.apply(delta(0, [1]), snapshot: true);
      expect(() => buffer.apply(delta(4, [5])), throwsFormatException);
      expect(
        () => buffer.apply(delta(0, [2], count: 4)),
        throwsFormatException,
      );
      expect(buffer.items, [1]);
    },
  );

  test('a snapshot cannot silently apply to a different session', () {
    final buffer = SessionBuffer('desktop', 'session');
    expect(
      () => buffer.apply(
        const LinkSessionUpdate(
          session: 'another',
          start: 0,
          count: 0,
          items: [],
        ),
        snapshot: true,
      ),
      throwsFormatException,
    );
  });
}
