import 'package:bao_link/bao_link.dart';
import 'package:flutter/services.dart';

/// 状态栏胶囊与 HyperOS 灵动岛的一条实时活动。
///
/// 只在需要人看一眼的时候出现：等你确认/回答、有对话在跑、一轮做完没看。
/// 不放对话正文，只放状态词和数量；对话标题只用来点开时定位。
typedef LiveActivitySpec = ({
  String kind,
  String chip,
  String text,
  String? title,
});

class LiveActivity {
  static const channel = MethodChannel('local.baocode.mobile/live');

  /// [sessions] 现在的样子，返回该显示的一条；没有就 null。
  /// 优先级：等你处理 > 运行中 > 完成未读（仅在后台）。
  static LiveActivitySpec? reduce(
    Iterable<SessionSummary> sessions, {
    required bool foreground,
    required String Function(String zh, String en) tr,
    required bool showWaiting,
    required bool showDone,
  }) {
    final list = sessions.toList();
    final waiting = list
        .where((s) => s.status == LinkSessionStatus.needsInput)
        .toList();
    if (showWaiting && waiting.isNotEmpty) {
      return (
        kind: 'waiting',
        chip: tr('待确认', 'Waiting'),
        text: waiting.length == 1
            ? waiting.first.title
            : tr('${waiting.length} 个对话等你处理', '${waiting.length} waiting'),
        title: waiting.first.title,
      );
    }
    final running = list
        .where((s) => s.status == LinkSessionStatus.running)
        .toList();
    if (running.isNotEmpty) {
      return (
        kind: 'running',
        chip: tr('运行中', 'Running'),
        text: running.length == 1
            ? running.first.title
            : tr('${running.length} 个对话正在运行', '${running.length} running'),
        title: running.first.title,
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
              : tr('${done.length} 个对话已完成', '${done.length} finished'),
          title: done.first.title,
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
        'title': spec.title,
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
