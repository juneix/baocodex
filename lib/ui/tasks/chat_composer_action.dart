// YCode — GPL-3.0-only.
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../widgets/lucide_icon.dart';

/// Send affordance for the standard chat composer: the gold icon itself, no
/// extra round background — the composer is already a surface.
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
      return const LucideIcon('circle-arrow-up', size: 20);
    }

    return IconButton(
      tooltip: tooltip,
      onPressed: enabled ? onSend : null,
      style: IconButton.styleFrom(
        fixedSize: const Size.square(MobileSizes.iconButton),
        minimumSize: const Size.square(MobileSizes.iconButton),
        padding: EdgeInsets.zero,
        backgroundColor: Colors.transparent,
        // 主题色直接落在图标上：黑金是浅金，禁用时退成灰。
        foregroundColor: enabled ? scheme.primary : scheme.onSurfaceVariant,
      ),
      icon: icon(),
    );
  }
}
