import 'package:bao_link/bao_link.dart';
import 'package:flutter/services.dart';

/// 状态栏胶囊与灵动岛的一条实时活动。
///
/// 只在需要人看一眼的时候出现：等你处理、有对话在跑、一轮做完没看。
/// 不放对话正文，只放状态词和数量。
typedef LiveActivitySpec = ({
  String kind,
  // 状态词：灵动岛和状态栏胶囊只读它，只放得下三个字。
  String chip,
  // 通知卡片第二行：对话标题或聚合计数。
  String text,
  // 通知卡片第一行尾部追加的补充信息（目前只有上下文用量），拼成「运行中丨上下文 45%」。
  // 灵动岛和状态栏胶囊看不到它，所以岛里不会被挤长。没有时为 null。
  String? detail,
  String? stopLabel,
  String? stopDesktop,
  String? stopSession,
  // 是否有会话正在跑：决定要不要用前台服务顶住进程保活。
  // 与显示哪一条无关——哪怕此刻显示的是「待处理」，只要别处有在跑的，也要保活。
  bool keepAlive,
});

/// 一条候选会话，由 [AppState] 收集好喂给 [LiveActivity.reduce]。
///
/// [waitKind] 与 [contextPercent] 只有已订阅（打开过）的会话才拿得到：
/// 前者是桌面等的类型（`approval` / `question`），后者是上下文用量百分比。
/// 拿不到时保持 null，界面退回统称。
typedef LiveSession = ({
  String desktopId,
  String id,
  String title,
  LinkSessionStatus status,
  bool unread,
  String? waitKind,
  int? contextPercent,
});

class LiveActivity {
  static const channel = MethodChannel('local.baocode.mobile/live');

  /// 通知上「停止」按钮按下时，原生侧回推一条 `{action, desktop, session}`。
  static const actionChannel = EventChannel('local.baocode.mobile/live_actions');

  static Stream<({String? desktop, String? session})>? _stops;

  /// 用户在通知上点「停止」：要停哪个会话。原生没宿主时没有事件。
  static Stream<({String? desktop, String? session})> get stopRequests =>
      _stops ??= actionChannel.receiveBroadcastStream().map((event) {
        final map = event is Map
            ? event.map((key, value) => MapEntry(key.toString(), value))
            : const <String, Object?>{};
        return (
          desktop: map['desktop'] as String?,
          session: map['session'] as String?,
        );
      });

  /// [sessions] 现在的样子，返回该显示的一条；没有就 null。
  /// 优先级：等你处理 > 运行中 > 完成未读（仅在后台）。
  ///
  /// 等你处理里，单个会话若能判出桌面在等什么，就细分成「待批准 / 待回答」；
  /// 多个或判不出时用统称「待处理」。
  static LiveActivitySpec? reduce(
    Iterable<LiveSession> sessions, {
    required bool foreground,
    required String Function(String zh, String en) tr,
    required bool showWaiting,
    required bool showDone,
  }) {
    final list = sessions.toList();
    final running = list
        .where((s) => s.status == LinkSessionStatus.running)
        .toList();
    // 有没有会话在跑，决定要不要保活——与此刻显示哪一条无关。
    final keepAlive = running.isNotEmpty;
    final waiting = list
        .where((s) => s.status == LinkSessionStatus.needsInput)
        .toList();
    if (showWaiting && waiting.isNotEmpty) {
      if (waiting.length == 1) {
        final one = waiting.single;
        final chip = switch (one.waitKind) {
          'approval' => tr('待批准', 'Approve'),
          'question' => tr('待回答', 'Answer'),
          _ => tr('待处理', 'Needs input'),
        };
        return (
          kind: 'waiting',
          chip: chip,
          text: one.title,
          detail: null,
          stopLabel: null,
          stopDesktop: null,
          stopSession: null,
          keepAlive: keepAlive,
        );
      }
      return (
        kind: 'waiting',
        chip: tr('待处理', 'Needs input'),
        text: tr('${waiting.length} 个待处理', '${waiting.length} need input'),
        detail: null,
        stopLabel: null,
        stopDesktop: null,
        stopSession: null,
        keepAlive: keepAlive,
      );
    }
    if (running.isNotEmpty) {
      if (running.length == 1) {
        final one = running.single;
        return (
          kind: 'running',
          chip: tr('运行中', 'Running'),
          text: one.title,
          // 上下文用量只进通知卡片第一行，岛里只有「运行中」三个字。
          detail: one.contextPercent != null
              ? tr('上下文 ${one.contextPercent}%', 'context ${one.contextPercent}%')
              : null,
          stopLabel: tr('停止', 'Stop'),
          stopDesktop: one.desktopId,
          stopSession: one.id,
          keepAlive: keepAlive,
        );
      }
      return (
        kind: 'running',
        chip: tr('运行中', 'Running'),
        text: tr('${running.length} 个运行中', '${running.length} running'),
        detail: null,
        stopLabel: tr('停止', 'Stop'),
        stopDesktop: running.first.desktopId,
        stopSession: running.first.id,
        keepAlive: keepAlive,
      );
    }
    if (!foreground) {
      final done = list
          .where((s) => s.status == LinkSessionStatus.idle && s.unread)
          .toList();
      if (showDone && done.isNotEmpty) {
        return (
          kind: 'done',
          chip: tr('已完成', 'Done'),
          text: done.length == 1
              ? done.first.title
              : tr('${done.length} 个已完成', '${done.length} finished'),
          detail: null,
          stopLabel: null,
          stopDesktop: null,
          stopSession: null,
          keepAlive: false,
        );
      }
    }
    return null;
  }

  /// 显示或更新那一条；原生侧没有宿主时静默跳过。
  static Future<void> show(LiveActivitySpec spec) async {
    try {
      await channel.invokeMethod<void>('update', {
        'kind': spec.kind,
        'chip': spec.chip,
        'text': spec.text,
        'detail': spec.detail,
        'stopLabel': spec.stopLabel,
        'stopDesktop': spec.stopDesktop,
        'stopSession': spec.stopSession,
        'keepAlive': spec.keepAlive,
      });
    } on PlatformException {
      /* 通知被拒绝不影响会话。 */
    } on MissingPluginException {
      /* 无宿主的测试环境没有该插件。 */
    }
  }

  static Future<void> clear() async {
    try {
      await channel.invokeMethod<void>('clear');
    } on PlatformException {
      /* 同上。 */
    } on MissingPluginException {
      /* 同上。 */
    }
  }
}
