import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/state/live_activity.dart';
import 'package:flutter_test/flutter_test.dart';

LiveSession _s(
  String id,
  LinkSessionStatus status, {
  bool unread = false,
  String? title,
  String? waitKind,
  int? contextPercent,
}) => (
  desktopId: 'd',
  id: id,
  title: title ?? id,
  status: status,
  unread: unread,
  waitKind: waitKind,
  contextPercent: contextPercent,
);

String _tr(String zh, String en) => zh;

void main() {
  LiveActivitySpec? reduce(
    List<LiveSession> sessions, {
    bool foreground = false,
    bool showWaiting = true,
    bool showDone = true,
  }) => LiveActivity.reduce(
    sessions,
    foreground: foreground,
    tr: _tr,
    showWaiting: showWaiting,
    showDone: showDone,
  );

  test('单个待处理能判出类型时细分为待批准，且别处有在跑的仍要保活', () {
    final spec = reduce([
      _s('跑', LinkSessionStatus.running),
      _s('等', LinkSessionStatus.needsInput, title: '要你批准', waitKind: 'approval'),
    ]);
    expect(spec?.kind, 'waiting');
    expect(spec?.chip, '待批准');
    expect(spec?.text, '要你批准');
    // 显示的是待处理，但还有会话在跑，仍要保活。
    expect(spec?.keepAlive, isTrue);
  });

  test('只有待处理、没有在跑的，不保活', () {
    final spec = reduce([_s('等', LinkSessionStatus.needsInput)]);
    expect(spec?.keepAlive, isFalse);
  });

  test('等回答时显示待回答', () {
    final spec = reduce([
      _s('问', LinkSessionStatus.needsInput, waitKind: 'question'),
    ]);
    expect(spec?.chip, '待回答');
  });

  test('单个待处理判不出类型时用统称待处理', () {
    final spec = reduce([_s('等', LinkSessionStatus.needsInput)]);
    expect(spec?.chip, '待处理');
  });

  test('多个待处理时只报条数，用统称', () {
    final spec = reduce([
      _s('一', LinkSessionStatus.needsInput, waitKind: 'approval'),
      _s('二', LinkSessionStatus.needsInput),
    ]);
    expect(spec?.kind, 'waiting');
    expect(spec?.chip, '待处理');
    expect(spec?.text, '2 个待处理');
  });

  test('没有待处理时显示运行中，第一行只有状态词，上下文另挂在 detail 上', () {
    final spec = reduce([
      _s('跑', LinkSessionStatus.running, title: '改代码', contextPercent: 45),
      _s('闲', LinkSessionStatus.idle),
    ]);
    expect(spec?.kind, 'running');
    // 岛和胶囊只放得下三个字，状态词不能拼上下文。
    expect(spec?.chip, '运行中');
    expect(spec?.text, '改代码');
    // detail 只给通知卡片第一行用，原生侧拼成「运行中丨上下文 45%」。
    expect(spec?.detail, '上下文 45%');
    // 运行中给停止按钮，带会话定位。
    expect(spec?.stopLabel, '停止');
    expect(spec?.stopDesktop, 'd');
    expect(spec?.stopSession, '跑');
    expect(spec?.keepAlive, isTrue);
  });

  test('运行中拿不到上下文时只写运行中，detail 为空', () {
    final spec = reduce([_s('跑', LinkSessionStatus.running)]);
    expect(spec?.chip, '运行中');
    expect(spec?.detail, isNull);
  });

  test('多个运行时只报条数，不带上下文', () {
    final spec = reduce([
      _s('一', LinkSessionStatus.running),
      _s('二', LinkSessionStatus.running),
    ]);
    expect(spec?.chip, '运行中');
    expect(spec?.text, '2 个运行中');
    expect(spec?.detail, isNull);
  });

  test('完成未读只在后台显示，回前台就收掉', () {
    final done = [_s('完', LinkSessionStatus.idle, unread: true)];
    expect(reduce(done, foreground: true), isNull);
    final spec = reduce(done);
    expect(spec?.kind, 'done');
    expect(spec?.chip, '已完成');
    expect(spec?.keepAlive, isFalse);
  });

  test('全都已读、没有在跑也不等你时什么也不显示', () {
    expect(reduce([_s('闲', LinkSessionStatus.idle)]), isNull);
    expect(reduce(const []), isNull);
  });

  test('关掉对应提醒开关后不再进岛', () {
    expect(
      reduce(
        [_s('等', LinkSessionStatus.needsInput)],
        showWaiting: false,
      ),
      isNull,
    );
    expect(
      reduce([_s('完', LinkSessionStatus.idle, unread: true)], showDone: false),
      isNull,
    );
  });
}
