// YCode — GPL-3.0-only.
import 'package:flutter/material.dart';

import '../widgets/lucide_icon.dart';

/// Send affordance for the standard chat composer.
class ChatComposerAction extends StatelessWidget {
  const ChatComposerAction({
    super.key,
    required this.busy,
    required this.enabled,
    required this.tooltip,
    required this.onSend,
  });

  final bool busy;
  final bool enabled;
  final String tooltip;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget icon() {
      if (busy) {
        return const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      }
      return const LucideIcon('arrow-up', size: 20);
    }

    return IconButton.filled(
      tooltip: tooltip,
      onPressed: enabled ? onSend : null,
      style: IconButton.styleFrom(
        fixedSize: const Size.square(36),
        minimumSize: const Size.square(36),
        padding: EdgeInsets.zero,
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        disabledBackgroundColor: scheme.onSurfaceVariant.withValues(alpha: .14),
        disabledForegroundColor: scheme.onSurfaceVariant.withValues(alpha: .7),
      ),
      icon: icon(),
    );
  }
}
