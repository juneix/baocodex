import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/state/bot_notice_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

LinkBotNotice notice(int id, {String kind = 'done'}) => LinkBotNotice(
  id: id,
  kind: kind,
  chat: 'chat-$id',
  title: '任务 $id',
  project: 'p',
);

LinkBot bot(List<LinkBotNotice> notices, {String id = 'b1'}) =>
    LinkBot(id: id, name: '小宝', notices: notices);

List<int> ids(List<LinkBotNotice> list) => [for (final n in list) n.id];

void main() {
  test('首次观测只建立水位，不返回历史通知', () {
    final tracker = BotNoticeTracker();
    expect(tracker.accept('d', bot([notice(1), notice(2)])), isEmpty);
  });

  test('同一快照重复到达不再返回', () {
    final tracker = BotNoticeTracker();
    tracker.accept('d', bot([notice(1)]));
    expect(tracker.accept('d', bot([notice(1)])), isEmpty);
    expect(ids(tracker.accept('d', bot([notice(1), notice(2)]))), [2]);
    expect(tracker.accept('d', bot([notice(1), notice(2)])), isEmpty);
  });

  test('乱序和重复 ID 按 ID 升序各返回一次', () {
    final tracker = BotNoticeTracker();
    tracker.accept('d', bot([notice(2)]));
    final fresh = tracker.accept(
      'd',
      bot([notice(5), notice(3), notice(5), notice(2)]),
    );
    expect(ids(fresh), [3, 5]);
    expect(tracker.accept('d', bot([notice(5), notice(3)])), isEmpty);
  });

  test('不同电脑、不同 Bot 的相同 ID 互相独立', () {
    final tracker = BotNoticeTracker();
    tracker.accept('d1', bot([notice(3)]));
    tracker.accept('d2', bot([]));
    tracker.accept('d1', bot([], id: 'b2'));
    expect(ids(tracker.accept('d2', bot([notice(3)]))), [3]);
    expect(ids(tracker.accept('d1', bot([notice(3)], id: 'b2'))), [3]);
    expect(tracker.accept('d1', bot([notice(3)])), isEmpty);
  });

  test('首个快照没有 notices 时之后出现的新通知可返回', () {
    final tracker = BotNoticeTracker();
    expect(tracker.accept('d', bot(const [])), isEmpty);
    expect(ids(tracker.accept('d', bot([notice(1)]))), [1]);
  });

  test('无效 ID 被忽略且不污染水位', () {
    final tracker = BotNoticeTracker();
    tracker.accept('d', bot([notice(4)]));
    expect(
      tracker.accept('d', bot([notice(0), notice(-2), notice(3)])),
      isEmpty,
    );
    expect(ids(tracker.accept('d', bot([notice(0), notice(5)]))), [5]);
  });

  test('forgetDesktop 只清该电脑，之后重新建立基线', () {
    final tracker = BotNoticeTracker();
    tracker.accept('d1', bot([notice(2)]));
    tracker.accept('d2', bot([notice(2)]));
    tracker.forgetDesktop('d1');
    expect(tracker.accept('d1', bot([notice(2), notice(3)])), isEmpty);
    expect(ids(tracker.accept('d1', bot([notice(4)]))), [4]);
    expect(tracker.accept('d2', bot([notice(2)])), isEmpty);
    expect(ids(tracker.accept('d2', bot([notice(2), notice(3)]))), [3]);
  });
}
