// YCode — GPL-3.0-only.
import 'package:bao_link/bao_link.dart';
import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../ui/widgets/lucide_icon.dart';

/// A sticker, shown by its name: the app ships no sticker artwork. Built-in
/// ids use the protocol's own names in the interface language; unknown ids
/// show the id itself rather than pretending to know what it was.
class StickerView extends StatelessWidget {
  const StickerView(this.id, {super.key});

  final String id;

  @override
  Widget build(BuildContext context) {
    final sticker = builtInSticker(id);
    final name = sticker == null ? id : AppState.phrase(sticker.zh, sticker.en);
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: AppState.phrase('贴纸：$name', 'Sticker: $name'),
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            LucideIcon('smile', size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                name,
                style: const TextStyle(fontSize: MobileType.body),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
