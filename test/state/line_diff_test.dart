import 'package:baocode_mobile/ui/files/line_diff.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('新增空文件基线不产生虚假的删除空行', () {
    final diff = lineDiff('', '第一行\n第二行');
    expect(diff.map((line) => line.kind), [LineChange.added, LineChange.added]);
    expect(diff.map((line) => line.after), [1, 2]);
    expect(lineDiff('', ''), isEmpty);
  });
  test('diff preserves exact before and after line streams', () {
    const before = 'first\nold\nlast';
    const after = 'first\nnew\nlast';
    final diff = lineDiff(before, after);
    expect(
      diff
          .where((line) => line.kind != LineChange.added)
          .map((line) => line.text)
          .join('\n'),
      before,
    );
    expect(
      diff
          .where((line) => line.kind != LineChange.removed)
          .map((line) => line.text)
          .join('\n'),
      after,
    );
    expect(diff.where((line) => line.kind == LineChange.added).single.after, 2);
    expect(
      diff.where((line) => line.kind == LineChange.removed).single.before,
      2,
    );
  });

  String side(List<ChangedLine> diff, LineChange skip) => diff
      .where((line) => line.kind != skip)
      .map((line) => line.text)
      .join('\n');

  test('大文件里相隔很远的几处小改动，只标出改了的那几行', () {
    final lines = List.generate(1000, (i) => 'line $i');
    final before = lines.join('\n');
    final after =
        ([...lines]
              ..[900] = 'changed 900'
              ..insertAll(100, ['new a', 'new b']))
            .join('\n');
    final diff = lineDiff(before, after);
    expect(side(diff, LineChange.added), before);
    expect(side(diff, LineChange.removed), after);
    expect(
      [
        for (final line in diff)
          if (line.kind != LineChange.context) line.text,
      ],
      ['new a', 'new b', 'line 900', 'changed 900'],
    );
    expect(changeStarts(diff), hasLength(2));
  });

  test('改得太多时整段算删了再加，文字一行不丢', () {
    final before = List.generate(3000, (i) => 'old $i').join('\n');
    final after = List.generate(3000, (i) => 'new $i').join('\n');
    final diff = lineDiff(before, after);
    expect(side(diff, LineChange.added), before);
    expect(side(diff, LineChange.removed), after);
  });
}
