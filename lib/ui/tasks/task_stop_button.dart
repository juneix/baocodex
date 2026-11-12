// YCode — GPL-3.0-only.
import 'package:bao_link/bao_link.dart';
import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../widgets/lucide_icon.dart';
import '../../models/user_facing_error.dart';

String taskKindLabel(AppState state, String kind) => switch (kind) {
  'command' => state.tr('命令', 'Command'),
  'agent' => state.tr('子代理', 'Subagent'),
  _ => state.tr('后台任务', 'Background task'),
};

String taskKindIcon(String kind) => switch (kind) {
  'command' => 'terminal',
  'agent' => 'bot',
  _ => 'activity',
};

/// The desktop's CommandStatus names; any other is one that ended.
String taskStatusLabel(AppState state, String status) => switch (status) {
  'running' => state.tr('运行中', 'Running'),
  'succeeded' => state.tr('已完成', 'Done'),
  'failed' => state.tr('失败', 'Failed'),
  _ => state.tr('已结束', 'Ended'),
};

String taskTitle(AppState state, LinkTask task) {
  if (task.description.trim().isNotEmpty) return task.description;
  final command = task.command?.trim();
  if (command != null && command.isNotEmpty) return command;
  return taskKindLabel(state, task.kind);
}

/// Why a stop did not go through, without the raw error.
String taskStopFailure(AppState state, Object error) {
  if (error is UserFacingError) return error.message;
  if (error is LinkRemoteException) {
    return switch (error.code) {
      LinkErrors.unknown || LinkErrors.unsupported => state.tr(
        '电脑端不支持从手机停止这个任务，请在电脑上停止。',
        'The desktop cannot stop this task from the phone. Stop it on the desktop.',
      ),
      _ => state.tr(
        '电脑拒绝了停止请求，请在电脑上查看。',
        'The desktop refused to stop it. Check on the desktop.',
      ),
    };
  }
  return state.tr(
    '停止请求没有确认送达，请看任务是否还在运行；不会自动重试。',
    'The stop was not confirmed. Check whether the task still runs; it is not retried.',
  );
}

/// 停止的图标：圆圈里两根竖条，颜色跟随所在按钮。
class HollowStopIcon extends StatelessWidget {
  const HollowStopIcon({super.key, this.size = 24});

  final double size;

  @override
  Widget build(BuildContext context) => LucideIcon(
    'circle-pause',
    key: const ValueKey('hollow-stop'),
    size: size,
  );
}

/// 手机上所有的停止：黑金圆形，停止中转圈，不能停时变淡。
class StopActionButton extends StatelessWidget {
  const StopActionButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
    this.busy = false,
    this.size = 40,
    this.iconSize = 24,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final bool busy;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final enabled = !busy && onPressed != null;
    return IconButton(
      tooltip: tooltip,
      onPressed: busy ? null : onPressed,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints.tight(Size.square(size)),
      style: IconButton.styleFrom(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: enabled
            ? MobileAccent.goldFill
            : Theme.of(context).colorScheme.onSurfaceVariant.withValues(
                alpha: .14,
              ),
        foregroundColor: enabled
            ? MobileAccent.goldInk
            : Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      icon: busy
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : HollowStopIcon(size: iconSize),
    );
  }
}

Future<bool> confirmTaskStop(
  BuildContext context, {
  required AppState state,
  required String description,
  String? title,
}) async {
  final tr = state.tr;
  final scheme = Theme.of(context).colorScheme;
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title ?? tr('停止这个任务？', 'Stop this task?')),
          content: Text(description),
          actions: dialogButtons([
            OutlinedButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('取消', 'Cancel')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr('停止', 'Stop')),
            ),
          ]),
        ),
      ) ??
      false;
}
