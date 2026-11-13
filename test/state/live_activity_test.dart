import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/state/live_activity.dart';
import 'package:flutter_test/flutter_test.dart';

SessionSummary _s(
  String id,
  LinkSessionStatus status, {
  bool unread = false,
  String? title,
}) => SessionSummary(
  id: id,
  project: 'p',
  title: title ?? id,
  updatedAt: DateTime(2026),
  status: status,
  unread: unread,
);

String _tr(String zh, String en) => zh;

void main() {
  LiveActivitySpec? reduce(
    List<SessionSummary> sessions, {
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

  test('等你处理的对话优先，胶囊只写状态词', () {
    final spec = reduce([
      _s('跑', LinkSessionStatus.running),
      _s('等', LinkSessionStatus.needsInput, title: '要你批准'),
    ]);
    expect(spec?.kind, 'waiting');
    expect(spec?.chip, '待确认');
    expect(spec?.text, '要你批准');
  });

  test('多个等你处理时只报条数', () {
    final spec = reduce([
      _s('一', LinkSessionStatus.needsInput),
      _s('二', LinkSessionStatus.needsInput),
    ]);
    expect(spec?.kind, 'waiting');
    expect(spec?.text, '2 个对话等你处理');
  });

  test('没有等你处理时显示运行中', () {
    final spec = reduce([
      _s('跑', LinkSessionStatus.running, title: '改代码'),
      _s('闲', LinkSessionStatus.idle),
    ]);
    expect(spec?.kind, 'running');
    expect(spec?.chip, '运行中');
    expect(spec?.text, '改代码');
  });

  test('完成未读只在后台显示，回前台就收掉', () {
    final done = [_s('完', LinkSessionStatus.idle, unread: true)];
    expect(reduce(done, foreground: true), isNull);
    final spec = reduce(done);
    expect(spec?.kind, 'done');
    expect(spec?.chip, '已完成');
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
