import 'dart:convert';
import 'dart:typed_data';

import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/link/link_store.dart';
import 'package:baocode_mobile/state/app_state.dart';
import 'package:baocode_mobile/state/conversation_input.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('编辑定位只认消息本身：换会话或内容变了拒绝，修订号变化不算', () {
    final buffer = SessionBuffer('a', 's')
      ..items.add({'t': 'user', 'text': 'old'});
    final anchor = MessageEditAnchor.capture(buffer, 0);
    expect(anchor.matches(buffer), isTrue);
    final other = SessionBuffer('a', 'other')
      ..items.add({'t': 'user', 'text': 'old'});
    expect(anchor.matches(other), isFalse);
    buffer.items[0] = {'t': 'user', 'text': 'other'};
    expect(anchor.matches(buffer), isFalse);
    buffer.items[0] = {'t': 'user', 'text': 'old'};
    buffer.revision++;
    expect(anchor.matches(buffer), isTrue);
  });

  group('编辑定位随同步判断是否失效', () {
    LinkSessionUpdate update(int start, List<Object?> items) =>
        LinkSessionUpdate(
          session: 's',
          start: start,
          count: start + items.length,
          items: items,
          live: true,
        );
    Map<String, Object?> msg(String t) => {'t': 'user', 'text': t};
    Map<String, Object?> timed(String t, int at) => {
      't': 'user',
      'text': t,
      'at': at,
    };

    SessionBuffer seeded() =>
        SessionBuffer('a', 's')
          ..apply(update(0, [msg('0'), msg('1'), msg('2')]), snapshot: true);

    test('运行中只改写被编辑条之后的尾部不失效', () {
      final buffer = seeded();
      final anchor = MessageEditAnchor.capture(buffer, 1);
      buffer.apply(update(2, [msg('2b')]));
      buffer.apply(update(3, [msg('3')]));
      expect(anchor.locate(buffer), 1);
    });

    test('重发同样的内容不失效：选图回来的快照和增量都一样', () {
      final buffer = seeded();
      final anchor = MessageEditAnchor.capture(buffer, 1);
      buffer.apply(update(1, [msg('1'), msg('2')]));
      expect(anchor.locate(buffer), 1);
      buffer.apply(update(0, [msg('0'), msg('1'), msg('2')]), snapshot: true);
      expect(anchor.locate(buffer), 1);
    });

    test('回合结束写回耗时和用量不算消息变化', () {
      final buffer = seeded();
      final anchor = MessageEditAnchor.capture(buffer, 1);
      buffer.apply(
        update(1, [
          {
            ...msg('1'),
            'worked': 1200,
            'usage': {'in': 1, 'out': 2},
          },
        ]),
      );
      expect(anchor.locate(buffer), 1);
    });

    test('长回复产生大量修订也不失效', () {
      final buffer = seeded();
      final anchor = MessageEditAnchor.capture(buffer, 0);
      for (var i = 0; i < 1001; i++) {
        buffer.apply(update(2, [msg('t$i')]));
      }
      expect(anchor.locate(buffer), 0);
    });

    test('消息真的变了失效，同步后也一样', () {
      final buffer = seeded();
      final anchor = MessageEditAnchor.capture(buffer, 1);
      buffer.apply(
        update(0, [msg('0'), msg('电脑上改过'), msg('2')]),
        snapshot: true,
      );
      expect(anchor.locate(buffer), isNull);
    });

    test('没有发送时间时，更早的用户消息变了就失效', () {
      final buffer = seeded();
      final anchor = MessageEditAnchor.capture(buffer, 2);
      buffer.apply(update(0, [msg('电脑上改过'), msg('1'), msg('2')]));
      expect(anchor.locate(buffer), isNull);
    });

    test('没有发送时间时，向前加载历史整体移位后失效', () {
      final buffer = seeded();
      final anchor = MessageEditAnchor.capture(buffer, 0);
      buffer.prepend({
        'items': [msg('old')],
        'earlier': false,
      });
      expect(anchor.locate(buffer), isNull);
    });

    test('有发送时间时，窗口移位后跟到新位置', () {
      final buffer = SessionBuffer('a', 's')
        ..apply(
          update(0, [timed('0', 10), timed('1', 20), timed('2', 30)]),
          snapshot: true,
        );
      final anchor = MessageEditAnchor.capture(buffer, 1);
      buffer.prepend({
        'items': [timed('old', 5)],
        'earlier': false,
      });
      expect(anchor.locate(buffer), 2);
      buffer.apply(update(0, [timed('1', 20), timed('2', 30)]), snapshot: true);
      expect(anchor.locate(buffer), 0);
    });

    test('有发送时间时，消息已不在窗口里或被回退后重发都失效', () {
      final buffer = SessionBuffer('a', 's')
        ..apply(update(0, [timed('0', 10), timed('1', 20)]), snapshot: true);
      final anchor = MessageEditAnchor.capture(buffer, 1);
      buffer.apply(update(0, [timed('0', 10), timed('1', 99)]), snapshot: true);
      expect(anchor.locate(buffer), isNull);
      buffer.apply(update(0, [timed('0', 10)]), snapshot: true);
      expect(anchor.locate(buffer), isNull);
    });

    test('有发送时间时，同样的消息出现两条无法确定就失效', () {
      final buffer = SessionBuffer('a', 's')
        ..apply(update(0, [timed('1', 20)]), snapshot: true);
      final anchor = MessageEditAnchor.capture(buffer, 0);
      buffer.apply(update(1, [timed('1', 20)]));
      expect(anchor.locate(buffer), isNull);
    });
  });

  test('发送只移除本次内容，保留新的文字、引用和附件', () {
    final oldImage = DraftImage('old.png', 'image/png', Uint8List(1));
    final newImage = DraftImage('new.png', 'image/png', Uint8List(2));
    final sent = InputDraft(
      text: 'first',
      images: [oldImage],
      mentions: const {'old.dart'},
    );
    final current = InputDraft(
      text: '@new.dart next',
      images: [oldImage, newImage],
      mentions: const {'old.dart', 'new.dart'},
    );
    final remaining = current.afterSending(sent);
    expect(remaining.text, '@new.dart next');
    expect(remaining.images, [newImage]);
    expect(remaining.mentions, {'new.dart'});
  });

  test('旧文字草稿只按用户编辑写新键，Bot 空草稿不能复活旧会话内容', () async {
    final store = MemoryLinkStore();
    final oldKey = jsonEncode(['a', 'old-session']);
    await store.write('drafts', jsonEncode({oldKey: 'legacy'}));
    final state = AppState(store: store, demo: true);
    addTearDown(state.dispose);
    await state.initialize();
    expect(
      state.inputDraft('a', 'bot:b', legacySessionId: 'old-session').text,
      'legacy',
    );
    await state.saveInputDraft('a', 'bot:b', const InputDraft());
    expect(
      state.inputDraft('a', 'bot:b', legacySessionId: 'old-session').text,
      '',
    );
    final saved = jsonDecode((await store.read('drafts'))!) as Map;
    expect(saved[oldKey], 'legacy');
    expect(saved[jsonEncode(['a', 'bot:b'])]['text'], '');
  });

  test('附件跨页面留在内存，落盘只有缺失提示元数据，不写图片字节', () async {
    final store = MemoryLinkStore();
    final state = AppState(store: store, demo: true);
    await state.initialize();
    final image = DraftImage(
      'sample.png',
      'image/png',
      Uint8List.fromList([1, 2, 3]),
    );
    await state.saveInputDraft(
      'a',
      'bot:b',
      InputDraft(text: 'hi', images: [image], mentions: const {'a.dart'}),
    );
    expect(state.inputDraft('a', 'bot:b').images.single, same(image));
    expect(state.inputDraft('b', 'bot:b').text, isEmpty);
    final stored = (await store.read('drafts'))!;
    expect(stored, isNot(contains('AQID')));
    state.dispose();
    final reopened = AppState(store: store, demo: true);
    addTearDown(reopened.dispose);
    await reopened.initialize();
    expect(reopened.inputDraft('a', 'bot:b').text, 'hi');
    expect(reopened.inputDraft('a', 'bot:b').mentions, {'a.dart'});
    expect(reopened.inputDraft('a', 'bot:b').images, isEmpty);
    expect(reopened.inputDraft('a', 'bot:b').imagesMissing, isTrue);
  });
}
