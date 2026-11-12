// YCode — GPL-3.0-only.
import 'package:flutter/material.dart';

import '../../state/local_message_queue.dart';
import '../../theme/app_theme.dart';
import '../widgets/lucide_icon.dart';

typedef Tr = String Function(String zh, String en);

/// A strip over the composer: what the next send does, or what is being
/// edited, with the one action that changes it.
class ComposerNotice extends StatelessWidget {
  const ComposerNotice({
    super.key,
    required this.icon,
    required this.title,
    this.detail,
    this.actionLabel,
    this.onAction,
    this.tone,
  });

  final String icon;
  final String title;
  final String? detail;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// The icon's and title's color; muted when null.
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final color = tone ?? scheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(MobileSpace.sm, 0, 0, MobileSpace.xs),
      child: Row(
        children: [
          LucideIcon(icon, size: 16, color: color),
          const SizedBox(width: MobileSpace.sm),
          Expanded(
            child: Text.rich(
              TextSpan(
                text: title,
                style: text.bodySmall!.copyWith(
                  color: tone ?? scheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
                children: [
                  if (detail != null)
                    TextSpan(
                      text: ' · $detail',
                      style: text.bodySmall!.copyWith(
                        fontSize: MobileType.aside,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                ],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (actionLabel != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: MobileSpace.md),
                textStyle: text.bodySmall!.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

/// The messages sent while the agent works, waiting for its turn to end:
/// each can be sent now (the turn stopped for it), taken back to edit, or
/// taken off the queue.
class QueuedMessagesPanel extends StatelessWidget {
  const QueuedMessagesPanel({
    super.key,
    required this.messages,
    required this.tr,
    required this.enabled,
    required this.onSendNow,
    required this.onEdit,
    required this.onRemove,
  });

  final List<LocalQueuedMessage> messages;
  final Tr tr;
  final bool enabled;
  final ValueChanged<LocalQueuedMessage> onSendNow;
  final ValueChanged<LocalQueuedMessage> onEdit;
  final ValueChanged<LocalQueuedMessage> onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    Widget action(String icon, String tooltip, VoidCallback onTap) =>
        IconButton(
          tooltip: tooltip,
          onPressed: enabled ? onTap : null,
          visualDensity: VisualDensity.compact,
          style: IconButton.styleFrom(
            minimumSize: const Size.square(40),
            fixedSize: const Size.square(40),
          ),
          // Muted: the messages, not their actions, are what to read.
          icon: LucideIcon(
            icon,
            size: 18,
            color: enabled ? scheme.onSurfaceVariant : null,
          ),
        );
    final media = MediaQuery.of(context);
    // 给输入框和工具行留出空间：排队消息再多也只占可用高度的一部分。
    final maxHeight = ((media.size.height - media.viewInsets.bottom) * .22)
        .clamp(72.0, 200.0);
    return Container(
      key: const ValueKey('queued-messages'),
      constraints: BoxConstraints(maxHeight: maxHeight),
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: scheme.onSurfaceVariant.withValues(alpha: .18),
        ),
      ),
      child: SingleChildScrollView(
        primary: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                MobileSpace.md,
                MobileSpace.sm,
                MobileSpace.md,
                0,
              ),
              child: Row(
                children: [
                  LucideIcon('clock', size: 14, color: scheme.onSurfaceVariant),
                  const SizedBox(width: MobileSpace.xs + 2),
                  Expanded(
                    child: Text(
                      tr(
                        '${messages.length} 条排队中 · 本轮结束后依次发送',
                        '${messages.length} queued · sent when this turn ends',
                      ),
                      style: text.labelSmall,
                    ),
                  ),
                ],
              ),
            ),
            for (final message in messages)
              Padding(
                padding: const EdgeInsets.only(left: MobileSpace.md),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: enabled ? () => onEdit(message) : null,
                        borderRadius: BorderRadius.circular(MobileSpace.xs),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: MobileSpace.sm,
                          ),
                          child: Text(
                            [
                              if (message.images.isNotEmpty)
                                tr(
                                  '[${message.images.length} 张图片]',
                                  '[${message.images.length} images]',
                                ),
                              if (message.text.isNotEmpty) message.text,
                            ].join(' '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall!.copyWith(
                              color: scheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // As the desktop's queue: edit, send now, remove.
                    action(
                      'pencil',
                      tr('重新编辑', 'Edit again'),
                      () => onEdit(message),
                    ),
                    action(
                      'arrow-up-tall',
                      tr('立即插入', 'Send now'),
                      () => onSendNow(message),
                    ),
                    action(
                      'trash-2',
                      tr('移出队列', 'Remove from queue'),
                      () => onRemove(message),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: MobileSpace.xs),
          ],
        ),
      ),
    );
  }
}
