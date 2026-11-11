import 'package:bao_link/bao_link.dart';
import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../widgets/mobile_widgets.dart';
import 'task_stop_button.dart';

/// Fullscreen view of the session goal the agent works toward, standing in
/// for the original app's `ui/tasks/goal_page.dart`. Read-only except for
/// the stop action, which is the same wire call the composer's stop uses.
class GoalPage extends StatefulWidget {
  const GoalPage({
    super.key,
    required this.state,
    required this.desktopId,
    this.sessionId,
    required this.goal,
  });

  final AppState state;
  final String desktopId;
  final String? sessionId;
  final Map<String, Object?> goal;

  @override
  State<GoalPage> createState() => _GoalPageState();
}

class _GoalPageState extends State<GoalPage> {
  bool _stopping = false;

  AppState get state => widget.state;

  Future<void> _stop(String condition) async {
    final confirmed = await confirmTaskStop(
      context,
      state: state,
      title: state.tr('停止这个目标？', 'Stop this goal?'),
      description: condition,
    );
    if (!confirmed || !mounted) return;
    setState(() => _stopping = true);
    await runUi(context, () async {
      await state.request(widget.desktopId, LinkMethods.stop, {
        'session': widget.sessionId,
      });
    });
    if (mounted) setState(() => _stopping = false);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) {
      final session = widget.sessionId;
      final buffer = session == null
          ? null
          : state.peekBuffer(widget.desktopId, session);
      // 打开后目标还在变；会话里已经没有它了，就是结束了。
      final ended = buffer != null && buffer.goal == null;
      return _page(context, buffer?.goal ?? widget.goal, ended: ended);
    },
  );

  Widget _page(
    BuildContext context,
    Map<String, Object?> goal, {
    required bool ended,
  }) {
    final condition = '${goal['condition'] ?? ''}';
    final stateName = '${goal['state'] ?? ''}';
    final reason = '${goal['reason'] ?? ''}';
    final checks = goal['checks'];
    final tokens = goal['tokens'];
    final running = !ended && _isRunning(stateName);
    return Scaffold(
      appBar: AppBar(
        title: Text(state.tr('目标', 'Goal')),
        actions: [
          if (running)
            StopActionButton(
              tooltip: state.tr('停止目标', 'Stop the goal'),
              busy: _stopping,
              onPressed:
                  widget.sessionId != null && state.isOnline(widget.desktopId)
                  ? () => _stop(condition)
                  : null,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _stateChip(context, stateName),
          const SizedBox(height: 12),
          SelectableText(
            condition,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (reason.isNotEmpty && reason != 'null') ...[
            const SizedBox(height: 12),
            Text(
              state.tr('最近一次检查', 'Last check'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(10),
              ),
              child: SelectableText(
                reason,
                style: MobileTheme.messageStyleOf(context),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            [
              if (checks != null) '${state.tr('检查次数', 'Checks')}: $checks',
              if (tokens != null) '${state.tr('累计 token', 'Tokens')}: $tokens',
            ].join('  ·  '),
            style: MobileTheme.metaStyleOf(context),
          ),
          const SizedBox(height: 20),
          Text(
            state.tr(
              '目标由智能体自主推进；停止后可以继续对话或重新设定。',
              'The agent drives the goal on its own. After stopping you can keep chatting or set a new one.',
            ),
            style: MobileTheme.metaStyleOf(context),
          ),
        ],
      ),
    );
  }

  /// The desktop sends `active`.
  static bool _isRunning(String stateName) =>
      stateName == 'active' || stateName == 'running';

  /// Goal states come from the desktop as plain words; the known ones get
  /// Chinese labels, anything else shows as-is rather than guessing.
  Widget _stateChip(BuildContext context, String stateName) {
    final colors = MobileTheme.statusColorsOf(context);
    final color = switch (stateName) {
      'active' || 'running' => colors.warning,
      'met' || 'achieved' => colors.success,
      'failed' => Theme.of(context).colorScheme.error,
      _ => Theme.of(context).colorScheme.onSurfaceVariant,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        goalStateLabel(state, stateName),
        style: MobileTheme.metaStyleOf(context, color: color),
      ),
    );
  }
}

String goalStateLabel(AppState state, String stateName) => switch (stateName) {
  'active' || 'running' => state.tr('进行中', 'Running'),
  'met' || 'achieved' => state.tr('已达成', 'Achieved'),
  'stopped' => state.tr('已停止', 'Stopped'),
  'failed' => state.tr('失败', 'Failed'),
  _ => stateName,
};

/// Opens the fullscreen goal page from the chat's inline goal card.
void openGoalPage(
  BuildContext context, {
  required AppState state,
  required String desktopId,
  String? sessionId,
  required Map<String, Object?> goal,
}) {
  openPage<void>(
    context,
    GoalPage(
      state: state,
      desktopId: desktopId,
      sessionId: sessionId,
      goal: goal,
    ),
  );
}
